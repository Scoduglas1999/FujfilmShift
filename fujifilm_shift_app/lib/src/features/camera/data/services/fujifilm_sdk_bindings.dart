import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// FFI bindings for Fujifilm SDK
// Based on XAPI.h header file

// Type definitions
typedef XSDK_HANDLE = Pointer<Void>;
typedef LIB_HANDLE = Pointer<Void>;
typedef XSDK_APIENTRY = Int32;

// Constants from XAPI.h
const int XSDK_DSC_IF_USB = 0x00000001;
const int XSDK_DSC_IF_WIFI_LOCAL = 0x00000010;
const int XSDK_DSC_IF_WIFI_IP = 0x00000020;

// Camera Mode
const int XSDK_DSC_MODE_TETHER = 0x0001;
const int XSDK_DSC_MODE_RAW = 0x0002;
const int XSDK_DSC_MODE_BR = 0x0004;
const int XSDK_DSC_MODE_WEBCAM = 0x0008;
const int XSDK_DSC_MODE_PIXEL_SHIFT = 0x0010;

// Priority Mode
const int XSDK_PRIORITY_CAMERA = 0x0001;
const int XSDK_PRIORITY_PC = 0x0002;

// Drive Mode
const int XSDK_DRIVE_MODE_S = 1; // Single Shot
const int XSDK_DRIVE_MODE_PIXELSHIFTMULTISHOT = 16;

// Release Mode
const int XSDK_RELEASE_PIXELSHIFT = 0x0020;

// Still Mode
const int XSDK_MODE_S = 1;

const int XSDK_IMAGEFORMAT_NONE = 0;


// API Error Codes
const int API_CODE_Init = 0x1001;
const int API_CODE_Exit = 0x1002;
const int API_CODE_CapPixelShiftSettings = 0x407A;

// Device Information Structure
final class XSDK_DeviceInformation extends Struct {
  @Array(256)
  external Array<Uint8> strVendor;
  @Array(256)
  external Array<Uint8> strManufacturer;
  @Array(256)
  external Array<Uint8> strProduct;
  @Array(256)
  external Array<Uint8> strFirmware;
  @Array(256)
  external Array<Uint8> strDeviceType;
  @Array(256)
  external Array<Uint8> strSerialNo;
  @Array(256)
  external Array<Uint8> strFramework;
  @Uint8()
  external int bDeviceId;
  @Array(32)
  external Array<Uint8> strDeviceName;
  @Array(32)
  external Array<Uint8> strYNo;
}

// Camera List Structure
@Packed(1)
final class XSDK_CameraList extends Struct {
  @Array(256)
  external Array<Uint8> strProduct;
  @Array(256)
  external Array<Uint8> strSerialNo;
  @Array(256)
  external Array<Uint8> strIPAddress;
  @Array(256)
  external Array<Uint8> strFramework;
  @Bool()
  external bool bValid;
}

// Lens Information Structure
final class XSDK_LensInformation extends Struct {
  @Array(256)
  external Array<Uint8> strLensName;

  @Int32()
  external int nLensMount;

  @Int32()
  external int nLensType;

  @Int32()
  external int nLensID;

  @Int32()
  external int nLensVersion;
}

// Image Information Structure
final class XSDK_ImageInformation extends Struct {
  @Int32()
  external int lFormat;

  @Int32()
  external int lDataSize;

  @Int32()
  external int lWidth;

  @Int32()
  external int lHeight;

  @Int32()
  external int lOrientation;

  @Array(10)
  external Array<Int32> lUnused;
}

// Pixel Shift Information Structure
final class XSDK_PixelShiftInformation extends Struct {
  @Int32()
  external int nStatus; // 0: Idle, 1: Shooting, 2: Finished, -1: Error
  @Int32()
  external int nProgress; // 0-100
  @Int32()
  external int nImagesTaken;
  @Int32()
  external int nTotalImages;
}

