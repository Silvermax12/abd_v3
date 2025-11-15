# Flutter App M3U8 Processing Logic After Backend Integration

This document details **every Flutter-side logic and its purpose** after receiving M3U8 URLs from the backend, covering the complete download pipeline from URL reception to final MP4 output.

## 1. Download Provider - Coordination & State Management

### `startM3u8Download()` Method
**Purpose:** Initiates the entire M3U8 download process after backend provides episode links.

**Logic Flow:**
```dart
Future<String?> startM3u8Download({
  required String animeSession,
  required List<int> episodes,
  required String quality,
  required String language,
  required String animeTitle,
  String? upgradeQuality,
}) async
```

**Key Operations:**
1. **API Service Call:** `await _apiService.scrapeM3u8Links()` - Gets episode links from backend
2. **Record Creation:** Creates `DownloadRecordHive` with metadata (title, quality, episodes)
3. **Background Processing:** Calls `_startM3u8DownloadBackground()` for concurrent downloads
4. **State Management:** Sets up listeners for real-time progress updates
5. **Background Service:** Registers with background download service for persistence

### `_startM3u8DownloadBackground()` Method
**Purpose:** Manages concurrent episode downloads with controlled parallelism.

**Concurrency Logic:**
```dart
// Max 2 concurrent downloads per anime record
final active = <int>{};
const maxConcurrency = 2;

void tryStartNext() {
  while (active.length < maxConcurrency && queue.isNotEmpty) {
    final ep = queue.removeAt(0);
    active.add(ep);
    _startControlledEpisode(record.id, ep, m3u8Url, animeTitle)
        .whenComplete(() => active.remove(ep));
  }
}
```

**Queue Management:**
- Creates episode tasks in Hive database
- Maintains download queues per record ID
- Handles episode ordering and dependencies

## 2. Episode-Level Download Control

### `_startControlledEpisode()` Method
**Purpose:** Handles individual episode download with full lifecycle management.

**Key Logic Areas:**

#### **Task ID Resolution**
```dart
// Aligns UI updates with backend task IDs for consistency
String taskKey = recordId;
final rec = box.get(recordId);
if (rec?.backendTaskId?.isNotEmpty == true) {
  taskKey = rec.backendTaskId!;
}
```

#### **Output Path Construction**
```dart
// Builds consistent filenames: "Anime_Title_Episode_1_720p_jpn.mp4"
final safeAnimeTitle = effectiveAnimeTitle.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
final builtFileName = '${safeAnimeTitle}_Episode_${episode}_${qualityLabel}_$langCode.mp4';
fullOutputPath = '${rec.directoryPath}/$builtFileName';
```

#### **M3U8 Service Integration**
```dart
await _m3u8Service.downloadM3u8WithControls(
  recordId: recordId,
  episode: episode,
  m3u8Url: m3u8Url,
  outputPath: fullOutputPath,
  quality: quality,
  // Progress callbacks for UI updates
  onDownloadProgress: (p) => _updateM3u8EpisodeProgress(taskKey, episode, p),
  onReencodeProgress: (p) async {
    _updateM3u8EpisodeReEncodeProgress(taskKey, episode, p);
    if (p >= 100.0) await _verifyAndCompleteDownload(taskKey, episode, fullOutputPath);
  },
  // Additional status callbacks
  onReencodeEta: (eta) => _updateM3u8EpisodeDetailedProgress(taskKey, episode, eta: eta),
  onReencodeSize: (size) => _updateM3u8EpisodeDetailedProgress(taskKey, episode, fileSize: size),
  onStatus: (status) async => await _handleEpisodeStatusUpdate(taskKey, episode, status, fullOutputPath),
);
```

## 3. Progress Tracking & UI Updates

### `_updateM3u8EpisodeProgress()` Method
**Purpose:** Updates download progress (0-100%) for UI display.

