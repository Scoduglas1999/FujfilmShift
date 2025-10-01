import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../../stitching/data/services/stitching_service.dart';
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
  Future<void> startPixelShift(PixelShiftSettings settings, {String? downloadLocation});

  /// Download images after pixel shift (deprecated - now automatic)
  Future<List<String>> downloadPixelShiftImages();

  /// Download all RAF files from SD card to destination folder
  Future<List<String>> downloadAllRAFFiles(String destinationFolder);

  /// Download images from camera buffer dynamically during pixel shift
  Future<List<String>> downloadImagesFromBuffer(String destinationFolder, {int expectedCount = 16, Duration timeout = const Duration(minutes: 5)});

  /// Gets the camera's current configuration as a raw byte array.
  Future<Uint8List?> getCameraSettings();

  /// Sets the camera's configuration from a raw byte array.
  Future<bool> setCameraSettings(Uint8List settings);

  /// Takes a single test shot
  Future<bool> takeTestShot();

  /// Lists files on camera's SD card
  Future<List<SDCardFile>> listSDCardFiles();

  /// Downloads a file from camera's SD card
  Future<bool> downloadFileFromSDCard(int fileIndex, String destinationPath);
}

/// Model for SD card file information
class SDCardFile {
  final int index;
  final String fileName;
  final int fileSize;
  final bool isFolder;

  SDCardFile({
    required this.index,
    required this.fileName,
    required this.fileSize,
    required this.isFolder,
  });
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
  Future<void> startPixelShift(PixelShiftSettings settings, {String? downloadLocation}) async {
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
    await _startPixelShiftHybridMode(settings, downloadLocation: downloadLocation);
  }

  /// Fixed Pixel Shift implementation - stays in PC Priority, uses manual trigger, saves to SD
  Future<void> _startPixelShiftHybridMode(PixelShiftSettings settings, {String? downloadLocation}) async {
    int originalDriveMode = XSDK_DRIVE_MODE_S;
    int originalMediaRecord = XSDK_MEDIAREC_OFF;

    try {
      print('--- Starting Pixel Shift Setup ---');
      print('[Info] Configuring camera for manual Pixel Shift trigger...');
      
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.starting,
        message: 'Configuring camera for Pixel Shift...',
      ));

      // 1. Save current drive mode
      final driveModePtr = malloc<Int32>();
      try {
        if (FujifilmSDK.xsdkGetProp(_cameraHandle!, 0x1340, driveModePtr) == 0) {
          originalDriveMode = driveModePtr.value;
          print('[Pixel Shift] Saved original drive mode: $originalDriveMode');
        }
      } finally {
        malloc.free(driveModePtr);
      }

      // 2. Save current media record setting
      final mediaRecordPtr = malloc<Int32>();
      try {
        if (FujifilmSDK.xsdkGetMediaRecord(_cameraHandle!, mediaRecordPtr) == 0) {
          originalMediaRecord = mediaRecordPtr.value;
          print('[Pixel Shift] Saved original media record: $originalMediaRecord');
        }
      } finally {
        malloc.free(mediaRecordPtr);
      }