// Content Information Structure
final class XSDK_ContentInformation extends Struct {
  @Array(256)
  external Array<Uint8> strFileName;
  @Int32()
  external int lFileSize;
  @Bool()
  external bool bIsFolder;
  // Other fields from SDK can be added here
}

// Dynamic library loader with robust error handling
class FujifilmSDKLibrary {
  static DynamicLibrary? _library;
  static bool _initialized = false;
  static String? _lastError;

  static DynamicLibrary? get library {
    if (_library == null && !_initialized) {
      _library = _loadLibrary();
      _initialized = true;
    }
    return _library;
  }

  static bool get isInitialized => _initialized;
  static bool get isLoaded => _library != null;
  static String? get lastError => _lastError;

  static DynamicLibrary? _loadLibrary() {
    try {
      // Get the directory of the executable
      final exePath = p.dirname(Platform.resolvedExecutable);

      // Construct the path to the DLL relative to the executable
      final dllPath = p.join(exePath, 'XAPI.dll');

      print("Attempting to load SDK from: $dllPath");

      if (File(dllPath).existsSync()) {
        try {
          _lastError = null;
          return DynamicLibrary.open(dllPath);
        } catch (e) {
          _lastError = 'Failed to load $dllPath: $e';
          print(_lastError);
        }
      } else {
        _lastError = 'XAPI.dll not found at $dllPath';
        print(_lastError);
      }

      // Fallback for when running in a development environment
      print("Fallback: Searching in project structure...");
      final possiblePaths = [
        'sdk/XAPI.dll', // SDK subdirectory relative to app root
        'fujifilm_shift_app/sdk/XAPI.dll', // SDK subdirectory relative to project root
      ];

      for (final path in possiblePaths) {
        final absolutePath = p.absolute(path);
        if (File(absolutePath).existsSync()) {
          try {
            print("Attempting to load SDK from: $absolutePath");
            _lastError = null;
            return DynamicLibrary.open(absolutePath);
          } catch (e) {
            _lastError = 'Failed to load $absolutePath: $e';
            print(_lastError);
            continue;
          }
        }
      }

      _lastError =
          'Fujifilm SDK not found. Please ensure XAPI.dll is available.';
      return null;
    } catch (e) {
      _lastError = 'Unexpected error loading Fujifilm SDK: $e';
      return null;
    }
  }

  static String getLibraryInfo() {
    if (_library != null) {
      return 'Fujifilm SDK loaded successfully';
    } else {
      return 'Fujifilm SDK not available: ${_lastError ?? "Unknown error"}';
    }
  }
}

// Function signatures
typedef _XSDK_InitNative = Int32 Function(Pointer<Void> hLib);
typedef XSDK_Init = int Function(Pointer<Void> hLib);

typedef _XSDK_ExitNative = Int32 Function();
typedef XSDK_Exit = int Function();

typedef _XSDK_DetectNative = Int32 Function(
    Int32 lInterface,
    Pointer<Utf8> pInterface,
    Pointer<Utf8> pDeviceName,
    Pointer<Int32> plCount);
typedef XSDK_Detect = int Function(
    int lInterface,
    Pointer<Utf8> pInterface,
    Pointer<Utf8> pDeviceName,
    Pointer<Int32> plCount);

typedef _XSDK_AppendNative = Int32 Function(
    Int32 lInterface,
    Pointer<Utf8> pInterface,
    Pointer<Utf8> pDeviceName,
    Pointer<Int32> plCount,
    Pointer<XSDK_CameraList> pCameraList);
typedef XSDK_Append = int Function(
    int lInterface,
    Pointer<Utf8> pInterface,
    Pointer<Utf8> pDeviceName,
    Pointer<Int32> plCount,
    Pointer<XSDK_CameraList> pCameraList);

typedef _XSDK_OpenExNative = Int32 Function(
    Pointer<Utf8> pDevice,
    Pointer<Pointer<Void>> phCamera,
    Pointer<Int32> plCameraMode,
    Pointer<Void> pOption);
