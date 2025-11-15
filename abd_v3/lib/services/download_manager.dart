import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task_model.dart';
import '../storage/hive_service.dart';
import '../storage/preferences_service.dart';
import 'cookie_manager_service.dart';
import 'download_m3u8.dart';

// Throughput Estimator for ETA calculation (from guide)
class ThroughputEstimator {
  final List<double> _samples = [];
  final int maxSamples;
  
  ThroughputEstimator({this.maxSamples = 10});
  
  void addSample(int bytes, int milliseconds) {
    if (milliseconds <= 0) return;
    
    final bps = bytes * 1000.0 / milliseconds;
    
    // Exponential moving average
    if (_samples.isEmpty) {
      _samples.add(bps);
    } else {
      const alpha = 0.3;
      final smoothed = (_samples.last * (1 - alpha)) + (bps * alpha);
      _samples.add(smoothed);
    }
    
    if (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }
  
  double get averageThroughput {
    if (_samples.isEmpty) return 0.0;
    return _samples.reduce((a, b) => a + b) / _samples.length;
  }
  
  String etaForRemainingBytes(int remainingBytes) {
    final bps = averageThroughput;
    if (bps <= 0 || remainingBytes <= 0) return '--';
    
    final seconds = remainingBytes / bps;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(0)}s';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = (seconds % 60).floor();
      return '${minutes}m ${remainingSeconds}s';
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).floor();
      return '${hours}h ${minutes}m';
    }
  }
  
  String get throughputText {
    final bps = averageThroughput;
    if (bps <= 0) return '--';
    
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bps >= 1024) {
      return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${bps.toStringAsFixed(0)} B/s';
    }
  }
}

class DownloadManager {
  static DownloadManager? _instance;
  static DownloadManager get instance {
    _instance ??= DownloadManager._();
    return _instance!;
  }

  DownloadManager._();

  final HiveService _hiveService = HiveService.instance;
  final PreferencesService _prefsService = PreferencesService.instance;

  final Map<String, StreamController<DownloadTask>> _progressControllers = {};
  
  int _activeDownloads = 0;
  final List<String> _processingQueue = [];

  // Get max concurrent downloads from preferences
  int get _maxConcurrentDownloads => _prefsService.maxConcurrentDownloads;

  // Helper method to download file using http package with proper headers
  Future<void> _downloadFile(String url, String savePath) async {
    final client = http.Client();
    try {
      final cookieManager = CookieManagerService.instance;
      final headers = _getHttpHeaders(url, cookieManager);
      
      final response = await client.get(Uri.parse(url), headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Download timeout');
        },
      );

      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  // Get HTTP headers with cookies and browser simulation
  Map<String, String> _getHttpHeaders(String url, CookieManagerService cookieManager) {
    final uri = Uri.parse(url);
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
      'Referer': '${uri.scheme}://${uri.host}/',
    };

    // Add cookies if available
    try {
      final cookieHeader = cookieManager.getCookieHeader();
      if (cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }
    } catch (e) {
      // Cookies might not be available, continue without them
      print('⚠️ Could not get cookies for request: $e');
    }

    return headers;
  }

  // Initialize
  Future<void> initialize() async {
    // Load persisted download tasks and resume if needed
    final tasks = _hiveService.getAllDownloadTasks();
    for (final task in tasks) {
      if (task.status == DownloadStatus.downloading) {
        // Mark as paused since app was restarted
        task.status = DownloadStatus.paused;
        await _hiveService.updateDownloadTask(task);
      }
    }
  }

