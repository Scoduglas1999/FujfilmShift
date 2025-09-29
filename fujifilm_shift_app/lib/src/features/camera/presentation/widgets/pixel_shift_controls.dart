import 'package:flutter/material.dart';
import 'package:fujifilm_shift_app/src/features/camera/data/models/camera_models.dart';

class PixelShiftControls extends StatelessWidget {
  final PixelShiftState state;
  final VoidCallback onStart;
  final VoidCallback onDownload;

  const PixelShiftControls({
    super.key,
    required this.state,
    required this.onStart,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pixel Shift Controls',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        _buildStatusIndicator(context),
        const SizedBox(height: 20),
        if (state.status == PixelShiftStatus.capturing ||
            state.status == PixelShiftStatus.downloading)
          _buildProgressBar(context),
        if (state.error != null) _buildErrorState(context),
        const SizedBox(height: 20),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    return Row(
      children: [
        Icon(
          _getStatusIcon(),
          color: _getStatusColor(context),
        ),
        const SizedBox(width: 12),
        Text(
          _getStatusText(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: _getStatusColor(context),
              ),
        ),
        if (state.status == PixelShiftStatus.capturing) ...[
          const Spacer(),
          Text(
            '${state.imagesTaken} / ${state.totalImages}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: LinearProgressIndicator(
        value: state.progress / 100,
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Text(
        'Error: ${state.error}',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final bool isIdle = state.status == PixelShiftStatus.idle ||
        state.status == PixelShiftStatus.error;
    final bool isFinished = state.status == PixelShiftStatus.finished;
    final bool isBusy =
        state.status == PixelShiftStatus.capturing || state.status == PixelShiftStatus.downloading;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isIdle)
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Capture'),
          ),
        if (isBusy)
          const ElevatedButton(
            onPressed: null,
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (isFinished)
          ElevatedButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download RAWs'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).colorScheme.onSecondary,
            ),
          ),
      ],
    );
  }

  String _getStatusText() {
    switch (state.status) {
      case PixelShiftStatus.idle:
        return 'Ready to capture';
      case PixelShiftStatus.capturing:
        return 'Capturing images...';
      case PixelShiftStatus.downloading:
        return 'Downloading images...';
      case PixelShiftStatus.finished:
        return 'Capture complete. Ready to download.';
      case PixelShiftStatus.error:
        return 'An error occurred';
    }
  }

  IconData _getStatusIcon() {
    switch (state.status) {
      case PixelShiftStatus.idle:
        return Icons.camera;
      case PixelShiftStatus.capturing:
        return Icons.camera_roll;
      case PixelShiftStatus.downloading:
        return Icons.downloading;
      case PixelShiftStatus.finished:
        return Icons.check_circle;
      case PixelShiftStatus.error:
        return Icons.error;
    }
  }

  Color _getStatusColor(BuildContext context) {
    switch (state.status) {
      case PixelShiftStatus.idle:
        return Theme.of(context).colorScheme.onSurface;
      case PixelShiftStatus.capturing:
      case PixelShiftStatus.downloading:
        return Theme.of(context).colorScheme.primary;
      case PixelShiftStatus.finished:
        return Theme.of(context).colorScheme.secondary;
      case PixelShiftStatus.error:
        return Theme.of(context).colorScheme.error;
    }
  }
}