typedef XSDK_OpenEx = int Function(
    Pointer<Utf8> pDevice,
    Pointer<Pointer<Void>> phCamera,
    Pointer<Int32> plCameraMode,
    Pointer<Void> pOption);

typedef _XSDK_CloseNative = Int32 Function(Pointer<Void> hCamera);
typedef XSDK_Close = int Function(Pointer<Void> hCamera);

typedef _XSDK_PowerOFFNative = Int32 Function(Pointer<Void> hCamera);
typedef XSDK_PowerOFF = int Function(Pointer<Void> hCamera);

typedef _XSDK_GetErrorNumberNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plAPICode,
    Pointer<Int32> plERRCode);
typedef XSDK_GetErrorNumber = int Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plAPICode,
    Pointer<Int32> plERRCode);

typedef _XSDK_GetVersionStringNative = Int32 Function(Pointer<Utf8> pVersionString);
typedef XSDK_GetVersionString = int Function(Pointer<Utf8> pVersionString);

typedef _XSDK_GetDeviceInfoNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<XSDK_DeviceInformation> pDevInfo);
typedef XSDK_GetDeviceInfo = int Function(
    Pointer<Void> hCamera,
    Pointer<XSDK_DeviceInformation> pDevInfo);

typedef _XSDK_GetFirmwareVersionNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<Utf8> pFirmwareVersion);
typedef XSDK_GetFirmwareVersion = int Function(
    Pointer<Void> hCamera,
    Pointer<Utf8> pFirmwareVersion);

typedef _XSDK_GetLensInfoNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<XSDK_LensInformation> pLensInfo);
typedef XSDK_GetLensInfo = int Function(
    Pointer<Void> hCamera,
    Pointer<XSDK_LensInformation> pLensInfo);

typedef _XSDK_CapPriorityModeNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plNumPriorityMode,
    Pointer<Int32> plPriorityMode);
typedef XSDK_CapPriorityMode = int Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plNumPriorityMode,
    Pointer<Int32> plPriorityMode);

typedef _XSDK_SetPriorityModeNative = Int32 Function(
    Pointer<Void> hCamera, Int32 lPriorityMode);
typedef XSDK_SetPriorityMode = int Function(
    Pointer<Void> hCamera, int lPriorityMode);

typedef _XSDK_GetPriorityModeNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plPriorityMode);
typedef XSDK_GetPriorityMode = int Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plPriorityMode);

typedef _XSDK_ReadImageInfoNative = Int32 Function(Pointer<Void> hCamera,
    Pointer<XSDK_ImageInformation> pImgInfo, Pointer<Int32> plPreviewSize);
typedef XSDK_ReadImageInfo = int Function(Pointer<Void> hCamera,
    Pointer<XSDK_ImageInformation> pImgInfo, Pointer<Int32> plPreviewSize);

typedef _XSDK_GetBufferCapacityNative = Int32 Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plShootFrameNum,
    Pointer<Int32> plTotalFrameNum);
typedef XSDK_GetBufferCapacity = int Function(
    Pointer<Void> hCamera,
    Pointer<Int32> plShootFrameNum,
    Pointer<Int32> plTotalFrameNum);

typedef _XSDK_ReadImageNative = Int32 Function(Pointer<Void> hCamera,
    Pointer<Uint8> pData, Int32 ulDataSize, Pointer<Int32> pulReadSize);
typedef XSDK_ReadImage = int Function(Pointer<Void> hCamera,
    Pointer<Uint8> pData, int ulDataSize, Pointer<Int32> pulReadSize);

// Property Functions
typedef _XSDK_SetPropNative = Int32 Function(
    Pointer<Void> hCamera, Int32 lAPICode, Int32 lAPIParam);
typedef XSDK_SetProp = int Function(
    Pointer<Void> hCamera, int lAPICode, int lAPIParam);

