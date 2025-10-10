import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/window_size_service.dart';
import 'features/camera/presentation/pages/camera_dashboard_page.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';

class FujifilmShiftApp extends ConsumerStatefulWidget {
  const FujifilmShiftApp({super.key});

  @override
  ConsumerState<FujifilmShiftApp> createState() => _FujifilmShiftAppState();
}

class _FujifilmShiftAppState extends ConsumerState<FujifilmShiftApp> with WindowListener {
  String _currentRoute = '/home';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // Set up post-frame callback for initial window sizing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adjustWindowSize();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResize() {
    // Optional: Handle window resize events if needed
  }

  @override
  Widget build(BuildContext context) {
    ThemeMode themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Fujifilm Shift',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const HomePage(),
      navigatorObservers: <NavigatorObserver>[_WindowSizeObserver(_onRouteChanged)],
      routes: <String, Widget Function(BuildContext)>{
        '/home': (BuildContext context) => const HomePage(),
        '/camera': (BuildContext context) => const CameraDashboardPage(),
        '/settings': (BuildContext context) => const SettingsPage(),
      },
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == '/camera') {
          return MaterialPageRoute(
            builder: (BuildContext context) => const CameraDashboardPage(),
          );
        }
        return null;
      },
    );
  }

  void _onRouteChanged(String route) {
    if (_currentRoute != route) {
      _currentRoute = route;
      _adjustWindowSize();
    }
  }

  Future<void> _adjustWindowSize() async {
    try {
      await WindowSizeService.adjustWindowSizeForContent(_currentRoute);
    } catch (e) {
      // Handle errors silently - window sizing is not critical
      debugPrint('Failed to adjust window size: $e');
    }
  }
}

class _WindowSizeObserver extends NavigatorObserver {

  _WindowSizeObserver(this.onRouteChanged);
  final Function(String) onRouteChanged;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _notifyRouteChange(route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _notifyRouteChange(previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _notifyRouteChange(newRoute);
    }
  }

  void _notifyRouteChange(Route? route) {
    if (route?.settings.name != null) {
      onRouteChanged(route!.settings.name!);
    }
  }
}