      // 3. Set MediaRecord to RAW so camera writes full-quality files to SD card
      // We will also transfer to PC via the tether buffer in PC Priority
      print('[Pixel Shift] 1. Setting MediaRecord to RAW (write to SD card)...');
      final mediaRecordResult = FujifilmSDK.xsdkSetMediaRecord(
        _cameraHandle!,
        XSDK_MEDIARECORD_RAW,
      );
      if (mediaRecordResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print('[ERROR] Failed to set MediaRecord! Error: $errorDetails');
      } else {
        print('[Pixel Shift] ✅ MediaRecord set to RAW - images will save to SD card');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Set Drive Mode to Pixel Shift
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
      print('[Pixel Shift] ✅ Drive mode set to Pixel Shift.');

      // 5. SWITCH TO CAMERA PRIORITY to allow manual shutter press
      final priorityPtr = malloc<Int32>();
      try {
        var curPriority = XSDK_PRIORITY_PC;
        if (FujifilmSDK.xsdkGetPriorityMode(_cameraHandle!, priorityPtr) == 0) {
          curPriority = priorityPtr.value;
        }
        if (curPriority != XSDK_PRIORITY_CAMERA) {
          final pr = FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_CAMERA);
          if (pr != 0) {
            final errorDetails = _getSDKErrorDetails(_cameraHandle);
            throw Exception('Failed to set Camera Priority mode. Details: $errorDetails');
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } finally {
        malloc.free(priorityPtr);
      }
      print('[Pixel Shift] 3. Camera Priority mode active (manual shutter enabled)');
      print('[Pixel Shift] ✅ Camera configured and ready');

      // 6. Prompt user to press the shutter manually; begin buffer polling afterwards
      print('[Pixel Shift] ========================================');
      print('[Pixel Shift] 🎯 READY - Press the SHUTTER BUTTON on the camera');
      print('[Pixel Shift] ========================================');

      // Begin buffer-based transfer AFTER manual shutter
      if (downloadLocation != null && downloadLocation.isNotEmpty) {
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final sequenceFolder = '$downloadLocation${Platform.pathSeparator}PixelShift_$timestamp';

        _pixelShiftStateController.add(PixelShiftState(
          status: PixelShiftStatus.downloading,
          message: 'Transferring RAF files to PC from camera buffer...\n(Sequence running)',
          progress: 65,
        ));

        // Expect 16 frames for standard Pixel Shift Multi-Shot
        final downloadedFiles = await downloadImagesFromBuffer(
          sequenceFolder,
          expectedCount: 16,
          timeout: const Duration(minutes: 6),
        );

        if (downloadedFiles.isNotEmpty) {
          print('[Pixel Shift] ✅ Buffer transfer complete: ${downloadedFiles.length} files');
          // Attempt stitching
          try {
            final stitcher = StitchingService();
            final result = await stitcher.stitchFujiPixelShift(
              downloadedFiles,
              outputDir: sequenceFolder,
              expectedFrames: 16,
              onProgress: (percent, msg) {
                _pixelShiftStateController.add(PixelShiftState(
                  status: PixelShiftStatus.downloading,
                  message: 'Stitching: ' + msg,
                  progress: percent,
                ));
              },
            );
            if (result.success) {
              print('[Pixel Shift] 🧵 Stitching succeeded: ' + (result.outputPath ?? '')); 
            } else {
              print('[Pixel Shift] 🧵 Stitching not completed: ' + (result.error ?? 'Unknown error'));
            }
          } catch (e) {
            print('[Pixel Shift] 🧵 Stitching error: $e');
          }
          _pixelShiftStateController.add(PixelShiftState(
            status: PixelShiftStatus.finished,
            message: '✅ Pixel Shift Complete!\n\n'
                'Transferred ${downloadedFiles.length} RAF files to:\n'
                '$sequenceFolder\n\n'
                'Files also saved on camera SD card.',
            progress: 100,
            totalImages: downloadedFiles.length,
            imagesTaken: downloadedFiles.length,
            downloadedFiles: downloadedFiles,
          ));
        } else {
          print('[Pixel Shift] ⚠️ No files received from buffer within timeout');
          _pixelShiftStateController.add(PixelShiftState(
            status: PixelShiftStatus.error,
            message: 'No files received from buffer.\n\n'
                '• Ensure PC Priority is active\n'
                '• Try again, or use Browse SD Card to pull files',
            progress: 100,
          ));
        }
      } else {
        print('[Pixel Shift] No download location set; skipping PC transfer');
      }

    } catch (e) {
      print('[Pixel Shift] An error occurred during the process: $e');
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.error,
        error: e.toString(),
      ),);
      rethrow;
    } finally {
      print('--- Resetting camera state ---');
      
      // Switch back to PC Priority mode
      print('[Pixel Shift] Switching back to PC Priority mode...');
      FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_PC);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Restore original media record setting
      print('[Pixel Shift] Restoring original media record setting...');
      FujifilmSDK.xsdkSetMediaRecord(_cameraHandle!, originalMediaRecord);
      
      // Return to original drive mode
      print('[Pixel Shift] Restoring original drive mode...');
      FujifilmSDK.xsdkSetDriveMode(_cameraHandle!, originalDriveMode);
      
      print('[Pixel Shift] ✅ Camera settings restored.');
    }
  }

  Future<void> _clearImageBuffer() async {
    _validateCameraConnected();
    print("Clearing camera buffer using 'Read to Delete' strategy...");

    final imageInfoPtr = calloc<XSDK_ImageInformation>();
    int clearedImageCount = 0;

    try {
      while (true) {
        final result = FujifilmSDK.xsdkReadImageInfo(
          _cameraHandle!,
          imageInfoPtr,
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

        try {
          // Reading the image also deletes it from the camera's buffer.
          // We don't check the result, just attempt the read to trigger deletion.
          FujifilmSDK.xsdkReadImage(
            _cameraHandle!,
            buffer,
            imageSize,
          );
          clearedImageCount++;
          print("Attempted to clear image ${clearedImageCount}.");
        } finally {
          calloc.free(buffer);
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
  Future<List<String>> downloadAllRAFFiles(String destinationFolder) async {
    _validateSDKInitialized();
    _validateCameraConnected();

    print('[Download] Starting RAF file download from SD card...');
    
    final downloadedFiles = <String>[];
    
    try {
      // Create destination folder if it doesn't exist
      final destDir = Directory(destinationFolder);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
        print('[Download] Created destination folder: $destinationFolder');
      }

      // Get list of files on SD card
      final files = await listSDCardFiles();
      print('[Download] Found ${files.length} total files on SD card');

      // Filter for RAF files
      final rafFiles = files.where((file) => 
        !file.isFolder && file.fileName.toUpperCase().endsWith('.RAF')
      ).toList();

      print('[Download] Found ${rafFiles.length} RAF files to download');

      if (rafFiles.isEmpty) {
        print('[Download] No RAF files found on SD card');
        return downloadedFiles;
      }

      // Download each RAF file
      int downloadCount = 0;
      for (final rafFile in rafFiles) {
        downloadCount++;
        print('[Download] Downloading $downloadCount/${rafFiles.length}: ${rafFile.fileName}');
        
        final destinationPath = '$destinationFolder${Platform.pathSeparator}${rafFile.fileName}';
        
        // Update progress
        final progress = (downloadCount / rafFiles.length * 100).round();
        _pixelShiftStateController.add(PixelShiftState(
          status: PixelShiftStatus.downloading,
          message: 'Downloading ${rafFile.fileName}...',
          progress: progress,
          imagesTaken: downloadCount,
          totalImages: rafFiles.length,
        ));

        final success = await downloadFileFromSDCard(rafFile.index, destinationPath);
        
        if (success) {
          downloadedFiles.add(destinationPath);
          print('[Download] ✅ Successfully downloaded: ${rafFile.fileName}');
        } else {
          print('[Download] ❌ Failed to download: ${rafFile.fileName}');
        }

        // Small delay to prevent overwhelming the camera
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('[Download] Download complete! Downloaded ${downloadedFiles.length} files to $destinationFolder');
      return downloadedFiles;
    } catch (e) {
      print('[Download] Error downloading RAF files: $e');
      rethrow;
    }
  }

  @override
  Future<List<String>> downloadImagesFromBuffer(
    String destinationFolder, {
    int expectedCount = 16,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _validateSDKInitialized();
    _validateCameraConnected();

    print('[Buffer Download] Starting dynamic image download from camera buffer...');
    print('[Buffer Download] Expecting $expectedCount images, timeout: ${timeout.inSeconds}s');
    
    final downloadedFiles = <String>[];
    final startTime = DateTime.now();
    int imageIndex = 1;
    bool captureStarted = false;
    int consecutiveFailures = 0;
    const maxConsecutiveFailures = 3;
    
    try {
      // Create destination folder if it doesn't exist
      final destDir = Directory(destinationFolder);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
        print('[Buffer Download] Created destination folder: $destinationFolder');
      }

      print('[Buffer Download] ⏳ Waiting for user to press shutter button...');
      
      // Poll for images until we have all expected images or timeout
      while (downloadedFiles.length < expectedCount) {
        // Check timeout
        if (DateTime.now().difference(startTime) > timeout) {
          print('[Buffer Download] ⏱️ Timeout reached after ${timeout.inSeconds}s');
          break;
        }

        // Check if image is available in buffer
        final imageInfoPtr = malloc<XSDK_ImageInformation>();
        
        try {
          final result = FujifilmSDK.xsdkReadImageInfo(
            _cameraHandle!,
            imageInfoPtr,
          );

          if (result == 0 && imageInfoPtr.ref.lFormat != XSDK_IMAGEFORMAT_NONE) {
            final imageSize = imageInfoPtr.ref.lDataSize;
            if (imageSize > 0 && imageSize < 8 * 1024 * 1024) {
              print('[Buffer Download] ⚠️ SDK reported very small size (${imageSize}B). Will still attempt read.');
            }
            if (imageSize > 600 * 1024 * 1024) {
              print('[Buffer Download] ⚠️ SDK reported huge size (${imageSize}B). Clamping to 600MB to avoid buffer over-alloc.');
            }
            
            if (!captureStarted) {
              captureStarted = true;
              print('[Buffer Download] 🎬 Capture started! First image detected');
              _pixelShiftStateController.add(PixelShiftState(
                status: PixelShiftStatus.capturing,
                message: 'Pixel shift in progress...\nDownloading images as they\'re captured',
                progress: 50,
              ));
            }
            
            // Image is available!
            print('[Buffer Download] 📸 Image ${downloadedFiles.length + 1}/$expectedCount available (reported size: ${imageSize} bytes)');

            // Update progress
            final progress = 50 + ((downloadedFiles.length / expectedCount) * 50).round();
            _pixelShiftStateController.add(PixelShiftState(
              status: PixelShiftStatus.downloading,
              message: 'Downloading image ${downloadedFiles.length + 1}/$expectedCount...',
              progress: progress,
              imagesTaken: downloadedFiles.length + 1,
              totalImages: expectedCount,
            ));

            // Use SDK-reported lDataSize exactly; skip only if invalid
            print('[Buffer Download] 📊 SDK-reported size: $imageSize bytes');
            if (imageSize <= 0) {
              print('[Buffer Download] ⚠️ Invalid size (≤0), skipping...');
              await Future.delayed(const Duration(seconds: 2));
              continue;
            }

            // Allocate exact buffer size per SDK
            final bufferSize = imageSize.clamp(1, 600 * 1024 * 1024);
            Pointer<Uint8>? imageBuffer;

            try {
              imageBuffer = malloc<Uint8>(bufferSize);

              // Read the image from buffer (this also removes it from buffer)
              final readResult = FujifilmSDK.xsdkReadImage(
                _cameraHandle!,
                imageBuffer,
                bufferSize,
              );

              // Check for "camera busy" error (36865)
              if (readResult != 0) {
                final errorDetails = _getSDKErrorDetails(_cameraHandle);
                
                // Error code 36865 typically means camera is busy/not ready
                if (errorDetails.contains('36865')) {
                  print('[Buffer Download] ⏳ Camera busy, image not ready yet. Waiting...');
                  await Future.delayed(const Duration(seconds: 3));
                  continue;
                }
                
                print('[Buffer Download] ❌ Failed to read image: $errorDetails (result: $readResult)');
                consecutiveFailures++;
                
                if (consecutiveFailures >= maxConsecutiveFailures) {
                  print('[Buffer Download] ⚠️ Too many consecutive failures, waiting longer...');
                  await Future.delayed(const Duration(seconds: 5));
                  consecutiveFailures = 0;
                } else {
                  await Future.delayed(const Duration(seconds: 2));
                }
                continue;
              }

              final actualSize = bufferSize; // ReadImage has no out-size param
              
              // Successfully read a reasonable-sized file
              final fileName = 'DSCF${imageIndex.toString().padLeft(4, '0')}.RAF';
              final filePath = '$destinationFolder${Platform.pathSeparator}$fileName';
              
              final file = File(filePath);
              await file.writeAsBytes(imageBuffer.asTypedList(actualSize));
              
              downloadedFiles.add(filePath);
              imageIndex++;
              consecutiveFailures = 0; // Reset failure counter
              
              print('[Buffer Download] ✅ Downloaded: $fileName ($actualSize bytes)');
              
              // Brief pause before checking for next image
              await Future.delayed(const Duration(milliseconds: 1500));
              
            } catch (e) {
              print('[Buffer Download] ⚠️ Exception during read: $e');
              await Future.delayed(const Duration(seconds: 3));
            } finally {
              if (imageBuffer != null) malloc.free(imageBuffer);
            }
          } else {
            // No image available yet
            if (!captureStarted) {
              // Still waiting for user to press shutter - check less frequently
              await Future.delayed(const Duration(seconds: 3));
            } else {
              // Capture started, waiting for next image
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } finally {
          malloc.free(imageInfoPtr);
        }
      }

      if (downloadedFiles.isEmpty && !captureStarted) {
        print('[Buffer Download] ⚠️ No capture was initiated - user may not have pressed shutter');
      }

      print('[Buffer Download] ✅ Download complete! Downloaded ${downloadedFiles.length} images to $destinationFolder');
      return downloadedFiles;
    } catch (e) {
      print('[Buffer Download] ❌ Error downloading from buffer: $e');
      rethrow;
    }
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

  @override
  Future<bool> takeTestShot() async {
    _validateSDKInitialized();
    _validateCameraConnected();

    print('[Test Shot] Taking single test shot...');

    final shotOptPtr = malloc<Int32>();
    final statusPtr = malloc<Int32>();

    try {
      shotOptPtr.value = 1; // Single shot

      // Use standard shutter release in Camera Priority mode
      final releaseResult = FujifilmSDK.xsdkReleaseEx(
        _cameraHandle!,
        XSDK_RELEASE_SHOOT_S1OFF,
        shotOptPtr,
        statusPtr,
      );

      if (releaseResult == 0) {
        print('[Test Shot] ✅ Test shot captured successfully');
        return true;
      } else {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print('[Test Shot] ❌ Failed: $errorDetails');
        return false;
      }
    } finally {
      malloc.free(shotOptPtr);
      malloc.free(statusPtr);
    }
  }

  @override
  Future<List<SDCardFile>> listSDCardFiles() async {
    _validateSDKInitialized();
    _validateCameraConnected();

    print('[SD Card] Listing files on SD card...');

    final numContentsPtr = malloc<Int32>();
    final files = <SDCardFile>[];

    try {
      // Get number of files on SD card
      final result = FujifilmSDK.xsdkGetNumContents(_cameraHandle!, numContentsPtr);
      
      if (result != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print('[SD Card] Failed to get file count. Error: $errorDetails');
        return files;
      }

      final numContents = numContentsPtr.value;
      print('[SD Card] Found $numContents files');

      // Get info for each file
      for (int i = 0; i < numContents; i++) {
        final contentInfoPtr = malloc<XSDK_ContentInformation>();
        
        try {
          final infoResult = FujifilmSDK.xsdkGetContentInfo(
            _cameraHandle!,
            i,
            contentInfoPtr,
          );

          if (infoResult == 0) {
            final fileName = convertUint8ArrayToString(contentInfoPtr.ref.strFileName);
            final fileSize = contentInfoPtr.ref.lFileSize;
            final isFolder = contentInfoPtr.ref.bIsFolder;

            files.add(SDCardFile(
              index: i,
              fileName: fileName,
              fileSize: fileSize,
              isFolder: isFolder,
            ));
          }
        } finally {
          malloc.free(contentInfoPtr);
        }
      }

      print('[SD Card] Successfully listed ${files.length} files');
      return files;
    } finally {
      malloc.free(numContentsPtr);
    }
  }

  @override
  Future<bool> downloadFileFromSDCard(int fileIndex, String destinationPath) async {
    _validateSDKInitialized();
    _validateCameraConnected();

    print('[SD Card] Downloading file index $fileIndex to $destinationPath');

    // First get file info to determine size
    final contentInfoPtr = malloc<XSDK_ContentInformation>();
    
    try {
      final infoResult = FujifilmSDK.xsdkGetContentInfo(
        _cameraHandle!,
        fileIndex,
        contentInfoPtr,
      );

      if (infoResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print('[SD Card] Failed to get file info. Error: $errorDetails');
        return false;
      }

      final fileSize = contentInfoPtr.ref.lFileSize;
      final fileName = convertUint8ArrayToString(contentInfoPtr.ref.strFileName);
      print('[SD Card] Downloading $fileName ($fileSize bytes)...');

      // Allocate buffer for file data
      final bufferPtr = malloc<Uint8>(fileSize);

      try {
        // Download file data
        final downloadResult = FujifilmSDK.xsdkGetContentData(
          _cameraHandle!,
          fileIndex,
          bufferPtr,
          fileSize,
        );

        if (downloadResult != 0) {
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          print('[SD Card] Failed to download file. Error: $errorDetails');
          return false;
        }

        // Write to destination file
        final file = File(destinationPath);
        await file.writeAsBytes(bufferPtr.asTypedList(fileSize));

        print('[SD Card] ✅ Successfully downloaded to $destinationPath');
        return true;
      } finally {
        malloc.free(bufferPtr);
      }
    } finally {
      malloc.free(contentInfoPtr);
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
