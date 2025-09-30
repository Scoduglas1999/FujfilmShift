/// Camera information models for Fujifilm SDK integration

// Battery information
class BatteryInfo { // minutes

  const BatteryInfo({
    required this.capacity,
    required this.status,
    required this.remainingTime,
  });

  factory BatteryInfo.fromSDKData(Map<String, dynamic> data) {
    // If battery data is not available from SDK, return a default battery info
    if (data.isEmpty) {
      return const BatteryInfo(
        capacity: 0,
        status: BatteryStatus.normal,
        remainingTime: 0,
      );
    }

    return BatteryInfo(
      capacity: data["capacity"] ?? 0,
      status: BatteryStatus.fromSDKValue(data["status"] ?? 0),
      remainingTime: data["remainingTime"] ?? 0,
    );
  }
  final int capacity; // 0-100 percentage
  final BatteryStatus status;
  final int remainingTime;

  // Convert to map for serialization
  Map<String, dynamic> toMap() => <String, dynamic>{
      "capacity": capacity,
      "status": status.index,
      "remainingTime": remainingTime,
    };
}

enum BatteryStatus {
  normal,
  low,
  critical,
  charging,
  full;

  static BatteryStatus fromSDKValue(int value) {
    switch (value) {
      case 0:
        return normal;
      case 1:
        return low;
      case 2:
        return critical;
      case 3:
        return charging;
      case 4:
        return full;
      default:
        return normal;
    }
  }
}

// ISO range information
class ISORange {

  const ISORange({
    required this.minISO,
    required this.maxISO,
    required this.availableISOs,
  });

  factory ISORange.fromSDKData(Map<String, dynamic> data) => ISORange(
      minISO: data['minISO'] ?? 100,
      maxISO: data['maxISO'] ?? 12800,
      availableISOs: data['availableISOs'] ?? _defaultISORange(),
    );
  final int minISO;
  final int maxISO;
  final List<int> availableISOs;

  static List<int> _defaultISORange() => <int>[
      100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
      1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400,
      8000, 10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200,
    ];
}

// Camera specifications
class CameraSpecs {

  const CameraSpecs({
    required this.sensorType,
    required this.sensorSize,
    required this.megapixels,
    required this.isoRange,
    required this.hasPixelShift,
  });
  final String sensorType;
  final String sensorSize;
  final int megapixels;
  final ISORange isoRange;
  final bool hasPixelShift;
}

// Camera information
class CameraInfo {

  const CameraInfo({
    required this.model,
    required this.serialNumber,
    required this.firmwareVersion,
    required this.connectionType,
    required this.isConnected, required this.supportsPixelShift, required this.specs, this.battery,
  });

  // Factory method to create from SDK data
  factory CameraInfo.fromSDKData(Map<String, dynamic> data) {
    final model = data["model"] ?? "Unknown";
    final CameraSpecs specs = _getCameraSpecs(model);

    return CameraInfo(
      model: model,
      serialNumber: data["serialNumber"] ?? "",
      firmwareVersion: data["firmwareVersion"] ?? "",
      connectionType: data["connectionType"] ?? "USB",
      battery: data["battery"] != null && data["battery"].isNotEmpty ? BatteryInfo.fromSDKData(data["battery"]) : null,
      isConnected: data["isConnected"] ?? false,
      supportsPixelShift: specs.hasPixelShift,
      specs: specs,
    );
  }
  final String model;
  final String serialNumber;
  final String firmwareVersion;
  final String connectionType; // USB, WiFi, etc.
  final BatteryInfo? battery;
  final bool isConnected;
  final bool supportsPixelShift;
  final CameraSpecs specs;

  // Copy with method for immutable updates
  CameraInfo copyWith({
    String? model,
    String? serialNumber,
    String? firmwareVersion,
    String? connectionType,
    BatteryInfo? battery,
    bool? isConnected,
    bool? supportsPixelShift,
    CameraSpecs? specs,
  }) => CameraInfo(
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      connectionType: connectionType ?? this.connectionType,
      battery: battery ?? this.battery,
      isConnected: isConnected ?? this.isConnected,
      supportsPixelShift: supportsPixelShift ?? this.supportsPixelShift,
      specs: specs ?? this.specs,
    );

  // Convert to map for serialization
  Map<String, dynamic> toMap() => <String, dynamic>{
      "model": model,
      "serialNumber": serialNumber,
      "firmwareVersion": firmwareVersion,
      "connectionType": connectionType,
      "battery": battery?.toMap(),
      "isConnected": isConnected,
      "supportsPixelShift": supportsPixelShift,
    };