```dart
void _updateM3u8EpisodeProgress(String taskId, int episode, double progress) {
  final box = Hive.box<DownloadRecordHive>(DownloadService.hiveBoxName);
  final rec = box.get(taskId);
  if (rec != null) {
    final ep = rec.episodeTasks.firstWhereOrNull((e) => e.episodeNumber == episode);
    if (ep != null) {
      ep.downloadProgress = progress;
      box.put(taskId, rec);
    }
  }
}
```

### `_updateM3u8EpisodeReEncodeProgress()` Method
**Purpose:** Updates FFmpeg re-encoding progress during video conversion.

```dart
void _updateM3u8EpisodeReEncodeProgress(String taskId, int episode, double progress) {
  // Similar to download progress but for re-encoding phase
  final box = Hive.box<DownloadRecordHive>(DownloadService.hiveBoxName);
  final rec = box.get(taskId);
  if (rec != null) {
    final ep = rec.episodeTasks.firstWhereOrNull((e) => e.episodeNumber == episode);
    if (ep != null) {
      ep.reEncodeProgress = progress;
      box.put(taskId, rec);
    }
  }
}
```

### `_updateM3u8EpisodeDetailedProgress()` Method
**Purpose:** Updates detailed progress information (ETA, file size, speed).

```dart
void _updateM3u8EpisodeDetailedProgress(String taskId, int episode, {
  String? eta,
  String? fileSize,
  String? downloadSpeed,
  String? downloadedSize
}) {
  final box = Hive.box<DownloadRecordHive>(DownloadService.hiveBoxName);
  final rec = box.get(taskId);
  if (rec != null) {
    final ep = rec.episodeTasks.firstWhereOrNull((e) => e.episodeNumber == episode);
    if (ep != null) {
      if (eta != null) ep.eta = eta;
      if (fileSize != null) ep.fileSize = fileSize;
      if (downloadSpeed != null) ep.downloadSpeed = downloadSpeed;
      if (downloadedSize != null) ep.downloadedSize = downloadedSize;
      box.put(taskId, rec);
    }
  }
}
```

### `_parseDetailedStatusInfo()` Method
**Purpose:** Parses detailed information from M3U8 service status messages.

```dart
Map<String, String?> _parseDetailedStatusInfo(String status) {
  final result = <String, String?>{};

  // Parse ETA: "ETA: 28s" or "Converting: 53.9% (ETA: 47s)"
  final etaRegex = RegExp(r'ETA:\s*([^)\s]+)');
  final etaMatch = etaRegex.firstMatch(status);
  if (etaMatch != null) result['eta'] = etaMatch.group(1);

  // Parse file size: "Size: 45.2 MB"
  final sizeRegex = RegExp(r'Size:\s*([^)\s]+)');
  final sizeMatch = sizeRegex.firstMatch(status);
  if (sizeMatch != null) result['fileSize'] = sizeMatch.group(1);

  return result;
}
```

## 4. M3U8 Service - Core Download Logic

### `downloadM3u8WithControls()` Method
**Purpose:** Main entry point for controlled M3U8 downloads with pause/resume/cancel support.

**Initialization Logic:**
```dart
final key = _key(recordId, episode);
final ctrl = _controls.putIfAbsent(key, () => _EpisodeControl());

// Initialize throughput estimator for ETA calculations
final throughputEstimator = ThroughputEstimator(maxSamples: 10);
int totalBytes = 0;
int downloadedBytes = 0;
```

### Stream Type Detection
**Purpose:** Automatically detects different HLS stream formats for appropriate processing.

```dart
// Analyze M3U8 content for stream characteristics
final hasJpgExtensions = m3u8Content.contains('.jpg');
final hasTsExtensions = m3u8Content.contains('.ts') || m3u8Content.contains('.m4s');
final hasEncryption = m3u8Content.contains('#EXT-X-KEY:METHOD=AES-128');

// Determine stream type
final isEncryptedJpegOverHls = hasJpgExtensions && !hasTsExtensions && hasEncryption;
final isTrueMjpegStream = hasJpgExtensions && !hasEncryption;
```

### Temporary Storage Management
**Purpose:** Creates and manages temporary directories for download processing.

