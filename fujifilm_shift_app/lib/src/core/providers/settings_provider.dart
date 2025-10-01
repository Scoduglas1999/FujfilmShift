import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

const String _downloadLocationKey = 'download_location';

/// Provider for download location
final downloadLocationProvider = StateNotifierProvider<DownloadLocationNotifier, String>((ref) {
  return DownloadLocationNotifier();
});

class DownloadLocationNotifier extends StateNotifier<String> {
  DownloadLocationNotifier() : super('') {
    _loadDownloadLocation();
  }

  Future<void> _loadDownloadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_downloadLocationKey);
    
    if (savedPath != null && savedPath.isNotEmpty) {
      state = savedPath;
    } else {
      // Set default to Downloads folder
      state = await _getDefaultDownloadPath();
    }
  }

  Future<String> _getDefaultDownloadPath() async {
    if (Platform.isWindows) {
      final userHome = Platform.environment['USERPROFILE'] ?? '';
      return '$userHome\\Downloads\\FujifilmPixelShift';
    } else if (Platform.isMacOS || Platform.isLinux) {
      final userHome = Platform.environment['HOME'] ?? '';
      return '$userHome/Downloads/FujifilmPixelShift';
    } else {
      // Fallback to app documents directory
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/FujifilmPixelShift';
    }
  }

  Future<void> setDownloadLocation(String path) async {
    state = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadLocationKey, path);
  }

  Future<void> resetToDefault() async {
    final defaultPath = await _getDefaultDownloadPath();
    await setDownloadLocation(defaultPath);
  }
}
