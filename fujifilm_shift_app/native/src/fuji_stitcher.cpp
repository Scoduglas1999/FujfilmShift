#include "fuji_stitcher.h"
// Prevent Windows headers (pulled indirectly) from defining min/max macros
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif
#include <opencv2/opencv.hpp>
#include <libraw/libraw.h>
#if defined(_WIN32)
#include <windows.h>
#endif
#include <string>
#include <vector>
#include <sstream>
#include <memory>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <limits>

namespace {

static void write_error(char* buf, int len, const std::string& msg) {
  if (!buf || len <= 0) return;
  const auto n = static_cast<int>(std::min<std::size_t>(len - 1, msg.size()));
  memcpy(buf, msg.data(), n);
  buf[n] = '\0';
}

struct ScopedLibRaw {
  LibRaw raw;
  int open(const char* path) { return raw.open_file(path); }
  int unpack() { return raw.unpack(); }
  int dcraw_process() { return raw.dcraw_process(); }
  libraw_processed_image_t* dcraw_make_mem_image() { return raw.dcraw_make_mem_image(nullptr); }
  void clear_mem(libraw_processed_image_t* p) { if (p) raw.dcraw_clear_mem(p); }
  ~ScopedLibRaw() { raw.recycle(); }
};

// Forward declarations (full types appear later in file)
struct CFAInfo;
struct Levels;
static CFAInfo detect_cfa(LibRaw& raw);
static Levels get_levels(const LibRaw& raw, const CFAInfo& cfa);
static inline int bayer_color_at(const LibRaw& raw, const CFAInfo& cfa, int row, int col);

// Decode RAF -> cv::Mat (float32 linear RGB, [0..1])
static bool decode_raf_to_float(const char* path, cv::Mat& out, std::string& err) {
  LibRaw raw;
  int rc = raw.open_file(path);
  if (rc != LIBRAW_SUCCESS) { err = std::string("LibRaw open failed: ") + libraw_strerror(rc); return false; }
  rc = raw.unpack();
  if (rc != LIBRAW_SUCCESS) { err = std::string("LibRaw unpack failed: ") + libraw_strerror(rc); raw.recycle(); return false; }

  // Try fast Bayer demosaic path to avoid processed pipeline crashes
  CFAInfo cfa = detect_cfa(raw);
  if (cfa.is_bayer) {
    const int w = raw.imgdata.sizes.iwidth;
    const int h = raw.imgdata.sizes.iheight;
    const int top = raw.imgdata.sizes.top_margin;
    const int left = raw.imgdata.sizes.left_margin;
    const int pitch = raw.imgdata.sizes.raw_width;
    unsigned short* data = raw.imgdata.rawdata.raw_image;
    if (!data) { err = "LibRaw raw_image is null"; raw.recycle(); return false; }
    Levels lv = get_levels(raw, cfa);

    cv::Mat mosaic16(h, w, CV_16U);
    for (int y = 0; y < h; ++y) {
      unsigned short* pm = mosaic16.ptr<unsigned short>(y);
      const int srcRow = (y + top) * pitch + left;
      for (int x = 0; x < w; ++x) {
        const unsigned short rv = data[srcRow + x];
        const int cidx = bayer_color_at(raw, cfa, y, x);
        const float black = lv.black[cidx];
        float norm = (float(rv) - black) / (std::max)(1.0f, lv.white - black);
        if (norm < 0.f) norm = 0.f; if (norm > 1.f) norm = 1.f;
        pm[x] = (unsigned short)std::lround(norm * 65535.0f);
      }
    }
    cv::Mat dem16;
    cv::demosaicing(mosaic16, dem16, cfa.cv_bayer_code);
    cv::Mat demF;
    dem16.convertTo(demF, CV_32FC3, 1.0 / 65535.0);
    cv::cvtColor(demF, out, cv::COLOR_BGR2RGB);
    raw.recycle();
    return true;
  }

  // Fallback to LibRaw processed pipeline (e.g., X-Trans)
  raw.imgdata.params.output_bps = 16;
  raw.imgdata.params.no_auto_bright = 1;
  raw.imgdata.params.use_camera_wb = 1;
  raw.imgdata.params.output_color = 1; // sRGB
  rc = raw.dcraw_process();
  if (rc != LIBRAW_SUCCESS) { err = std::string("LibRaw process failed: ") + libraw_strerror(rc); raw.recycle(); return false; }
  libraw_processed_image_t* img = raw.dcraw_make_mem_image(&rc);
  if (!img || rc != LIBRAW_SUCCESS) { err = std::string("LibRaw make_mem_image failed: ") + libraw_strerror(rc); raw.recycle(); return false; }
  if (img->type != LIBRAW_IMAGE_BITMAP || img->bits != 16 || img->colors != 3) {
    err = "Unexpected processed image format";
    raw.dcraw_clear_mem(img);
    raw.recycle();
    return false;
  }
  cv::Mat mat16(img->height, img->width, CV_16UC3, img->data);
  cv::Mat tmpF;
  mat16.convertTo(tmpF, CV_32FC3, 1.0 / 65535.0);
  cv::cvtColor(tmpF, out, cv::COLOR_BGR2RGB);
  raw.dcraw_clear_mem(img);
  raw.recycle();
  return true;
}

// Estimate sub-pixel shift via phase correlation on luminance
static cv::Point2d estimate_shift(const cv::Mat& ref, const cv::Mat& img) {
  cv::Mat refGray, imgGray;
  cv::cvtColor(ref, refGray, cv::COLOR_BGR2GRAY);
  cv::cvtColor(img, imgGray, cv::COLOR_BGR2GRAY);
  cv::Point2d shift = cv::phaseCorrelate(refGray, imgGray);
  return shift; // dx, dy
}

struct CFAInfo {
  bool is_bayer = false;
  bool is_xtrans = false;
  // Bayer description such as "RGGB", "BGGR", "GRBG", "GBRG"
  std::string bayer;
  // OpenCV demosaic code (if Bayer)
  int cv_bayer_code = cv::COLOR_BayerRG2BGR;
  // cdesc mapping from index->char ('R','G','B','G')
  char cdesc[5] = { 'R','G','B','G','\0' };
};

static CFAInfo detect_cfa(LibRaw& raw) {
  CFAInfo info;
  // Copy cdesc mapping
  for (int i = 0; i < 4; ++i) info.cdesc[i] = raw.imgdata.idata.cdesc[i];
  info.cdesc[4] = '\0';

  // X-Trans present?
  if (raw.imgdata.idata.filters == 0 && raw.imgdata.idata.xtrans[0][0] >= 0) {
    info.is_xtrans = true;
    return info;
  }

  // Decode 2x2 Bayer pattern from filters (2 bits per entry)
  unsigned long flt = raw.imgdata.idata.filters;
  auto idx = [&](int y, int x) -> int {
    return (int)((flt >> (2 * ((y & 1) * 2 + (x & 1)))) & 3);
  };

  char tl = info.cdesc[idx(0,0)];
  char tr = info.cdesc[idx(0,1)];
  char bl = info.cdesc[idx(1,0)];
  char br = info.cdesc[idx(1,1)];
  info.bayer = std::string() + tl + tr + bl + br;
  info.is_bayer = true;

  if (info.bayer == "RGGB") info.cv_bayer_code = cv::COLOR_BayerRG2BGR;
  else if (info.bayer == "BGGR") info.cv_bayer_code = cv::COLOR_BayerBG2BGR;
  else if (info.bayer == "GRBG") info.cv_bayer_code = cv::COLOR_BayerGR2BGR;
  else if (info.bayer == "GBRG") info.cv_bayer_code = cv::COLOR_BayerGB2BGR;
  else info.cv_bayer_code = cv::COLOR_BayerRG2BGR; // default

  return info;
}

// Splat a sample into mosaic only at pixels whose CFA channel matches cidx.
static void splat_bilinear_cfa(cv::Mat& mosaicSum, cv::Mat& mosaicCnt,
                               unsigned long filters, const char* cdesc,
                               int top_margin, int left_margin,
                               int upscale,
                               double tx, double ty, float v, int cidx) {
  const int width = mosaicSum.cols;
  const int height = mosaicSum.rows;
  const int x0 = (int)std::floor(tx);
  const int y0 = (int)std::floor(ty);
  const double ax = tx - x0;
  const double ay = ty - y0;
  const double w00 = (1.0 - ax) * (1.0 - ay);
  const double w10 = ax * (1.0 - ay);
  const double w01 = (1.0 - ax) * ay;
  const double w11 = ax * ay;
  auto chan_at = [&](int y, int x) -> int {
    const int baseY = (y / upscale) + top_margin;
    const int baseX = (x / upscale) + left_margin;
    const int yb = baseY & 1;
    const int xb = baseX & 1;
    const int idx = (int)((filters >> (2 * (yb * 2 + xb))) & 3);
    const char ch = cdesc[idx];
    if (ch == 'R') return 0; if (ch == 'G') return 1; if (ch == 'B') return 2; return 1;
  };
  if (x0 >= 0 && y0 >= 0 && x0 < width && y0 < height && chan_at(y0, x0) == cidx) {
    mosaicSum.at<float>(y0, x0) += (float)w00 * v;
    mosaicCnt.at<int>(y0, x0) += (w00 > 0.0 ? 1 : 0);
  }
  if (x0 + 1 >= 0 && y0 >= 0 && x0 + 1 < width && y0 < height && chan_at(y0, x0 + 1) == cidx) {
    mosaicSum.at<float>(y0, x0 + 1) += (float)w10 * v;
    mosaicCnt.at<int>(y0, x0 + 1) += (w10 > 0.0 ? 1 : 0);
  }
  if (x0 >= 0 && y0 + 1 >= 0 && x0 < width && y0 + 1 < height && chan_at(y0 + 1, x0) == cidx) {
    mosaicSum.at<float>(y0 + 1, x0) += (float)w01 * v;
    mosaicCnt.at<int>(y0 + 1, x0) += (w01 > 0.0 ? 1 : 0);
  }
  if (x0 + 1 >= 0 && y0 + 1 >= 0 && x0 + 1 < width && y0 + 1 < height && chan_at(y0 + 1, x0 + 1) == cidx) {
    mosaicSum.at<float>(y0 + 1, x0 + 1) += (float)w11 * v;
    mosaicCnt.at<int>(y0 + 1, x0 + 1) += (w11 > 0.0 ? 1 : 0);
  }
}

static inline int color_idx_from_char(char ch) {
  if (ch == 'R') return 0;
  if (ch == 'G') return 1;
  if (ch == 'B') return 2;
  return 1;
}

// Get color index (0=R,1=G,2=B) for Bayer pixel at (row,col) in visible area, accounting for margins
static inline int bayer_color_at(const LibRaw& raw, const CFAInfo& cfa, int row, int col) {
  // LibRaw's filters are anchored to absolute sensor coords (including margins)
  const int rr = row + raw.imgdata.sizes.top_margin;
  const int cc = col + raw.imgdata.sizes.left_margin;
  const unsigned long flt = raw.imgdata.idata.filters;
  const int yb = rr & 1;
  const int xb = cc & 1;
  const int idx = (int)((flt >> (2 * (yb * 2 + xb))) & 3);
  return color_idx_from_char(cfa.cdesc[idx]);
}

// Extract per-channel black levels and white level
struct Levels {
  float black[3] = {0,0,0};
  float white = 16383.0f;
};

static Levels get_levels(const LibRaw& raw, const CFAInfo& cfa) {
  Levels lv;
  // Map LibRaw's cblack[4] indices to R,G,B using cdesc
  float tmpBlack[4] = {0,0,0,0};
  for (int i = 0; i < 4; ++i) tmpBlack[i] = (float)raw.imgdata.color.cblack[i];
  // Average greens if needed
  float rB = 0.f, gB = 0.f, bB = 0.f; int gCount = 0;
  for (int i = 0; i < 4; ++i) {
    const char ch = raw.imgdata.idata.cdesc[i];
    if (ch == 'R') rB = tmpBlack[i];
    else if (ch == 'B') bB = tmpBlack[i];
    else if (ch == 'G') { gB += tmpBlack[i]; gCount++; }
  }
  if (gCount > 0) gB /= gCount;
  lv.black[0] = rB; lv.black[1] = gB; lv.black[2] = bB;
  // White level: use LibRaw maximum if available, else fallback
  if (raw.imgdata.color.maximum > 0) lv.white = (float)raw.imgdata.color.maximum;
  else lv.white = 16383.0f; // fallback
  return lv;
}

struct WhiteBalance {
  float mul[3] = {1.f, 1.f, 1.f};
};

static WhiteBalance get_wb(const LibRaw& raw) {
  WhiteBalance wb;
  // Use cam_mul if available
  for (int i = 0; i < 3; ++i) wb.mul[i] = raw.imgdata.color.cam_mul[i] > 0 ? (float)raw.imgdata.color.cam_mul[i] : 1.f;
  // Normalize so that green multiplier is 1
  const float g = wb.mul[1] > 1e-6f ? wb.mul[1] : 1.0f;
  wb.mul[0] /= g; wb.mul[1] /= g; wb.mul[2] /= g;
  return wb;
}

// Optional 3x3 color matrix from camera->RGB, built from LibRaw rgb_cam[3][4]
static cv::Mat get_color_matrix_rgb(const LibRaw& raw) {
  cv::Mat M = cv::Mat::eye(3, 3, CV_32F);
  const float (*rgb_cam)[4] = raw.imgdata.color.rgb_cam;
  // If matrix appears valid (non-zero), use first 3 columns
  float sumabs = 0.0f;
  for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) sumabs += std::abs(rgb_cam[r][c]);
  if (sumabs > 0.0f) {
    for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) M.at<float>(r,c) = rgb_cam[r][c];
  }
  return M;
}

}

