# Native Fuji Pixel Shift Stitcher

Builds a shared library exposing `FS_StitchFujiPixelShift` to combine Fujifilm Pixel Shift sequences.

## Dependencies

- OpenCV (core, imgproc, imgcodecs)
- LibRaw

Recommended: use vcpkg

```
vcpkg install opencv libraw
```

## Build

```
cd fujifilm_shift_app/native
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="<path-to-vcpkg>/scripts/buildsystems/vcpkg.cmake" -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

Artifacts:

- Windows: `build/Release/fuji_stitcher.dll`
- macOS: `build/libfuji_stitcher.dylib`
- Linux: `build/libfuji_stitcher.so`

Copy the built library to one of:

- Next to the app executable
- `fujifilm_shift_app/sdk/`
- `fujifilm_shift_app/native/build/`

## C API

```
int FS_StitchFujiPixelShift(
  const char* output_path,
  const char** input_paths,
  int input_count,
  const char* options_json,
  char* error_buf,
  int error_buf_len
);
```

Returns 0 on success; non-zero on error and writes a human-readable message to `error_buf`.

## Notes

Current implementation:

- Decodes RAF via LibRaw to 16-bit bitmap, converts to float32 linear RGB
- Estimates sub-pixel shifts via phase correlation on luminance
- Warps frames and averages in float
- Writes 16-bit TIFF

Planned improvements:

- Robust motion masking and outlier rejection
- Per-channel chroma reconstruction strategies
- DNG output with metadata
- Multi-threading and tiling for very large frames