  // Static method to get camera specifications based on model
  static CameraSpecs _getCameraSpecs(String model) {
    // Dynamic camera specs based on detected model from SDK
    final upperModel = model.toUpperCase();

    // Determine pixel shift capability based on model
    final hasPixelShift = _supportsPixelShift(upperModel);

    // Get specs based on model
    if (upperModel.contains('X-T5')) {
      return CameraSpecs(
        sensorType: 'X-Trans CMOS 5 HR',
        sensorSize: 'APS-C',
        megapixels: 40,
        isoRange: const ISORange(minISO: 125, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: hasPixelShift,
      );
    } else if (upperModel.contains('X-H2')) {
      return CameraSpecs(
        sensorType: 'X-Trans CMOS 5 HS',
        sensorSize: 'APS-C',
        megapixels: upperModel.contains('X-H2S') ? 26 : 40,
        isoRange: const ISORange(minISO: 125, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: hasPixelShift,
      );
    } else if (upperModel.contains('X-S20')) {
      return const CameraSpecs(
        sensorType: 'X-Trans CMOS 4',
        sensorSize: 'APS-C',
        megapixels: 26,
        isoRange: ISORange(minISO: 160, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: false,
      );
    } else if (upperModel.contains('X-M5')) {
      return const CameraSpecs(
        sensorType: 'X-Trans CMOS 4',
        sensorSize: 'APS-C',
        megapixels: 26,
        isoRange: ISORange(minISO: 160, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: false,
      );
    } else if (upperModel.contains('GFX50S')) {
      return CameraSpecs(
        sensorType: 'CMOS',
        sensorSize: 'Medium Format (44x33mm)',
        megapixels: 51,
        isoRange: const ISORange(minISO: 100, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: hasPixelShift,
      );
    } else if (upperModel.contains('GFX100')) {
      return CameraSpecs(
        sensorType: upperModel.contains('II') ? 'CMOS II' : 'CMOS',
        sensorSize: 'Medium Format (44x33mm)',
        megapixels: upperModel.contains('100') ? 102 : 100,
        isoRange: const ISORange(minISO: 80, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: hasPixelShift,
      );
    } else if (upperModel.contains('X-PRO3')) {
      return const CameraSpecs(
        sensorType: 'X-Trans CMOS 4',
        sensorSize: 'APS-C',
        megapixels: 26,
        isoRange: ISORange(minISO: 160, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: false,
      );
    } else {
      // Default specs for unknown models
      return const CameraSpecs(
        sensorType: 'Unknown',
        sensorSize: 'Unknown',
        megapixels: 0,
        isoRange: ISORange(minISO: 100, maxISO: 12800, availableISOs: <int>[]),
        hasPixelShift: false,
      );
    }
  }

  static bool _supportsPixelShift(String model) {
    // Check if model supports pixel shift based on SDK capabilities
    // This would normally be checked via API_CODE_CapPixelShiftSettings
    final upperModel = model.toUpperCase();
    return upperModel.contains('X-T5') ||
           upperModel.contains('X-H2') && !upperModel.contains('X-H2S') ||
           upperModel.contains('GFX50S') ||
           upperModel.contains('GFX100');
  }
}

// Pixel shift settings
class PixelShiftSettings { // number of shots to take

  const PixelShiftSettings({
    required this.enabled,
    required this.interval,
    required this.shots,
  });
  final bool enabled;
  final int interval; // milliseconds
  final int shots;
}

// Pixel shift status
class PixelShiftState {

  const PixelShiftState({
    this.status = PixelShiftStatus.idle,
    this.progress = 0,
    this.imagesTaken = 0,
    this.totalImages = 0,
    this.error,
    this.message,
    this.downloadedFiles,
  });
  final PixelShiftStatus status;
  final int progress;
  final int imagesTaken;
  final int totalImages;
  final String? error;
  final String? message;
  final List<String>? downloadedFiles;

  PixelShiftState copyWith({
    PixelShiftStatus? status,
    int? progress,
    int? imagesTaken,
    int? totalImages,
    String? error,
    String? message,
    List<String>? downloadedFiles,
  }) => PixelShiftState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      imagesTaken: imagesTaken ?? this.imagesTaken,
      totalImages: totalImages ?? this.totalImages,
      error: error ?? this.error,
      message: message ?? this.message,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
    );
}

enum PixelShiftStatus {
  idle,
  starting,
  capturing,
  waitingForManualTrigger,
  downloading,
  finished,
  error,
  unknown,
}

// Connection status
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  unsupported,
}

enum ConnectionError {
  noCameraDetected,
  connectionFailed,
  unsupportedModel,
  sdkError,
  permissionDenied,
}