typedef _XSDK_GetPropNative = Int32 Function(
    Pointer<Void> hCamera, Int32 lAPICode, Pointer<Int32> plAPIParam);
typedef XSDK_GetProp = int Function(
    Pointer<Void> hCamera, int lAPICode, Pointer<Int32> plAPIParam);

typedef _XSDK_CapPropNative = Int32 Function(Pointer<Void> hCamera,
    Int32 lAPICode, Pointer<Int32> plNum, Pointer<Int32> plCapability);
typedef XSDK_CapProp = int Function(Pointer<Void> hCamera, int lAPICode,
    Pointer<Int32> plNum, Pointer<Int32> plCapability);

// Drive Mode Binding
typedef _XSDK_CapDriveModeNative = Int32 Function(Pointer<Void> hCamera,
    Pointer<Int32> plNumDriveMode, Pointer<Int32> plDriveMode);
typedef XSDK_CapDriveMode = int Function(Pointer<Void> hCamera,
    Pointer<Int32> plNumDriveMode, Pointer<Int32> plDriveMode);
typedef _XSDK_SetDriveModeNative = Int32 Function(Pointer<Void> hCamera, Int32 lMode);
typedef XSDK_SetDriveMode = int Function(Pointer<Void> hCamera, int lMode);

// Mode Bindings
typedef _XSDK_CapModeNative = Int32 Function(
    Pointer<Void> hCamera, Pointer<Int32> plNumMode, Pointer<Int32> plMode);
typedef XSDK_CapMode = int Function(
    Pointer<Void> hCamera, Pointer<Int32> plNumMode, Pointer<Int32> plMode);

typedef _XSDK_SetModeNative = Int32 Function(Pointer<Void> hCamera, Int32 lMode);
typedef XSDK_SetMode = int Function(Pointer<Void> hCamera, int lMode);

typedef _XSDK_GetModeNative = Int32 Function(
    Pointer<Void> hCamera, Pointer<Int32> plMode);
typedef XSDK_GetMode = int Function(Pointer<Void> hCamera, Pointer<Int32> plMode);

// Release Binding
typedef _XSDK_ReleaseNative = Int32 Function(
    Pointer<Void> hCamera, Int32 lMode, Pointer<Int32> pShotOpt, Pointer<Int32> pStatus);
typedef XSDK_Release = int Function(
    Pointer<Void> hCamera, int lMode, Pointer<Int32> pShotOpt, Pointer<Int32> pStatus);

// Pixel Shift Bindings
typedef _XSDK_StartPixelShiftShootingNative = Int32 Function(Pointer<Void> hCamera);
typedef XSDK_StartPixelShiftShooting = int Function(Pointer<Void> hCamera);

typedef _XSDK_GetPixelShiftInfoNative = Int32 Function(
    Pointer<Void> hCamera, Pointer<XSDK_PixelShiftInformation> pInfo);
typedef XSDK_GetPixelShiftInfo = int Function(
    Pointer<Void> hCamera, Pointer<XSDK_PixelShiftInformation> pInfo);

// File Download Bindings
typedef _XSDK_GetNumContentsNative = Int32 Function(
    Pointer<Void> hCamera, Pointer<Int32> plNumContents);
typedef XSDK_GetNumContents = int Function(
    Pointer<Void> hCamera, Pointer<Int32> plNumContents);

typedef _XSDK_GetContentInfoNative = Int32 Function(Pointer<Void> hCamera,
    Int32 lIndex, Pointer<XSDK_ContentInformation> pContentInfo);
typedef XSDK_GetContentInfo = int Function(Pointer<Void> hCamera, int lIndex,
    Pointer<XSDK_ContentInformation> pContentInfo);

typedef _XSDK_GetContentDataNative = Int32 Function(Pointer<Void> hCamera,
    Int32 lIndex, Pointer<Uint8> pBuffer, Int32 lBufferSize);
typedef XSDK_GetContentData = int Function(Pointer<Void> hCamera, int lIndex,
    Pointer<Uint8> pBuffer, int lBufferSize);


