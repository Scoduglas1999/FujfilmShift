import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import '../models/camera_models.dart';
import 'fujifilm_sdk_bindings.dart';

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
}

/// Fujifilm camera service implementation
class FujifilmCameraService implements CameraService {
  // Singleton pattern
  static FujifilmCameraService? _instance;
  static FujifilmCameraService get instance {
    _instance ??= FujifilmCameraService._();
    return _instance!;
  }

  // Private constructor
  FujifilmCameraService._();

  // Stream controllers for reactive updates
  var _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  var _cameraInfoController = StreamController<CameraInfo?>.broadcast();
  var _pixelShiftStateController = StreamController<PixelShiftState>.broadcast();

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
          return [];
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

                final cameraInfo = CameraInfo.fromSDKData({
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
          _currentCameraInfo = CameraInfo.fromSDKData({
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
    return await _checkPixelShiftDriveMode();
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
              _cameraHandle!, originalPriorityModePtr) ==
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
              'Could not get the number of drive modes. Details: ${_getSDKErrorDetails(_cameraHandle)}');
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
              _cameraHandle!, numDriveModePtr, driveModesPtr);
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
          _currentCameraInfo = CameraInfo.fromSDKData({
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
      // Be optimistic: if the camera doesn't explicitly list pixel shift,
      // try the default mode anyway. The subsequent SDK calls will fail if it's
      // truly unsupported.
      if (!await isPixelShiftSupported()) {
        print(
            "Warning: Camera does not report Pixel Shift support, but attempting to proceed.");
        _pixelShiftDriveModeValue = XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT;
      }
    }

    // Final check in case the above logic fails to set a value
    if (_pixelShiftDriveModeValue == null) {
      _pixelShiftStateController.add(const PixelShiftState(
          status: PixelShiftStatus.error,
          error: "Could not determine a valid Pixel Shift drive mode."));
      throw Exception("Could not determine a valid Pixel Shift drive mode.");
    }

    try {
      print('[Pixel Shift] Starting process...');
      _pixelShiftStateController
          .add(const PixelShiftState(status: PixelShiftStatus.capturing));

      // 1. Set PC Priority Mode
      print('[Pixel Shift] 1. Setting PC priority mode...');
      final pcPriorityResult =
          FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_PC);
      if (pcPriorityResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print(
            '[Pixel Shift] FAILED to set PC priority mode. Details: $errorDetails');
        throw Exception(
            'Failed to set PC priority mode. Error: $pcPriorityResult. Details: $errorDetails');
      }
      print('[Pixel Shift] PC priority mode set successfully.');
      await Future.delayed(
          const Duration(milliseconds: 200)); // Allow time for mode switch

      // 2. Set camera's drive mode to Pixel Shift
      print('[Pixel Shift] 2. Setting drive mode to Pixel Shift...');
      final driveModeResult = FujifilmSDK.xsdkSetDriveMode(
          _cameraHandle!, _pixelShiftDriveModeValue!);
      if (driveModeResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print(
            '[Pixel Shift] FAILED to set Pixel Shift drive mode. Details: $errorDetails');
        throw Exception(
            'Failed to set Pixel Shift drive mode. Error: $driveModeResult. Details: $errorDetails');
      }
      await Future.delayed(const Duration(milliseconds: 250)); // Short delay
      print('[Pixel Shift] Drive mode set to Pixel Shift successfully.');

      // 3. Start shooting by triggering the shutter release
      print('[Pixel Shift] 3. Triggering shutter release...');
      final releaseResult = FujifilmSDK.xsdkRelease(
        _cameraHandle!,
        XSDK_RELEASE_PIXELSHIFT,
        nullptr,
        nullptr,
      );
      if (releaseResult != 0) {
        final errorDetails = _getSDKErrorDetails(_cameraHandle);
        print('[Pixel Shift] FAILED to trigger shutter. Details: $errorDetails');
        throw Exception(
            'Failed to start Pixel Shift shooting. Error: $releaseResult. Details: $errorDetails');
      }
      print('[Pixel Shift] Shutter triggered successfully.');

      // 4. Download images from buffer
      print('[Pixel Shift] 4. Starting image download...');
      await _downloadImagesFromBuffer();
      print('[Pixel Shift] Image download complete.');
    } catch (e) {
      print('[Pixel Shift] An error occurred during the process: $e');
      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.error,
        error: e.toString(),
      ));
      rethrow;
    } finally {
      print('[Pixel Shift] Cleaning up and resetting camera state...');
      // It's good practice to return control to the camera after the operation
      // and reset the drive mode if needed.
      FujifilmSDK.xsdkSetMode(_cameraHandle!, XSDK_MODE_S);
      await Future.delayed(const Duration(milliseconds: 100));
      FujifilmSDK.xsdkSetDriveMode(_cameraHandle!, XSDK_DRIVE_MODE_S);
      await Future.delayed(const Duration(milliseconds: 100));
      FujifilmSDK.xsdkSetPriorityMode(_cameraHandle!, XSDK_PRIORITY_CAMERA);
      print('[Pixel Shift] Camera state reset.');
    }
  }

  Future<void> _clearImageBuffer() async {
    print("Checking for and clearing any images in the camera's buffer...");

    // Declare pointers at method level for proper scoping
    late final Pointer<XSDK_ImageInformation> imageInfoPtr;
    late final Pointer<Int32> previewSizePtr;

    try {
      // Use the same download logic, but without UI updates and with a timeout.
      imageInfoPtr = calloc<XSDK_ImageInformation>();
      previewSizePtr = calloc<Int32>();
      int clearedImageCount = 0;

      // Set a timeout to avoid getting stuck in an infinite loop on connection.
      final bufferClearanceTimeout =
          Future.delayed(const Duration(seconds: 10));

      final completer = Completer<void>();

      Future<void> clearLoop() async {
        while (true) {
          if (completer.isCompleted) break;

          final result = FujifilmSDK.xsdkReadImageInfo(
              _cameraHandle!, imageInfoPtr, previewSizePtr);
          if (result != 0) {
            // Buffer is likely empty or there's another issue.
            break;
          }

          final imageInfo = imageInfoPtr.ref;
          if (imageInfo.lFormat == XSDK_IMAGEFORMAT_NONE) {
            // Buffer is confirmed empty.
            break;
          }

          final imageSize = imageInfo.lDataSize;
          if (imageSize <= 0) {
            // Invalid image size, stop trying.
            break;
          }

          // Image found, so download and delete it.
          final buffer = calloc<Uint8>(imageSize);
          final readSizePtr = calloc<Int32>();
          try {
            final readResult = FujifilmSDK.xsdkReadImage(
                _cameraHandle!, buffer, imageSize, readSizePtr);
            if (readResult == 0) {
              clearedImageCount++;
              print("Cleared image $clearedImageCount from buffer.");
            } else {
              // Failed to read the image, stop to avoid getting stuck.
              break;
            }
          } finally {
            calloc.free(buffer);
            calloc.free(readSizePtr);
          }
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      // Run the clearing loop with a timeout.
      await Future.any([clearLoop(), bufferClearanceTimeout.then((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      })]);

      if (clearedImageCount > 0) {
        print("Finished clearing $clearedImageCount images from the buffer.");
      } else {
        print("Camera buffer is already clear.");
      }

    } catch (e) {
      print("An error occurred while clearing the camera buffer: $e");
      // Don't rethrow, as this shouldn't block the connection process.
    } finally {
      calloc.free(imageInfoPtr);
      calloc.free(previewSizePtr);
    }
  }

  Future<void> _downloadImagesFromBuffer() async {
    final downloadedFilePaths = <String>[];
    final imageInfoPtr = calloc<XSDK_ImageInformation>();
    final previewSizePtr = calloc<Int32>();
    int imageCounter = 0;
    const totalImages = 20; // Assumption for progress reporting

    final appDocDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDocDir.path}/pixel_shift_images');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    try {
      while (true) {
        // Stop after a reasonable number of images to prevent infinite loops
        if (imageCounter >= totalImages) {
          break;
        }

        // Use a short delay for polling
        await Future.delayed(const Duration(milliseconds: 200));

        final result = FujifilmSDK.xsdkReadImageInfo(
            _cameraHandle!, imageInfoPtr, previewSizePtr);

        if (result != 0) {
          // Continue polling if the buffer is empty, but break on persistent errors
          final errorDetails = _getSDKErrorDetails(_cameraHandle);
          print('xsdkReadImageInfo returned an error: $errorDetails');
          // A more robust solution would check for specific "buffer empty" error codes
          continue;
        }

        final imageInfo = imageInfoPtr.ref;
        if (imageInfo.lFormat == XSDK_IMAGEFORMAT_NONE) {
          print("No more images in buffer.");
          break; // Exit loop when no image is available
        }

        final imageSize = imageInfo.lDataSize;
        if (imageSize <= 0) {
          continue; // Skip if image size is invalid
        }

        imageCounter++;
        _pixelShiftStateController.add(PixelShiftState(
          status: PixelShiftStatus.downloading,
          progress: (imageCounter / totalImages * 100).clamp(0, 99).toInt(),
          imagesTaken: imageCounter,
          totalImages: totalImages,
        ));

        final buffer = calloc<Uint8>(imageSize);
        final readSizePtr = calloc<Int32>();

        try {
          final readResult = FujifilmSDK.xsdkReadImage(
              _cameraHandle!, buffer, imageSize, readSizePtr);

          if (readResult == 0) {
            final readSize = readSizePtr.value;
            final fileName = 'pixel_shift_$imageCounter.raf';
            final filePath = '${downloadDir.path}/$fileName';
            final file = File(filePath);
            await file.writeAsBytes(buffer.asTypedList(readSize));
            downloadedFilePaths.add(filePath);
          } else {
            final errorDetails = _getSDKErrorDetails(_cameraHandle);
            print(
                'Failed to download image $imageCounter. Error: $errorDetails');
          }
        } finally {
          calloc.free(buffer);
          calloc.free(readSizePtr);
        }
      }

      _pixelShiftStateController.add(PixelShiftState(
        status: PixelShiftStatus.finished,
        progress: 100,
        imagesTaken: imageCounter,
        totalImages: imageCounter,
        downloadedFiles: downloadedFilePaths,
      ));
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
        "Warning: downloadPixelShiftImages() is deprecated. Download starts automatically.");
    return [];
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
    const supportedModels = [
      'X-T5',
      'X-H2',
      'X-H2S',
      'GFX50S II',
      'GFX100',
      'GFX100S',
      'GFX100 II'
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
