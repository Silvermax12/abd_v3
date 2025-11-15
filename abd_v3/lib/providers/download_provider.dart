import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/download_task_model.dart';
import '../services/download_manager.dart';

// Provider for DownloadManager
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager.instance;
});

// State for downloads
class DownloadsState {
  final List<DownloadTask> tasks;
  final bool isLoading;
  final String? error;

  DownloadsState({
    this.tasks = const [],
    this.isLoading = false,
    this.error,
  });

  DownloadsState copyWith({
    List<DownloadTask>? tasks,
    bool? isLoading,
    String? error,
  }) {
    return DownloadsState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  List<DownloadTask> get activeTasks =>
      tasks.where((t) => t.isActive).toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.isCompleted).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.isFailed).toList();
}

// Notifier for downloads
class DownloadsNotifier extends StateNotifier<DownloadsState> {
  final DownloadManager _downloadManager;
  Timer? _refreshTimer;
  final Map<String, StreamSubscription> _progressSubscriptions = {};

  DownloadsNotifier(this._downloadManager) : super(DownloadsState()) {
    _loadTasks();
    _startPeriodicRefresh();
  }

  void _loadTasks() {
    final tasks = _downloadManager.getAllTasks();

    state = state.copyWith(tasks: tasks);

    // Subscribe to progress updates for active tasks
    for (final task in tasks) {
      if (task.isActive || task.status == DownloadStatus.processing) {
        _subscribeToProgress(task.id);
      }
    }
  }

  void _subscribeToProgress(String taskId) {
    if (_progressSubscriptions.containsKey(taskId)) {
      return;
    }

    final subscription = _downloadManager.getProgressStream(taskId).listen(
      (updatedTask) {
        debugPrint('DownloadProvider: Progress update received for ${updatedTask.animeTitle} - progress: ${updatedTask.progress}');
        final tasks = state.tasks.map((t) {
          return t.id == taskId ? updatedTask : t;
        }).toList();
        state = state.copyWith(tasks: tasks);
        debugPrint('DownloadProvider: State updated, tasks count: ${state.tasks.length}');
      },
      onError: (e) {
        debugPrint('DownloadProvider: Progress stream error: $e');
      },
    );

    _progressSubscriptions[taskId] = subscription;
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadTasks();
    });
  }

  Future<DownloadTask> addDownload({
    required String m3u8Url,
    required String animeTitle,
    required String episodeTitle,
    required int episodeNumber,
    required String resolution,
    required String animeSession,
    required String episodeSession,
  }) async {
    debugPrint('DownloadProvider: addDownload called for $animeTitle - Episode $episodeNumber ($resolution)');

    try {
      debugPrint('DownloadProvider: Calling download manager addDownload...');
      final task = await _downloadManager.addDownload(
        m3u8Url: m3u8Url,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        episodeNumber: episodeNumber,
        resolution: resolution,
        animeSession: animeSession,
        episodeSession: episodeSession,
      );

      _subscribeToProgress(task.id);
      _loadTasks();

      return task;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateTaskM3u8Url({
    required String taskId,
    required String? m3u8Url,
    required bool failed,
    String? errorMessage,
  }) async {
    debugPrint('DownloadProvider: updateTaskM3u8Url called for task $taskId - failed: $failed');
    
    try {
      await _downloadManager.updateTaskM3u8Url(
        taskId: taskId,
        m3u8Url: m3u8Url,
        failed: failed,
        errorMessage: errorMessage,
      );
      
      if (!failed && m3u8Url != null) {
        _subscribeToProgress(taskId);
      }
      
      _loadTasks();
    } catch (e) {
      debugPrint('DownloadProvider: Error updating task m3u8 URL: $e');
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> pauseDownload(String taskId) async {
    await _downloadManager.pauseDownload(taskId);
    _loadTasks();
  }

  Future<void> resumeDownload(String taskId) async {
    await _downloadManager.resumeDownload(taskId);
    _subscribeToProgress(taskId);
    _loadTasks();
  }

  Future<void> cancelDownload(String taskId) async {
    await _downloadManager.cancelDownload(taskId);
    _progressSubscriptions[taskId]?.cancel();
    _progressSubscriptions.remove(taskId);
    _loadTasks();
  }

  Future<void> deleteTask(String taskId) async {
    await _downloadManager.deleteTask(taskId);
    _progressSubscriptions[taskId]?.cancel();
    _progressSubscriptions.remove(taskId);
    _loadTasks();
  }

  Future<void> clearCompleted() async {
    await _downloadManager.clearCompleted();
    _loadTasks();
  }

  void refresh() {
    _loadTasks();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final subscription in _progressSubscriptions.values) {
      subscription.cancel();
    }
    _progressSubscriptions.clear();
    super.dispose();
  }
}

// Provider for downloads
final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
  final downloadManager = ref.watch(downloadManagerProvider);
  return DownloadsNotifier(downloadManager);
});