// Dart wrapper functions with null safety
class FujifilmSDK {
  static final DynamicLibrary _lib = _loadSdk();

  static DynamicLibrary _loadSdk() {
    final lib = FujifilmSDKLibrary.library;
    if (lib == null) {
      throw StateError(
          'Fujifilm SDK library not loaded. ${FujifilmSDKLibrary.lastError}');
    }
    return lib;
  }

  static Pointer<Void> getLibraryHandle() {
    return _lib.handle;
  }

  // Initialize SDK with proper library handle
  static int xsdkInitWithHandle() {
    return _xsdkInit(_lib.handle);
  }

  // Function pointers - initialized lazily to handle null library
  static final XSDK_Init _xsdkInit =
      _lib.lookup<NativeFunction<_XSDK_InitNative>>('XSDK_Init').asFunction<XSDK_Init>();
  static final XSDK_Exit _xsdkExit =
      _lib.lookup<NativeFunction<_XSDK_ExitNative>>('XSDK_Exit').asFunction<XSDK_Exit>();
  static final XSDK_Detect _xsdkDetect =
      _lib.lookup<NativeFunction<_XSDK_DetectNative>>('XSDK_Detect').asFunction<XSDK_Detect>();
  static final XSDK_Append _xsdkAppend =
      _lib.lookup<NativeFunction<_XSDK_AppendNative>>('XSDK_Append').asFunction<XSDK_Append>();
  static final XSDK_OpenEx _xsdkOpenEx =
      _lib.lookup<NativeFunction<_XSDK_OpenExNative>>('XSDK_OpenEx').asFunction<XSDK_OpenEx>();
  static final XSDK_Close _xsdkClose =
      _lib.lookup<NativeFunction<_XSDK_CloseNative>>('XSDK_Close').asFunction<XSDK_Close>();
  static final XSDK_PowerOFF _xsdkPowerOff =
      _lib.lookup<NativeFunction<_XSDK_PowerOFFNative>>('XSDK_PowerOFF').asFunction<XSDK_PowerOFF>();
  static final XSDK_GetErrorNumber _xsdkGetErrorNumber = _lib
      .lookup<NativeFunction<_XSDK_GetErrorNumberNative>>('XSDK_GetErrorNumber')
      .asFunction<XSDK_GetErrorNumber>();
  static final XSDK_GetVersionString _xsdkGetVersionString = _lib
      .lookup<NativeFunction<_XSDK_GetVersionStringNative>>(
          'XSDK_GetVersionString')
      .asFunction<XSDK_GetVersionString>();
  static final XSDK_GetDeviceInfo _xsdkGetDeviceInfo = _lib
      .lookup<NativeFunction<_XSDK_GetDeviceInfoNative>>('XSDK_GetDeviceInfo')
      .asFunction<XSDK_GetDeviceInfo>();
  static final XSDK_GetFirmwareVersion _xsdkGetFirmwareVersion = _lib
      .lookup<NativeFunction<_XSDK_GetFirmwareVersionNative>>(
          'XSDK_GetFirmwareVersion')
      .asFunction<XSDK_GetFirmwareVersion>();
  static final XSDK_GetLensInfo _xsdkGetLensInfo = _lib
      .lookup<NativeFunction<_XSDK_GetLensInfoNative>>('XSDK_GetLensInfo')
      .asFunction<XSDK_GetLensInfo>();
  static final XSDK_CapPriorityMode _xsdkCapPriorityMode = _lib
      .lookup<NativeFunction<_XSDK_CapPriorityModeNative>>(
          'XSDK_CapPriorityMode')
      .asFunction<XSDK_CapPriorityMode>();
  static final XSDK_SetPriorityMode _xsdkSetPriorityMode = _lib
      .lookup<NativeFunction<_XSDK_SetPriorityModeNative>>(
          'XSDK_SetPriorityMode')
      .asFunction<XSDK_SetPriorityMode>();
  static final XSDK_GetPriorityMode _xsdkGetPriorityMode = _lib
      .lookup<NativeFunction<_XSDK_GetPriorityModeNative>>(
          'XSDK_GetPriorityMode')
      .asFunction<XSDK_GetPriorityMode>();
  static final XSDK_ReadImageInfo _xsdkReadImageInfo = _lib
      .lookup<NativeFunction<_XSDK_ReadImageInfoNative>>('XSDK_ReadImageInfo')
      .asFunction<XSDK_ReadImageInfo>();
  static final XSDK_GetBufferCapacity _xsdkGetBufferCapacity = _lib
      .lookup<NativeFunction<_XSDK_GetBufferCapacityNative>>(
          'XSDK_GetBufferCapacity')
      .asFunction<XSDK_GetBufferCapacity>();
  static final XSDK_ReadImage _xsdkReadImage = _lib
      .lookup<NativeFunction<_XSDK_ReadImageNative>>('XSDK_ReadImage')
      .asFunction<XSDK_ReadImage>();

