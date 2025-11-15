import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'cookie_manager_service.dart';
import '../models/download_task_model.dart';
import 'bitfield_state_manager.dart';
import 'atomic_file_utils.dart';
import 'error_classifier.dart';
import 'network_monitor.dart';
import 'adaptive_concurrency_manager.dart';
import 'http_client_pool.dart';
import 'ordered_merge_queue.dart';
import 'bandwidth_manager.dart';

class M3U8Downloader {
  final DownloadTask task;
  final Function(DownloadTask)? onProgress; 
  Directory? _tempDir;
  
  // Retry configuration (now using error classifier)
  static const int baseTimeoutSeconds = 60;
  static const int segmentTimeoutSeconds = 45;
  
  // Components
  late NetworkMonitor _networkMonitor;
  late AdaptiveConcurrencyManager _concurrencyManager;
  late HttpClientPool _clientPool;
  late BandwidthManager _bandwidthManager;
  BitfieldStateManager? _stateManager;
  OrderedMergeQueue? _mergeQueue;
  
  // State
  Uint8List? _bitfield;
  int _completedCount = 0;
  bool _cancelled = false;
  
  M3U8Downloader(this.task, {this.onProgress});

  Future<void> download() async {
    try {
      // Create temp directory
      final tempDir = await getTemporaryDirectory();
      _tempDir = Directory(path.join(tempDir.path, 'm3u8_download_${task.id}'));
      if (!await _tempDir!.exists()) {
        await _tempDir!.create(recursive: true);
      }

      print('📥 Starting M3U8 download from: ${task.m3u8Url}');

      // Initialize components
      _networkMonitor = NetworkMonitor();
      _concurrencyManager = AdaptiveConcurrencyManager(
        networkMonitor: _networkMonitor,
        initialConcurrency: 4,
        maxConcurrency: 8,
        minConcurrency: 1,
      );
      _concurrencyManager.startAutoAdjustment();
      _clientPool = HttpClientPool(maxSize: 8);
      _bandwidthManager = BandwidthManager(); // Unlimited by default

      // Update status to processing
      task.status = DownloadStatus.processing;
      _notifyProgress();

      // Download and process the M3U8 stream
      await downloadAndProcess();
    } catch (e) {
      print('❌ Error during M3U8 download: $e');
      rethrow;
    } finally {
      // Cleanup
      _concurrencyManager.dispose();
      _clientPool.closeAll();
      
      // Clean up temporary directory only if download completed
      if (task.status == DownloadStatus.completed && _tempDir != null) {
        try {
          await _tempDir!.delete(recursive: true);
        } catch (e) {
          print('⚠️ Warning: Could not clean up temp directory: $e');
        }
      }
    }
  }

