import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

import "src/app.dart";
import "src/core/theme/app_theme.dart";
import "src/core/providers/theme_provider.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize shared preferences for theme persistence
  var prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: <dynamic>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FujifilmShiftApp(),
    ),
  );
}
