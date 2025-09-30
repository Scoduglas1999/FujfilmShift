import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/camera_provider.dart';
import '../../data/models/camera_models.dart';
import '../widgets/camera_settings_manager.dart';
import '../widgets/pixel_shift_controls.dart';

class CameraDashboardPage extends ConsumerStatefulWidget {
  const CameraDashboardPage({super.key});

  @override
  ConsumerState<CameraDashboardPage> createState() => _CameraDashboardPageState();
}

class _CameraDashboardPageState extends ConsumerState<CameraDashboardPage> {
  @override
  void initState() {
    super.initState();
    // Refresh camera info when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cameraProvider.notifier).refreshCameraInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cameraInfo = ref.watch(connectedCameraProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Details'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCameraInfo,
          ),
        ],
      ),
      body: cameraInfo == null
          ? _buildNoCameraState(context)
          : _buildCameraDetails(context, cameraInfo),
    );
  }

  Widget _buildNoCameraState(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.camera_alt_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            "No Camera Connected",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            "Connect your Fujifilm camera from the home screen to view detailed information.",
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text("Go Back"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildCameraDetails(BuildContext context, cameraInfo) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Camera header card
          _buildCameraHeaderCard(context, cameraInfo),

          const SizedBox(height: 24),

          // Camera specifications
          _buildSpecificationsCard(context, cameraInfo),

          const SizedBox(height: 24),

          // Battery information
          if (cameraInfo.battery != null)
            _buildBatteryCard(context, cameraInfo.battery),

          const SizedBox(height: 24),

          // Pixel shift capability
          _buildPixelShiftCard(context, cameraInfo),

          const SizedBox(height: 24),

          // Connection details
          _buildConnectionCard(context, cameraInfo),
 
          const SizedBox(height: 24),
 
          // Settings Management Card
          CameraSettingsManager(cameraService: ref.read(cameraServiceProvider)),
        ],
      ),
    );

  Widget _buildCameraHeaderCard(BuildContext context, cameraInfo) => Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    cameraInfo.model,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Serial: ${cameraInfo.serialNumber}",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Firmware: ${cameraInfo.firmwareVersion}",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cameraInfo.supportsPixelShift
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                cameraInfo.supportsPixelShift ? "Pixel Shift Ready" : "Standard",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cameraInfo.supportsPixelShift
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildSpecificationsCard(BuildContext context, cameraInfo) {
    final specs = cameraInfo.specs;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Specifications',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildSpecRow(context, 'Sensor Type', specs.sensorType),
            const SizedBox(height: 12),
            _buildSpecRow(context, 'Sensor Size', specs.sensorSize),
            const SizedBox(height: 12),
            _buildSpecRow(context, 'Megapixels', '${specs.megapixels} MP'),
            const SizedBox(height: 12),
            _buildSpecRow(context, 'ISO Range', '${specs.isoRange.minISO} - ${specs.isoRange.maxISO}'),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard(BuildContext context, battery) => Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _getBatteryIcon(battery.status),
                  color: _getBatteryColor(context, battery.status),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  "Battery",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  "${battery.capacity}%",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _getBatteryColor(context, battery.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: battery.capacity / 100,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getBatteryColor(context, battery.status),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildBatteryDetail(
                    context,
                    "Status",
                    _getBatteryStatusText(battery.status),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildBatteryDetail(
                    context,
                    "Time Remaining",
                    "${battery.remainingTime} min",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

  Widget _buildPixelShiftCard(BuildContext context, CameraInfo cameraInfo) {
    final pixelShiftState = ref.watch(pixelShiftStateProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  cameraInfo.supportsPixelShift
                      ? Icons.high_quality_outlined
                      : Icons.camera_alt_outlined,
                  color: cameraInfo.supportsPixelShift
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Pixel Shift Support',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cameraInfo.supportsPixelShift
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                cameraInfo.supportsPixelShift
                    ? "This camera supports Fujifilm's advanced pixel-shift technology for ultra-high resolution images with improved color accuracy and reduced noise."
                    : 'This camera model does not support pixel-shift functionality. Consider using an X-T5, X-H2, or GFX series camera for pixel-shift features.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cameraInfo.supportsPixelShift
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (cameraInfo.supportsPixelShift) ...<Widget>[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
              PixelShiftControls(
                state: pixelShiftState,
                onStart: () {
                  // For now, use default settings. In the future, these could be configurable.
                  const settings = PixelShiftSettings(
                    enabled: true,
                    shots: 20, // A common value for high-res pixel shift
                    interval: 1000, // 1 second between shots
                  );
                  ref.read(cameraProvider.notifier).startPixelShift(settings);
                },
                onDownload: () {
                  ref.read(cameraProvider.notifier).downloadPixelShiftImages();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context, cameraInfo) => Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "Connection Details",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildSpecRow(context, "Connection Type", cameraInfo.connectionType.toUpperCase()),
            const SizedBox(height: 12),
            _buildSpecRow(context, "Status", "Connected"),
          ],
        ),
      ),
    );

  Widget _buildSpecRow(BuildContext context, String label, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            "$label:",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

  Widget _buildBatteryDetail(BuildContext context, String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

  IconData _getBatteryIcon(batteryStatus) {
    switch (batteryStatus) {
      case BatteryStatus.full:
        return Icons.battery_full;
      case BatteryStatus.normal:
        return Icons.battery_6_bar;
      case BatteryStatus.low:
        return Icons.battery_3_bar;
      case BatteryStatus.critical:
        return Icons.battery_1_bar;
      case BatteryStatus.charging:
        return Icons.battery_charging_full;
      default:
        return Icons.battery_unknown;
    }
  }

  Color _getBatteryColor(BuildContext context, batteryStatus) {
    switch (batteryStatus) {
      case BatteryStatus.full:
        return Theme.of(context).colorScheme.secondary;
      case BatteryStatus.normal:
        return Colors.orange;
      case BatteryStatus.low:
        return Theme.of(context).colorScheme.error;
      case BatteryStatus.critical:
        return Theme.of(context).colorScheme.error;
      case BatteryStatus.charging:
        return Theme.of(context).colorScheme.primary;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _getBatteryStatusText(batteryStatus) {
    switch (batteryStatus) {
      case BatteryStatus.full:
        return 'Full';
      case BatteryStatus.normal:
        return 'Good';
      case BatteryStatus.low:
        return 'Low';
      case BatteryStatus.critical:
        return 'Critical';
      case BatteryStatus.charging:
        return 'Charging';
      default:
        return 'Unknown';
    }
  }

  void _refreshCameraInfo() {
    ref.read(cameraProvider.notifier).refreshCameraInfo();
  }
}
