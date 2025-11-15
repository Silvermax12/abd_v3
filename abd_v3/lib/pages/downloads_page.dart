import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_provider.dart';
import '../widgets/download_progress_card.dart';
import '../models/download_task_model.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsState = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: 'Active (${_getAllActiveTasks(downloadsState).length})',
            ),
            Tab(
              text: 'Completed (${downloadsState.completedTasks.length})',
            ),
            Tab(
              text: 'Failed (${_getAllFailedTasks(downloadsState).length})',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(downloadsProvider.notifier).refresh();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_completed') {
                await ref.read(downloadsProvider.notifier).clearCompleted();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Completed downloads cleared')),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_completed',
                child: Row(
                  children: [
                    Icon(Icons.clear_all),
                    SizedBox(width: 8),
                    Text('Clear Completed'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(_getAllActiveTasks(downloadsState), 'active'),
          _buildTaskList(downloadsState.completedTasks, 'completed'),
          _buildTaskList(_getAllFailedTasks(downloadsState), 'failed'),
        ],
      ),
    );
  }

  List<DownloadTask> _getAllActiveTasks(DownloadsState state) {
    // Include downloading, queued, processing, and fetchingM3u8 tasks as active
    return state.tasks.where((task) =>
      task.status == DownloadStatus.downloading ||
      task.status == DownloadStatus.queued ||
      task.status == DownloadStatus.processing ||
      task.status == DownloadStatus.fetchingM3u8
    ).toList();
  }

  List<DownloadTask> _getAllFailedTasks(DownloadsState state) {
    // Include failed and cancelled tasks as failed/terminated
    return state.tasks.where((task) =>
      task.status == DownloadStatus.failed ||
      task.status == DownloadStatus.cancelled
    ).toList();
  }

  Widget _buildTaskList(List<DownloadTask> tasks, String category) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getEmptyIcon(category),
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(category),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return DownloadProgressCard(
          task: task,
          onPause: () {
            ref.read(downloadsProvider.notifier).pauseDownload(task.id);
          },
          onResume: () {
            ref.read(downloadsProvider.notifier).resumeDownload(task.id);
          },
          onCancel: () {
            _showCancelDialog(task);
          },
          onDelete: () {
            _showDeleteDialog(task);
          },
        );
      },
    );
  }

  IconData _getEmptyIcon(String category) {
    switch (category) {
      case 'active':
        return Icons.cloud_download_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.folder_outlined;
    }
  }

  String _getEmptyMessage(String category) {
    switch (category) {
      case 'active':
        return 'No active downloads';
      case 'completed':
        return 'No completed downloads';
      case 'failed':
        return 'No failed downloads';
      default:
        return 'No downloads';
    }
  }

  void _showCancelDialog(DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Download'),
        content: Text(
          'Are you sure you want to cancel downloading "${task.episodeTitle}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              ref.read(downloadsProvider.notifier).cancelDownload(task.id);
              Navigator.pop(context);
            },
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text(
          'Are you sure you want to delete "${task.episodeTitle}" from the list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              ref.read(downloadsProvider.notifier).deleteTask(task.id);
              Navigator.pop(context);
            },
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

