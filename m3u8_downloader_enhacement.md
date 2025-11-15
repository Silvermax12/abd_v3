# M3U8 Downloader Enhancement Roadmap

## Current Implementation Status ✅
You've successfully implemented basic retry logic with:
- 5 retry attempts per request
- Exponential backoff (2s, 4s, 8s, 16s, 32s)
- Increased timeouts (60s playlist, 45s segments, 30s keys)
- Comprehensive error logging
- Retry methods for both text and binary content

## Priority Enhancements (FDM-Inspired Features)

### 🔥 HIGH PRIORITY - Immediate Impact

#### 1. **Parallel Segment Downloads** 🚀
**Why:** FDM's core innovation - download multiple segments simultaneously instead of sequentially.

**Current:** Downloads segments one-by-one (slow and fragile)
**Goal:** Download 4-8 segments concurrently for 3-5x speed improvement

**Implementation:**
```dart
class ParallelDownloader {
  final int maxConcurrentDownloads;
  final Semaphore _semaphore;

  ParallelDownloader({this.maxConcurrentDownloads = 4})
      : _semaphore = Semaphore(maxConcurrentDownloads);

  Future<void> downloadAllSegments(List<String> segmentUrls) async {
    final results = <int, Uint8List>{};
    final errors = <int, Exception>{};

    final futures = segmentUrls.asMap().entries.map((entry) async {
      await _semaphore.acquire();
      try {
        final data = await _fetchBytesWithRetry(entry.value);
        results[entry.key] = data;
      } catch (e) {
        errors[entry.key] = e as Exception;
      } finally {
        _semaphore.release();
      }
    });

    await Future.wait(futures);

    // Handle results and retry failed segments
    await _retryFailedSegments(results, errors, segmentUrls);
  }
}
```

**Benefits:**
- 3-5x faster downloads
- Network failures affect only individual segments
- Better bandwidth utilization

#### 2. **Resume Capability** 💾
**Why:** Never lose progress due to interruptions.

**Implementation:**
```dart
class DownloadStateManager {
  final String stateFile = 'download_progress.json';

  Future<void> saveProgress(int completedSegments, List<String> segmentUrls) async {
    final state = {
      'completedSegments': completedSegments,
      'totalSegments': segmentUrls.length,
      'timestamp': DateTime.now().toIso8601String(),
      'segmentUrls': segmentUrls,
    };

    await File(stateFile).writeAsString(jsonEncode(state));
  }

  Map<String, dynamic>? loadProgress() {
    try {
      final file = File(stateFile);
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync());
      }
    } catch (e) {
      print('Failed to load progress: $e');
    }
    return null;
  }

  Future<void> resumeDownload() async {
    final state = loadProgress();
    if (state != null) {
      final completedSegments = state['completedSegments'] as int;
      final segmentUrls = List<String>.from(state['segmentUrls']);

      // Resume from where we left off
      await downloadSegmentsFromIndex(completedSegments, segmentUrls);
    }
  }
}
```

**Benefits:**
- Resume interrupted downloads
- No wasted bandwidth/time
- Graceful app restarts

#### 3. **Connection Pooling** 🔄
**Why:** Reuse HTTP connections for efficiency (FDM standard).

**Implementation:**
```dart
class ConnectionPool {
  final List<HttpClient> _available = [];
  final List<HttpClient> _active = [];
  final int _maxConnections;

  ConnectionPool(this._maxConnections);

  Future<HttpClient> getConnection() async {
    if (_available.isNotEmpty) {
      final client = _available.removeLast();
      _active.add(client);
      return client;
    }

    if (_active.length < _maxConnections) {
      final client = HttpClient();
      _active.add(client);
      return client;
    }

    // Wait for connection to become available
    await Future.delayed(Duration(milliseconds: 100));
    return getConnection();
  }

  void releaseConnection(HttpClient client) {
    _active.remove(client);
    _available.add(client);
  }
}
```

**Benefits:**
- Faster subsequent requests
- Reduced connection overhead
- Better resource management

### ⚡ MEDIUM PRIORITY - Quality of Life

#### 4. **Network Health Monitoring** 📊
**Why:** Adapt to changing network conditions.

**Implementation:**
```dart
class NetworkMonitor {
  final List<Duration> _responseTimes = [];
  final List<bool> _successes = [];
  static const int _historySize = 10;

  void recordResult(bool success, Duration responseTime) {
    _successes.add(success);
    _responseTimes.add(responseTime);

    // Keep only recent history
    if (_successes.length > _historySize) {
      _successes.removeAt(0);
      _responseTimes.removeAt(0);
    }
  }

  double get successRate => _successes.where((s) => s).length / _successes.length;

  Duration get averageResponseTime {
    if (_responseTimes.isEmpty) return Duration(seconds: 1);
    final avgMs = _responseTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _responseTimes.length;
    return Duration(milliseconds: avgMs.round());
  }

  bool shouldReduceConcurrency() => successRate < 0.7;
  bool shouldIncreaseTimeouts() => averageResponseTime > Duration(seconds: 5);
  bool isNetworkPoor() => successRate < 0.5;
}
```

**Benefits:**
- Automatically adjust download strategy
- Better performance on poor networks
- Prevent overwhelming bad connections

#### 5. **Smart Error Classification** 🧠
**Why:** Different errors need different handling strategies.