  // Add a new download task
  Future<DownloadTask> addDownload({
    required String m3u8Url,
    required String animeTitle,
    required String episodeTitle,
    required int episodeNumber,
    required String resolution,
    required String animeSession,
    required String episodeSession,
  }) async {
    // Generate unique ID
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Get download path
    final outputPath = await _getDownloadPath(animeTitle, episodeNumber, resolution);

    // Check if m3u8 URL is pending (needs to be fetched in background)
    final isFetchingM3u8 = m3u8Url.startsWith('pending://');

    // Create task
    final task = DownloadTask(
      id: id,
      m3u8Url: m3u8Url,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
      episodeNumber: episodeNumber,
      resolution: resolution,
      outputPath: outputPath,
      animeSession: animeSession,
      episodeSession: episodeSession,
      status: isFetchingM3u8 ? DownloadStatus.fetchingM3u8 : DownloadStatus.queued,
    );

    // Save to storage
    await _hiveService.saveDownloadTask(task);

    // Start download if slots available (only for non-pending tasks)
    if (!isFetchingM3u8) {
      _processQueue();
    }

    return task;
  }

  // Update task m3u8 URL (called when background fetch completes)
  Future<void> updateTaskM3u8Url({
    required String taskId,
    required String? m3u8Url,
    required bool failed,
    String? errorMessage,
  }) async {
    final task = _hiveService.getDownloadTask(taskId);
    if (task == null) {
      throw Exception('Task not found: $taskId');
    }

    if (failed || m3u8Url == null) {
      // Mark as failed
      task.status = DownloadStatus.failed;
      task.errorMessage = errorMessage ?? 'Failed to fetch download link';
      await _hiveService.updateDownloadTask(task);
      _notifyProgress(task);
      return;
    }

    // Update with actual m3u8 URL and change status to queued
    final updatedTask = DownloadTask(
      id: task.id,
      m3u8Url: m3u8Url,
      animeTitle: task.animeTitle,
      episodeTitle: task.episodeTitle,
      episodeNumber: task.episodeNumber,
      resolution: task.resolution,
      outputPath: task.outputPath,
      animeSession: task.animeSession,
      episodeSession: task.episodeSession,
      status: DownloadStatus.queued,
      progress: 0.0,
      downloadedBytes: 0,
      totalBytes: task.totalBytes,
      speedMBps: 0.0,
      etaSeconds: task.etaSeconds,
      errorMessage: null,
      createdAt: task.createdAt,
      completedAt: null,
    );

    await _hiveService.updateDownloadTask(updatedTask);
    _notifyProgress(updatedTask);

    // Start download if slots available
    _processQueue();
  }

  // Get download path
  Future<String> _getDownloadPath(String animeTitle, int episodeNumber, String resolution) async {
    final basePath = _prefsService.downloadPath;
    Directory baseDir;

    if (basePath != null && basePath.isNotEmpty) {
      baseDir = Directory(basePath);
    } else {
      // Default to Downloads/Animepahe Downloader/
      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Download/Animepahe Downloader');
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        baseDir = Directory('$userProfile\\Downloads\\Animepahe Downloader');
      } else {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        baseDir = Directory('${dir.path}/Animepahe Downloader');
      }
    }

    // Create anime subdirectory
    final sanitizedTitle = animeTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final animeDir = Directory('${baseDir.path}/$sanitizedTitle');

    // Create directory if it doesn't exist
    if (!await animeDir.exists()) {
      await animeDir.create(recursive: true);
    }