  Future<void> downloadAndProcess() async {
    print('📥 Fetching M3U8 playlist...');

    // Download the M3U8 playlist with retry logic
    final playlistContent = await _fetchWithRetry(
      task.m3u8Url,
      'M3U8 playlist',
    );
    print('✅ M3U8 playlist fetched (${playlistContent.length} bytes)');
    print('📊 Parsing playlist...');

    // Parse the M3U8 content and extract encryption info
    final parseResult = _parseM3U8WithEncryption(playlistContent);
    final segments = parseResult['segments'] as List<String>;
    final keyUrl = parseResult['keyUrl'] as String?;
    final encryptionMethod = parseResult['encryptionMethod'] as String?;

    if (segments.isEmpty) {
      throw Exception('No segments found in playlist');
    }

    print('📊 Found ${segments.length} segments');

    // Initialize state manager
    final stateFilePath = path.join(_tempDir!.path, 'download_state.bitfield');
    _stateManager = BitfieldStateManager(stateFilePath);
    
    // Try to load existing state for resume
    BitfieldLoadResult? savedState;
    try {
      savedState = await _stateManager!.load();
      if (savedState != null) {
        print('📂 Resuming from saved state (${savedState.segmentCount} segments)');
        _bitfield = savedState.bitfield;
        _completedCount = BitfieldStateManager.countCompleted(_bitfield!);
        print('📊 Resuming: ${_completedCount}/${segments.length} segments completed');
      }
    } catch (e) {
      print('⚠️ Could not load saved state: $e');
    }
    
    // Create new bitfield if needed
    _bitfield ??= BitfieldStateManager.createBitfield(segments.length);
    
    // Initialize merge queue
    _mergeQueue = OrderedMergeQueue(
      outputDir: _tempDir!.path,
      totalSegments: segments.length,
    );

    // Download encryption key if present
    Uint8List? encryptionKey;
    if (keyUrl != null && encryptionMethod == 'AES-128') {
      print('🔐 Downloading encryption key...');
      try {
        final keyBytes = await _fetchBytesWithRetry(
          keyUrl,
          'encryption key',
          timeoutSeconds: 30,
        );
        encryptionKey = keyBytes;
        print('✅ Encryption key downloaded (${encryptionKey.length} bytes)');
      } catch (e) {
        throw Exception('Failed to download encryption key: $e');
      }
    }

    // Download segments in parallel with adaptive concurrency
    await _downloadSegmentsParallel(segments, encryptionKey);

    print('✅ All segments downloaded');
    print('🎬 Concatenating video segments...');

    // Update progress to 85%
    task.progress = 0.85;
    _notifyProgress();

    // Get all segments in order for merge
    final segmentFiles = _mergeQueue!.getAllSegmentsInOrder();
    
    // Validate all segments exist
    if (!await _mergeQueue!.validateAllSegments()) {
      throw Exception('Some segments are missing or corrupted');
    }

    // Create concat file for ffmpeg
    final concatFile = File(path.join(_tempDir!.path, 'concat.txt'));
    final concatContent = segmentFiles.map((file) => "file '$file'").join('\n');
    await AtomicFileUtils.atomicWriteString(concatFile.path, concatContent);

    // Use ffmpeg_kit to concatenate video segments
    final ffmpegCommand = '-y -f concat -safe 0 -i "${concatFile.path}" '
        '-c copy "${task.outputPath}"';

    print('🎬 Running FFmpeg: $ffmpegCommand');

    final session = await FFmpegKit.execute(ffmpegCommand);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      print('✅ Video concatenation completed successfully!');
      print('📁 Output saved to: ${task.outputPath}');
      _notifyProgress();
      
      // Clean up state file after successful completion
      await _stateManager!.delete();
    } else {
      final output = await session.getOutput();
      final logs = await session.getLogsAsString();
      print('❌ FFmpeg error:');
      print('Return code: $returnCode');
      print('Output: $output');
      print('Logs: $logs');
      throw Exception('FFmpeg failed with return code: $returnCode');
    }
  }

  /// Download segments in parallel with adaptive concurrency
  Future<void> _downloadSegmentsParallel(
    List<String> segments,
    Uint8List? encryptionKey,
  ) async {
    final totalSegments = segments.length;
    final completer = Completer<void>();
    final activeDownloads = <Future>[];
    final pendingSegments = <int>[];
    final errors = <int, Exception>{};
    
    // Add pending segments (skip already completed ones)
    for (int i = 0; i < totalSegments; i++) {
      if (!BitfieldStateManager.isSegmentDownloaded(_bitfield!, i)) {
        pendingSegments.add(i);
      } else {
        // Already downloaded - add to merge queue
        final segmentPath = path.join(_tempDir!.path, 'segment_${i.toString().padLeft(6, '0')}.ts');
        final segmentFile = File(segmentPath);
        if (await segmentFile.exists()) {
          _mergeQueue!.addSegment(i, segmentPath);
        } else {
          // File missing, re-download
          pendingSegments.add(i);
        }
      }
    }
    
    print('📊 Starting parallel download: ${pendingSegments.length} segments to download, ${_completedCount} already completed');
    
    // Semaphore for concurrency control
    int activeCount = 0;
    final lock = Lock();
    
    Future<void> downloadSegment(int index) async {
      if (_cancelled) return;
      
      final segmentUrl = segments[index];
      final segmentPath = path.join(_tempDir!.path, 'segment_${index.toString().padLeft(6, '0')}.ts');
      
      try {
        final startTime = DateTime.now();
        
        // Download segment with retry and streaming write
        await _downloadSegmentToFile(
          segmentUrl,
          segmentPath,
          'segment ${index + 1}',
          index,
        );
        
        // Decrypt if needed
        if (encryptionKey != null) {
          await _decryptSegmentFile(segmentPath, encryptionKey, index);
        }
        
        final duration = DateTime.now().difference(startTime);
        _networkMonitor.recordResult(true, duration);
        
        // Mark as completed in bitfield
        BitfieldStateManager.markSegmentDownloaded(_bitfield!, index);
        _completedCount++;
        
        // Save state after each segment (frequent persistence for resume)
        await _saveState(totalSegments);
        
        // Add to merge queue (out-of-order is OK)
        _mergeQueue!.addSegment(index, segmentPath);
        
        // Update progress
        task.progress = (_completedCount / totalSegments) * 0.8;
        _notifyProgress();
        
      } catch (e) {
        final duration = DateTime.now().difference(DateTime.now());
        _networkMonitor.recordResult(false, duration);
        errors[index] = e is Exception ? e : Exception(e.toString());
        print('❌ Failed to download segment ${index + 1}: $e');
        
        // Adjust concurrency based on errors
        _concurrencyManager.adjustConcurrency();
      }
    }
    
    // Start downloads with controlled concurrency
    int nextPendingIndex = 0;
    
    Future<void> scheduleNext() async {
      while (!_cancelled && nextPendingIndex < pendingSegments.length) {
        bool scheduled = false;
        await lock.synchronized(() async {
          if (activeCount >= _concurrencyManager.currentConcurrency) {
            return;
          }
          
          if (nextPendingIndex >= pendingSegments.length) {
            return;
          }
          
          final segmentIndex = pendingSegments[nextPendingIndex++];
          activeCount++;
          scheduled = true;
          
          activeDownloads.add(
            downloadSegment(segmentIndex).whenComplete(() {
              lock.synchronized(() async {
                activeCount--;
              }).then((_) {
                // Schedule next if available
                if (!_cancelled && nextPendingIndex < pendingSegments.length) {
                  scheduleNext();
                }
                
                // Check if all done
                if (activeCount == 0 && nextPendingIndex >= pendingSegments.length) {
                  if (!completer.isCompleted) {
                    if (errors.isEmpty) {
                      completer.complete();
                    } else {
                      completer.completeError(Exception('Some segments failed to download'));
                    }
                  }
                }
              });
            }),
          );
        });
        
        if (!scheduled) {
          // No more to schedule, wait a bit
          await Future.delayed(Duration(milliseconds: 10));
          if (activeCount == 0 && nextPendingIndex >= pendingSegments.length) {
            // All done
            break;
          }
        }
      }
    }
    
    // Start initial batch
    for (int i = 0; i < _concurrencyManager.currentConcurrency && i < pendingSegments.length; i++) {
      scheduleNext();
    }
    
    // Wait for all downloads to complete
    await completer.future;
    
    if (errors.isNotEmpty) {
      throw Exception('Failed to download ${errors.length} segments');
    }
  }

  /// Download a segment directly to file (streaming write, not memory)
  Future<void> _downloadSegmentToFile(
    String url,
    String filePath,
    String description,
    int segmentIndex,
  ) async {
    final tempPath = '$filePath.tmp';
    http.Client? client;
    
    try {
      // Get client from pool
      client = await _clientPool.acquire();
      
      final headers = _getHttpHeaders(url, CookieManagerService.instance);
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      
      final startTime = DateTime.now();
      final streamedResponse = await client.send(request).timeout(
        Duration(seconds: segmentTimeoutSeconds),
        onTimeout: () {
          throw TimeoutException('Timeout downloading $description');
        },
      );
      
      // Classify error if status is not 200
      if (streamedResponse.statusCode != 200) {
        final error = Exception('HTTP ${streamedResponse.statusCode}');
        final errorType = ErrorClassifier.classifyError(error, streamedResponse.statusCode);
        final retryConfig = ErrorClassifier.getRetryConfig(errorType);
        
        if (!retryConfig.shouldRetry) {
          throw error;
        }
        
        // Retry logic would go here
        throw error; // For now, throw immediately
      }
      
      // Stream directly to file
      final file = File(tempPath);
      final sink = file.openWrite();
      
      await streamedResponse.stream.forEach((chunk) {
        sink.add(chunk);
        
        // Apply bandwidth throttling
        _bandwidthManager.throttle(chunk.length);
      });
      
      await sink.flush();
      await sink.close();
      
      final duration = DateTime.now().difference(startTime);
      
      // Record network metrics
      _networkMonitor.recordResult(true, duration);
      
      // Atomic rename
      final targetFile = File(filePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await file.rename(filePath);
      
    } catch (e) {
      // Clean up temp file on error
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      
      final statusCode = e is http.Response ? e.statusCode : null;
      final errorType = ErrorClassifier.classifyError(e, statusCode);
      final retryConfig = ErrorClassifier.getRetryConfig(errorType);
      
      if (retryConfig.shouldRetry) {
        // Retry with exponential backoff
        for (int attempt = 1; attempt <= retryConfig.maxRetries; attempt++) {
          await Future.delayed(Duration(
            milliseconds: (retryConfig.baseDelay.inMilliseconds * (1 << (attempt - 1))).toInt(),
          ));
          
          try {
            return await _downloadSegmentToFile(url, filePath, description, segmentIndex);
          } catch (retryError) {
            if (attempt == retryConfig.maxRetries) {
              rethrow;
            }
          }
        }
      }
      
      rethrow;
    } finally {
      if (client != null) {
        _clientPool.release(client);
      }
    }
  }

  /// Decrypt a segment file in place
  Future<void> _decryptSegmentFile(String filePath, Uint8List key, int segmentIndex) async {
    try {
      final encryptedData = await File(filePath).readAsBytes();
      final decryptedData = _decryptAES128(encryptedData, key, segmentIndex);
      
      // Atomic write decrypted data
      await AtomicFileUtils.atomicWriteBytes(filePath, decryptedData);
    } catch (e) {
      print('⚠️ Warning: Failed to decrypt segment file $segmentIndex: $e');
      rethrow;
    }
  }

  /// Save download state
  Future<void> _saveState(int segmentCount) async {
    if (_stateManager != null && _bitfield != null) {
      try {
        await _stateManager!.save(_bitfield!, segmentCount);
      } catch (e) {
        print('⚠️ Warning: Failed to save download state: $e');
        // Don't throw - state saving failure shouldn't stop download
      }
    }
  }

  Map<String, dynamic> _parseM3U8WithEncryption(String content) {
    final lines = content.split('\n');
    final segments = <String>[];
    String? keyUrl;
    String? encryptionMethod;

    // Extract base URL
    final baseUrl = task.m3u8Url.substring(0, task.m3u8Url.lastIndexOf('/') + 1);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.startsWith('#EXT-X-KEY:')) {
          // Extract key URL and method from EXT-X-KEY line
          final methodMatch = RegExp(r'METHOD=([^,]+)').firstMatch(trimmed);
          final keyMatch = RegExp(r'URI="([^"]*)"').firstMatch(trimmed);
          
          if (methodMatch != null) {
            encryptionMethod = methodMatch.group(1);
          }
          
          if (keyMatch != null) {
            final keyUri = keyMatch.group(1)!;
            keyUrl = keyUri.startsWith('http') ? keyUri : baseUrl + keyUri;
          }
        } else if (!trimmed.startsWith('#')) {
          // If it's a relative URL, make it absolute
          final segmentUrl = trimmed.startsWith('http') ? trimmed : baseUrl + trimmed;
          segments.add(segmentUrl);
        }
      }
    }

    return {
      'segments': segments,
      'keyUrl': keyUrl,
      'encryptionMethod': encryptionMethod,
    };
  }

  Uint8List _decryptAES128(Uint8List encryptedData, Uint8List key, int segmentIndex) {
    try {
      // HLS AES-128 uses segment sequence number as IV
      // IV is typically the segment index in last 8 bytes (big-endian)
      final iv = Uint8List(16);
      
      // Convert segment index to 8-byte big-endian representation
      final segmentIndexBytes = Uint8List(8);
      final indexValue = segmentIndex.toUnsigned(64);
      
      // Convert to big-endian bytes
      for (int i = 0; i < 8; i++) {
        segmentIndexBytes[7 - i] = (indexValue >> (i * 8)) & 0xFF;
      }
      
      // Copy to last 8 bytes of IV (big-endian)
      for (int i = 0; i < 8; i++) {
        iv[15 - i] = segmentIndexBytes[7 - i];
      }

      // Create AES-128-CBC decrypter
      final aesKey = encrypt.Key(key);
      final aesIv = encrypt.IV(iv);
      final encrypter = encrypt.Encrypter(encrypt.AES(aesKey, mode: encrypt.AESMode.cbc));

      // Decrypt the data
      final decrypted = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: aesIv);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      print('⚠️ Warning: Failed to decrypt segment $segmentIndex: $e');
      // Return original data if decryption fails
      return encryptedData;
    }
  }

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

  void _notifyProgress() {
    if (onProgress != null) {
      onProgress!(task);
    }
  }

  /// Fetch HTTP content with retry logic and exponential backoff (using error classifier)
  Future<String> _fetchWithRetry(
    String url,
    String description, {
    int? timeoutSeconds,
  }) async {
    final timeout = timeoutSeconds ?? baseTimeoutSeconds;
    final cookieManager = CookieManagerService.instance;
    Exception? lastError;
    int? lastStatusCode;

    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        if (attempt > 1) {
          print('🔍 Fetching $description (Attempt $attempt/5)...');
        }
        
        final headers = _getHttpHeaders(url, cookieManager);
        final client = await _clientPool.acquire();
        
        try {
          final response = await client.get(Uri.parse(url), headers: headers).timeout(
            Duration(seconds: timeout),
            onTimeout: () {
              throw TimeoutException('Network timeout after ${timeout}s while fetching $description');
            },
          );
          
          lastStatusCode = response.statusCode;
          
          if (response.statusCode == 200) {
            if (attempt > 1) {
              print('✅ $description fetched successfully (${response.body.length} bytes)');
            }
            _clientPool.release(client);
            return response.body;
          } else {
            throw Exception('HTTP ${response.statusCode} while fetching $description');
          }
        } finally {
          _clientPool.release(client);
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        // Classify error and decide retry strategy
        final errorType = ErrorClassifier.classifyError(lastError, lastStatusCode);
        final retryConfig = ErrorClassifier.getRetryConfig(errorType);
        
        if (!retryConfig.shouldRetry || attempt >= retryConfig.maxRetries) {
          print('❌ Failed to fetch $description: $lastError');
          throw lastError;
        }
        
        // Exponential backoff
        final delayMs = retryConfig.baseDelay.inMilliseconds * (1 << (attempt - 1));
        print('🔄 Retrying in ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw Exception('Failed to fetch $description after 5 attempts: $lastError');
  }

  /// Fetch HTTP bytes with retry logic (using error classifier)
  Future<Uint8List> _fetchBytesWithRetry(
    String url,
    String description, {
    int? timeoutSeconds,
  }) async {
    final timeout = timeoutSeconds ?? baseTimeoutSeconds;
    final cookieManager = CookieManagerService.instance;
    Exception? lastError;
    int? lastStatusCode;

    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        if (attempt > 1) {
          print('🔍 Fetching $description (Attempt $attempt/5)...');
        }
        
        final headers = _getHttpHeaders(url, cookieManager);
        final client = await _clientPool.acquire();
        
        try {
          final response = await client.get(Uri.parse(url), headers: headers).timeout(
            Duration(seconds: timeout),
            onTimeout: () {
              throw TimeoutException('Network timeout after ${timeout}s while fetching $description');
            },
          );
          
          lastStatusCode = response.statusCode;
          
          if (response.statusCode == 200) {
            if (attempt > 1) {
              print('✅ $description fetched successfully (${response.bodyBytes.length} bytes)');
            }
            _clientPool.release(client);
            return Uint8List.fromList(response.bodyBytes);
          } else {
            throw Exception('HTTP ${response.statusCode} while fetching $description');
          }
        } finally {
          _clientPool.release(client);
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        // Classify error and decide retry strategy
        final errorType = ErrorClassifier.classifyError(lastError, lastStatusCode);
        final retryConfig = ErrorClassifier.getRetryConfig(errorType);
        
        if (!retryConfig.shouldRetry || attempt >= retryConfig.maxRetries) {
          print('❌ Failed to fetch $description: $lastError');
          throw lastError;
        }
        
        // Exponential backoff
        final delayMs = retryConfig.baseDelay.inMilliseconds * (1 << (attempt - 1));
        print('🔄 Retrying in ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw Exception('Failed to fetch $description after 5 attempts: $lastError');
  }
}

/// Simple lock for synchronization
class Lock {
  bool _locked = false;
  final _waiters = <Completer<void>>[];
  
  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_locked) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}