**Implementation:**
```dart
enum ErrorType {
  retryableNetwork,    // Timeouts, connection failures
  retryableServer,     // 5xx errors, rate limits
  nonRetryableClient,  // 4xx errors (except 408, 429)
  nonRetryableAuth,    // 401, 403
  permanent,           // 404, etc.
}

class ErrorClassifier {
  static ErrorType classifyError(dynamic error, int? statusCode) {
    if (error is TimeoutException) return ErrorType.retryableNetwork;
    if (error is SocketException) return ErrorType.retryableNetwork;

    if (statusCode != null) {
      if ([408, 429].contains(statusCode)) return ErrorType.retryableNetwork;
      if (statusCode >= 500) return ErrorType.retryableServer;
      if ([401, 403].contains(statusCode)) return ErrorType.nonRetryableAuth;
      if (statusCode >= 400) return ErrorType.nonRetryableClient;
    }

    return ErrorType.permanent;
  }

  static RetryConfig getRetryConfig(ErrorType errorType) {
    switch (errorType) {
      case ErrorType.retryableNetwork:
        return RetryConfig(maxRetries: 5, baseDelay: Duration(seconds: 1));
      case ErrorType.retryableServer:
        return RetryConfig(maxRetries: 3, baseDelay: Duration(seconds: 2));
      case ErrorType.nonRetryableClient:
      case ErrorType.nonRetryableAuth:
      case ErrorType.permanent:
        return RetryConfig(maxRetries: 0, baseDelay: Duration.zero);
    }
  }
}
```

**Benefits:**
- No wasted retries on permanent errors
- Faster failure detection
- Smarter retry strategies

#### 6. **Bandwidth Management** ⚖️
**Why:** Respect network limits and prevent overwhelming connections.

**Implementation:**
```dart
class BandwidthManager {
  final int maxBytesPerSecond;
  int _bytesThisSecond = 0;
  DateTime _lastReset = DateTime.now();

  BandwidthManager({this.maxBytesPerSecond = 1024 * 1024}); // 1MB/s default

  Future<void> throttle(int bytesToSend) async {
    final now = DateTime.now();
    if (now.difference(_lastReset).inSeconds >= 1) {
      _bytesThisSecond = 0;
      _lastReset = now;
    }

    if (_bytesThisSecond + bytesToSend > maxBytesPerSecond) {
      final waitTime = Duration(seconds: 1) - now.difference(_lastReset);
      if (waitTime.isNegative) return;
      await Future.delayed(waitTime);
      _bytesThisSecond = 0;
      _lastReset = DateTime.now();
    }

    _bytesThisSecond += bytesToSend;
  }
}
```

**Benefits:**
- Respect server limits
- Better network coexistence
- Prevent bandwidth hogging

### 🛠️ ADVANCED FEATURES - Future-Proofing

#### 7. **Live Stream Support** 📺
**Why:** Handle changing M3U8 playlists for live streams.

**Implementation:**
```dart
class LiveStreamHandler {
  final Duration playlistRefreshInterval;
  final List<String> _processedSegments = [];

  Future<void> downloadLiveStream(String m3u8Url) async {
    while (true) {  // Continue until stream ends
      final playlist = await fetchPlaylist(m3u8Url);
      final newSegments = getNewSegments(playlist, _processedSegments);

      if (newSegments.isNotEmpty) {
        await downloadSegments(newSegments);
        _processedSegments.addAll(newSegments.map((s) => extractSegmentId(s)));
      }

      await Future.delayed(playlistRefreshInterval);
    }
  }
}
```

#### 8. **Download Speed Limiting** 🐌
**Why:** Prevent overwhelming slow/unstable networks.**

#### 9. **Progress Callbacks & UI Updates** 📱
**Why:** Real-time download progress for better UX.**

#### 10. **Segment Integrity Verification** ✅
**Why:** Ensure downloaded segments are valid before processing.**

## Implementation Priority Order

### Phase 1 (Immediate - 1-2 days)
1. ✅ Parallel Segment Downloads
2. ✅ Resume Capability
3. ✅ Connection Pooling

### Phase 2 (Short-term - 1 week)
4. Network Health Monitoring
5. Smart Error Classification
6. Bandwidth Management

### Phase 3 (Long-term - Future releases)
7. Live Stream Support
8. Download Speed Limiting
9. Progress Callbacks & UI Updates
10. Segment Integrity Verification

## Expected Performance Improvements

| Feature | Current Performance | Expected Improvement |
|---------|-------------------|---------------------|
| Parallel Downloads | 1 segment at a time | 4-8 segments concurrent |
| Network Resilience | Fails on first error | Retries intelligently |
| Resume Capability | Restarts from beginning | Resumes from interruption |
| Resource Usage | New connection per request | Connection reuse |
| Error Handling | Generic failures | Smart error classification |

## Testing Recommendations

1. **Network Failure Simulation**: Test with artificial network failures
2. **Resume Testing**: Kill app mid-download and verify resume works
3. **Speed Testing**: Compare download speeds before/after parallel downloads
4. **Memory Testing**: Monitor memory usage with connection pooling
5. **Edge Case Testing**: Test with corrupted segments, invalid URLs, etc.

This roadmap will transform your M3U8 downloader from basic retry logic into a professional-grade download manager on par with FDM's reliability and performance.