  // Property functions
  static final XSDK_SetProp _xsdkSetProp = _lib
      .lookup<NativeFunction<_XSDK_SetPropNative>>('XSDK_SetProp')
      .asFunction<XSDK_SetProp>();
  static final XSDK_GetProp _xsdkGetProp = _lib
      .lookup<NativeFunction<_XSDK_GetPropNative>>('XSDK_GetProp')
      .asFunction<XSDK_GetProp>();
  static final XSDK_CapProp _xsdkCapProp = _lib
      .lookup<NativeFunction<_XSDK_CapPropNative>>('XSDK_CapProp')
      .asFunction<XSDK_CapProp>();

  // Drive Mode function
  static final XSDK_CapDriveMode _xsdkCapDriveMode = _lib
      .lookup<NativeFunction<_XSDK_CapDriveModeNative>>('XSDK_CapDriveMode')
      .asFunction<XSDK_CapDriveMode>();
  static final XSDK_SetDriveMode _xsdkSetDriveMode =
      _lib.lookup<NativeFunction<_XSDK_SetDriveModeNative>>('XSDK_SetDriveMode').asFunction<XSDK_SetDriveMode>();

  // Mode functions
  static final XSDK_SetMode _xsdkSetMode =
      _lib.lookup<NativeFunction<_XSDK_SetModeNative>>('XSDK_SetMode').asFunction<XSDK_SetMode>();
  static final XSDK_GetMode _xsdkGetMode =
      _lib.lookup<NativeFunction<_XSDK_GetModeNative>>('XSDK_GetMode').asFunction<XSDK_GetMode>();

  // Release function
  static final XSDK_Release _xsdkRelease = _lib
      .lookup<NativeFunction<_XSDK_ReleaseNative>>('XSDK_Release')
      .asFunction<XSDK_Release>();

  // Pixel Shift functions
  static final XSDK_StartPixelShiftShooting _xsdkStartPixelShiftShooting = _lib
      .lookup<NativeFunction<_XSDK_StartPixelShiftShootingNative>>(
          'XSDK_StartPixelShiftShooting')
      .asFunction<XSDK_StartPixelShiftShooting>();

  static final XSDK_GetPixelShiftInfo _xsdkGetPixelShiftInfo = _lib
      .lookup<NativeFunction<_XSDK_GetPixelShiftInfoNative>>(
          'XSDK_GetPixelShiftInfo')
      .asFunction<XSDK_GetPixelShiftInfo>();

  // File Download functions
  static final XSDK_GetNumContents _xsdkGetNumContents = _lib
      .lookup<NativeFunction<_XSDK_GetNumContentsNative>>('XSDK_GetNumContents')
      .asFunction<XSDK_GetNumContents>();

  static final XSDK_GetContentInfo _xsdkGetContentInfo = _lib
      .lookup<NativeFunction<_XSDK_GetContentInfoNative>>('XSDK_GetContentInfo')
      .asFunction<XSDK_GetContentInfo>();

