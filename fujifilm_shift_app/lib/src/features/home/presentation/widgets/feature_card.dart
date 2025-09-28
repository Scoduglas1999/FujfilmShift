import "package:flutter/material.dart";

class FeatureCard extends StatelessWidget {
  const FeatureCard({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <dynamic>[
        Text(
          "Key Features",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _FeatureItem(
          icon: Icons.camera_alt_outlined,
          title: "Pixel-Shift Control",
          description: "Configure and control multi-shot pixel-shift sequences with precision timing and settings.",
        ),
        const SizedBox(height: 12),
        _FeatureItem(
          icon: Icons.download_outlined,
          title: "Automatic Download",
          description: "Seamlessly download RAW files from your camera's SD card after capture.",
        ),
        const SizedBox(height: 12),
        _FeatureItem(
          icon: Icons.auto_awesome,
          title: "Computational Stitching",
          description: "Advanced algorithms combine multiple exposures into a single high-resolution image.",
        ),
        const SizedBox(height: 12),
        _FeatureItem(
          icon: Icons.cloud_upload_outlined,
          title: "Cloud Integration",
          description: "Export processed images directly to cloud storage services.",
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <dynamic>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <dynamic>[
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
