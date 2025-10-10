import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/core/providers/theme_provider.dart';
import 'src/core/services/window_size_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize shared preferences for theme persistence
  SharedPreferences prefs = await SharedPreferences.getInstance();

  // Initialize window manager for desktop platforms
  await WindowSizeService.initialize();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FujifilmShiftApp(),
    ),
  );
}
