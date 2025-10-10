import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

class WindowSizeService {
  static const double _minWindowWidth = 800;
  static const double _minWindowHeight = 600;
  static const double _maxWindowWidth = 1920;
  static const double _maxWindowHeight = 1080;

  // Content dimensions based on UI layout analysis
  static const double _homePageContentWidth = 1200;
  static const double _homePageContentHeight = 900;
  static const double _cameraPageContentWidth = 1400;
  static const double _cameraPageContentHeight = 800;
  static const double _settingsPageContentWidth = 1000;
  static const double _settingsPageContentHeight = 700;

  // Padding and margins
  static const double _windowPadding = 32;
  static const double _appBarHeight = 64;

  static Future<void> initialize() async {
    await windowManager.ensureInitialized();

    // Set minimum and maximum window sizes
    await windowManager.setMinimumSize(const Size(_minWindowWidth, _minWindowHeight));
    await windowManager.setMaximumSize(const Size(_maxWindowWidth, _maxWindowHeight));
  }

  static Future<void> adjustWindowSizeForContent(String currentRoute) async {
    final screenSize = await _getScreenSize();
    final contentSize = _getContentSizeForRoute(currentRoute);

    // Calculate required window size
    final requiredSize = _calculateOptimalWindowSize(contentSize, screenSize);

    // Adjust window size
    await windowManager.setSize(requiredSize);

    // Center the window
    await _centerWindow(requiredSize, screenSize);
  }

  static Size _getContentSizeForRoute(String route) {
    switch (route) {
      case '/home':
        return const Size(_homePageContentWidth, _homePageContentHeight);
      case '/camera':
        return const Size(_cameraPageContentWidth, _cameraPageContentHeight);
      case '/settings':
        return const Size(_settingsPageContentWidth, _settingsPageContentHeight);
      default:
        return const Size(_homePageContentWidth, _homePageContentHeight);
    }
  }

  static Future<Size> _getScreenSize() async {
    // Get primary screen size using screen_retriever
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      return Size(display.size.width, display.size.height);
    } catch (e) {
      // Fallback to standard desktop sizes if platform method fails
      return const Size(1920, 1080); // Common desktop resolution
    }
  }

  static Size _calculateOptimalWindowSize(Size contentSize, Size screenSize) {
    // Add padding for window decorations and margins
    final paddedContentSize = Size(
      contentSize.width + _windowPadding * 2,
      contentSize.height + _windowPadding * 2 + _appBarHeight,
    );

    // Ensure minimum size
    final windowWidth = paddedContentSize.width.clamp(_minWindowWidth, _maxWindowWidth);
    final windowHeight = paddedContentSize.height.clamp(_minWindowHeight, _maxWindowHeight);

    // If content fits within screen, use content size, otherwise fit to screen
    final finalWidth = windowWidth <= screenSize.width ? windowWidth : screenSize.width * 0.9;
    final finalHeight = windowHeight <= screenSize.height ? windowHeight : screenSize.height * 0.9;

    return Size(finalWidth, finalHeight);
  }

  static Future<void> _centerWindow(Size windowSize, Size screenSize) async {
    final offsetX = (screenSize.width - windowSize.width) / 2;
    final offsetY = (screenSize.height - windowSize.height) / 2;

    await windowManager.setPosition(Offset(offsetX, offsetY));
  }

  static Future<Size> getCurrentWindowSize() async {
    final bounds = await windowManager.getBounds();
    return Size(bounds.size.width, bounds.size.height);
  }

  static Future<void> setWindowSize(Size size) async {
    await windowManager.setSize(size);
  }

  static Future<void> setWindowPosition(Offset offset) async {
    await windowManager.setPosition(offset);
  }
}
