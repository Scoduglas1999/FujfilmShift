import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ThemeData theme = Theme.of(context);
    ThemeNotifier themeNotifier = ref.watch(themeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // Appearance section
          _SettingsSection(
            title: 'Appearance',
            children: <Widget>[
              _SettingsTile(
                title: 'Theme',
                subtitle: _getThemeText(ref),
                leading: Icon(
                  _getThemeIcon(ref),
                  color: theme.colorScheme.primary,
                ),
                trailing: PopupMenuButton<ThemeMode>(
                  onSelected: themeNotifier.setTheme,
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<ThemeMode>>[
                    const PopupMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    const PopupMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    const PopupMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _getThemeText(ref),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_drop_down,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Camera section
          _SettingsSection(
            title: 'Camera',
            children: <Widget>[
              _SettingsTile(
                title: 'Auto-connect',
                subtitle: 'Automatically connect to last used camera',
                leading: Icon(
                  Icons.wifi,
                  color: theme.colorScheme.primary,
                ),
                trailing: Switch(
                  value: false, // TODO: Get from provider
                  onChanged: (bool value) {
                    // TODO: Update provider
                  },
                ),
              ),
              _DownloadLocationTile(ref: ref),
            ],
          ),

          const SizedBox(height: 32),

          // Processing section
          _SettingsSection(
            title: 'Processing',
            children: <Widget>[
              _SettingsTile(
                title: 'Auto-stitch',
                subtitle: 'Automatically stitch images after download',
                leading: Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                trailing: Switch(
                  value: true, // TODO: Get from provider
                  onChanged: (bool value) {
                    // TODO: Update provider
                  },
                ),
              ),
              _SettingsTile(
                title: 'Output Format',
                subtitle: 'TIFF',
                leading: Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.primary,
                ),
                onTap: () {
                  // TODO: Show format options
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          // About section
          _SettingsSection(
            title: 'About',
            children: <Widget>[
              _SettingsTile(
                title: 'Version',
                subtitle: '1.0.0',
                leading: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              _SettingsTile(
                title: 'Help & Support',
                subtitle: 'Get help and contact support',
                leading: Icon(
                  Icons.help_outline,
                  color: theme.colorScheme.primary,
                ),
                onTap: () {
                  // TODO: Show help
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getThemeText(WidgetRef ref) {
    ThemeMode theme = ref.watch(themeProvider);
    switch (theme) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System';
    }
  }

  IconData _getThemeIcon(WidgetRef ref) {
    ThemeMode theme = ref.watch(themeProvider);
    switch (theme) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      default:
        return Icons.brightness_auto;
    }
  }
}

class _SettingsSection extends StatelessWidget {

  const _SettingsSection({
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {

  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: leading,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _DownloadLocationTile extends StatelessWidget {
  const _DownloadLocationTile({required this.ref});
  
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final downloadLocation = ref.watch(downloadLocationProvider);
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        Icons.folder_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Download Location',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            downloadLocation.isEmpty ? 'Loading...' : downloadLocation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _pickDirectory(context, ref),
        tooltip: 'Change location',
      ),
      onTap: () => _pickDirectory(context, ref),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _pickDirectory(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Download Location',
      );

      if (result != null) {
        // Create directory if it doesn't exist
        final dir = Directory(result);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        await ref.read(downloadLocationProvider.notifier).setDownloadLocation(result);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download location set to: $result'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set download location: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
