import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/data/models/camera_models.dart';
import '../../features/camera/data/services/camera_service.dart';

/// Provider for camera state management
final cameraServiceProvider = Provider<CameraService>((ref) {
  // Use the real Fujifilm SDK service (singleton instance)
  return FujifilmCameraService.instance;
});

/// State notifier for camera connection and information
class CameraNotifier extends StateNotifier<CameraState> {
  final CameraService _cameraService;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _cameraInfoSubscription;
  StreamSubscription? _pixelShiftSubscription;
  bool _isInitialized = false;

  CameraNotifier(this._cameraService) : super(const CameraState()) {
    initialize();
  }

  Future<void> initialize() async {
    // Prevent multiple initializations
    if (_isInitialized) {
      return;
    }

    try {
      // Listen to connection status changes
      _connectionSubscription = _cameraService.connectionStatus.listen((status) {
        state = state.copyWith(connectionStatus: status);
      });

      // Listen to camera info changes
      _cameraInfoSubscription = _cameraService.cameraInfoStream.listen((cameraInfo) {
        state = state.copyWith(cameraInfo: cameraInfo);
      });

      // Listen to pixel shift state changes
      _pixelShiftSubscription = _cameraService.pixelShiftState.listen((pixelShiftState) {
        state = state.copyWith(pixelShiftState: pixelShiftState);
      });

      // Initialize SDK
      final success = await _cameraService.initializeSDK();
      if (success) {
        // Detect available cameras
        await _detectCameras();
      } else {
        state = state.copyWith(
          connectionStatus: ConnectionStatus.error,
          error: ConnectionError.sdkError,
        );
      }

      _isInitialized = true;
    } catch (e) {
      state = state.copyWith(
        connectionStatus: ConnectionStatus.error,
        error: ConnectionError.sdkError,
      );
      _isInitialized = true; // Mark as initialized even on error to prevent retries
    }
  }

  Future<void> _detectCameras() async {
    try {
      state = state.copyWith(isLoading: true);
      final cameras = await _cameraService.detectCameras();
      state = state.copyWith(
        availableCameras: cameras,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ConnectionError.noCameraDetected,
      );
    }
  }

  Future<bool> connectToCamera(String deviceId) async {
    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
      );

      final success = await _cameraService.connectToCamera(deviceId);

      if (success) {
        // Get updated camera info
        final cameraInfo = await _cameraService.getCameraInfo();
        state = state.copyWith(
          cameraInfo: cameraInfo,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: ConnectionError.connectionFailed,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ConnectionError.connectionFailed,
      );
      return false;
    }
  }

  Future<void> disconnectCamera() async {
    try {
      state = state.copyWith(isLoading: true);
      await _cameraService.disconnectCamera();
      state = state.copyWith(
        cameraInfo: null,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ConnectionError.connectionFailed,
      );
    }
  }

  Future<bool> isPixelShiftSupported() async {
    try {
      return await _cameraService.isPixelShiftSupported();
    } catch (e) {
      return false;
    }
  }

  Future<void> startPixelShift(PixelShiftSettings settings) async {
    try {
      await _cameraService.startPixelShift(settings);
    } catch (e) {
      // Error is already handled and pushed to the stream in the service
    }
  }

  Future<void> downloadPixelShiftImages() async {
    try {
      await _cameraService.downloadPixelShiftImages();
    } catch (e) {
      // Error is already handled and pushed to the stream in the service
    }
  }

  Future<void> refreshCameraInfo() async {
    if (state.cameraInfo != null) {
      try {
        final cameraInfo = await _cameraService.getCameraInfo();
        final batteryInfo = await _cameraService.getBatteryInfo();

        state = state.copyWith(
          cameraInfo: cameraInfo?.copyWith(battery: batteryInfo),
        );
      } catch (e) {
        // Silent fail for refresh
      }
    }
  }

  Future<void> retryInitialization() async {
    // Cancel existing subscriptions
    _connectionSubscription?.cancel();
    _cameraInfoSubscription?.cancel();
    _pixelShiftSubscription?.cancel();

    // Reset initialization state
    _isInitialized = false;

    // Clean up SDK
    await _cameraService.disposeSDK();

    // Reinitialize
    await initialize();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _cameraInfoSubscription?.cancel();
    _pixelShiftSubscription?.cancel();
    _cameraService.disposeSDK();
    super.dispose();
  }
}

/// State class for camera information
class CameraState {
  final ConnectionStatus connectionStatus;
  final List<CameraInfo> availableCameras;
  final CameraInfo? cameraInfo;
  final PixelShiftState pixelShiftState;
  final bool isLoading;
  final ConnectionError? error;

  const CameraState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.availableCameras = const [],
    this.cameraInfo,
    this.pixelShiftState = const PixelShiftState(),
    this.isLoading = false,
    this.error,
  });

  bool get isConnected => connectionStatus == ConnectionStatus.connected;
  bool get hasError => error != null;
  bool get hasAvailableCameras => availableCameras.isNotEmpty;

  CameraState copyWith({
    ConnectionStatus? connectionStatus,
    List<CameraInfo>? availableCameras,
    CameraInfo? cameraInfo,
    PixelShiftState? pixelShiftState,
    bool? isLoading,
    ConnectionError? error,
  }) {
    return CameraState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      availableCameras: availableCameras ?? this.availableCameras,
      cameraInfo: cameraInfo ?? this.cameraInfo,
      pixelShiftState: pixelShiftState ?? this.pixelShiftState,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Provider for camera state
final cameraProvider = StateNotifierProvider<CameraNotifier, CameraState>((ref) {
  final cameraService = ref.watch(cameraServiceProvider);
  return CameraNotifier(cameraService);
});

/// Provider for checking if pixel shift is supported
final pixelShiftSupportProvider = FutureProvider<bool>((ref) async {
  final cameraNotifier = ref.watch(cameraProvider.notifier);
  return await cameraNotifier.isPixelShiftSupported();
});

/// Provider for pixel shift state
final pixelShiftStateProvider = Provider<PixelShiftState>((ref) {
  final state = ref.watch(cameraProvider);
  return state.pixelShiftState;
});

/// Provider for available cameras
final availableCamerasProvider = Provider<List<CameraInfo>>((ref) {
  final state = ref.watch(cameraProvider);
  return state.availableCameras;
});

/// Provider for connected camera info
final connectedCameraProvider = Provider<CameraInfo?>((ref) {
  final state = ref.watch(cameraProvider);
  return state.cameraInfo;
});

/// Provider for connection status
final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  final state = ref.watch(cameraProvider);
  return state.connectionStatus;
});

/// Provider for loading state
final cameraLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(cameraProvider);
  return state.isLoading;
});

/// Provider for error state
final cameraErrorProvider = Provider<ConnectionError?>((ref) {
  final state = ref.watch(cameraProvider);
  return state.error;
});
