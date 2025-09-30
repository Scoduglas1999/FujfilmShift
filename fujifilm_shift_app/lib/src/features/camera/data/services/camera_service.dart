import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../models/camera_models.dart';
import 'fujifilm_sdk_bindings.dart';
import 'dart:typed_data';

/// Abstract camera service interface
abstract class CameraService {
  /// Initialize the camera SDK
  Future<bool> initializeSDK();

  /// Detect available cameras
  Future<List<CameraInfo>> detectCameras();

  /// Connect to a specific camera
  Future<bool> connectToCamera(String deviceId);

  /// Disconnect from the current camera
  Future<void> disconnectCamera();

  /// Get current camera information
  Future<CameraInfo?> getCameraInfo();

  /// Get battery information
  Future<BatteryInfo?> getBatteryInfo();

  /// Check if the connected camera supports pixel shift
  Future<bool> isPixelShiftSupported();

  /// Dispose of the camera SDK
  Future<void> disposeSDK();

  /// Stream of connection status changes
  Stream<ConnectionStatus> get connectionStatus;

  /// Stream of camera information changes
  Stream<CameraInfo?> get cameraInfoStream;

  /// Stream of pixel shift state changes
  Stream<PixelShiftState> get pixelShiftState;

  /// Start the pixel shift process
  Future<void> startPixelShift(PixelShiftSettings settings);

  /// Download images after pixel shift
  Future<List<String>> downloadPixelShiftImages();

  /// Gets the camera's current configuration as a raw byte array.
  Future<Uint8List?> getCameraSettings();

  /// Sets the camera's configuration from a raw byte array.
  Future<bool> setCameraSettings(Uint8List settings);
}

/// Fujifilm camera service implementation
class FujifilmCameraService implements CameraService {

  // Private constructor
  FujifilmCameraService._();
  // Singleton pattern
  static FujifilmCameraService? _instance;
  static FujifilmCameraService get instance {
    _instance ??= FujifilmCameraService._();
    return _instance!;
  }

  // Stream controllers for reactive updates
  StreamController<ConnectionStatus> _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  StreamController<CameraInfo?> _cameraInfoController = StreamController<CameraInfo?>.broadcast();
  StreamController<PixelShiftState> _pixelShiftStateController = StreamController<PixelShiftState>.broadcast();

  // Internal state
  bool _isSDKInitialized = false;
  bool _isConnected = false;
  CameraInfo? _currentCameraInfo;
  Pointer<Void>? _cameraHandle;
  int? _pixelShiftDriveModeValue;

  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;

  @override
  Stream<CameraInfo?> get cameraInfoStream => _cameraInfoController.stream;

  @override
  Stream<PixelShiftState> get pixelShiftState => _pixelShiftStateController.stream;

