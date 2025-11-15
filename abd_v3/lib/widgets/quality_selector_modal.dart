import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/episode_model.dart';
import '../providers/quality_provider.dart';
import '../providers/download_provider.dart';
import '../providers/episode_list_provider.dart';

class QualitySelectorModal extends ConsumerStatefulWidget {
  final String animeSession;
  final String episodeSession;
  final String animeTitle;

  const QualitySelectorModal({
    super.key,
    required this.animeSession,
    required this.episodeSession,
    required this.animeTitle,
  });

  @override
  ConsumerState<QualitySelectorModal> createState() =>
      _QualitySelectorModalState();
}

class _QualitySelectorModalState extends ConsumerState<QualitySelectorModal> {
  @override
  void initState() {
    super.initState();
    // Load qualities on init
    Future.microtask(() {
      final providerKey = '${widget.animeSession}_${widget.episodeSession}';
      ref
          .read(qualityProvider(providerKey).notifier)
          .loadQualities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final providerKey = '${widget.animeSession}_${widget.episodeSession}';
    final qualityState = ref.watch(qualityProvider(providerKey));

    // Debug logging
    debugPrint('QualitySelectorModal: Building for key $providerKey - isLoading: ${qualityState.isLoading}, options: ${qualityState.options.length}, error: ${qualityState.error}');
    for (final option in qualityState.options) {
      debugPrint('  - Option: ${option.label} (${option.resolution})');
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.high_quality, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Quality',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Body
          Flexible(
            child: _buildBody(qualityState),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(QualityState state) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading quality options...'),
            ],
          ),
        ),
      );
    }

    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error: ${state.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  final providerKey = '${widget.animeSession}_${widget.episodeSession}';
                  ref
                      .read(qualityProvider(providerKey).notifier)
                      .loadQualities();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text('No quality options found'),
            ],
          ),
        ),
      );
    }

    if (state.isExtractingM3U8) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Extracting download link...'),
              SizedBox(height: 8),
              Text(
                'This may take up to 20 seconds',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.options.length,
      itemBuilder: (context, index) {
        final quality = state.options[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.high_quality,
                color: Colors.blue,
              ),
            ),
          ),
          title: Text(quality.label),
          subtitle: const Text('Click to download'),
          trailing: const Icon(Icons.download),
          onTap: () => _handleQualitySelect(quality),
        );
      },
    );
  }

  Future<void> _handleQualitySelect(quality) async {
    debugPrint('QualitySelectorModal: _handleQualitySelect called for ${quality.label}');
    
    // Get episode details first
    final episodeState = ref.read(episodeListProvider(widget.animeSession));
    final episode = episodeState.episodes.firstWhere(
      (e) => e.session == widget.episodeSession,
      orElse: () => Episode(
        session: widget.episodeSession,
        number: 0,
        title: 'Unknown',
        animeSession: widget.animeSession,
      ),
    );

    try {
      // Create download card immediately with a temporary placeholder URL
      debugPrint('QualitySelectorModal: Creating download card immediately...');
      final task = await ref.read(downloadsProvider.notifier).addDownload(
            m3u8Url: 'pending://fetching', // Placeholder URL
            animeTitle: widget.animeTitle,
            episodeTitle: episode.title,
            episodeNumber: episode.number,
            resolution: quality.label,
            animeSession: widget.animeSession,
            episodeSession: widget.episodeSession,
          );

      if (!mounted) return;

      // Close dialog and show success message immediately
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fetching download link for Episode ${episode.number}...'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              Navigator.pushNamed(context, '/downloads');
            },
          ),
        ),
      );

      // Extract m3u8 in the background with retry logic
      final providerKey = '${widget.animeSession}_${widget.episodeSession}';
      debugPrint('QualitySelectorModal: Fetching M3U8 in background for provider key: $providerKey');
      
      // Get provider references before async operation to avoid ref issues after widget disposal
      final downloadsNotifier = ref.read(downloadsProvider.notifier);
      final qualityNotifier = ref.read(qualityProvider(providerKey).notifier);
      
      // Run in background
      _fetchM3u8InBackground(task.id, quality, downloadsNotifier, qualityNotifier);
      
    } catch (e) {
      debugPrint('QualitySelectorModal: Error creating download task: $e');
      if (!mounted) return;

      // Show retry dialog instead of snackbar for M3U8 extraction failures
      showDialog(
        context: context,
        barrierDismissible: false, // Prevent accidental dismissal
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Download Link Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Failed to extract download link for ${quality.label}:',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Click Retry to attempt extraction again, or Cancel to return to quality selection.',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                Navigator.of(context).pop(); // Close quality modal
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                // Retry the same quality selection
                _handleQualitySelect(quality);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  }

  // Background m3u8 fetching with automatic task update
  // Uses provider notifiers directly instead of ref to avoid disposal issues
  void _fetchM3u8InBackground(
    String taskId,
    quality,
    DownloadsNotifier downloadsNotifier,
    QualityNotifier qualityNotifier,
  ) async {
    try {
      debugPrint('QualitySelectorModal: Background M3U8 fetch started for task $taskId');
      
      // Extract m3u8 with retry logic (3 attempts with exponential backoff)
      final m3u8 = await qualityNotifier.extractM3U8(quality, maxRetries: 3);

      if (m3u8 == null) {
        debugPrint('QualitySelectorModal: Background M3U8 fetch failed for task $taskId');
        // Update task status to failed
        await downloadsNotifier.updateTaskM3u8Url(
          taskId: taskId,
          m3u8Url: null,
          failed: true,
          errorMessage: 'Failed to fetch download link after multiple retries',
        );
        return;
      }

      debugPrint('QualitySelectorModal: Background M3U8 fetch succeeded for task $taskId');
      // Update task with actual m3u8 URL
      await downloadsNotifier.updateTaskM3u8Url(
        taskId: taskId,
        m3u8Url: m3u8,
        failed: false,
      );
    } catch (e) {
      debugPrint('QualitySelectorModal: Background M3U8 fetch error for task $taskId: $e');
      // Update task status to failed
      try {
        await downloadsNotifier.updateTaskM3u8Url(
          taskId: taskId,
          m3u8Url: null,
          failed: true,
          errorMessage: e.toString(),
        );
      } catch (updateError) {
        debugPrint('QualitySelectorModal: Failed to update task status: $updateError');
        // Ignore update errors - task will remain in fetchingM3u8 state
      }
    }
  }
}

