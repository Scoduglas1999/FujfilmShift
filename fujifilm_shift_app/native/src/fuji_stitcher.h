#pragma once

#ifdef _WIN32
#  ifdef FUJI_STITCHER_EXPORTS
#    define FUJI_API __declspec(dllexport)
#  else
#    define FUJI_API __declspec(dllimport)
#  endif
#else
#  define FUJI_API __attribute__((visibility("default")))
#endif

extern "C" {
// Returns 0 on success, non-zero on error.
// Writes human-readable error to error_buf (NUL-terminated).
FUJI_API int FS_StitchFujiPixelShift(
  const char* output_path,
  const char** input_paths,
  int input_count,
  const char* options_json,
  char* error_buf,
  int error_buf_len
);
}




