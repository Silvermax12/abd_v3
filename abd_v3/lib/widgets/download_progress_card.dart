import 'package:flutter/material.dart';
import '../models/download_task_model.dart';

class DownloadProgressCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  const DownloadProgressCard({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.animeTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Episode ${task.episodeNumber} - ${task.resolution}p',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar or fetching indicator
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued ||
                task.status == DownloadStatus.processing)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(height: 8),
                ],
              )
            else if (task.status == DownloadStatus.fetchingM3u8)
              Column(
                children: [
                  LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.cyan.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fetching download link...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),

            // Stats row
            _buildStatsRow(),

            // Error message
            if (task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                'Error: ${task.errorMessage}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Action buttons
            const SizedBox(height: 8),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    String label;
    IconData icon;

    switch (task.status) {
      case DownloadStatus.queued:
        color = Colors.orange;
        label = 'Queued';
        icon = Icons.schedule;
        break;
      case DownloadStatus.downloading:
        color = Colors.blue;
        label = 'Downloading';
        icon = Icons.download;
        break;
      case DownloadStatus.paused:
        color = Colors.grey;
        label = 'Paused';
        icon = Icons.pause;
        break;
      case DownloadStatus.completed:
        color = Colors.green;
        label = 'Completed';
        icon = Icons.check_circle;
        break;
      case DownloadStatus.failed:
        color = Colors.red;
        label = 'Failed';
        icon = Icons.error;
        break;
      case DownloadStatus.cancelled:
        color = Colors.grey;
        label = 'Cancelled';
        icon = Icons.cancel;
        break;
      case DownloadStatus.processing:
        color = Colors.purple;
        label = 'Processing';
        icon = Icons.settings;
        break;
      case DownloadStatus.fetchingM3u8:
        color = Colors.cyan;
        label = 'Fetching M3U8';
        icon = Icons.link;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = <Widget>[];

    // Progress percentage
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued ||
        task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.processing) {
      stats.add(_buildStat(
        Icons.pie_chart,
        task.displayProgress,
      ));
    }

    // Download speed
    if (task.status == DownloadStatus.downloading && task.speedMBps > 0) {
      stats.add(_buildStat(
        Icons.speed,
        task.displaySpeed,
      ));
    }

    // ETA
    if (task.status == DownloadStatus.downloading && task.etaSeconds != null) {
      stats.add(_buildStat(
        Icons.access_time,
        task.displayETA,
      ));
    }

    // File size
    if (task.totalBytes != null || task.downloadedBytes > 0) {
      stats.add(_buildStat(
        Icons.storage,
        task.displaySize,
      ));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (int i = 0; i < stats.length; i++) ...[
          stats[i],
          if (i < stats.length - 1) const SizedBox(width: 16),
        ],
      ],
    );
  }

  Widget _buildStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final buttons = <Widget>[];

    if (task.canPause && onPause != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onPause,
          icon: const Icon(Icons.pause, size: 16),
          label: const Text('Pause'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    if (task.canResume && onResume != null) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Resume'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    if (task.canCancel && onCancel != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    if ((task.status == DownloadStatus.completed ||
            task.status == DownloadStatus.cancelled ||
            task.status == DownloadStatus.failed) &&
        onDelete != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete, size: 16),
          label: const Text('Delete'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons,
    );
  }
}