  static final XSDK_GetContentData _xsdkGetContentData = _lib
      .lookup<NativeFunction<_XSDK_GetContentDataNative>>('XSDK_GetContentData')
      .asFunction<XSDK_GetContentData>();


  static int xsdkInit(Pointer<Void> hLib) {
    return _xsdkInit(hLib);
  }

  static int xsdkExit() {
    return _xsdkExit();
  }

  static int xsdkDetect(int lInterface, Pointer<Utf8> pInterface,
      Pointer<Utf8> pDeviceName, Pointer<Int32> plCount) {
    return _xsdkDetect(lInterface, pInterface, pDeviceName, plCount);
  }

  static int xsdkAppend(
      int lInterface,
      Pointer<Utf8> pInterface,
      Pointer<Utf8> pDeviceName,
      Pointer<Int32> plCount,
      Pointer<XSDK_CameraList> pCameraList) {
    return _xsdkAppend(lInterface, pInterface, pDeviceName, plCount, pCameraList);
  }

  static int xsdkOpenEx(Pointer<Utf8> pDevice, Pointer<Pointer<Void>> phCamera,
      Pointer<Int32> plCameraMode, Pointer<Void> pOption) {
    return _xsdkOpenEx(pDevice, phCamera, plCameraMode, pOption);
  }

  static int xsdkClose(Pointer<Void> hCamera) {
    return _xsdkClose(hCamera);
  }

  static int xsdkPowerOff(Pointer<Void> hCamera) {
    return _xsdkPowerOff(hCamera);
  }

  static int xsdkGetErrorNumber(Pointer<Void> hCamera, Pointer<Int32> plAPICode,
      Pointer<Int32> plERRCode) {
    return _xsdkGetErrorNumber(hCamera, plAPICode, plERRCode);
  }

  static int xsdkGetVersionString(Pointer<Utf8> pVersionString) {
    return _xsdkGetVersionString(pVersionString);
  }

  static int xsdkGetDeviceInfo(
      Pointer<Void> hCamera, Pointer<XSDK_DeviceInformation> pDevInfo) {
    return _xsdkGetDeviceInfo(hCamera, pDevInfo);
  }

  static int xsdkGetFirmwareVersion(
      Pointer<Void> hCamera, Pointer<Utf8> pFirmwareVersion) {
    return _xsdkGetFirmwareVersion(hCamera, pFirmwareVersion);
  }

  static int xsdkGetLensInfo(
      Pointer<Void> hCamera, Pointer<XSDK_LensInformation> pLensInfo) {
    return _xsdkGetLensInfo(hCamera, pLensInfo);
  }

  static int xsdkCapPriorityMode(Pointer<Void> hCamera,
      Pointer<Int32> plNumPriorityMode, Pointer<Int32> plPriorityMode) {
    return _xsdkCapPriorityMode(hCamera, plNumPriorityMode, plPriorityMode);
  }

  static int xsdkSetPriorityMode(Pointer<Void> hCamera, int lPriorityMode) {
    return _xsdkSetPriorityMode(hCamera, lPriorityMode);
  }

  static int xsdkGetPriorityMode(
      Pointer<Void> hCamera, Pointer<Int32> plPriorityMode) {
    return _xsdkGetPriorityMode(hCamera, plPriorityMode);
  }

  static int xsdkReadImageInfo(
      Pointer<Void> hCamera,
      Pointer<XSDK_ImageInformation> pImgInfo,
      Pointer<Int32> plPreviewSize) {
    return _xsdkReadImageInfo(hCamera, pImgInfo, plPreviewSize);
  }

  static int xsdkGetBufferCapacity(Pointer<Void> hCamera,
      Pointer<Int32> plShootFrameNum, Pointer<Int32> plTotalFrameNum) {
    return _xsdkGetBufferCapacity(hCamera, plShootFrameNum, plTotalFrameNum);
  }