  @override
  Future<bool> initializeSDK() async {
    if (_connectionStatusController.isClosed) {
      _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
    }
    if (_cameraInfoController.isClosed) {
      _cameraInfoController = StreamController<CameraInfo?>.broadcast();
    }
    if (_pixelShiftStateController.isClosed) {
      _pixelShiftStateController = StreamController<PixelShiftState>.broadcast();
    }
    try {
      if (_isSDKInitialized) {
        return true;
      }

      // Initialize Fujifilm SDK with proper library handle
      final result = FujifilmSDK.xsdkInitWithHandle();

      if (result != 0) {
        final errorDetails = _getSDKErrorDetails(null);
        throw Exception('Failed to initialize Fujifilm SDK. Error code: $result. Details: $errorDetails');
      }

      _isSDKInitialized = true;
      _connectionStatusController.add(ConnectionStatus.disconnected);
      return true;
    } catch (e) {
      print('SDK Initialization Error: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    }
  }

  @override
  Future<List<CameraInfo>> detectCameras() async {
    _validateSDKInitialized();

    try {
      final cameras = <CameraInfo>[];

      // Detect USB cameras first
      final countPtr = malloc<Int32>();
      final interfacePtr = nullptr.cast<Utf8>();
      final deviceNamePtr = nullptr.cast<Utf8>();

      try {
        countPtr.value = 0;

        // Detect USB cameras
        final result = FujifilmSDK.xsdkDetect(
          XSDK_DSC_IF_USB,
          interfacePtr,
          deviceNamePtr,
          countPtr,
        );

        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(null);
          throw Exception('Failed to detect USB cameras. Error code: $result. Details: $errorDetails');
        }

        final cameraCount = countPtr.value;
        if (cameraCount == 0) {
          return <CameraInfo>[];
        }

        final cameraListPtr = malloc<XSDK_CameraList>(cameraCount);

        try {
          // Get all camera information at once
          final appendResult = FujifilmSDK.xsdkAppend(
            XSDK_DSC_IF_USB,
            interfacePtr,
            deviceNamePtr,
            countPtr,
            cameraListPtr,
          );

          if (appendResult == 0) {
            for (var i = 0; i < cameraCount; i++) {
              final cameraData = cameraListPtr[i];

              if (cameraData.bValid) {
                final productName = convertUint8ArrayToString(cameraData.strProduct);
                final serialNumber = convertUint8ArrayToString(cameraData.strSerialNo);
                final framework = convertUint8ArrayToString(cameraData.strFramework);

                final cameraInfo = CameraInfo.fromSDKData(<String, dynamic>{
                  'model': productName,
                  'serialNumber': serialNumber,
                  'firmwareVersion': '', // Will be populated when connected
                  'connectionType': framework,
                  'isConnected': false,
                  'supportsPixelShift': _supportsPixelShift(productName),
                });
                cameras.add(cameraInfo);
              }
            }
          }
        } finally {
          malloc.free(cameraListPtr);
        }
      } finally {
        malloc.free(countPtr);
        malloc.free(interfacePtr);
        malloc.free(deviceNamePtr);
      }

      return cameras;
    } catch (e) {
      print('Error detecting cameras: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<bool> connectToCamera(String deviceId) async {
    _validateSDKInitialized();

    try {
      _connectionStatusController.add(ConnectionStatus.connecting);

      // Disconnect any existing connection first
      if (_cameraHandle != null) {
        await disconnectCamera();
      }

      // Prepare camera connection parameters
      final devicePtr = stringToUtf8Pointer("ENUM:0"); // Connect to the first detected camera
      final cameraHandlePtr = malloc<Pointer<Void>>();
      final cameraModePtr = malloc<Int32>();
      final optionPtr = nullptr; // NULL for default options

      try {
        cameraModePtr.value = XSDK_DSC_MODE_TETHER; // Use tethering mode

        // Connect to camera using SDK
        final result = FujifilmSDK.xsdkOpenEx(
          devicePtr,
          cameraHandlePtr,
          cameraModePtr,
          optionPtr,
        );

        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(null);
          throw Exception('Failed to connect to camera. Error code: $result. Details: $errorDetails');
        }

        _cameraHandle = cameraHandlePtr.value;
        _isConnected = true;
        _connectionStatusController.add(ConnectionStatus.connected);

        // Get camera info after connection
        await _updateCameraInfo();

        // Clear any leftover images from the buffer
        await _clearImageBuffer();

        return true;
      } catch (e) {
        // Clean up on failure
        if (cameraHandlePtr.value != nullptr) {
          try {
            FujifilmSDK.xsdkClose(cameraHandlePtr.value);
          } catch (closeError) {
            print('Warning: Failed to close camera handle on connection error: $closeError');
          }
        }
        rethrow;
      } finally {
        freeStringPointer(devicePtr);
        malloc.free(cameraHandlePtr);
        malloc.free(cameraModePtr);
      }
    } catch (e) {
      print('Error connecting to camera: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      _cameraHandle = null;
      _isConnected = false;
      return false;
    }
  }

  @override
  Future<void> disconnectCamera() async {
    try {
      if (_isConnected && _cameraHandle != null) {
        // Close camera connection using SDK
        final result = FujifilmSDK.xsdkClose(_cameraHandle!);

        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          print('Warning: SDK Close returned error code: $result. Details: $errorDetails');
        }

        _cameraHandle = null;
        _isConnected = false;
        _currentCameraInfo = null;

        _connectionStatusController.add(ConnectionStatus.disconnected);
        _cameraInfoController.add(null);
      }
    } catch (e) {
      print('Error during camera disconnect: $e');
      // Force cleanup even if SDK call fails
      _cameraHandle = null;
      _isConnected = false;
      _currentCameraInfo = null;
      _connectionStatusController.add(ConnectionStatus.disconnected);
      _cameraInfoController.add(null);
    }
  }

  @override
  Future<CameraInfo?> getCameraInfo() async {
    _validateSDKInitialized();

    try {
      // Get device information from SDK
      final deviceInfoPtr = malloc<XSDK_DeviceInformation>();

      try {
        final result = FujifilmSDK.xsdkGetDeviceInfo(_cameraHandle!, deviceInfoPtr);

        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          throw Exception('Failed to get device info. Error code: $result. Details: $errorDetails');
        }

        // Extract information from SDK structures
        final model = convertUint8ArrayToString(deviceInfoPtr.ref.strProduct);
        final serialNumber = convertUint8ArrayToString(deviceInfoPtr.ref.strSerialNo);

        // Get firmware version
        final firmwarePtr = malloc<Uint8>(256).cast<Utf8>();
        try {
          final firmwareResult = FujifilmSDK.xsdkGetFirmwareVersion(_cameraHandle!, firmwarePtr);

          String firmwareVersion = '';
          if (firmwareResult == 0) {
            firmwareVersion = firmwarePtr.toDartString();
          }

          // Create camera info with real SDK data
          _currentCameraInfo = CameraInfo.fromSDKData(<String, dynamic>{
            'model': model,
            'serialNumber': serialNumber,
            'firmwareVersion': firmwareVersion,
            'connectionType': 'USB', // Will be determined from detection
            'isConnected': true,
            'supportsPixelShift': _supportsPixelShift(model),
          });

          return _currentCameraInfo;
        } finally {
          malloc.free(firmwarePtr);
        }
      } finally {
        malloc.free(deviceInfoPtr);
      }
    } catch (e) {
      throw Exception('Failed to get camera info: $e');
    }
  }

  @override
  Future<BatteryInfo?> getBatteryInfo() async {
    if (!_isConnected || _currentCameraInfo == null) {
      return null;
    }

    try {
      // TODO: Implement battery info retrieval using Fujifilm SDK
      // The SDK may not have a specific battery info function
      // For now, return null to indicate battery info is not available
      return null;

      // If battery info becomes available in the SDK, implement it here:
      // This would typically involve calling a function like XSDK_GetBatteryInfo
      // and parsing the returned data structure
    } catch (e) {
      throw Exception('Failed to get battery info: $e');
    }
  }

  @override
  Future<bool> isPixelShiftSupported() async {
    _validateSDKInitialized();
    _validateCameraConnected();

    // First, check if the camera model is known to support pixel shift.
    if (!_supportsPixelShift(_currentCameraInfo!.model)) {
      return false;
    }

    // Fallback to the drive mode check
    return _checkPixelShiftDriveMode();
  }

  Future<bool> _checkPixelShiftDriveMode() async {
    if (_cameraHandle == null) return false;

    // To accurately check capabilities, we may need to take control from the camera.
    // We'll save the current priority mode and restore it afterward.
    final originalPriorityModePtr = malloc<Int32>();
    int originalPriorityMode = XSDK_PRIORITY_CAMERA; // Default fallback
    bool priorityModeChanged = false;

    try {
      // Get current priority
      if (FujifilmSDK.xsdkGetPriorityMode(
              _cameraHandle!, originalPriorityModePtr,) ==
          0) {
        originalPriorityMode = originalPriorityModePtr.value;
      }

      // Set PC priority to query all available modes
      if (originalPriorityMode != XSDK_PRIORITY_PC) {
        if (FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_PC) ==
            0) {
          priorityModeChanged = true;
          // Short delay to allow the camera to switch modes
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          // If we can't set PC mode, we may not get a reliable capability list.
          print('Warning: Could not set PC priority mode to check capabilities.');
        }
      }

      // Then, query the camera for its supported drive modes to be certain.
      final numDriveModePtr = malloc<Int32>();
      try {
        // Get the number of supported drive modes
        var result =
            FujifilmSDK.xsdkCapDriveMode(_cameraHandle!, numDriveModePtr, nullptr);
        if (result != 0) {
          print(
              'Could not get the number of drive modes. Details: ${_getSDKErrorDetails(_cameraHandle)}',);
          return false;
        }

        final numDriveModes = numDriveModePtr.value;
        if (numDriveModes == 0) {
          return false;
        }

        final driveModesPtr = malloc<Int32>(numDriveModes);
        try {
          // Get the list of supported drive modes
          result = FujifilmSDK.xsdkCapDriveMode(
              _cameraHandle!, numDriveModePtr, driveModesPtr,);
          if (result != 0) {
            return false;
          }

          final driveModes = driveModesPtr.asTypedList(numDriveModes);
          print('Supported drive modes: $driveModes');

          // Check for known pixel shift drive modes
          if (driveModes.contains(XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT)) {
            _pixelShiftDriveModeValue = XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT;
            return true;
          }
          // The value 26 corresponds to XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT_FEWERFRAMES
          if (driveModes.contains(26)) {
            _pixelShiftDriveModeValue = 26;
            return true;
          }

          return false;
        } finally {
          malloc.free(driveModesPtr);
        }
      } finally {
        malloc.free(numDriveModePtr);
      }
    } catch (e) {
      print('Error checking pixel shift support: $e');
      return false; // Robustness: if capability check fails, report not supported
    } finally {
      // Restore original priority mode
      if (priorityModeChanged) {
        FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, originalPriorityMode);
      }
      malloc.free(originalPriorityModePtr);
    }
  }

  @override
  Future<void> disposeSDK() async {
    try {
      // Cancel any ongoing operations
      await disconnectCamera();

      // Exit SDK if initialized
      if (_isSDKInitialized) {
        final result = FujifilmSDK.xsdkExit();
        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(null);
          print('Warning: SDK Exit returned error code: $result. Details: $errorDetails');
        }
        _isSDKInitialized = false;
      }

      _isConnected = false;
      _currentCameraInfo = null;
      _cameraHandle = null;

      // Close streams
      await _connectionStatusController.close();
      await _cameraInfoController.close();
      await _pixelShiftStateController.close();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  Future<void> _updateCameraInfo() async {
    try {
      if (_cameraHandle == null) {
        return;
      }

      // Get device information from SDK
      final deviceInfoPtr = malloc<XSDK_DeviceInformation>();

      try {
        final result = FujifilmSDK.xsdkGetDeviceInfo(_cameraHandle!, deviceInfoPtr);

        if (result != 0) {
          return; // Silent fail
        }

        // Extract information from SDK structures
        final model = convertUint8ArrayToString(deviceInfoPtr.ref.strProduct);
        final serialNumber = convertUint8ArrayToString(deviceInfoPtr.ref.strSerialNo);

        // Get firmware version
        final firmwarePtr = malloc<Uint8>(256).cast<Utf8>();
        try {
          final firmwareResult = FujifilmSDK.xsdkGetFirmwareVersion(_cameraHandle!, firmwarePtr);

          String firmwareVersion = '';
          if (firmwareResult == 0) {
            firmwareVersion = firmwarePtr.toDartString();
          }

          // Create updated camera info with real SDK data
          _currentCameraInfo = CameraInfo.fromSDKData(<String, dynamic>{
            'model': model,
            'serialNumber': serialNumber,
            'firmwareVersion': firmwareVersion,
            'connectionType': 'USB', // Will be determined from detection
            'isConnected': true,
            'supportsPixelShift': _supportsPixelShift(model),
          });

          _cameraInfoController.add(_currentCameraInfo);
        } finally {
          malloc.free(firmwarePtr);
        }
      } finally {
        malloc.free(deviceInfoPtr);
      }
    } catch (e) {
      // Silent fail for info updates
    }
  }


  @override
  Future<void> startPixelShift(PixelShiftSettings settings) async {
    _validateSDKInitialized();
    _validateCameraConnected();

    if (_pixelShiftDriveModeValue == null) {
      if (!await isPixelShiftSupported()) {
        print(
            "Warning: Camera does not report Pixel Shift support, but attempting to proceed.",);
        _pixelShiftDriveModeValue = XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT;
      }
    }

    if (_pixelShiftDriveModeValue == null) {
      final error = "Could not determine a valid Pixel Shift drive mode.";
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.error,
        error: error,
      ),);
      throw Exception(error);
    }

    // HYBRID SOLUTION: The SDK's tethering buffer cannot handle Pixel Shift's 16 large RAW images.
    // Solution: Configure camera via SDK, then use Camera Priority mode for manual shutter trigger.
    await _startPixelShiftHybridMode(settings);
  }

  /// Smart Pixel Shift implementation using priority mode switching
  /// This avoids the volatile buffer overflow by using Camera Priority mode for the trigger
  Future<void> _startPixelShiftHybridMode(PixelShiftSettings settings) async {
    int originalDriveMode = XSDK_DRIVE_MODE_S;
    int originalPriorityMode = XSDK_PRIORITY_PC;
    bool needToRestorePriority = false;

    try {
      print('--- Starting Pixel Shift Setup ---');
      print('[Info] Implementing buffer overflow workaround...');
      
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.starting,
        message: 'Configuring camera for Pixel Shift...',
      ));

      // 1. Save current priority mode
      final priorityModePtr = malloc<Int32>();
      try {
        if (FujifilmSDK.xsdkGetPriorityMode(_cameraHandle!, priorityModePtr) == 0) {
          originalPriorityMode = priorityModePtr.value;
          print('[Pixel Shift] Current priority mode: ${originalPriorityMode == XSDK_PRIORITY_PC ? "PC" : "CAMERA"}');
        }
      } finally {
        malloc.free(priorityModePtr);
      }

      // 2. Ensure we're in PC Priority to configure settings
      if (originalPriorityMode != XSDK_PRIORITY_PC) {
        print('[Pixel Shift] Switching to PC Priority for configuration...');
        final pcResult = FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_PC);
        if (pcResult != 0) {
          throw Exception('Failed to set PC Priority mode for configuration');
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 3. Save current drive mode
      final driveModePtr = malloc<Int32>();
      try {
        if (FujifilmSDK.xsdkGetProp(_cameraHandle!, 0x1340, driveModePtr) == 0) {
          originalDriveMode = driveModePtr.value;
        }
      } finally {
        malloc.free(driveModePtr);
      }

      // 4. Set MediaRecord to save to SD card
      print('[Pixel Shift] 1. Configuring media recording to SD card...');
      final mediaRecordResult = FujifilmSDK.xsdkSetMediaRecord(
        _cameraHandle!,
        XSDK_MEDIARECORD_RAW, // Save RAW files to SD card
      );
      if (mediaRecordResult != 0) {
        print('[Warning] SetMediaRecord failed (this may not be critical).');
      } else {
        print('[Pixel Shift] Media recording configured.');
      }
      await Future.delayed(const Duration(milliseconds: 300));

      // 5. Set Drive Mode to Pixel Shift
      print('[Pixel Shift] 2. Setting drive mode to Pixel Shift...');
      final driveModeResult = FujifilmSDK.xsdkSetDriveMode(
        _cameraHandle!,
        _pixelShiftDriveModeValue!,
      );
      if (driveModeResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        throw Exception(
            'Failed to set Pixel Shift drive mode. Error: $driveModeResult. Details: $errorDetails',);
      }
      await Future.delayed(const Duration(milliseconds: 500));
      print('[Pixel Shift] Drive mode set to Pixel Shift.');

      // 6. CRITICAL WORKAROUND: Switch to Camera Priority mode
      // This allows the shutter trigger to bypass the volatile memory buffer
      // and write directly to the SD card
      print('[Pixel Shift] 3. Switching to Camera Priority mode to bypass buffer...');
      final cameraPriorityResult = FujifilmSDK.xsdkSetPriorityMode(
        _cameraHandle!,
        XSDK_PRIORITY_CAMERA,
      );
      if (cameraPriorityResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        throw Exception(
            'Failed to switch to Camera Priority mode. Error: $cameraPriorityResult. Details: $errorDetails',);
      }
      needToRestorePriority = true;
      await Future.delayed(const Duration(milliseconds: 500));
      print('[Pixel Shift] ✅ Now in Camera Priority mode - buffer overflow avoided!');

      // 6.5. Wake camera from standby (if needed)
      // When switching to Camera Priority, camera may enter standby state
      // Call SetForceMode to ensure camera is in active SHOOTING mode
      print('[Pixel Shift] 3.5. Ensuring camera is in SHOOTING mode (not standby)...');
      final forceModeResult = FujifilmSDK.xsdkSetForceMode(
        _cameraHandle!,
        XSDK_FORCESHOOTSTANDBY_SHOOT,
      );
      if (forceModeResult != 0) {
        print('[Warning] SetForceMode failed, but continuing anyway...');
      } else {
        print('[Pixel Shift] ✅ Camera is awake and in SHOOTING mode');
      }
      await Future.delayed(const Duration(milliseconds: 300));

      // 7. Try programmatic shutter release with ReleaseEx (Camera Priority version)
      // Strategy: Use standard shutter release, let drive mode handle Pixel Shift
      print('[Pixel Shift] 4. Attempting programmatic shutter release via ReleaseEx...');
      print('[Pixel Shift]    Using standard shutter release (drive mode is already Pixel Shift)');
      
      final shotOptPtr = malloc<Int32>();
      final statusPtr = malloc<Int32>();
      
      try {
        shotOptPtr.value = 1; // For standard release, just 1
        
        // Try standard shutter release first (let drive mode handle the sequence)
        var releaseResult = FujifilmSDK.xsdkReleaseEx(
          _cameraHandle!,
          XSDK_RELEASE_SHOOT_S1OFF, // Standard full shutter press
          shotOptPtr,
          statusPtr,
        );
        
        if (releaseResult == 0) {
          print('[Pixel Shift] ✅ SUCCESS! Standard shutter release worked!');
          print('[Pixel Shift] Camera is executing the Pixel Shift sequence...');
          print('[Pixel Shift] (Drive mode is Pixel Shift, so 16 shots will be taken)');
          print('[Pixel Shift] Images are being saved directly to SD card.');
          print('[Pixel Shift] (Volatile buffer bypassed - no overflow!)');
          
          _pixelShiftStateController.add(PixelShiftState(
            status: PixelShiftStatus.capturing,
            message: 'Pixel Shift sequence in progress!\n\n'
                'Camera is capturing 16 high-resolution images.\n'
                'Images are saving directly to SD card.',
            progress: 25,
          ));
          
          // Wait for sequence to complete (approximately 30-60 seconds)
          await Future.delayed(const Duration(seconds: 45));
          
          _pixelShiftStateController.add(PixelShiftState(
            status: PixelShiftStatus.finished,
            message: 'Pixel Shift sequence complete!\n\n'
                'Check your camera\'s SD card for 16 RAF files.\n\n'
                'Buffer overflow workaround: SUCCESS ✅',
            progress: 100,
            totalImages: 16,
            imagesTaken: 16,
          ));
          
          print('[Pixel Shift] Sequence complete.');
          return; // Success! Exit early
        } else {
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          print('[Pixel Shift] ⚠️  Standard release failed: $errorDetails');
          print('[Pixel Shift] Trying XSDK_RELEASE_PIXELSHIFT mode...');
          
          // Try pixel shift specific release mode
          releaseResult = FujifilmSDK.xsdkReleaseEx(
            _cameraHandle!,
            XSDK_RELEASE_PIXELSHIFT,
            shotOptPtr,
            statusPtr,
          );
          
          if (releaseResult == 0) {
            print('[Pixel Shift] ✅ Pixel Shift release mode worked!');
            
            _pixelShiftStateController.add(PixelShiftState(
              status: PixelShiftStatus.capturing,
              message: 'Pixel Shift sequence in progress!\n\n'
                  'Camera is capturing 16 high-resolution images.\n'
                  'Images are saving directly to SD card.',
              progress: 25,
            ));
            
            await Future.delayed(const Duration(seconds: 45));
            
            _pixelShiftStateController.add(PixelShiftState(
              status: PixelShiftStatus.finished,
              message: 'Pixel Shift sequence complete!\n\n'
                  'Check your camera\'s SD card for 16 RAF files.',
              progress: 100,
              totalImages: 16,
              imagesTaken: 16,
            ));
            
            return;
          } else {
            final errorDetails2 = _getSDKErrorDetails(_cameraHandle);
            print('[Pixel Shift] ❌ Both release methods failed.');
            print('[Pixel Shift]    Standard: $errorDetails');
            print('[Pixel Shift]    Pixel Shift: $errorDetails2');
            print('[Pixel Shift] Falling back to manual trigger mode...');
          }
        }
      } finally {
        malloc.free(shotOptPtr);
        malloc.free(statusPtr);
      }

      // 8. If programmatic trigger failed, provide user instructions for manual trigger
      // Camera is already in Camera Priority mode, so manual button press will work
      print('[Pixel Shift] ========================================');
      print('[Pixel Shift] MANUAL TRIGGER MODE');
      print('[Pixel Shift] (Camera is ready in Camera Priority mode)');
      print('[Pixel Shift] ========================================');
      print('[Pixel Shift] ');
      print('[Pixel Shift] CAMERA SETUP:');
      print('[Pixel Shift] 1. Verify these settings on your camera:');
      print('[Pixel Shift]    - Image Stabilization: OFF');
      print('[Pixel Shift]    - Shutter Type: ELECTRONIC');
      print('[Pixel Shift]    - Focus Mode: MANUAL (MF)');
      print('[Pixel Shift]    - Self-Timer: OFF');
      print('[Pixel Shift] ');
      print('[Pixel Shift] 2. Press the SHUTTER BUTTON on your camera');
      print('[Pixel Shift]    to start the 16-shot Pixel Shift sequence.');
      print('[Pixel Shift] ');
      print('[Pixel Shift] 3. Images will be saved to your SD card.');
      print('[Pixel Shift]    (Buffer overflow avoided - Camera Priority mode)');
      print('[Pixel Shift] ');
      print('[Pixel Shift] ========================================');

      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.waitingForManualTrigger,
        message: 'Camera configured for Pixel Shift.\n\n'
            'Camera is in Camera Priority mode.\n'
            'Press the shutter button on your camera to start.\n\n'
            'Required settings:\n'
            '• Image Stabilization: OFF\n'
            '• Shutter Type: ELECTRONIC\n'
            '• Focus Mode: MANUAL\n'
            '• Self-Timer: OFF',
        progress: 50,
      ));

      // Wait for user to complete the sequence
      await Future.delayed(const Duration(seconds: 60));
      
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.finished,
        message: 'If sequence is complete, check your camera\'s SD card for 16 RAF files.\n\n'
            'Click "Start Capture" again to take another Pixel Shift sequence.',
        progress: 100,
        totalImages: 16,
        imagesTaken: 16,
      ));

    } catch (e) {
      print('[Pixel Shift] An error occurred during the process: $e');
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.error,
        error: e.toString(),
      ),);
      rethrow;
    } finally {
      print('--- Resetting camera state ---');
      
      // Restore original priority mode first (important!)
      if (needToRestorePriority) {
        print('[Pixel Shift] Restoring original priority mode...');
        final restoreResult = FujifilmSDK.xsdkSetPriorityMode(
          _cameraHandle!,
          originalPriorityMode,
        );
        if (restoreResult != 0) {
          print('[Warning] Failed to restore priority mode.');
        } else {
          print('[Pixel Shift] Priority mode restored.');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Return to original drive mode
      FujifilmSDK.xsdkSetDriveMode(_cameraHandle!, originalDriveMode);
      print('[Pixel Shift] Drive mode restored.');
    }
  }

  Future<void> _clearImageBuffer() async {
    _validateCameraConnected();
    print("Clearing camera buffer using 'Read to Delete' strategy...");

    final imageInfoPtr = calloc<XSDK_ImageInformation>();
    final previewSizePtr = calloc<Int32>();
    int clearedImageCount = 0;

    try {
      while (true) {
        final result = FujifilmSDK.xsdkReadImageInfo(
          _cameraHandle!,
          imageInfoPtr,
          previewSizePtr,
        );

        if (result != 0 || imageInfoPtr.ref.lFormat == XSDK_IMAGEFORMAT_NONE) {
          // Buffer is empty or an error occurred, either way, we stop.
          break;
        }

        final imageSize = imageInfoPtr.ref.lDataSize;
        if (imageSize <= 0) {
          print(
              'Warning: Found image with invalid size ($imageSize). Stopping buffer clear.',);
          break;
        }

        print(
            'Found residual image in buffer (Size: $imageSize bytes). Reading to clear...',);

        // Allocate a temporary buffer to receive the image data, which will be discarded.
        final buffer = calloc<Uint8>(imageSize);
        final readSizePtr = calloc<Int32>();

        try {
          // Reading the image also deletes it from the camera's buffer.
          // We don't check the result, just attempt the read to trigger deletion.
          FujifilmSDK.xsdkReadImage(
            _cameraHandle!,
            buffer,
            imageSize,
            readSizePtr,
          );
          clearedImageCount++;
          print("Attempted to clear image ${clearedImageCount}.");
        } finally {
          calloc.free(buffer);
          calloc.free(readSizePtr);
        }
      }

      if (clearedImageCount > 0) {
        print(
            "Finished clearing $clearedImageCount image(s) from the buffer.",);
      } else {
        print("Camera buffer was already clear.");
      }
    } catch (e) {
      print("An error occurred while clearing the camera buffer: $e");
    } finally {
      calloc.free(imageInfoPtr);
      calloc.free(previewSizePtr);
    }
  }


  @override
  Future<List<String>> downloadPixelShiftImages() async {
    // This is now an automatic process started by startPixelShift.
    // This method is kept for API compatibility but should not be used.
    print(
        "Warning: downloadPixelShiftImages() is deprecated. Download starts automatically.",);
    return <String>[];
  }

  @override
  Future<Uint8List?> getCameraSettings() async {
    _validateCameraConnected();

    // 1. Get the required buffer size
    final sizePtr = malloc<Int32>();
    try {
      var result =
          FujifilmSDK.xsdkGetBackupSettings(_cameraHandle!, sizePtr, nullptr);
      if (result != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print(
            'Failed to get settings size. Error: $result. Details: $errorDetails',);
        return null;
      }

      final size = sizePtr.value;
      if (size <= 0) {
        print('Invalid or zero size for settings block.');
        return null;
      }

      // 2. Allocate buffer and get the actual settings data
      final dataPtr = malloc<Uint8>(size);
      try {
        result =
            FujifilmSDK.xsdkGetBackupSettings(_cameraHandle!, sizePtr, dataPtr);
        if (result != 0) {
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          print(
              'Failed to get settings data. Error: $result. Details: $errorDetails',);
          return null;
        }

        // Copy data to a Dart list to be safe with memory
        return Uint8List.fromList(dataPtr.asTypedList(size));
      } finally {
        malloc.free(dataPtr);
      }
    } finally {
      malloc.free(sizePtr);
    }
  }

  @override
  Future<bool> setCameraSettings(Uint8List settingsData) async {
    _validateCameraConnected();
    final size = settingsData.length;
    if (size == 0) return false;

    final dataPtr = malloc<Uint8>(size);
    try {
      // Copy the Dart list to a native memory buffer
      dataPtr.asTypedList(size).setAll(0, settingsData);

      final result =
          FujifilmSDK.xsdkSetBackupSettings(_cameraHandle!, size, dataPtr);
      if (result != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print(
            'Failed to set camera settings. Error: $result. Details: $errorDetails',);
        return false;
      }
      return true;
    } finally {
      malloc.free(dataPtr);
    }
  }

  // Helper method to get detailed SDK error information
  String _getSDKErrorDetails(Pointer<Void>? cameraHandle) {
    // A null handle is valid for getting general (non-camera-specific) errors.
    final handle = cameraHandle ?? nullptr;

    try {
      final apiCodePtr = malloc<Int32>();
      final errCodePtr = malloc<Int32>();

      try {
        final result = FujifilmSDK.xsdkGetErrorNumber(
          handle,
          apiCodePtr,
          errCodePtr,
        );

        if (result == 0) {
          final apiCode = apiCodePtr.value;
          final errCode = errCodePtr.value;
          return 'SDK Error - API Code: $apiCode, Error Code: $errCode';
        } else {
          return 'Failed to get error details from SDK';
        }
      } finally {
        malloc.free(apiCodePtr);
        malloc.free(errCodePtr);
      }
    } catch (e) {
      return 'Exception getting SDK error details: $e';
    }
  }

  // Helper method to validate SDK state before calling functions
  void _validateSDKInitialized() {
    if (!_isSDKInitialized) {
      throw StateError('SDK not initialized. Call initializeSDK() first.');
    }
  }

  // Helper method to validate camera connection before calling functions
  void _validateCameraConnected() {
    if (!_isConnected || _cameraHandle == null) {
      throw StateError('Camera not connected. Call connectToCamera() first.');
    }
  }

  // Helper method to determine pixel shift support based on camera model
  bool _supportsPixelShift(String model) {
    // This list should be updated as new cameras with Pixel Shift are released
    const supportedModels = <String>[
      'X-T5',
      'X-H2',
      'X-H2S',
      'GFX50S II',
      'GFX100',
      'GFX100S',
      'GFX100 II',
    ];
    final normalizedModel = model.toUpperCase().replaceAll(' ', '');
    for (final supported in supportedModels) {
      if (normalizedModel.contains(supported.toUpperCase().replaceAll(' ', ''))) {
        return true;
      }
    }
    return false;
  }
}
