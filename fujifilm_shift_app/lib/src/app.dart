import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/theme/app_theme.dart";
import "core/providers/theme_provider.dart";
import "features/camera/presentation/pages/camera_dashboard_page.dart";
import "features/home/presentation/pages/home_page.dart";
import "features/settings/presentation/pages/settings_page.dart";

class FujifilmShiftApp extends ConsumerWidget {
  const FujifilmShiftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: "Fujifilm Shift",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const HomePage(),
      routes: <String, Object Function(dynamic context)>{
        "/home": (context) => const HomePage(),
        "/camera": (context) => const CameraDashboardPage(),
        "/settings": (context) => const SettingsPage(),
      },
    );
  }
}
