import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/data/models/camera_models.dart';
import '../../features/camera/data/services/camera_service.dart';

export '../../features/camera/data/services/camera_service.dart' show SDCardFile;

/// Provider for camera state management
final Provider<CameraService> cameraServiceProvider = Provider<CameraService>((ProviderRef<CameraService> ref) {
  // Use the real Fujifilm SDK service (singleton instance)
  return FujifilmCameraService.instance;
});

/// State notifier for camera connection and information
class CameraNotifier extends StateNotifier<CameraState> {

  CameraNotifier(this._cameraService) : super(const CameraState()) {
    initialize();
  }
  final CameraService _cameraService;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _cameraInfoSubscription;
  StreamSubscription? _pixelShiftSubscription;
  bool _isInitialized = false;

  Future<void> initialize() async {
    // Prevent multiple initializations
    if (_isInitialized) {
      return;
    }

    try {
      // Listen to connection status changes
      _connectionSubscription = _cameraService.connectionStatus.listen((ConnectionStatus status) {
        state = state.copyWith(connectionStatus: status);
      });

      // Listen to camera info changes
      _cameraInfoSubscription = _cameraService.cameraInfoStream.listen((CameraInfo? cameraInfo) {
        state = state.copyWith(cameraInfo: cameraInfo);
      });

      // Listen to pixel shift state changes
      _pixelShiftSubscription = _cameraService.pixelShiftState.listen((PixelShiftState pixelShiftState) {
        state = state.copyWith(pixelShiftState: pixelShiftState);
      });

      // Initialize SDK
      final success = await _cameraService.initializeSDK();
      if (success) {
        // Detect available cameras
        await detectCameras();
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

  Future<void> detectCameras() async {
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

  Future<void> startPixelShift(PixelShiftSettings settings, {String? downloadLocation}) async {
    try {
      await _cameraService.startPixelShift(settings, downloadLocation: downloadLocation);
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

  Future<bool> takeTestShot() async {
    try {
      return await _cameraService.takeTestShot();
    } catch (e) {
      return false;
    }
  }

  Future<List<SDCardFile>> listSDCardFiles() async {
    try {
      return await _cameraService.listSDCardFiles();
    } catch (e) {
      return [];
    }
  }

  Future<bool> downloadFileFromSDCard(int fileIndex, String destinationPath) async {
    try {
      return await _cameraService.downloadFileFromSDCard(fileIndex, destinationPath);
    } catch (e) {
      return false;
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

  const CameraState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.availableCameras = const <CameraInfo>[],
    this.cameraInfo,
    this.pixelShiftState = const PixelShiftState(),
    this.isLoading = false,
    this.error,
  });
  final ConnectionStatus connectionStatus;
  final List<CameraInfo> availableCameras;
  final CameraInfo? cameraInfo;
  final PixelShiftState pixelShiftState;
  final bool isLoading;
  final ConnectionError? error;

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
  }) => CameraState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      availableCameras: availableCameras ?? this.availableCameras,
      cameraInfo: cameraInfo ?? this.cameraInfo,
      pixelShiftState: pixelShiftState ?? this.pixelShiftState,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
}

/// Provider for camera state
final StateNotifierProvider<CameraNotifier, CameraState> cameraProvider = StateNotifierProvider<CameraNotifier, CameraState>((StateNotifierProviderRef<CameraNotifier, CameraState> ref) {
  final cameraService = ref.watch(cameraServiceProvider);
  return CameraNotifier(cameraService);
});

/// Provider for checking if pixel shift is supported
final FutureProvider<bool> pixelShiftSupportProvider = FutureProvider<bool>((FutureProviderRef<bool> ref) async {
  final cameraNotifier = ref.watch(cameraProvider.notifier);
  return cameraNotifier.isPixelShiftSupported();
});

/// Provider for pixel shift state
final Provider<PixelShiftState> pixelShiftStateProvider = Provider<PixelShiftState>((ProviderRef<PixelShiftState> ref) {
  final state = ref.watch(cameraProvider);
  return state.pixelShiftState;
});

/// Provider for available cameras
final Provider<List<CameraInfo>> availableCamerasProvider = Provider<List<CameraInfo>>((ProviderRef<List<CameraInfo>> ref) {
  final state = ref.watch(cameraProvider);
  return state.availableCameras;
});

/// Provider for connected camera info
final Provider<CameraInfo?> connectedCameraProvider = Provider<CameraInfo?>((ProviderRef<CameraInfo?> ref) {
  final state = ref.watch(cameraProvider);
  return state.cameraInfo;
});

/// Provider for connection status
final Provider<ConnectionStatus> connectionStatusProvider = Provider<ConnectionStatus>((ProviderRef<ConnectionStatus> ref) {
  final state = ref.watch(cameraProvider);
  return state.connectionStatus;
});

/// Provider for loading state
final Provider<bool> cameraLoadingProvider = Provider<bool>((ProviderRef<bool> ref) {
  final state = ref.watch(cameraProvider);
  return state.isLoading;
});

/// Provider for error state
final Provider<ConnectionError?> cameraErrorProvider = Provider<ConnectionError?>((ProviderRef<ConnectionError?> ref) {
  final state = ref.watch(cameraProvider);
  return state.error;
});
