import 'dart:async';
import 'dart:io';
import 'native_stitcher_bindings.dart';
import 'dart:convert';
import 'dart:isolate';

// Top-level isolate entry to avoid capturing non-sendable objects
NativeStitchResult _stitchIsolateEntry(List<dynamic> args) {
  final files = (args[0] as List).cast<String>();
  final outPath = args[1] as String;
  final options = args[2] as String;
  return NativeStitcher.combineFujiPixelShiftSync(files, outPath, optionsJson: options);
}

// Spawn entry: args = [SendPort, List<String> files, String out, String options]
void _stitchSpawn(List<dynamic> args) {
  final send = args[0] as SendPort;
  final files = (args[1] as List).cast<String>();
  final outPath = args[2] as String;
  final options = args[3] as String;
  final res = NativeStitcher.combineFujiPixelShiftSync(files, outPath, optionsJson: options);
  send.send({'success': res.success, 'error': res.error});
}

/// Result of a Pixel Shift stitching job.
class PixelShiftStitchResult {
  final bool success;
  final String? outputPath;
  final String? logPath;
  final String? error;

  const PixelShiftStitchResult({
    required this.success,
    this.outputPath,
    this.logPath,
    this.error,
  });
}

/// Service stub for stitching Fujifilm Pixel Shift sequences (16 RAF frames).
///
/// This class provides a single integration point for a future native combiner
/// (LibRaw/OpenCV-based) or an external CLI tool. It validates inputs, manages
/// output directories and logs, and invokes the configured stitcher.
class StitchingService {
  /// Optional path to an external stitcher CLI, configured by the user.
  /// Example placeholders: RawTherapee CLI (if it adds Fuji Pixel Shift),
  /// a custom `fuji-stitcher.exe`, etc.
  final String? externalStitcherPath;

  StitchingService({this.externalStitcherPath});

  /// Stitches a Fuji Pixel Shift sequence.
  ///
  /// - [rafFiles]: 16 RAF file paths in capture order.
  /// - [outputDir]: destination directory for the final DNG/TIFF and logs.
  /// - [expectedFrames]: default 16; adjust if fewer-frames mode is used.
  Future<PixelShiftStitchResult> stitchFujiPixelShift(
    List<String> rafFiles, {
    required String outputDir,
    int expectedFrames = 16,
    void Function(int percent, String message)? onProgress,
  }) async {
    try {
      if (rafFiles.isEmpty) {
        return const PixelShiftStitchResult(
          success: false,
          error: 'No RAF files provided for stitching',
        );
      }

      // Ensure output directory exists
      final outDir = Directory(outputDir);
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }

      // Validate RAF files exist
      final validRafs = <String>[];
      for (final path in rafFiles) {
        if (File(path).existsSync()) {
          validRafs.add(path);
        }
      }
      if (validRafs.length < (expectedFrames / 2).ceil()) {
        return PixelShiftStitchResult(
          success: false,
          error:
              'Insufficient RAF files for stitching. Found ${validRafs.length}, expected ~$expectedFrames.',
        );
      }

      // Prepare log file
      final logPath = _timestampedPath(outputDir, prefix: 'stitch', ext: 'log');
      final logSink = File(logPath).openWrite(mode: FileMode.writeOnlyAppend);
      void log(String msg) {
        final line = '[Stitch] ${DateTime.now().toIso8601String()}  ' + msg;
        logSink.writeln(line);
      }

      try {
        log('Starting stitch job with ${validRafs.length} RAF files');

        // First, try native stitcher if available
        final outputPathNative = _timestampedPath(outputDir, prefix: 'PixelShift', ext: 'tiff');
        final progressPath = _timestampedPath(outputDir, prefix: 'stitch_progress', ext: 'txt');
        if (NativeStitcher.isAvailable) {
          log('Attempting native stitcher...');
          // Log where the DLL was loaded from if possible
          if (NativeStitcher.lastError != null) {
            log('Native loader note: ' + NativeStitcher.lastError!);
          }
          final optionsJson = jsonEncode({
            'progress_path': progressPath,
          });
          // Start lightweight progress watcher
          Timer? progressTimer;
          int lastLines = 0;
          int lastPercent = 0;
          void emit(int p, String m) {
            if (p < 0) p = 0; if (p > 100) p = 100;
            if (p != lastPercent) {
              lastPercent = p;
              if (onProgress != null) onProgress(p, m);
            }
          }
          progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
            try {
              final f = File(progressPath);
              if (!await f.exists()) return;
              final lines = await f.readAsLines();
              if (lines.length == lastLines) return;
              for (var i = lastLines; i < lines.length; i++) {
                final line = lines[i].trim();
                if (line.isEmpty) continue;
                final dec = RegExp(r'^decoded\s+(\d+)/(\d+)$');
                final al = RegExp(r'^aligned\s+(\d+)/(\d+)$');
                final m1 = dec.firstMatch(line);
                final m2 = al.firstMatch(line);
                if (m1 != null) {
                  final cur = int.parse(m1.group(1)!);
                  final tot = int.parse(m1.group(2)!);
                  final pct = ((cur / tot) * 40).clamp(0, 40).toInt();
                  emit(pct, 'Decoding $cur/$tot');
                } else if (m2 != null) {
                  final cur = int.parse(m2.group(1)!);
                  final tot = int.parse(m2.group(2)!);
                  final pct = 40 + (((cur - 1) / (tot - 1)) * 45).clamp(0, 45).toInt();
                  emit(pct, 'Aligning $cur/$tot');
                } else if (line == 'merged frames') {
                  emit(90, 'Merging');
                } else if (line == 'wrote output') {
                  emit(100, 'Writing output');
                }
              }
              lastLines = lines.length;
            } catch (_) {}
          });

          // Run native stitch in a background isolate via spawn (no closures sent)
          late NativeStitchResult native;
          try {
            final filesCopy = List<String>.from(validRafs);
            final outCopy = String.fromCharCodes(outputPathNative.codeUnits);
            final optCopy = String.fromCharCodes(optionsJson.codeUnits);
            final rp = ReceivePort();
            await Isolate.spawn(_stitchSpawn, [rp.sendPort, filesCopy, outCopy, optCopy], errorsAreFatal: true);
            final msg = await rp.first as Map;
            native = NativeStitchResult(msg['success'] as bool, msg['error'] as String?);
          } finally {
            progressTimer.cancel();
          }
          if (native.success && File(outputPathNative).existsSync()) {
            await logSink.flush();
            return PixelShiftStitchResult(
              success: true,
              outputPath: outputPathNative,
              logPath: logPath,
            );
          } else {
            log('Native stitcher unavailable or failed: ' + (native.error ?? 'unknown'));
            // Append progress file (if any) to log for troubleshooting
            try {
              if (File(progressPath).existsSync()) {
                final prog = await File(progressPath).readAsString();
                for (final line in prog.split('\n')) {
                  if (line.trim().isEmpty) continue;
                  log('[PROG] ' + line.trim());
                }
              }
            } catch (_) {}
          }
        } else {
          log('Native stitcher not available: ' + (NativeStitcher.lastError ?? 'unknown'));
        }

