import "package:flutter/material.dart";

class CameraDashboardPage extends StatelessWidget {
  const CameraDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Camera Control"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <dynamic>[
            // Camera status card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <dynamic>[
                    Row(
                      children: <dynamic>[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "No Camera Connected",
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Connect your Fujifilm camera to access pixel-shift controls and capture features.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _scanForCameras,
                        icon: const Icon(Icons.search),
                        label: const Text("Scan for Cameras"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Available cameras list (when connected)
            Text(
              "Available Cameras",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                children: <_CameraListItem>[
                  _CameraListItem(
                    name: "X-T5",
                    model: "Fujifilm X-T5",
                    status: "Disconnected",
                    onTap: () => _connectToCamera("X-T5"),
                  ),
                  _CameraListItem(
                    name: "X-H2S",
                    model: "Fujifilm X-H2S",
                    status: "Disconnected",
                    onTap: () => _connectToCamera("X-H2S"),
                  ),
                  _CameraListItem(
                    name: "GFX100S",
                    model: "Fujifilm GFX100S",
                    status: "Disconnected",
                    onTap: () => _connectToCamera("GFX100S"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scanForCameras() {
    // TODO: Implement camera scanning
  }

  void _connectToCamera(String cameraName) {
    // TODO: Implement camera connection
  }
}

class _CameraListItem extends StatelessWidget {

  const _CameraListItem({
    required this.name,
    required this.model,
    required this.status,
    required this.onTap,
  });
  final String name;
  final String model;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          child: Icon(
            Icons.camera_alt_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          model,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(theme),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _getStatusTextColor(theme),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Color _getStatusColor(ThemeData theme) {
    switch (status) {
      case "Connected":
        return theme.colorScheme.secondary.withOpacity(0.1);
      case "Disconnected":
        return theme.colorScheme.error.withOpacity(0.1);
      default:
        return theme.colorScheme.surfaceVariant;
    }
  }

  Color _getStatusTextColor(ThemeData theme) {
    switch (status) {
      case "Connected":
        return theme.colorScheme.secondary;
      case "Disconnected":
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
