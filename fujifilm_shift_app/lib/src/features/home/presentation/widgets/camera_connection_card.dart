import "package:flutter/material.dart";

class CameraConnectionCard extends StatelessWidget {
  const CameraConnectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <dynamic>[
          Row(
            children: <dynamic>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getConnectionColor(context),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Camera Connection",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _getConnectionStatus(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _getConnectionColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _getConnectionDescription(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_isDisconnected(context)) ...<dynamic>[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _connectCamera,
                icon: const Icon(Icons.link_outlined),
                label: const Text("Connect Camera"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...<dynamic>[
            Row(
              children: <dynamic>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _disconnectCamera,
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
                    onPressed: _configureCamera,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text("Configure"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getConnectionColor(BuildContext context) {
    // TODO: Get actual connection state from provider
    const bool isConnected = false; // Placeholder

    if (isConnected) {
      return Theme.of(context).colorScheme.secondary;
    } else {
      return Theme.of(context).colorScheme.error;
    }
  }

  String _getConnectionStatus(BuildContext context) {
    // TODO: Get actual connection state from provider
    const bool isConnected = false; // Placeholder

    return isConnected ? "Connected" : "Disconnected";
  }

  String _getConnectionDescription(BuildContext context) {
    // TODO: Get actual connection state from provider
    const bool isConnected = false; // Placeholder

    if (isConnected) {
      return "Your Fujifilm camera is connected and ready for pixel-shift capture.";
    } else {
      return "Connect your Fujifilm camera to start using pixel-shift features.";
    }
  }

  bool _isDisconnected(BuildContext context) {
    // TODO: Get actual connection state from provider
    return true; // Placeholder
  }

  void _connectCamera() {
    // TODO: Implement camera connection
  }

  void _disconnectCamera() {
    // TODO: Implement camera disconnection
  }

  void _configureCamera() {
    // TODO: Navigate to camera configuration
  }
}