```dart
final tempDir = await getTemporaryDirectory();
final workDir = Directory('${tempDir.path}/m3u8_${recordId}_ep$episode');

// Resume detection: check if directory exists
final bool isResume = await workDir.exists();
if (!isResume) await workDir.create(recursive: true);

_tempPaths[key] = workDir.path;
```

### URL Persistence for Resume
**Purpose:** Saves M3U8 URLs to sidecar files for crash recovery.

```dart
final urlFile = File('${workDir.path}/m3u8_url.txt');
if (m3u8Url.trim().isNotEmpty) {
  await urlFile.writeAsString(m3u8Url.trim(), flush: true);
}

// Recovery on resume
if (await urlFile.exists()) {
  final cached = await urlFile.readAsString();
  if (cached.trim().isNotEmpty) m3u8Url = cached.trim();
}
```

## 5. Segment Processing Logic

### Encrypted JPEG-over-HLS Processing
**Purpose:** Handles AES-128 encrypted JPEG frames served over HLS.

**Encryption Key Download:**
```dart
if (encryptionInfo != null && encryptionInfo['uri'] != null) {
  onStatus('Downloading encryption key...');
  encryptionKey = await _downloadEncryptionKey(encryptionInfo['uri']!);
}
```

**Resume-Aware Download:**
```dart
// Count existing segments for resume start index
int resumeStartIndex = 0;
if (await concatFile.exists()) {
  final lines = await concatFile.readAsLines();
  resumeStartIndex = lines.where((l) => l.trim().startsWith("file '")).length;
}

// Pre-calculate downloaded bytes from existing files
if (resumeStartIndex > 0) {
  final existing = await workDir.list().toList();
  for (final entity in existing) {
    if (entity is File && entity.path.endsWith('.ts')) {
      final st = await entity.stat();
      downloadedBytes += st.size;
    }
  }
}
```

**Segment Download with Retry:**
```dart
for (int i = resumeStartIndex; i < segments.length; i++) {
  if (ctrl.cancelled) throw Exception('Cancelled');
  await ctrl.waitIfPaused();

  final segmentUrl = segments[i];
  final segmentFile = File('${workDir.path}/segment_${i.toString().padLeft(4, '0')}.ts');

  // Download with retries and progress tracking
  final dioCancel = ctrl.createDioCancelToken();
  segmentData = await _getBytesWithRetries(url: segmentUrl, cancelToken: dioCancel);

  // Decrypt if encrypted
  if (encryptionKey != null) {
    segmentData = await _decryptAes128(segmentData, encryptionKey);
  }

  await segmentFile.writeAsBytes(segmentData);
  sink.writeln("file '$segmentPath'");
}
```

### True MJPEG Stream Processing
**Purpose:** Handles unencrypted JPEG frame sequences.

**Frame Download Logic:**
```dart
int resumeStartFrame = 0;
// Count existing .jpg files for resume
final existingFrames = existing.whereType<File>()
    .where((f) => frameRegex.hasMatch(path.basename(f.path))).toList();
resumeStartFrame = existingFrames.length;

for (int i = resumeStartFrame; i < segments.length; i++) {
  final segmentFile = File('${workDir.path}/frame_${i.toString().padLeft(6, '0')}.jpg');
  final bytes = await _getBytesWithRetries(url: segmentUrl, cancelToken: dioCancel);
  await segmentFile.writeAsBytes(bytes);
  onDownloadProgress(((i + 1) / segments.length) * 50.0); // First 50% for download
}
```

## 6. FFmpeg Re-encoding Logic

### Quality-Based Encoding
**Purpose:** Maps quality settings to optimal FFmpeg CRF values.

```dart
int getCrfForQuality(String quality) {
  final normalized = quality.toLowerCase().endsWith('p') ? quality : '${quality}p';
  switch (normalized) {
    case '360p': return 27;  // Lower quality, higher compression
    case '480p': return 26;
    case '720p': return 23;  // Balanced quality
    case '1080p': return 20; // Higher quality, lower compression
    case '2160p':
    case '4k': return 18;    // Best quality
    default: return 23;      // Safe default
  }
}
```