    final fileName = 'E${episodeNumber.toString().padLeft(2, '0')}_${resolution}p.mp4';
    return '${animeDir.path}/$fileName';
  }

  // Process download queue
  void _processQueue() {
    if (_activeDownloads >= _maxConcurrentDownloads) {
      return;
    }

    final queuedTasks = _hiveService.getQueuedDownloadTasks();
    for (final task in queuedTasks) {
      if (_activeDownloads >= _maxConcurrentDownloads) {
        break;
      }

      // Skip tasks that are still fetching m3u8
      if (task.status == DownloadStatus.fetchingM3u8) {
        continue;
      }

      if (!_processingQueue.contains(task.id)) {
        _processingQueue.add(task.id);
        _startDownload(task);
      }
    }
  }

  // Start a download
  Future<void> _startDownload(DownloadTask task) async {
    _activeDownloads++;

    try {
      // Update status
      task.status = DownloadStatus.downloading;
      await _hiveService.updateDownloadTask(task);
      _notifyProgress(task);

      // For HLS streams, go directly to FFmpeg processing
      // FFmpeg will handle the download and decryption
      await _processWithFFmpeg(task);
    } catch (e) {
      if (kDebugMode) {
        print('Download error for ${task.id}: $e');
      }

      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      await _hiveService.updateDownloadTask(task);
      _notifyProgress(task);
    } finally {
      _activeDownloads--;
      _processingQueue.remove(task.id);
      _progressControllers[task.id]?.close();
      _progressControllers.remove(task.id);

      // Process next in queue
      _processQueue();
    }
  }

  // All m3u8 processing methods removed - now using M3U8Downloader

  // Process with FFmpeg using M3U8Downloader
  Future<void> _processWithFFmpeg(DownloadTask task) async {
    if (!_prefsService.useFFmpeg) {
      // Download the m3u8 file directly
      try {
        await _downloadFile(task.m3u8Url, task.outputPath);
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.completedAt = DateTime.now();
        await _hiveService.updateDownloadTask(task);
        _notifyProgress(task);
      } catch (e) {
        throw Exception('Failed to download m3u8 file: $e');
      }
      return;
    }

    // Use the new M3U8Downloader
    final downloader = M3U8Downloader(
      task,
      onProgress: (updatedTask) {
        _hiveService.updateDownloadTask(updatedTask);
        _notifyProgress(updatedTask);
      },
    );

    await downloader.download();
    
    // Final update after download completes
    await _hiveService.updateDownloadTask(task);
    _notifyProgress(task);
  }

  // Pause download
  Future<void> pauseDownload(String taskId) async {
    final task = _hiveService.getDownloadTask(taskId);
    if (task == null || !task.canPause) return;

    // Mark as paused (HTTP requests don't use cancel tokens)
    task.status = DownloadStatus.paused;
    await _hiveService.updateDownloadTask(task);
    _notifyProgress(task);

    _processingQueue.remove(taskId);
  }

  // Resume download
  Future<void> resumeDownload(String taskId) async {
    final task = _hiveService.getDownloadTask(taskId);
    if (task == null || !task.canResume) return;

    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    await _hiveService.updateDownloadTask(task);
    _notifyProgress(task);

    _processQueue();
  }

  // Cancel download
  Future<void> cancelDownload(String taskId) async {
    final task = _hiveService.getDownloadTask(taskId);
    if (task == null || !task.canCancel) return;

    // Mark as cancelled (HTTP requests don't use cancel tokens)
    task.status = DownloadStatus.cancelled;
    await _hiveService.updateDownloadTask(task);
    _notifyProgress(task);

    _processingQueue.remove(taskId);

    // Delete partial file
    try {
      final file = File(task.outputPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore
    }
  }

  // Delete task
  Future<void> deleteTask(String taskId) async {
    await pauseDownload(taskId);
    await _hiveService.deleteDownloadTask(taskId);
    _progressControllers[taskId]?.close();
    _progressControllers.remove(taskId);
  }

  // Get progress stream for a task
  Stream<DownloadTask> getProgressStream(String taskId) {
    if (!_progressControllers.containsKey(taskId)) {
      _progressControllers[taskId] = StreamController<DownloadTask>.broadcast();
    }
    return _progressControllers[taskId]!.stream;
  }

  // Notify progress
  void _notifyProgress(DownloadTask task) {
    if (_progressControllers.containsKey(task.id)) {
      _progressControllers[task.id]!.add(task);
    }
  }

  // Get all tasks
  List<DownloadTask> getAllTasks() {
    return _hiveService.getAllDownloadTasks();
  }

  // Get active tasks
  List<DownloadTask> getActiveTasks() {
    return _hiveService.getActiveDownloadTasks();
  }

  // Clean up completed tasks
  Future<void> clearCompleted() async {
    final tasks = _hiveService.getAllDownloadTasks();
    for (final task in tasks) {
      if (task.status == DownloadStatus.completed) {
        await _hiveService.deleteDownloadTask(task.id);
      }
    }
  }

  // Dispose
  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }

}

