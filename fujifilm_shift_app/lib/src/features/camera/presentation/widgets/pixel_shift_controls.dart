import 'package:flutter/material.dart';
import '../../data/models/camera_models.dart';

class PixelShiftControls extends StatelessWidget {

  const PixelShiftControls({
    required this.state, required this.onStart, required this.onDownload, super.key,
  });
  final PixelShiftState state;
  final VoidCallback onStart;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          "Pixel Shift Controls",
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

  Widget _buildStatusIndicator(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
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
            if (state.status == PixelShiftStatus.capturing) ...<Widget>[
              const Spacer(),
              Text(
                "${state.imagesTaken} / ${state.totalImages}",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
        if (state.message != null) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getStatusColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _getStatusColor(context).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: _getStatusColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.message!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _getStatusColor(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

  Widget _buildProgressBar(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: LinearProgressIndicator(
        value: state.progress / 100,
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
    );

  Widget _buildErrorState(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        "Error: ${state.error}",
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );

  Widget _buildActionButtons(BuildContext context) {
    final isIdle = state.status == PixelShiftStatus.idle ||
        state.status == PixelShiftStatus.error;
    final isFinished = state.status == PixelShiftStatus.finished;
    final isBusy =
        state.status == PixelShiftStatus.starting ||
        state.status == PixelShiftStatus.capturing ||
        state.status == PixelShiftStatus.waitingForManualTrigger ||
        state.status == PixelShiftStatus.downloading;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (isIdle)
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Capture'),
          ),
        if (isBusy)
          ElevatedButton.icon(
            onPressed: null,
            icon: state.status == PixelShiftStatus.waitingForManualTrigger
                ? const Icon(Icons.touch_app, size: 20)
                : const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            label: Text(state.status == PixelShiftStatus.waitingForManualTrigger 
                ? 'Press Camera Shutter' 
                : 'Processing...'),
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
      case PixelShiftStatus.starting:
        return 'Starting capture...';
      case PixelShiftStatus.capturing:
        return 'Capturing images...';
      case PixelShiftStatus.waitingForManualTrigger:
        return 'Waiting for manual trigger';
      case PixelShiftStatus.downloading:
        return 'Downloading images...';
      case PixelShiftStatus.finished:
        return 'Capture complete. Ready to download.';
      case PixelShiftStatus.error:
        return 'An error occurred';
      case PixelShiftStatus.unknown:
        return 'Unknown status';
    }
  }

  IconData _getStatusIcon() {
    switch (state.status) {
      case PixelShiftStatus.idle:
        return Icons.camera;
      case PixelShiftStatus.starting:
        return Icons.camera;
      case PixelShiftStatus.capturing:
        return Icons.camera_roll;
      case PixelShiftStatus.waitingForManualTrigger:
        return Icons.touch_app;
      case PixelShiftStatus.downloading:
        return Icons.downloading;
      case PixelShiftStatus.finished:
        return Icons.check_circle;
      case PixelShiftStatus.error:
        return Icons.error;
      case PixelShiftStatus.unknown:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(BuildContext context) {
    switch (state.status) {
      case PixelShiftStatus.idle:
        return Theme.of(context).colorScheme.onSurface;
      case PixelShiftStatus.starting:
      case PixelShiftStatus.capturing:
      case PixelShiftStatus.downloading:
        return Theme.of(context).colorScheme.primary;
      case PixelShiftStatus.waitingForManualTrigger:
        return Colors.orange;
      case PixelShiftStatus.finished:
        return Theme.of(context).colorScheme.secondary;
      case PixelShiftStatus.error:
        return Theme.of(context).colorScheme.error;
      case PixelShiftStatus.unknown:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    }
  }
}