### Platform-Specific FFmpeg Execution
**Purpose:** Uses appropriate FFmpeg implementation per platform.

**Windows (Native ffmpeg.exe):**
```dart
if (Platform.isWindows) {
  final args = ['-y', '-f', 'concat', '-safe', '0', '-i', concatFile.path,
                '-c:v', 'libx264', '-preset', 'fast', '-crf', crf.toString(),
                '-c:a', 'aac', '-b:a', '128k', outputPath];
  final code = await FFmpegService.instance.runFFmpeg(arguments: args);
}
```

**Mobile (FFmpegKit):**
```dart
FFmpegKit.executeAsync(
  '-y -f concat -safe 0 -i "${concatFile.path}" -c:v libx264 -preset fast -crf $crf -c:a aac -b:a 128k "$outputPath"',
  (session) async {
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      onReencodeProgress(100.0);
      completer.complete(outputPath);
    }
  }
);
```

### Progress Parsing During Encoding
**Purpose:** Extracts progress information from FFmpeg stderr output.

```dart
if (message.contains('time=')) {
  final parsed = _parseFFmpegProgress(message);
  if (parsed != null) {
    final currentTime = parsed['time']!;
    final progressPercent = (currentTime / totalDuration * 100).clamp(0.0, 99.9);
    onReencodeProgress(progressPercent);

    final remaining = currentTime < totalDuration ? (totalDuration - currentTime) : 0.0;
    onReencodeEta(_formatDuration(remaining.toInt()));
  }
}
```

## 7. Throughput Estimation & ETA Calculation

### `ThroughputEstimator` Class
**Purpose:** Calculates network speed and predicts completion time.

**Sample Collection:**
```dart
void addSample(int bytes, int milliseconds) {
  final bps = bytes * 1000.0 / milliseconds;
  // Exponential moving average for smooth data
  const alpha = 0.3;
  final smoothed = (_samples.last * (1 - alpha)) + (bps * alpha);
  _samples.add(smoothed);
}
```

**ETA Calculation:**
```dart
String etaForRemainingBytes(int remainingBytes) {
  final bps = averageThroughput;
  if (bps <= 0 || remainingBytes <= 0) return '--';

  final seconds = remainingBytes / bps;
  if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
  else if (seconds < 3600) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).floor();
    return '${minutes}m ${remainingSeconds}s';
  } else {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }
}
```

## 8. Error Handling & Recovery

### `_getBytesWithRetries()` Method
**Purpose:** Downloads with automatic retry on transient network failures.

**Retry Logic:**
```dart
int attempt = 0;
while (true) {
  attempt++;
  try {
    final resp = await dio.get(url, cancelToken: cancelToken);
    return resp.data;
  } catch (e) {
    if (!_isTransientNetworkError(e) || attempt >= maxAttempts) rethrow;

    // Exponential backoff with jitter
    final delay = baseDelay * (1 << (attempt - 1));
    final jitterMs = 100 + (attempt * 50);
    await Future.delayed(delay + Duration(milliseconds: jitterMs));
  }
}
```

### Transient Error Detection
**Purpose:** Identifies recoverable vs permanent network errors.

```dart
bool _isTransientNetworkError(Object error) {
  final message = error.toString().toLowerCase();
  // Windows semaphore timeout, connection resets, timeouts, etc.
  return message.contains('semaphore timeout') ||
         message.contains('connection reset') ||
         message.contains('timed out') ||
         // Add other transient error patterns
         message.contains('network is unreachable');
}
```

## 9. Pause/Resume/Cancel Control

### `_EpisodeControl` Class
**Purpose:** Manages per-episode download state and control operations.

