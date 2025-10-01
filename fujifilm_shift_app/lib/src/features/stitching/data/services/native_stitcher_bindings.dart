import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi show DynamicLibrary;

class _NativeStitcherLibrary {
  static DynamicLibrary? _lib;
  static bool _attempted = false;
  static String? lastError;

  static DynamicLibrary? get library {
    if (_attempted) return _lib;
    _attempted = true;
    _lib = _load();
    return _lib;
  }


  static DynamicLibrary? _load() {
    try {
      // 0) Environment override
      final envPath = Platform.environment['FUJI_STITCH_DLL_PATH'];
      if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
        try {
          return DynamicLibrary.open(envPath);
        } catch (e) {
          lastError = 'Failed to load native stitcher at env path $envPath: $e';
        }
      }

      // 1) Try alongside the executable
      final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
      final exePath = p.join(exeDir.path, _dllName);
      if (File(exePath).existsSync()) {
        try {
          try { _Win32.setDllDirectory(exeDir.path); } catch (_) {}
          return DynamicLibrary.open(exePath);
        } catch (e) {
          lastError = 'Failed to load native stitcher at $exePath: $e';
        }
      }

      // 1b) Try common paths relative to the current working directory (dart run)
      final cwd = Directory.current.path;
      final cwdCandidates = <String>[
        // Prefer local copy next to CWD (user build step copies here)
        p.join(cwd, _dllName),
        // Prefer freshly built native DLL with matching vcpkg dependencies
        p.join(p.join(p.join(p.join(cwd, 'native'), 'build'), 'Release'), _dllName),
        p.join(p.join(p.join(cwd, 'native'), 'build'), _dllName),
        // Fall back to SDK copy last (may have conflicting deps)
        p.join(p.join(cwd, 'sdk'), _dllName),
      ];
      for (final abs in cwdCandidates) {
        if (File(abs).existsSync()) {
          try {
            try { _Win32.setDllDirectory(p.dirname(abs)); } catch (_) {}
            return DynamicLibrary.open(abs);
          } catch (e) {
            lastError = 'Failed to load native stitcher at $abs: $e';
          }
        }
      }

      // 2) Try project-local known locations (dev workflow), searching from a guessed repo root
      final candidates = <String>[
        // relative to repo root
        'fujifilm_shift_app/native/build/Release/' + _dllName,
        'fujifilm_shift_app/native/build/' + _dllName,
        'fujifilm_shift_app/' + _dllName,
        'fujifilm_shift_app/sdk/' + _dllName,
        'sdk/' + _dllName,
      ];
      // dev exe lives at build/windows/x64/runner/{Debug,Release}/
      // climb up five levels to repo root
      final up1 = Directory(p.join(exeDir.path, '..')).absolute.path;
      final up2 = Directory(p.join(up1, '..')).absolute.path;
      final up3 = Directory(p.join(up2, '..')).absolute.path;
      final up4 = Directory(p.join(up3, '..')).absolute.path;
      final up5 = Directory(p.join(up4, '..')).absolute.path;

      for (final rel in candidates) {
        final abs = p.join(up5, rel);
        if (File(abs).existsSync()) {
          try {
            if (Platform.isWindows) {
              try { _Win32.setDllDirectory(p.dirname(abs)); } catch (_) {}
            }
            return DynamicLibrary.open(abs);
          } catch (e) {
            lastError = 'Failed to load native stitcher at $abs: $e';
          }
        }
      }

      lastError ??= 'Native stitcher $_dllName not found';
      return null;
    } catch (e) {
      lastError = 'Unexpected native stitcher load error: $e';
      return null;
    }
  }

  static String get _dllName {
    if (Platform.isWindows) return 'fuji_stitcher.dll';
    if (Platform.isMacOS) return 'libfuji_stitcher.dylib';
    return 'libfuji_stitcher.so';
  }
}

// C signature (proposed):
// int FS_StitchFujiPixelShift(const char* output_path,
//                             const char** input_paths,
//                             int input_count,
//                             const char* options_json,
//                             char* error_buf,
//                             int error_buf_len);
typedef FS_StitchFujiPixelShift = Int32 Function(
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> inputPaths,
  Int32 inputCount,
  Pointer<Utf8> optionsJson,
  Pointer<Utf8> errorBuf,
  Int32 errorBufLen,
);

typedef Dart_FS_StitchFujiPixelShift = int Function(
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> inputPaths,
  int inputCount,
  Pointer<Utf8> optionsJson,
  Pointer<Utf8> errorBuf,
  int errorBufLen,
);

class NativeStitchResult {
  final bool success;
  final String? error;
  const NativeStitchResult(this.success, this.error);
}

class NativeStitcher {
  static Dart_FS_StitchFujiPixelShift? _stitchFn;
  static String? get lastError => _NativeStitcherLibrary.lastError;

  static bool get isAvailable {
    final lib = _NativeStitcherLibrary.library;
    if (lib == null) return false;
    _ensureLoaded(lib);
    return _stitchFn != null;
  }

