import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fujifilm_shift_app/src/features/camera/data/services/camera_service.dart';

class CameraSettingsManager extends StatelessWidget {
  const CameraSettingsManager({
    required this.cameraService,
    super.key,
  });

  final CameraService cameraService;

  Future<void> _saveSettingsToFile(BuildContext context) async {
    try {
      final settings = await cameraService.getCameraSettings();
      if (settings == null) {
        _showSnackBar(context, 'Failed to retrieve camera settings.');
        return;
      }

      final fileName =
          'fujifilm-settings-${DateTime.now().millisecondsSinceEpoch}.bin';
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Camera Settings',
        fileName: fileName,
      );

      if (outputFile != null) {
        await File(outputFile).writeAsBytes(settings);
        _showSnackBar(context, 'Settings saved to $outputFile');
      }
    } catch (e) {
      _showSnackBar(context, 'Error saving settings: $e');
    }
  }

  Future<void> _loadSettingsFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final settings = await file.readAsBytes();
        
        final success = await cameraService.setCameraSettings(settings);
        
        if (success) {
          _showSnackBar(context, 'Successfully applied settings from ${file.path}.');
        } else {
          _showSnackBar(context, 'Failed to apply settings.');
        }
      }
    } catch (e) {
      _showSnackBar(context, 'Error loading settings: $e');
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings Management (for Debugging)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use these tools to discover the byte offsets for Pixel Shift settings. '
              '1. Save the current settings. '
              '2. Manually change one setting on the camera. '
              '3. Save the new settings. '
              '4. Compare the two files in a hex editor to find the changed byte.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _saveSettingsToFile(context),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save Settings'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _loadSettingsFromFile(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Load Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
