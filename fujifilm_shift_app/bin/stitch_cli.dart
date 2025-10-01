import 'dart:io';
import '../lib/src/features/stitching/data/services/stitching_service.dart';

void printUsage() {
  stdout.writeln('Usage: dart run bin/stitch_cli.dart --input <folder> [--out <folder>]');
  stdout.writeln('Notes:');
  stdout.writeln('  - Place fuji_stitcher.dll in sdk/ (project root) or set FUJI_STITCH_DLL_PATH');
}

Future<int> main(List<String> args) async {
  String? input;
  String? out;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--input' && i + 1 < args.length) {
      input = args[++i];
    } else if (a == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else if (a == '-h' || a == '--help') {
      printUsage();
      return 0;
    }
  }

  if (input == null) {
    printUsage();
    return 2;
  }

  final inDir = Directory(input!);
  if (!inDir.existsSync()) {
    stderr.writeln('Input folder does not exist: $input');
    return 2;
  }

  // Gather RAFs
  final rafs = inDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toUpperCase().endsWith('.RAF'))
      .map((f) => f.path)
      .toList()
    ..sort();

  if (rafs.length < 2) {
    stderr.writeln('Found only ${rafs.length} RAF files in $input');
    return 2;
  }

  final outDir = out ?? input!;
  stdout.writeln('Stitching ${rafs.length} RAFs');
  stdout.writeln('Output folder: $outDir');

  final stitcher = StitchingService();
  int lastPct = -1;
  final result = await stitcher.stitchFujiPixelShift(
    rafs,
    outputDir: outDir,
    expectedFrames: rafs.length,
    onProgress: (p, m) {
      if (p != lastPct) {
        stdout.writeln('[${p.toString().padLeft(3)}%] $m');
        lastPct = p;
      }
    },
  );

  if (result.success) {
    stdout.writeln('Success: ${result.outputPath}');
    return 0;
  } else {
    stderr.writeln('Failed: ${result.error ?? 'unknown error'}');
    if (result.logPath != null) {
      stderr.writeln('See log: ${result.logPath}');
    }
    return 1;
  }
}