  static void _ensureLoaded(DynamicLibrary lib) {
    if (_stitchFn != null) return;
    try {
      _stitchFn = lib
          .lookup<NativeFunction<FS_StitchFujiPixelShift>>('FS_StitchFujiPixelShift')
          .asFunction<Dart_FS_StitchFujiPixelShift>();
    } catch (e) {
      _NativeStitcherLibrary.lastError =
          'Missing FS_StitchFujiPixelShift symbol: $e';
    }
  }

  static Future<NativeStitchResult> combineFujiPixelShift(
    List<String> rafFiles,
    String outputPath, {
    String optionsJson = '{}',
  }) async {
    final lib = _NativeStitcherLibrary.library;
    if (lib == null) {
      return NativeStitchResult(false, _NativeStitcherLibrary.lastError);
    }
    _ensureLoaded(lib);
    if (_stitchFn == null) {
      return const NativeStitchResult(false, 'Native stitcher function not available');
    }

    // Prepare native arguments
    final outputPtr = outputPath.toNativeUtf8();
    final optionsPtr = optionsJson.toNativeUtf8();
    final errorBufLen = 4096;
    final errorBuf = calloc<Uint8>(errorBufLen);

    late Pointer<Pointer<Utf8>> inputsPtr;
    final inputPtrs = <Pointer<Utf8>>[];
    try {
      inputsPtr = calloc<Pointer<Utf8>>(rafFiles.length);
      for (var i = 0; i < rafFiles.length; i++) {
        final p = rafFiles[i].toNativeUtf8();
        inputPtrs.add(p);
        inputsPtr[i] = p;
      }

      final rc = _stitchFn!(outputPtr, inputsPtr, rafFiles.length, optionsPtr, errorBuf.cast<Utf8>(), errorBufLen);
      if (rc == 0) {
        return const NativeStitchResult(true, null);
      } else {
        final err = errorBuf.cast<Utf8>().toDartString();
        return NativeStitchResult(false, err.isEmpty ? 'Native stitcher error code $rc' : err);
      }
    } catch (e) {
      return NativeStitchResult(false, e.toString());
    } finally {
      calloc.free(outputPtr);
      calloc.free(optionsPtr);
      calloc.free(errorBuf);
      for (final p in inputPtrs) {
        calloc.free(p);
      }
      calloc.free(inputsPtr);
    }
  }

  // Synchronous variant for Isolate.run (must not return a Future or capture
  // non-sendable objects). Performs the same work as combineFujiPixelShift.
  static NativeStitchResult combineFujiPixelShiftSync(
    List<String> rafFiles,
    String outputPath, {
    String optionsJson = '{}',
  }) {
    final lib = _NativeStitcherLibrary.library;
    if (lib == null) {
      return NativeStitchResult(false, _NativeStitcherLibrary.lastError);
    }
    _ensureLoaded(lib);
    if (_stitchFn == null) {
      return const NativeStitchResult(false, 'Native stitcher function not available');
    }

    final outputPtr = outputPath.toNativeUtf8();
    final optionsPtr = optionsJson.toNativeUtf8();
    final errorBufLen = 4096;
    final errorBuf = calloc<Uint8>(errorBufLen);

    late Pointer<Pointer<Utf8>> inputsPtr;
    final inputPtrs = <Pointer<Utf8>>[];
    try {
      inputsPtr = calloc<Pointer<Utf8>>(rafFiles.length);
      for (var i = 0; i < rafFiles.length; i++) {
        final p = rafFiles[i].toNativeUtf8();
        inputPtrs.add(p);
        inputsPtr[i] = p;
      }

      final rc = _stitchFn!(outputPtr, inputsPtr, rafFiles.length, optionsPtr, errorBuf.cast<Utf8>(), errorBufLen);
      if (rc == 0) {
        return const NativeStitchResult(true, null);
      } else {
        final err = errorBuf.cast<Utf8>().toDartString();
        return NativeStitchResult(false, err.isEmpty ? 'Native stitcher error code $rc' : err);
      }
    } catch (e) {
      return NativeStitchResult(false, e.toString());
    } finally {
      calloc.free(outputPtr);
      calloc.free(optionsPtr);
      calloc.free(errorBuf);
      for (final p in inputPtrs) {
        calloc.free(p);
      }
      calloc.free(inputsPtr);
    }
  }
}

// Local path utilities without importing 'package:path/path.dart' to avoid new deps here.
class p {
  static String dirname(String path) => File(path).parent.path;
  static String join(String a, String b) => a + Platform.pathSeparator + b;
  static String absolute(String path) => File(path).absolute.path;
}

// Minimal Win32 SetDllDirectory binding to prefer colocated dependencies
class _Win32 {
  static void setDllDirectory(String dir) {
    if (!Platform.isWindows) return;
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final SetDllDirectoryW = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('SetDllDirectoryW');
    final wdir = dir.toNativeUtf16();
    try { SetDllDirectoryW(wdir); } finally { calloc.free(wdir); }
  }
}