  static int xsdkReadImage(Pointer<Void> hCamera, Pointer<Uint8> pData,
      int ulDataSize, Pointer<Int32> pulReadSize) {
    return _xsdkReadImage(hCamera, pData, ulDataSize, pulReadSize);
  }

  static int xsdkSetProp(Pointer<Void> hCamera, int lAPICode, int lAPIParam) {
    return _xsdkSetProp(hCamera, lAPICode, lAPIParam);
  }

  static int xsdkGetProp(
      Pointer<Void> hCamera, int lAPICode, Pointer<Int32> plAPIParam) {
    return _xsdkGetProp(hCamera, lAPICode, plAPIParam);
  }

  static int xsdkCapProp(Pointer<Void> hCamera, int lAPICode,
      Pointer<Int32> plNum, Pointer<Int32> plCapability) {
    return _xsdkCapProp(hCamera, lAPICode, plNum, plCapability);
  }

  static int xsdkCapDriveMode(Pointer<Void> hCamera,
      Pointer<Int32> plNumDriveMode, Pointer<Int32> plDriveMode) {
    return _xsdkCapDriveMode(hCamera, plNumDriveMode, plDriveMode);
  }

  static int xsdkSetDriveMode(Pointer<Void> hCamera, int lMode) {
    return _xsdkSetDriveMode(hCamera, lMode);
  }

  static int xsdkSetMode(Pointer<Void> hCamera, int lMode) {
    return _xsdkSetMode(hCamera, lMode);
  }

  static int xsdkGetMode(Pointer<Void> hCamera, Pointer<Int32> plMode) {
    return _xsdkGetMode(hCamera, plMode);
  }

  static int xsdkRelease(
      Pointer<Void> hCamera, int lMode, Pointer<Int32> pShotOpt, Pointer<Int32> pStatus) {
    return _xsdkRelease(hCamera, lMode, pShotOpt, pStatus);
  }

  static int xsdkStartPixelShiftShooting(Pointer<Void> hCamera) {
    return _xsdkStartPixelShiftShooting(hCamera);
  }

  static int xsdkGetPixelShiftInfo(
      Pointer<Void> hCamera, Pointer<XSDK_PixelShiftInformation> pInfo) {
    return _xsdkGetPixelShiftInfo(hCamera, pInfo);
  }

  static int xsdkGetNumContents(
      Pointer<Void> hCamera, Pointer<Int32> plNumContents) {
    return _xsdkGetNumContents(hCamera, plNumContents);
  }

  static int xsdkGetContentInfo(Pointer<Void> hCamera, int lIndex,
      Pointer<XSDK_ContentInformation> pContentInfo) {
    return _xsdkGetContentInfo(hCamera, lIndex, pContentInfo);
  }

  static int xsdkGetContentData(Pointer<Void> hCamera, int lIndex,
      Pointer<Uint8> pBuffer, int lBufferSize) {
    return _xsdkGetContentData(hCamera, lIndex, pBuffer, lBufferSize);
  }
}

// Helper functions for string conversion
String convertUint8ArrayToString(Array<Uint8> array) {
  final list = <int>[];
  // Array size is determined by the @Array() annotation in the struct
  // For 256-byte arrays, iterate through all elements
  for (var i = 0; i < 256; i++) {
    final byte = array[i];
    if (byte == 0) break; // Null terminator
    list.add(byte);
  }
  return String.fromCharCodes(list);
}

String convertUint8PointerToString(Pointer<Uint8> pointer) {
  final list = <int>[];
  var i = 0;
  while (true) {
    final byte = pointer[i];
    if (byte == 0) break; // Null terminator
    list.add(byte);
    i++;
  }
  return String.fromCharCodes(list);
}

Pointer<Utf8> stringToUtf8Pointer(String str) {
  return str.toNativeUtf8();
}

void freeStringPointer(Pointer<Utf8> pointer) {
  malloc.free(pointer);
}
