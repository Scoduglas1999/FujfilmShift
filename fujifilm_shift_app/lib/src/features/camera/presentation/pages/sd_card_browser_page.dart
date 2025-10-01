import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../../../core/providers/camera_provider.dart';
import '../../../../core/providers/settings_provider.dart';

class SDCardBrowserPage extends ConsumerStatefulWidget {
  const SDCardBrowserPage({super.key});

  @override
  ConsumerState<SDCardBrowserPage> createState() => _SDCardBrowserPageState();
}

class _SDCardBrowserPageState extends ConsumerState<SDCardBrowserPage> {
  List<SDCardFile>? _files;
  bool _isLoading = true;
  String? _error;
  final Set<int> _selectedIndices = {};
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final files = await ref.read(cameraProvider.notifier).listSDCardFiles();
      setState(() {
        _files = files.where((f) => !f.isFolder && f.fileName.toUpperCase().endsWith('.RAF')).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadSelected() async {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select files to download'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final downloadLocation = ref.read(downloadLocationProvider);
    if (downloadLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set download location in settings'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Create directory if it doesn't exist
    final dir = Directory(downloadLocation);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    final selectedFiles = _selectedIndices.map((i) => _files![i]).toList();
    int completed = 0;

    for (final file in selectedFiles) {
      try {
        final destinationPath = '$downloadLocation${Platform.pathSeparator}${file.fileName}';
        final success = await ref.read(cameraProvider.notifier).downloadFileFromSDCard(
          file.index,
          destinationPath,
        );

        if (success) {
          completed++;
          setState(() {
            _downloadProgress = completed / selectedFiles.length;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to download ${file.fileName}'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error downloading ${file.fileName}: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    setState(() {
      _isDownloading = false;
      _selectedIndices.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Downloaded $completed of ${selectedFiles.length} files'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SD Card Browser'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLoading && _files != null && _files!.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (_selectedIndices.length == _files!.length) {
                    _selectedIndices.clear();
                  } else {
                    _selectedIndices.addAll(List.generate(_files!.length, (i) => i));
                  }
                });
              },
              icon: Icon(
                _selectedIndices.length == _files!.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              label: Text(
                _selectedIndices.length == _files!.length ? 'Deselect All' : 'Select All',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadFiles,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: _selectedIndices.isNotEmpty && !_isDownloading
          ? FloatingActionButton.extended(
              onPressed: _downloadSelected,
              icon: const Icon(Icons.download),
              label: Text('Download (${_selectedIndices.length})'),
            )
          : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading SD card contents...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load SD card',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files == null || _files!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No RAF files found',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The SD card appears to be empty or contains no RAF files.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_isDownloading)
          LinearProgressIndicator(
            value: _downloadProgress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _files!.length,
            itemBuilder: (context, index) {
              final file = _files![index];
              final isSelected = _selectedIndices.contains(index);

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withOpacity(0.2),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: CheckboxListTile(
                  value: isSelected,
                  onChanged: _isDownloading
                      ? null
                      : (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedIndices.add(index);
                            } else {
                              _selectedIndices.remove(index);
                            }
                          });
                        },
                  title: Text(
                    file.fileName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${(file.fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  secondary: Icon(
                    Icons.image_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