```dart
class _EpisodeControl {
  bool paused = false;
  bool cancelled = false;
  Completer<void>? _pauseWaiter;
  CancelToken? _dioCancelToken;

  Future<void> waitIfPaused() async {
    while (paused && !cancelled) {
      _pauseWaiter ??= Completer<void>();
      await _pauseWaiter!.future;
    }
  }

  void resume() {
    paused = false;
    _pauseWaiter?.complete();
    _pauseWaiter = null;
  }

  void cancelOngoingRequest() {
    cancelled = true;
    _dioCancelToken?.cancel('Cancelled');
  }
}
```

## 10. Completion Verification & Cleanup

### `_verifyAndCompleteDownload()` Method
**Purpose:** Ensures download integrity before marking as complete.

```dart
Future<void> _verifyAndCompleteDownload(String taskId, int episode, String filePath) async {
  try {
    final file = File(filePath);

    // Wait for file operations to complete
    await Future.delayed(const Duration(seconds: 1));

    // Verify file exists and has content
    if (!await file.exists()) {
      print('⚠️ File not found after completion: $filePath');
      return;
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      print('⚠️ File is empty after completion: $filePath');
      return;
    }

    // Mark as completed in database
    await _markEpisodeCompleted(taskId, episode, fileSize);

  } catch (e) {
    print('❌ Verification failed for episode $episode: $e');
  }
}
```

### `_handleEpisodeStatusUpdate()` Method
**Purpose:** Processes status messages and updates episode state accordingly.

```dart
Future<void> _handleEpisodeStatusUpdate(String taskId, int episode, String status, String filePath) async {
  final box = Hive.box<DownloadRecordHive>(DownloadService.hiveBoxName);
  final rec = box.get(taskId);

  if (rec != null) {
    final ep = rec.episodeTasks.firstWhereOrNull((e) => e.episodeNumber == episode);
    if (ep != null) {
      ep.statusMessage = status;

      // Check for completion indicators
      if (status.contains('completed') || status.contains('finished')) {
        ep.status = EpisodeStatus.completed;
      } else if (status.contains('failed') || status.contains('error')) {
        ep.status = EpisodeStatus.failed;
      }

      await box.put(taskId, rec);
    }
  }
}
```

## 11. M3U8 Content Parsing

### `_parseM3u8Content()` Method
**Purpose:** Extracts segment URLs and encryption information from M3U8 playlists.

```dart
Map<String, dynamic> _parseM3u8Content(String m3u8Content, String baseUrl) {
  final segments = <String>[];
  Map<String, String>? encryptionInfo;

  final lines = m3u8Content.split('\n');

  for (final line in lines) {
    final trimmed = line.trim();

    // Parse encryption information
    if (trimmed.startsWith('#EXT-X-KEY:')) {
      encryptionInfo = _parseEncryptionInfo(trimmed, baseUrl);
    }

    // Extract segment URLs (skip comments and empty lines)
    if (trimmed.isNotEmpty && !trimmed.startsWith('#') && trimmed.contains('http')) {
      segments.add(trimmed);
    }
  }

  return {
    'segments': segments,
    'encryption': encryptionInfo,
  };
}
```

### `_parseEncryptionInfo()` Method
**Purpose:** Extracts AES-128 encryption parameters from M3U8 key tags.

```dart
Map<String, String>? _parseEncryptionInfo(String keyLine, String baseUrl) {
  // #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key",IV=0x...
  final methodMatch = RegExp(r'METHOD=([^,]+)').firstMatch(keyLine);
  final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(keyLine);
  final ivMatch = RegExp(r'IV=([^,]+)').firstMatch(keyLine);

  if (methodMatch != null && uriMatch != null) {
    return {
      'method': methodMatch.group(1)!,
      'uri': _resolveUrl(uriMatch.group(1)!, baseUrl),
      'iv': ivMatch?.group(1), // Optional initialization vector
    };
  }
  return null;
}
```

## 12. Size Estimation Logic

### `estimateTotalBytes()` Method
**Purpose:** Predicts total download size by sampling segment sizes.