        // If an external stitcher is configured and exists, call it.
        final external = externalStitcherPath ?? _detectExternalStitcher();
        if (external != null && File(external).existsSync()) {
          // Generic invocation contract (to be adapted per tool):
          // external --mode fuji-pixelshift --output <file> -- <raf1> <raf2> ...
          final outputPath = _timestampedPath(outputDir, prefix: 'PixelShift', ext: 'dng');
          final args = <String>[
            '--mode',
            'fuji-pixelshift',
            '--output',
            outputPath,
            '--expected',
            expectedFrames.toString(),
            '--',
            ...validRafs,
          ];

          log('Invoking external stitcher: ' + external);
          final proc = await Process.start(external, args, runInShell: true);
          proc.stdout.transform(SystemEncoding().decoder).listen((s) => log(s.trim()));
          proc.stderr.transform(SystemEncoding().decoder).listen((s) => log('[ERR] ' + s.trim()));
          final code = await proc.exitCode;
          log('External stitcher exited with code $code');

          await logSink.flush();

          if (code == 0 && File(outputPath).existsSync()) {
            return PixelShiftStitchResult(
              success: true,
              outputPath: outputPath,
              logPath: logPath,
            );
          }

          return PixelShiftStitchResult(
            success: false,
            logPath: logPath,
            error: 'External stitcher failed with code $code',
          );
        }

        // No external stitcher configured: write manifest and return guidance.
        final manifestPath = _timestampedPath(outputDir, prefix: 'manifest', ext: 'txt');
        final manifest = File(manifestPath).openWrite();
        manifest.writeln('Fuji Pixel Shift Stitch Manifest');
        manifest.writeln('Expected frames: $expectedFrames');
        manifest.writeln('Frames:');
        for (final p in validRafs) {
          manifest.writeln(p);
        }
        await manifest.close();

        await logSink.flush();
        return PixelShiftStitchResult(
          success: false,
          logPath: logPath,
          error:
              'No external stitcher configured. Configure a combiner CLI and retry.',
        );
      } finally {
        await logSink.close();
      }
    } catch (e) {
      return PixelShiftStitchResult(success: false, error: e.toString());
    }
  }

  String? _detectExternalStitcher() {
    // Placeholder: attempt common install paths or env var.
    final fromEnv = Platform.environment['FUJI_STITCH_CLI_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    // Example: try RawTherapee-cli (if it ever supports Fuji Pixel Shift)
    final rtWin = 'C\\\Program Files\\\RawTherapee\\\rawtherapee-cli.exe';
    if (File(rtWin).existsSync()) return rtWin;
    return null;
  }

  String _timestampedPath(String dir, {required String prefix, required String ext}) {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = prefix + '_' + ts + '.' + ext;
    return dir + Platform.pathSeparator + fileName;
  }
}


