import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/camera_provider.dart';
import '../../../camera/data/models/camera_models.dart';
import '../../../camera/presentation/pages/camera_dashboard_page.dart';

class CameraConnectionCard extends ConsumerWidget {
  const CameraConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final cameraInfo = ref.watch(connectedCameraProvider);
    final hasError = ref.watch(cameraErrorProvider) != null;

    ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getConnectionColor(context, connectionStatus),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Camera Connection',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _getConnectionStatusText(connectionStatus),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _getConnectionColor(context, connectionStatus),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _getConnectionDescription(context, connectionStatus, cameraInfo),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (cameraInfo != null) ...<Widget>[
            const SizedBox(height: 12),
            _buildCameraInfo(context, cameraInfo),
          ],
          const SizedBox(height: 16),
          if (connectionStatus == ConnectionStatus.disconnected) ...<Widget>[
            _buildCameraSelection(context, ref),
          ] else if (connectionStatus == ConnectionStatus.connected) ...<Widget>[
            _buildConnectedActions(context, ref),
          ] else if (connectionStatus == ConnectionStatus.connecting) ...<Widget>[
            _buildConnectingState(context),
          ] else if (hasError) ...<Widget>[
            _buildErrorState(context, ref),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraInfo(BuildContext context, cameraInfo) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "${cameraInfo.model} • ${cameraInfo.serialNumber}",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(
                Icons.battery_std_outlined,
                size: 16,
                color: _getBatteryColor(context, cameraInfo.battery?.status),
              ),
              const SizedBox(width: 4),
              Text(
                cameraInfo.battery != null
                    ? "${cameraInfo.battery.capacity}%"
                    : "Battery: Unknown",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cameraInfo.supportsPixelShift
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cameraInfo.supportsPixelShift ? "Pixel Shift" : "Standard",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cameraInfo.supportsPixelShift
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

  Widget _buildCameraSelection(BuildContext context, WidgetRef ref) {
    final availableCameras = ref.watch(availableCamerasProvider);

    if (availableCameras.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _scanForCameras(context, ref),
          icon: const Icon(Icons.search_outlined),
          label: const Text('Scan for Cameras'),
        ),
      );
    }

    return Column(
      children: <Widget>[
        ...availableCameras.map((CameraInfo camera) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _connectToCamera(context, ref, camera.model),
              icon: const Icon(Icons.link_outlined),
              label: Text('Connect ${camera.model}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _scanForCameras(context, ref),
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Rescan'),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedActions(BuildContext context, WidgetRef ref) => Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _disconnectCamera(context, ref),
            icon: const Icon(Icons.link_off_outlined),
            label: const Text("Disconnect"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _navigateToCameraDashboard(context),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text("Details"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );

  Widget _buildConnectingState(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text("Connecting to camera..."),
        ],
      ),
    );

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    final error = ref.watch(cameraErrorProvider);
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getErrorMessage(error),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _retryConnection(context, ref),
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Color _getConnectionColor(BuildContext context, ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Theme.of(context).colorScheme.secondary;
      case ConnectionStatus.connecting:
        return Theme.of(context).colorScheme.primary;
      case ConnectionStatus.error:
        return Theme.of(context).colorScheme.error;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.unsupported:
        return Theme.of(context).colorScheme.error;
    }
  }

  String _getConnectionStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting';
      case ConnectionStatus.error:
        return 'Demo Mode';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.unsupported:
        return 'Unsupported';
    }
  }

  String _getConnectionDescription(
    BuildContext context,
    ConnectionStatus status,
    cameraInfo,
  ) {
    switch (status) {
      case ConnectionStatus.connected:
        if (cameraInfo != null) {
          return '${cameraInfo.model} is connected and ready for pixel-shift capture.';
        }
        return 'Camera is connected and ready for pixel-shift capture.';
      case ConnectionStatus.connecting:
        return 'Establishing connection to your Fujifilm camera...';
      case ConnectionStatus.error:
        return 'Fujifilm SDK not available. Running in demo mode with simulated cameras. Select a demo camera to explore features.';
      case ConnectionStatus.disconnected:
        return 'Connect your Fujifilm camera to start using pixel-shift features.';
      case ConnectionStatus.unsupported:
        return 'Connected camera does not support pixel-shift functionality.';
    }
  }

  Color _getBatteryColor(BuildContext context, batteryStatus) {
    if (batteryStatus == null) return Theme.of(context).colorScheme.onSurfaceVariant;

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

  String _getErrorMessage(ConnectionError? error) {
    switch (error) {
      case ConnectionError.noCameraDetected:
        return 'No cameras detected. Please ensure your camera is connected and powered on.';
      case ConnectionError.connectionFailed:
        return 'Failed to connect to camera. Please check your USB connection.';
      case ConnectionError.unsupportedModel:
        return 'Connected camera model is not supported for pixel-shift.';
      case ConnectionError.sdkError:
        return 'Fujifilm SDK not available. Running in demo mode with simulated cameras. To use real cameras, install the Fujifilm X Series Digital Camera Shooting SDK.';
      case ConnectionError.permissionDenied:
        return 'Permission denied. Please check camera permissions.';
      default:
        return 'An unknown error occurred.';
    }
  }

  void _connectToCamera(BuildContext context, WidgetRef ref, String model) {
    final cameraNotifier = ref.read(cameraProvider.notifier);
    cameraNotifier.connectToCamera(model);
  }

  void _disconnectCamera(BuildContext context, WidgetRef ref) {
    final cameraNotifier = ref.read(cameraProvider.notifier);
    cameraNotifier.disconnectCamera();
  }

  void _navigateToCameraDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (BuildContext context) => const CameraDashboardPage()),
    );
  }

  void _scanForCameras(BuildContext context, WidgetRef ref) {
    // Trigger manual camera detection
    ref.read(cameraProvider.notifier).detectCameras();
    
    // Show feedback to user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scanning for connected Fujifilm cameras...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _retryConnection(BuildContext context, WidgetRef ref) {
    // Retry the initialization process
    final cameraNotifier = ref.read(cameraProvider.notifier);
    cameraNotifier.retryInitialization();
  }
}