extern "C" FUJI_API int FS_StitchFujiPixelShift(
  const char* output_path,
  const char** input_paths,
  int input_count,
  const char* options_json,
  char* error_buf,
  int error_buf_len
) {
  try {
    if (!output_path || !input_paths || input_count <= 0) {
      write_error(error_buf, error_buf_len, "Invalid arguments");
      return 2;
    }

    // Limit OpenCV threading to keep UI responsive
    int cpus = cv::getNumberOfCPUs();
    int threads = (cpus > 2) ? (cpus - 2) : 1;
    cv::setNumThreads(threads);

    // Progress support via simple text file
    std::string progress_path;
    // Fallback progress path in output directory
    {
      const char* sep = strrchr(output_path, '\\');
      const char* sep2 = strrchr(output_path, '/');
      const char* p = sep ? sep : sep2;
      std::string outdir = p ? std::string(output_path, p - output_path) : std::string(".");
      progress_path = outdir + "/stitch_progress.txt";
    }
    if (options_json && options_json[0]) {
      // naive extraction of value for key "progress_path":"..."
      std::string s(options_json);
      auto kpos = s.find("\"progress_path\"");
      if (kpos != std::string::npos) {
        auto colon = s.find(':', kpos);
        if (colon != std::string::npos) {
          auto q1 = s.find('"', colon + 1);
          if (q1 != std::string::npos) {
            auto q2 = s.find('"', q1 + 1);
            if (q2 != std::string::npos && q2 > q1 + 1) {
              progress_path = s.substr(q1 + 1, q2 - (q1 + 1));
            }
          }
        }
      }
    }
    auto report = [&](const std::string& msg){
      if (progress_path.empty()) return;
      FILE* f = fopen(progress_path.c_str(), "a");
      if (!f) return;
      fprintf(f, "%s\n", msg.c_str());
      fclose(f);
    };
    report("entered");
#if defined(_WIN32)
    // Log which LibRaw DLL is actually loaded to diagnose dependency issues
    {
      HMODULE h = GetModuleHandleA("raw_r.dll");
      if (!h) h = LoadLibraryA("raw_r.dll");
      if (h) {
        char buf[MAX_PATH] = {0};
        if (GetModuleFileNameA(h, buf, MAX_PATH) > 0) {
          report(std::string("libraw: ") + buf);
        } else {
          report("libraw: loaded (path unknown)");
        }
      } else {
        report("libraw: not loaded");
      }
    }
#endif

    // Options
    bool use_raw_domain = false;
    if (options_json && options_json[0]) {
      std::string s(options_json);
      if (s.find("\"raw_domain\":true") != std::string::npos) use_raw_domain = true;
    }

    // Branch: processed-domain SR (stable) vs raw-domain SR (experimental)
    if (!use_raw_domain) {
      // Alignment and fusion on LibRaw-processed 16-bit RGB
      std::vector<cv::Point2d> smallShifts(input_count);
      std::vector<int> smallWidths(input_count);

      // Decode first
      report(std::string("predecode ") + input_paths[0]);
      cv::Mat firstFull16;
      std::string err;
      if (!decode_raf_to_float(input_paths[0], firstFull16, err)) {
        write_error(error_buf, error_buf_len, std::string("Decode failed: ") + err);
        return 4;
      }
      report("decoded 1/" + std::to_string(input_count));
      cv::Mat refSmall;
      cv::cvtColor(firstFull16, refSmall, cv::COLOR_RGB2GRAY);
      int maxW = 2048;
      double scale = 1.0;
      if (refSmall.cols > maxW) {
        scale = static_cast<double>(maxW) / refSmall.cols;
        cv::resize(refSmall, refSmall, cv::Size(), scale, scale, cv::INTER_AREA);
      }
      smallWidths[0] = refSmall.cols;
      smallShifts[0] = cv::Point2d(0, 0);

      // Initialize high-res accumulator (2x)
      const int hiW = firstFull16.cols * 2;
      const int hiH = firstFull16.rows * 2;
      cv::Mat acc(hiH, hiW, CV_32FC3, cv::Scalar(0,0,0));
      {
        cv::Mat firstHi;
        cv::resize(firstFull16, firstHi, cv::Size(hiW, hiH), 0, 0, cv::INTER_CUBIC);
        acc += firstHi;
      }

      for (int i = 1; i < input_count; ++i) {
        report(std::string("open ") + input_paths[i]);
        cv::Mat full16_tmp;
        if (!decode_raf_to_float(input_paths[i], full16_tmp, err)) {
          write_error(error_buf, error_buf_len, std::string("Decode failed: ") + err);
          return 4;
        }
        cv::Mat curSmall;
        cv::cvtColor(full16_tmp, curSmall, cv::COLOR_RGB2GRAY);
        if (scale != 1.0) cv::resize(curSmall, curSmall, cv::Size(), scale, scale, cv::INTER_AREA);
        smallWidths[i] = curSmall.cols;
        cv::Point2d shiftSmall = cv::phaseCorrelate(refSmall, curSmall);
        smallShifts[i] = shiftSmall;
        report("aligned " + std::to_string(i+1) + "/" + std::to_string(input_count));

        double ratio = static_cast<double>(firstFull16.cols) / static_cast<double>(smallWidths[i]);
        cv::Point2d shiftFull(shiftSmall.x * ratio, shiftSmall.y * ratio);

        cv::Mat hi;
        cv::resize(full16_tmp, hi, cv::Size(hiW, hiH), 0, 0, cv::INTER_CUBIC);
        cv::Mat warpedHi;
        cv::Mat M = (cv::Mat_<double>(2,3) << 1, 0, shiftFull.x * 2.0, 0, 1, shiftFull.y * 2.0);
        cv::warpAffine(hi, warpedHi, M, hi.size(), cv::INTER_LINEAR, cv::BORDER_REFLECT);
        acc += warpedHi;
        report("decoded " + std::to_string(i+1) + "/" + std::to_string(input_count));
      }

      acc /= static_cast<float>(input_count);
      report("merged frames");
      cv::Mat accClamped;
      cv::max(acc, cv::Scalar(0.0f, 0.0f, 0.0f), accClamped);
      cv::min(accClamped, cv::Scalar(1.0f, 1.0f, 1.0f), accClamped);
      cv::Mat out16RGB;
      accClamped.convertTo(out16RGB, CV_16UC3, 65535.0);
      cv::Mat out16BGR;
      cv::cvtColor(out16RGB, out16BGR, cv::COLOR_RGB2BGR);
      std::vector<int> params = { cv::IMWRITE_TIFF_COMPRESSION, 5 };
      if (!cv::imwrite(output_path, out16BGR, params)) {
        write_error(error_buf, error_buf_len, "Failed to write output image");
        return 5;
      }
      report("wrote output");
      report("return 0");
      return 0;
    }

    // Experimental raw-domain branch below
    std::vector<cv::Point2d> smallShifts(input_count);
    std::vector<int> smallWidths(input_count);

    // Prepare alignment preview variables
    cv::Mat refSmall;
    int maxW = 2048;
    double scale = 1.0;
    smallShifts[0] = cv::Point2d(0, 0);

    // Open first image via LibRaw to get raw sizes/CFA
    LibRaw raw0;
    report("preopen raw0");
    if (int rc = raw0.open_file(input_paths[0]); rc != LIBRAW_SUCCESS) {
      report(std::string("raw0 open failed: ") + libraw_strerror(rc));
      write_error(error_buf, error_buf_len, std::string("LibRaw open failed: ") + libraw_strerror(rc));
      return 4;
    }
    report("preunpack raw0");
    int rc = raw0.unpack();
    if (rc != LIBRAW_SUCCESS) {
      report(std::string("raw0 unpack failed: ") + libraw_strerror(rc));
      write_error(error_buf, error_buf_len, std::string("LibRaw unpack failed: ") + libraw_strerror(rc));
      raw0.recycle();
      return 4;
    }
    const int iwidth = raw0.imgdata.sizes.iwidth;
    const int iheight = raw0.imgdata.sizes.iheight;
    const int top_margin = raw0.imgdata.sizes.top_margin;
    const int left_margin = raw0.imgdata.sizes.left_margin;
    const int raw_pitch = raw0.imgdata.sizes.raw_width;
    report(std::string("dims ") + std::to_string(iwidth) + "x" + std::to_string(iheight) +
           " margins " + std::to_string(left_margin) + "," + std::to_string(top_margin) +
           " pitch " + std::to_string(raw_pitch));
    CFAInfo cfa = detect_cfa(raw0);
    Levels levels = get_levels(raw0, cfa);
    // Defer WB and color matrix application until after demosaic
    WhiteBalance wb = get_wb(raw0);
    cv::Mat colorM = get_color_matrix_rgb(raw0);
    const unsigned long filters0 = raw0.imgdata.idata.filters;
    unsigned short* firstRaw = raw0.imgdata.rawdata.raw_image;
    if (!firstRaw) {
      report("raw_image null");
      write_error(error_buf, error_buf_len, "LibRaw returned null raw_image pointer");
      raw0.recycle();
      return 7;
    }
    report("raw_image ok");

    if (cfa.is_xtrans) {
      raw0.recycle();
      report("xtrans not supported yet");
      write_error(error_buf, error_buf_len, "X-Trans raw-domain path not yet implemented");
      return 6;
    }

    // Allocate SR mosaic (temporarily set to 1x to avoid OOM; upgrade to 2x later)
    const int upscale = 1;
    const int hiW = iwidth * upscale;
    const int hiH = iheight * upscale;
    cv::Mat mosaicSum = cv::Mat::zeros(hiH, hiW, CV_32F);
    cv::Mat mosaicCnt = cv::Mat::zeros(hiH, hiW, CV_32S);

    // Build small reference from raw mosaic and deposit first frame at zero shift
    report("seed first begin");
    {
      cv::Mat refMono(iheight, iwidth, CV_32F);
      for (int ry = 0; ry < iheight; ++ry) {
        const int srcRow = (ry + top_margin) * raw_pitch + left_margin;
        float* prow = refMono.ptr<float>(ry);
        for (int rx = 0; rx < iwidth; ++rx) {
          const unsigned short rv = firstRaw[srcRow + rx];
          const int cidx = bayer_color_at(raw0, cfa, ry, rx);
          float black = levels.black[cidx];
          float norm = (float(rv) - black) / (std::max)(1.0f, levels.white - black);
          if (norm < 0.f) norm = 0.f; if (norm > 1.f) norm = 1.f;
          prow[rx] = norm;
          const double tx = rx * upscale;
          const double ty = ry * upscale;
          splat_bilinear_cfa(mosaicSum, mosaicCnt, filters0, cfa.cdesc, top_margin, left_margin, upscale, tx, ty, norm, cidx);
        }
      }
      scale = 1.0;
      if (iwidth > maxW) {
        scale = static_cast<double>(maxW) / (double)iwidth;
        cv::resize(refMono, refSmall, cv::Size(), scale, scale, cv::INTER_AREA);
      } else {
        refSmall = refMono;
      }
      smallWidths[0] = refSmall.cols;
      report("decoded 1/" + std::to_string(input_count));
      report("seed first done");
    }
    raw0.recycle();

    // Process remaining frames
    for (int i = 1; i < input_count; ++i) {
      report(std::string("open ") + input_paths[i]);

      // Open raw and deposit
      LibRaw raw;
      if (int rc = raw.open_file(input_paths[i]); rc != LIBRAW_SUCCESS) {
        write_error(error_buf, error_buf_len, std::string("LibRaw open failed: ") + libraw_strerror(rc));
        return 4;
      }
      int rc2 = raw.unpack();
      if (rc2 != LIBRAW_SUCCESS) {
        write_error(error_buf, error_buf_len, std::string("LibRaw unpack failed: ") + libraw_strerror(rc));
        raw.recycle();
        return 4;
      }
      CFAInfo cfa_i = detect_cfa(raw);
      if (!cfa_i.is_bayer) {
        raw.recycle();
        write_error(error_buf, error_buf_len, "Mixed sensor types in sequence (X-Trans not supported yet)");
        return 6;
      }
      unsigned short* data = raw.imgdata.rawdata.raw_image;
      const int iw = raw.imgdata.sizes.iwidth;
      const int ih = raw.imgdata.sizes.iheight;
      const int tp = raw.imgdata.sizes.top_margin;
      const int lp = raw.imgdata.sizes.left_margin;
      const int pitch = raw.imgdata.sizes.raw_width;
      Levels lv_i = get_levels(raw, cfa_i);

      // Build small grayscale preview from raw mosaic for alignment
      cv::Mat curSmall;
      {
        cv::Mat mono(ih, iw, CV_32F);
        for (int ry = 0; ry < ih; ++ry) {
          const int srcRow = (ry + tp) * pitch + lp;
          float* prow = mono.ptr<float>(ry);
          for (int rx = 0; rx < iw; ++rx) {
            const unsigned short rv = data[srcRow + rx];
            const int cidx = bayer_color_at(raw, cfa_i, ry, rx);
            float black = lv_i.black[cidx];
            float norm = (float(rv) - black) / std::max(1.0f, lv_i.white - black);
            if (norm < 0.f) norm = 0.f; if (norm > 1.f) norm = 1.f;
            prow[rx] = norm;
          }
        }
        if (scale != 1.0) cv::resize(mono, curSmall, cv::Size(), scale, scale, cv::INTER_AREA);
        else curSmall = mono;
      }
      smallWidths[i] = curSmall.cols;
      cv::Point2d shiftSmall = cv::phaseCorrelate(refSmall, curSmall);
      smallShifts[i] = shiftSmall;
      report("aligned " + std::to_string(i+1) + "/" + std::to_string(input_count));

      const double ratio = static_cast<double>(iwidth) / static_cast<double>(smallWidths[i]);
      const double dx_full = shiftSmall.x * ratio; // in raw pixel units
      const double dy_full = shiftSmall.y * ratio;

      const double sx = dx_full * upscale;
      const double sy = dy_full * upscale;
      for (int ry = 0; ry < ih; ++ry) {
        const int srcRow = (ry + tp) * pitch + lp;
        for (int rx = 0; rx < iw; ++rx) {
          const unsigned short rv = data[srcRow + rx];
          const int cidx = bayer_color_at(raw, cfa_i, ry, rx);
          float black = lv_i.black[cidx];
          float norm = (float(rv) - black) / (std::max)(1.0f, lv_i.white - black);
          if (norm < 0.f) norm = 0.f; if (norm > 1.f) norm = 1.f;
          const double tx = rx * upscale + sx;
          const double ty = ry * upscale + sy;
          splat_bilinear_cfa(mosaicSum, mosaicCnt, filters0, cfa.cdesc, top_margin, left_margin, upscale, tx, ty, norm, cidx);
        }
      }
      raw.recycle();
      report("decoded " + std::to_string(i+1) + "/" + std::to_string(input_count));
    }

    // Finalize mosaic averages and fill holes
    report("finalize begin");
    cv::Mat mosaic32(hiH, hiW, CV_32F, cv::Scalar(0));
    for (int y = 0; y < hiH; ++y) {
      const float* ps = mosaicSum.ptr<float>(y);
      const int* pc = mosaicCnt.ptr<int>(y);
      float* pm = mosaic32.ptr<float>(y);
      for (int x = 0; x < hiW; ++x) {
        const int c = pc[x];
        pm[x] = (c > 0) ? (ps[x] / (float)c) : std::numeric_limits<float>::quiet_NaN();
      }
    }
    // Simple hole fill: average valid neighbors (3x3) iterated twice
    for (int iter = 0; iter < 2; ++iter) {
      cv::Mat filled = mosaic32.clone();
      for (int y = 0; y < mosaic32.rows; ++y) {
        float* pfo = filled.ptr<float>(y);
        for (int x = 0; x < mosaic32.cols; ++x) {
          float v = mosaic32.at<float>(y, x);
          if (!std::isnan(v)) { pfo[x] = v; continue; }
          double sumN = 0.0; int cntN = 0;
          for (int dy = -1; dy <= 1; ++dy) {
            int yy = y + dy; if (yy < 0 || yy >= mosaic32.rows) continue;
            for (int dx = -1; dx <= 1; ++dx) {
              int xx = x + dx; if (xx < 0 || xx >= mosaic32.cols) continue;
              float vn = mosaic32.at<float>(yy, xx);
              if (!std::isnan(vn)) { sumN += vn; cntN++; }
            }
          }
          if (cntN > 0) pfo[x] = (float)(sumN / cntN);
        }
      }
      mosaic32 = std::move(filled);
    }
    for (int y = 0; y < mosaic32.rows; ++y) {
      float* pm = mosaic32.ptr<float>(y);
      for (int x = 0; x < mosaic32.cols; ++x) if (std::isnan(pm[x])) pm[x] = 0.f;
    }

    // Demosaic via OpenCV using detected Bayer code
    report("demosaic begin");
    cv::Mat mosaic16;
    mosaic32.convertTo(mosaic16, CV_16U, 65535.0);
    cv::Mat demosaiced16;
    cv::demosaicing(mosaic16, demosaiced16, cfa.cv_bayer_code);

    // Convert to float for WB and color matrix
    cv::Mat demosaicedF;
    demosaiced16.convertTo(demosaicedF, CV_32FC3, 1.0 / 65535.0);
    // OpenCV outputs BGR; convert to RGB for matrix math
    cv::Mat demosaicedRGB;
    cv::cvtColor(demosaicedF, demosaicedRGB, cv::COLOR_BGR2RGB);

    // Apply camera white balance after demosaic
    if (wb.mul[0] != 1.f || wb.mul[1] != 1.f || wb.mul[2] != 1.f) {
      std::vector<cv::Mat> chs(3);
      cv::split(demosaicedRGB, chs);
      chs[0] *= wb.mul[0]; // R
      chs[1] *= wb.mul[1]; // G
      chs[2] *= wb.mul[2]; // B
      cv::merge(chs, demosaicedRGB);
    }

    // Apply color matrix (camera->RGB)
    if (!colorM.empty()) {
      cv::Mat reshaped = demosaicedRGB.reshape(1, hiH * hiW); // Nx3 (RGB)
      cv::Mat transformed;
      cv::gemm(reshaped, colorM.t(), 1.0, cv::Mat(), 0.0, transformed);
      demosaicedRGB = transformed.reshape(3, hiH);
    }

    // Clamp and write TIFF in BGR for imwrite
    cv::Mat clamped; cv::max(demosaicedRGB, cv::Scalar(0.f,0.f,0.f), clamped);
    cv::min(clamped, cv::Scalar(1.f,1.f,1.f), clamped);
    cv::Mat out16RGB; clamped.convertTo(out16RGB, CV_16UC3, 65535.0);
    cv::Mat out16BGR; cv::cvtColor(out16RGB, out16BGR, cv::COLOR_RGB2BGR);
    std::vector<int> params = { cv::IMWRITE_TIFF_COMPRESSION, 5 };
    report("write begin");
    if (!cv::imwrite(output_path, out16BGR, params)) {
      write_error(error_buf, error_buf_len, "Failed to write output image");
      return 5;
    }
    report("merged frames");
    report("wrote output");
    report("return 0");
    return 0;
  } catch (const std::exception& e) {
    write_error(error_buf, error_buf_len, std::string("Exception: ") + e.what());
    return 9;
  } catch (...) {
    write_error(error_buf, error_buf_len, "Unknown exception");
    return 10;
  }
}