```dart
Future<int> estimateTotalBytes(List<String> segmentUrls) async {
  final client = http.Client();
  int knownBytes = 0;
  int knownCount = 0;

  // Sample first few segments to estimate average size
  final sampleSize = min(5, segmentUrls.length); // Sample up to 5 segments
  final sampleUrls = segmentUrls.take(sampleSize);

  // Concurrent but limited requests to avoid overwhelming servers
  final concurrencyLimit = 6;
  final futures = <Future>[];

  for (final url in sampleUrls) {
    if (futures.length >= concurrencyLimit) {
      await Future.wait(futures);
      futures.clear();
    }

    futures.add(_getContentLength(url));
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
  }

  // Calculate average size and extrapolate
  if (knownCount > 0) {
    final averageBytes = knownBytes / knownCount;
    return (averageBytes * segmentUrls.length).round();
  }

  return 0; // Fallback if no samples succeeded
}
```

## 13. AES-128 Decryption Logic

### `_downloadEncryptionKey()` Method
**Purpose:** Downloads encryption keys for AES-128 encrypted streams.

```dart
Future<List<int>?> _downloadEncryptionKey(String keyUrl) async {
  try {
    final response = await http.get(Uri.parse(keyUrl));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
  } catch (e) {
    print('❌ Failed to download encryption key: $e');
  }
  return null;
}
```

### `_decryptAes128()` Method
**Purpose:** Decrypts AES-128 encrypted video segments.

```dart
Future<List<int>?> _decryptAes128(List<int> encryptedData, List<int> key) async {
  try {
    final cipher = encrypt.Encrypter(encrypt.AES(encrypt.Key(key)));
    // AES-128 uses 16-byte blocks
    final decrypted = cipher.decryptBytes(
      encrypt.Encrypted(encryptedData),
      iv: encrypt.IV.fromLength(16), // Default IV for HLS
    );
    return decrypted;
  } catch (e) {
    print('❌ AES-128 decryption failed: $e');
    return null;
  }
}
```

## 14. Platform-Specific Optimizations

### Windows FFmpeg Integration
**Purpose:** Uses native ffmpeg.exe for better performance on Windows.

```dart
if (Platform.isWindows) {
  final code = await FFmpegService.instance.runFFmpeg(
    arguments: args,
    onStdErr: (line) {
      // Parse progress from stderr
      if (line.contains('time=')) {
        final parsed = _parseFFmpegProgress(line);
        if (parsed != null) {
          final progress = (parsed['time']! / totalDuration * 100).clamp(0.0, 99.9);
          onReencodeProgress(progress);
        }
      }
    },
  );
  return code == 0;
}
```

### Mobile FFmpegKit Integration
**Purpose:** Uses FFmpegKit for cross-platform mobile support.

```dart
FFmpegKit.executeAsync(
  command,
  (session) async {
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      onReencodeProgress(100.0);
      completer.complete(outputPath);
    } else {
      final logs = await session.getLogsAsString();
      completer.completeError(Exception('FFmpeg failed: $logs'));
    }
  },
  (log) => print('FFmpeg: ${log.getMessage()}'),
  null, // No statistics callback needed
);
```

## Summary of All Flutter Logic Components

1. **Download Coordination** - Provider manages concurrent downloads and state
2. **Episode Control** - Individual episode lifecycle with pause/resume/cancel
3. **Progress Tracking** - Real-time UI updates with detailed status information
4. **Stream Detection** - Automatic recognition of different HLS stream types
5. **Segment Processing** - Download, decryption, and concatenation of video segments
6. **FFmpeg Integration** - Platform-specific video encoding and conversion
7. **Throughput Estimation** - Network speed calculation and ETA prediction
8. **Error Recovery** - Retry logic for transient network failures
9. **Control Management** - Pause/resume/cancel functionality per episode
10. **Completion Verification** - File integrity checks before marking complete
11. **Content Parsing** - M3U8 playlist parsing for segments and encryption
12. **Size Estimation** - Download size prediction for progress display
13. **Encryption Handling** - AES-128 decryption for protected streams
14. **Platform Optimization** - Native performance on each platform

This comprehensive pipeline transforms M3U8 URLs into playable MP4 files with full user control, progress visibility, and robust error handling throughout the entire process.
