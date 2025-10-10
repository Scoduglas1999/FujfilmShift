import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Provider<SharedPreferences> sharedPreferencesProvider = Provider<SharedPreferences>((ProviderRef<SharedPreferences> ref) {
  throw UnimplementedError();
});

final StateNotifierProvider<ThemeNotifier, ThemeMode> themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((StateNotifierProviderRef<ThemeNotifier, ThemeMode> ref) {
  SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});

class ThemeNotifier extends StateNotifier<ThemeMode> {

  ThemeNotifier(this._prefs) : super(ThemeMode.system) {
    _loadTheme();
  }
  final SharedPreferences _prefs;

  static const String _themeKey = 'theme_mode';

  Future<void> _loadTheme() async {
    int themeIndex = _prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    state = ThemeMode.values[themeIndex];
  }

  Future<void> setTheme(ThemeMode theme) async {
    state = theme;
    await _prefs.setInt(_themeKey, theme.index);
  }

  void toggleTheme() {
    ThemeMode currentTheme = state;
    ThemeMode newTheme;

    switch (currentTheme) {
      case ThemeMode.light:
        newTheme = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        newTheme = ThemeMode.system;
        break;
      case ThemeMode.system:
        newTheme = ThemeMode.light;
        break;
    }

    setTheme(newTheme);
  }
}
