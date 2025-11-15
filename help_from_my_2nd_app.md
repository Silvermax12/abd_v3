# Complete Guide: M3U8 Handling in Flutter

This comprehensive guide documents how a Flutter app handles `.m3u8` links received from a backend API, including the complete processing pipeline, stream type detection, and a step-by-step implementation guide for implementing this functionality in another Flutter app.

## Table of Contents

1. [Overview](#overview)
2. [Backend Integration](#backend-integration)
3. [M3U8 Processing Pipeline](#m3u8-processing-pipeline)
4. [Stream Type Detection](#stream-type-detection)
5. [Core Implementation Details](#core-implementation-details)
6. [FFmpeg Integration](#ffmpeg-integration)
7. [State Management](#state-management)
8. [Complete Implementation Guide](#complete-implementation-guide)
9. [Best Practices](#best-practices)

---

## Overview

The Flutter app handles M3U8 (HTTP Live Streaming) playlists by:

1. **Receiving** `.m3u8` URLs from a backend API
2. **Fetching** the playlist content via HTTP
3. **Analyzing** the content to detect stream type (encrypted JPEG-over-HLS, true MJPEG, or standard HLS)
4. **Downloading** segments/frames with resume support
5. **Decrypting** encrypted segments if needed (AES-128)
6. **Re-encoding** using FFmpeg to produce final MP4 files
7. **Tracking** progress through callbacks and persistent storage

The system supports pause/resume, cancellation, error recovery, and handles multiple stream formats automatically.

---

## Backend Integration

### API Methods for Getting M3U8 Links

The app uses three main approaches to obtain M3U8 links from the backend:

#### 1. Direct Scraping (`scrapeM3u8Links`)

**Purpose:** Immediately fetch M3U8 links for specified episodes.

**API Endpoint:** `POST /scrape-m3u8`

**Request Format:**
```dart
final response = await dio.post('/scrape-m3u8', data: {
  'anime_session': animeSession,
  'episodes': [1, 2, 3],  // List of episode numbers
  'quality': '720',       // e.g., '360', '480', '720', '1080'
  'language': 'eng',      // e.g., 'eng', 'jpn', 'chi'
  'upgrade_quality': '1080',  // Optional: upgrade to higher quality
});
```

**Response Format:**
```json
{
  "episode_links": {
    "1": {
      "url": "https://cdn.example.com/ep1.m3u8",
      "quality": "720",
      "language": "eng"
    },
    "2": {
      "url": "https://cdn.example.com/ep2.m3u8",
      "quality": "720",
      "language": "eng"
    }
  }
}
```

**Implementation Example:**
```dart
Future<Map<String, dynamic>> scrapeM3u8Links({
  required String animeSession,
  required List<int> episodes,
  required String quality,
  required String language,
  String? upgradeQuality,
}) async {
  try {
    final requestData = {
      'anime_session': animeSession,
      'episodes': episodes,
      'quality': quality,
      'language': language,
    };

    if (upgradeQuality != null) {
      requestData['upgrade_quality'] = upgradeQuality;
    }

    final response = await dio.post('/scrape-m3u8', data: requestData);

    if (response.statusCode == 200) {
      return response.data;
    }
    throw Exception('Failed to scrape m3u8 links');
  } on DioException catch (e) {
    throw Exception('Error scraping m3u8 links: ${e.message}');
  }
}
```

#### 2. Job-Based Download (`downloadM3u8`)

**Purpose:** Start a background job that processes episodes and provides links incrementally.

**API Endpoint:** `POST /download-m3u8`

**Request Format:**
```dart
final response = await dio.post('/download-m3u8', data: {
  'anime_session': animeSession,
  'episodes': [1, 2, 3],
  'quality': '720',
  'language': 'eng',
  'anime_title': 'Anime Title',
  'upgrade_quality': '1080',  // Optional
});
```

**Response Format:**
```json
{
  "job_id": "abc123-def456-ghi789"
}
```

**Implementation Example:**
```dart
Future<Map<String, dynamic>> downloadM3u8({
  required String animeSession,
  required List<int> episodes,
  required String quality,
  required String language,
  required String animeTitle,
  String? upgradeQuality,
}) async {
  try {
    final requestData = {
      'anime_session': animeSession,
      'episodes': episodes,
      'quality': quality,
      'language': language,
      'anime_title': animeTitle,
    };

    if (upgradeQuality != null) {
      requestData['upgrade_quality'] = upgradeQuality;
    }

    final response = await dio.post('/download-m3u8', data: requestData);

    if (response.statusCode == 200) {
      return response.data;  // Contains 'job_id'
    }
    throw Exception('Failed to start M3U8 download');
  } on DioException catch (e) {
    throw Exception('Error starting download: ${e.message}');
  }
}
```

#### 3. Job-Based Polling (`getDownloadLinks`)

**Purpose:** Poll for links from a background job, receiving them incrementally as they become available.

**API Endpoint:** `GET /get-links/{jobId}`

**Response Format:**
```json
{
  "done": false,
  "links": {
    "1": {
      "url": "https://cdn.example.com/ep1.m3u8",
      "quality": "720",
      "language": "eng"
    }
  },
  "total_episodes": 3,
  "anime_title": "Anime Title"
}
```

**Polling Implementation:**
```dart
void startJobBasedPolling(String jobId) {
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      final linksResponse = await dio.get('/get-links/$jobId');
      final done = linksResponse.data['done'] as bool;
      final links = linksResponse.data['links'] as Map<String, dynamic>;

      // Process incremental links
      if (links.isNotEmpty) {
        await processIncrementalLinks(jobId, links);
      }

      // Stop polling when done
      if (done) {
        timer.cancel();
      }
    } catch (e) {
      print('Polling error: $e');
      // Continue polling on error
    }
  });
}
```

### Link Structure

Each episode link contains:
- **`url`**: The M3U8 playlist URL (e.g., `https://cdn.example.com/stream.m3u8`)
- **`quality`**: Video quality (e.g., `"720"`, `"1080"`)
- **`language`**: Audio language code (e.g., `"eng"`, `"jpn"`)

---

## M3U8 Processing Pipeline

The complete processing pipeline consists of 6 main phases:

```
┌─────────────────┐
│  Backend API   │
│  (M3U8 URLs)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  1. Fetch       │  HTTP GET to retrieve playlist content
│  M3U8 Content   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  2. Parse       │  Extract segments, encryption info
│  M3U8 Content   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  3. Detect      │  Analyze content to determine stream type
│  Stream Type    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  4. Download    │  Download segments/frames with resume
│  Segments       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  5. Decrypt     │  Decrypt AES-128 encrypted segments
│  (if needed)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  6. Re-encode   │  FFmpeg processing to MP4
│  with FFmpeg    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Final MP4 File │
└─────────────────┘
```

### Phase 1: Fetch M3U8 Content

**Purpose:** Retrieve the M3U8 playlist file from the URL.

**Implementation:**
```dart
Future<String> fetchM3u8Content(String m3u8Url) async {
  final response = await http.get(Uri.parse(m3u8Url));
  
  if (response.statusCode != 200) {
    throw Exception('Failed to fetch M3U8: ${response.statusCode} - ${response.reasonPhrase}');
  }
  
  final m3u8Content = response.body;
  print('✅ M3U8 fetched successfully (${m3u8Content.length} bytes)');
  
  return m3u8Content;
}
```

**Error Handling:**
- HTTP errors (non-200 status codes)
- Network timeouts
- Connection failures

### Phase 2: Parse M3U8 Content

**Purpose:** Extract segment URLs and encryption information from the playlist.

**M3U8 Format Example:**
```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example.com/key.bin"
#EXTINF:6.0,
https://cdn.example.com/segment001.ts
#EXTINF:6.0,
https://cdn.example.com/segment002.ts
```

**Parsing Implementation:**
```dart
Map<String, dynamic> parseM3u8Content(String m3u8Content, String baseUrl) {
  final segments = <String>[];
  Map<String, String>? encryptionInfo;

  final lines = m3u8Content.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    // Check for encryption key
    if (line.startsWith('#EXT-X-KEY:')) {
      encryptionInfo = parseEncryptionInfo(line, baseUrl);
    }

    // Parse segments (non-comment lines with URLs)
    if (line.isNotEmpty && 
        !line.startsWith('#') && 
        line.contains('http')) {
      segments.add(line);
    }
  }

  print('📊 Parsed ${segments.length} segment URLs from M3U8');
  if (encryptionInfo != null) {
    print('🔐 Found encryption: ${encryptionInfo['method']}');
  }

  return {
    'segments': segments,
    'encryption': encryptionInfo,
  };
}

Map<String, String>? parseEncryptionInfo(String keyLine, String baseUrl) {
  try {
    // Example: #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key"
    final methodMatch = RegExp(r'METHOD=([^,]+)').firstMatch(keyLine);
    final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(keyLine);

    if (methodMatch != null && uriMatch != null) {
      String keyUri = uriMatch.group(1)!;

      // Resolve relative URLs
      if (!keyUri.startsWith('http')) {
        final baseUri = Uri.parse(baseUrl);
        final relativeUri = Uri.parse(keyUri);
        keyUri = baseUri.resolveUri(relativeUri).toString();
      }

      return {
        'method': methodMatch.group(1)!,  // e.g., "AES-128"
        'uri': keyUri,                     // Resolved key URL
      };
    }
  } catch (e) {
    print('⚠️ Error parsing encryption info: $e');
  }
  return null;
}
```

**Return Structure:**
```dart
{
  'segments': List<String>,        // Array of segment URLs
  'encryption': Map<String, String>?  // { 'method': 'AES-128', 'uri': '...' } or null
}
```

### Phase 3: Detect Stream Type

**Purpose:** Analyze M3U8 content to determine the appropriate processing strategy.

**Detection Logic:**
```dart
void detectStreamType(String m3u8Content) {
  // Step 1: Extension Analysis
  final hasJpgExtensions = m3u8Content.contains('.jpg');
  final hasTsExtensions = m3u8Content.contains('.ts') || m3u8Content.contains('.m4s');
  final hasEncryption = m3u8Content.contains('#EXT-X-KEY:METHOD=AES-128');

  // Step 2: Stream Type Classification
  final isEncryptedJpegOverHls = hasJpgExtensions && !hasTsExtensions && hasEncryption;
  final isTrueMjpegStream = hasJpgExtensions && !hasEncryption;
  final isStandardHls = !isEncryptedJpegOverHls && !isTrueMjpegStream;

  // Route to appropriate handler
  if (isEncryptedJpegOverHls) {
    processEncryptedJpegOverHls(segments, encryptionInfo);
  } else if (isTrueMjpegStream) {
    processTrueMjpegStream(segments);
  } else {
    processStandardHls(segments, encryptionInfo);
  }
}
```

**Stream Type Detection Table:**

| Stream Type | JPG Extensions | TS Extensions | Encryption | Processing Method |
|-------------|----------------|---------------|------------|-------------------|
| **Encrypted JPEG-over-HLS** | ✅ | ❌ | ✅ | Download + Decrypt + Concat + Encode |
| **True MJPEG** | ✅ | ❌ | ❌ | Download Frames + Image Sequence |
| **Standard HLS** | ❌ | ✅ | ❌/✅ | Download + Concat + Encode |

### Phase 4: Download Segments

**Purpose:** Download all segments/frames with resume support and progress tracking.

#### For Encrypted JPEG-over-HLS and Standard HLS:

```dart
Future<void> downloadSegments({
  required List<String> segments,
  required String workDir,
  required Function(double) onProgress,
  required Function(String) onStatus,
  List<int>? encryptionKey,
  int resumeStartIndex = 0,
}) async {
  final concatFile = File('$workDir/concat.txt');
  final sink = await concatFile.exists()
      ? concatFile.openWrite(mode: FileMode.append)
      : concatFile.openWrite();

  int downloadedBytes = 0;
  final totalBytes = await estimateTotalBytes(segments);

  for (int i = resumeStartIndex; i < segments.length; i++) {
    final segmentUrl = segments[i];
    final segmentFile = File('$workDir/segment_${i.toString().padLeft(4, '0')}.ts');

    // Skip if already downloaded
    if (await segmentFile.exists()) {
      final size = await segmentFile.length();
      downloadedBytes += size;
      final segmentPath = segmentFile.absolute.path;
      sink.writeln("file '$segmentPath'");
      continue;
    }

    // Download segment
    final segmentData = await downloadSegmentWithRetries(segmentUrl);

    // Decrypt if needed
    List<int> decryptedData = segmentData;
    if (encryptionKey != null && encryptionKey.isNotEmpty) {
      decryptedData = await decryptAes128(segmentData, encryptionKey);
    }

    // Save segment
    await segmentFile.writeAsBytes(decryptedData);
    downloadedBytes += decryptedData.length;

    // Update concat file
    final segmentPath = segmentFile.absolute.path;
    sink.writeln("file '$segmentPath'");

    // Update progress
    final progressPercent = ((i + 1) / segments.length) * 100.0;
    onProgress(progressPercent);
    onStatus('Downloading segment ${i + 1}/${segments.length}');
  }

  await sink.close();
}
```

#### For True MJPEG Streams:

```dart
Future<void> downloadMjpegFrames({
  required List<String> segmentUrls,
  required String workDir,
  required Function(double) onProgress,
  required Function(String) onStatus,
  int resumeStartFrame = 0,
}) async {
  // Count existing frames
  final existingFrames = Directory(workDir)
      .listSync()
      .where((f) => f.path.contains('frame_') && f.path.endsWith('.jpg'))
      .length;

  int startFrame = resumeStartFrame > 0 ? resumeStartFrame : existingFrames;

  for (int i = startFrame; i < segmentUrls.length; i++) {
    final frameUrl = segmentUrls[i];
    final frameFile = File('$workDir/frame_${i.toString().padLeft(6, '0')}.jpg');

    // Skip if already downloaded
    if (await frameFile.exists()) continue;

    // Download frame
    final frameData = await downloadSegmentWithRetries(frameUrl);
    await frameFile.writeAsBytes(frameData);

    // Update progress
    final progressPercent = ((i + 1) / segmentUrls.length) * 100.0;
    onProgress(progressPercent);
    onStatus('Downloading frame ${i + 1}/${segmentUrls.length}');
  }
}
```

**Resume Support:**
- Checks for existing segment/frame files
- Counts lines in `concat.txt` for encrypted/standard HLS
- Counts existing frame files for MJPEG
- Continues from last downloaded item

**Retry Logic:**
```dart
Future<List<int>> downloadSegmentWithRetries(String url, {int maxRetries = 3}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      if (attempt == maxRetries) {
        throw Exception('Failed to download segment after $maxRetries attempts: $e');
      }
      await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
    }
  }
  throw Exception('Failed to download segment');
}
```

### Phase 5: Decrypt Segments

**Purpose:** Decrypt AES-128 encrypted segments using the encryption key.

**Key Download:**
```dart
Future<List<int>> downloadEncryptionKey(String keyUri) async {
  final response = await http.get(Uri.parse(keyUri));
  if (response.statusCode != 200) {
    throw Exception('Failed to download encryption key: ${response.statusCode}');
  }
  return response.bodyBytes;
}
```

**Decryption Implementation:**
```dart
Future<List<int>> decryptAes128(List<int> encryptedData, List<int> key) async {
  try {
    final keyBytes = encrypt.Key(Uint8List.fromList(key));
    final iv = Uint8List(16); // AES-128 uses 16-byte IV
    // For HLS, IV is typically the segment sequence number
    // This is a simplified version - actual implementation may vary
    
    final encrypter = encrypt.Encrypter(encrypt.AES(keyBytes));
    final encrypted = encrypt.Encrypted(Uint8List.fromList(encryptedData));
    
    // Note: Actual HLS decryption may require segment-specific IV handling
    final decrypted = encrypter.decrypt(encrypted, iv: encrypt.IV(iv));
    
    return decrypted.codeUnits;
  } catch (e) {
    print('❌ Decryption failed: $e');
    rethrow;
  }
}
```

**Note:** Real HLS decryption requires proper IV handling (often segment sequence number). The `encrypt` package may need custom IV logic.

### Phase 6: Re-encode with FFmpeg

**Purpose:** Convert downloaded segments/frames into final MP4 file.

#### For Encrypted JPEG-over-HLS and Standard HLS:

**FFmpeg Command:**
```bash
ffmpeg -y -f concat -safe 0 -i "concat.txt" -c:v libx264 -preset fast -crf 24 -c:a aac -b:a 128k "output.mp4"
```

**Implementation:**
```dart
Future<void> reencodeWithFFmpeg({
  required String concatFile,
  required String outputPath,
  required String quality,
  required Function(double) onProgress,
  required Function(String) onStatus,
}) async {
  final crf = getCrfForQuality(quality);
  final args = [
    '-y',
    '-f', 'concat',
    '-safe', '0',
    '-i', concatFile,
    '-c:v', 'libx264',
    '-preset', 'fast',
    '-crf', crf.toString(),
    '-c:a', 'aac',
    '-b:a', '128k',
    outputPath,
  ];

  await FFmpegService.instance.runFFmpeg(
    arguments: args,
    onStdErr: (line) {
      // Parse FFmpeg progress from stderr
      final progress = parseFFmpegProgress(line);
      if (progress != null) {
        onProgress(progress);
      }
      onStatus(line);
    },
  );
}
```

#### For True MJPEG Streams:

**FFmpeg Command:**
```bash
ffmpeg -y -f image2 -i "frame_%06d.jpg" -c:v libx264 -preset fast -crf 24 -c:a aac -b:a 128k -r 24 "output.mp4"
```

**Implementation:**
```dart
Future<void> reencodeMjpegWithFFmpeg({
  required String workDir,
  required String outputPath,
  required String quality,
  required Function(double) onProgress,
  required Function(String) onStatus,
}) async {
  final crf = getCrfForQuality(quality);
  final args = [
    '-y',
    '-f', 'image2',
    '-i', '$workDir/frame_%06d.jpg',
    '-c:v', 'libx264',
    '-preset', 'fast',
    '-crf', crf.toString(),
    '-c:a', 'aac',
    '-b:a', '128k',
    '-r', '24',  // Frame rate for MJPEG
    outputPath,
  ];

  await FFmpegService.instance.runFFmpeg(
    arguments: args,
    onStdErr: (line) {
      final progress = parseFFmpegProgress(line);
      if (progress != null) {
        onProgress(progress);
      }
      onStatus(line);
    },
  );
}
```

**CRF Quality Mapping:**
```dart
int getCrfForQuality(String quality) {
  switch (quality) {
    case '360':
      return 28;  // Higher CRF = lower quality, smaller file
    case '480':
      return 26;
    case '720':
      return 24;
    case '1080':
      return 22;  // Lower CRF = higher quality, larger file
    default:
      return 24;  // Default to 720p quality
  }
}
```

---

## Stream Type Detection

### Detection Criteria

The app uses content analysis to detect three stream types:

#### 1. Encrypted JPEG-over-HLS

**Detection:**
```dart
final isEncryptedJpegOverHls = 
    m3u8Content.contains('.jpg') && 
    !m3u8Content.contains('.ts') && 
    !m3u8Content.contains('.m4s') &&
    m3u8Content.contains('#EXT-X-KEY:METHOD=AES-128');
```

**Characteristics:**
- Contains `.jpg` extensions in segment URLs
- No `.ts` or `.m4s` extensions
- Has AES-128 encryption
- JPEG frames are encrypted segments

**Processing:**
1. Download encrypted JPEG segments
2. Decrypt each segment
3. Concatenate decrypted segments
4. Re-encode with FFmpeg

#### 2. True MJPEG Streams

**Detection:**
```dart
final isTrueMjpegStream = 
    m3u8Content.contains('.jpg') && 
    !m3u8Content.contains('#EXT-X-KEY:METHOD=AES-128');
```

**Characteristics:**
- Contains `.jpg` extensions
- No encryption
- Unencrypted JPEG frames in sequence

**Processing:**
1. Download JPEG frames individually
2. Save as `frame_000001.jpg`, `frame_000002.jpg`, etc.
3. Use FFmpeg image sequence input to create video

#### 3. Standard HLS Streams

**Detection:**
```dart
final isStandardHls = 
    !isEncryptedJpegOverHls && 
    !isTrueMjpegStream;
```

**Characteristics:**
- Contains `.ts` or `.m4s` extensions
- May or may not have encryption
- Traditional HLS video segments

**Processing:**
1. Download TS/M4S segments
2. Decrypt if encrypted
3. Concatenate segments
4. Re-encode with FFmpeg (or use segments directly if compatible)

---

## Core Implementation Details

### M3U8 Parsing Logic

**Complete Parser:**
```dart
class M3u8Parser {
  Map<String, dynamic> parse(String m3u8Content, String baseUrl) {
    final segments = <String>[];
    Map<String, String>? encryptionInfo;
    final lines = m3u8Content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Parse encryption key
      if (line.startsWith('#EXT-X-KEY:')) {
        encryptionInfo = _parseEncryptionInfo(line, baseUrl);
      }

      // Parse segment URLs
      if (line.isNotEmpty && 
          !line.startsWith('#') && 
          (line.startsWith('http') || line.startsWith('/'))) {
        // Resolve relative URLs
        String segmentUrl = line;
        if (!line.startsWith('http')) {
          final baseUri = Uri.parse(baseUrl);
          final relativeUri = Uri.parse(line);
          segmentUrl = baseUri.resolveUri(relativeUri).toString();
        }
        segments.add(segmentUrl);
      }
    }

    return {
      'segments': segments,
      'encryption': encryptionInfo,
    };
  }

  Map<String, String>? _parseEncryptionInfo(String keyLine, String baseUrl) {
    final methodMatch = RegExp(r'METHOD=([^,]+)').firstMatch(keyLine);
    final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(keyLine);

    if (methodMatch != null && uriMatch != null) {
      String keyUri = uriMatch.group(1)!;
      if (!keyUri.startsWith('http')) {
        final baseUri = Uri.parse(baseUrl);
        final relativeUri = Uri.parse(keyUri);
        keyUri = baseUri.resolveUri(relativeUri).toString();
      }

      return {
        'method': methodMatch.group(1)!,
        'uri': keyUri,
      };
    }
    return null;
  }
}
```

### Encryption Handling

**Key Download:**
```dart
Future<List<int>> downloadEncryptionKey(String keyUri) async {
  try {
    final response = await http.get(Uri.parse(keyUri));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to download key: ${response.statusCode}');
  } catch (e) {
    throw Exception('Error downloading encryption key: $e');
  }
}
```

**AES-128 Decryption:**
```dart
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:typed_data';

Future<List<int>> decryptAes128Segment(
  List<int> encryptedData,
  List<int> key,
  int segmentIndex,  // For IV calculation
) async {
  try {
    final keyBytes = encrypt.Key(Uint8List.fromList(key));
    
    // HLS AES-128 uses segment sequence number as IV
    final ivBytes = Uint8List(16);
    final segmentIndexBytes = Uint8List.view(
      segmentIndex.toUnsigned(64).toBytes().buffer
    );
    // Copy segment index to IV (last 8 bytes, big-endian)
    for (int i = 0; i < 8; i++) {
      ivBytes[15 - i] = segmentIndexBytes[7 - i];
    }
    
    final encrypter = encrypt.Encrypter(encrypt.AES(keyBytes));
    final encrypted = encrypt.Encrypted(Uint8List.fromList(encryptedData));
    final iv = encrypt.IV(ivBytes);
    
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return decrypted.codeUnits;
  } catch (e) {
    print('❌ Decryption failed: $e');
    rethrow;
  }
}
```

### Segment Download with Retry Logic

```dart
class SegmentDownloader {
  Future<List<int>> downloadWithRetries(
    String url, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    CancelToken? cancelToken,
  }) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        attempt++;
        
        final dio = Dio();
        final response = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken,
        );
        
        if (response.statusCode == 200 && response.data != null) {
          return response.data!;
        }
        
        throw Exception('HTTP ${response.statusCode}');
      } catch (e) {
        if (attempt >= maxRetries) {
          throw Exception('Failed after $maxRetries attempts: $e');
        }
        
        // Check if cancelled
        if (e.toString().contains('cancelled') || 
            e.toString().contains('Cancelled')) {
          throw Exception('Download cancelled');
        }
        
        // Exponential backoff
        await Future.delayed(retryDelay * attempt);
      }
    }
    
    throw Exception('Download failed');
  }
}
```

### Progress Tracking and ETA Calculation

**Throughput Estimator:**
```dart
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
```

**Usage:**
```dart
final estimator = ThroughputEstimator();

// During download
final downloadStart = DateTime.now();
final segmentData = await downloadSegment(url);
final downloadEnd = DateTime.now();
final downloadTimeMs = downloadEnd.difference(downloadStart).inMilliseconds;

estimator.addSample(segmentData.length, downloadTimeMs);

// Calculate ETA
final remainingBytes = totalBytes - downloadedBytes;
final eta = estimator.etaForRemainingBytes(remainingBytes);
final speed = estimator.throughputText;
```

### Pause/Resume/Cancel Controls

**Control Class:**
```dart
class EpisodeControl {
  bool paused = false;
  bool cancelled = false;
  Completer<void>? _pauseWaiter;
  CancelToken? _cancelToken;
  
  Future<void> waitIfPaused() async {
    while (paused && !cancelled) {
      _pauseWaiter ??= Completer<void>();
      await Future.any([
        _pauseWaiter!.future,
        Future.delayed(const Duration(milliseconds: 200)),
      ]);
    }
  }
  
  void resume() {
    paused = false;
    _pauseWaiter?.complete();
    _pauseWaiter = null;
  }
  
  void cancel() {
    cancelled = true;
    _cancelToken?.cancel('Cancelled');
    _pauseWaiter?.complete();
  }
  
  CancelToken createCancelToken() {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    return _cancelToken!;
  }
}
```

**Usage in Download Loop:**
```dart
for (int i = 0; i < segments.length; i++) {
  // Check for cancellation
  if (control.cancelled) {
    throw Exception('Cancelled');
  }
  
  // Wait if paused
  await control.waitIfPaused();
  
  // Check again after pause
  if (control.shouldCancelRequest()) {
    throw Exception('Paused');
  }
  
  // Download with cancel token
  final cancelToken = control.createCancelToken();
  final segmentData = await downloadSegment(
    segments[i],
    cancelToken: cancelToken,
  );
  
  // Process segment...
}
```

---

## FFmpeg Integration

### Platform-Specific FFmpeg Usage

**Windows (Native FFmpeg.exe):**
```dart
import 'dart:io';

class FFmpegService {
  static final FFmpegService instance = FFmpegService._internal();
  FFmpegService._internal();
  
  Future<int> runFFmpeg({
    required List<String> arguments,
    required Function(String) onStdErr,
  }) async {
    if (Platform.isWindows) {
      // Use native ffmpeg.exe
      final process = await Process.start(
        'ffmpeg.exe',  // Must be in PATH or provide full path
        arguments,
      );
      
      process.stderr.transform(utf8.decoder).listen((line) {
        onStdErr(line);
      });
      
      final exitCode = await process.exitCode;
      return exitCode;
    } else {
      // Use FFmpegKit for mobile
      return await runFFmpegKit(arguments, onStdErr);
    }
  }
}
```

**Mobile (FFmpegKit):**
```dart
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

Future<int> runFFmpegKit(
  List<String> arguments,
  Function(String) onStdErr,
) async {
  final command = arguments.join(' ');
  
  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();
  
  // Get output
  final output = await session.getOutput();
  if (output != null) {
    onStdErr(output);
  }
  
  if (ReturnCode.isSuccess(returnCode)) {
    return 0;
  } else {
    return returnCode?.getValue() ?? -1;
  }
}
```

### FFmpeg Progress Parsing

**Progress Parser:**
```dart
double? parseFFmpegProgress(String message) {
  try {
    // Example: "frame= 2538 fps=139 q=32.0 size=    4352kB time=00:01:48.49 bitrate= 328.6kbits/s speed=5.96x"
    
    final timeRegex = RegExp(r'time=(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)');
    final timeMatch = timeRegex.firstMatch(message);
    
    if (timeMatch != null) {
      final hours = double.parse(timeMatch.group(1)!);
      final minutes = double.parse(timeMatch.group(2)!);
      final seconds = double.parse(timeMatch.group(3)!);
      final currentTime = hours * 3600 + minutes * 60 + seconds;
      
      // Calculate progress if total duration is known
      if (totalDuration != null && totalDuration! > 0) {
        final progress = (currentTime / totalDuration!) * 100.0;
        return progress.clamp(0.0, 100.0);
      }
    }
  } catch (e) {
    // Ignore parse errors
  }
  return null;
}
```

**Complete Progress Parser:**
```dart
Map<String, dynamic>? parseFFmpegProgress(String message) {
  try {
    final frameRegex = RegExp(r'frame=\s*(\d+)');
    final fpsRegex = RegExp(r'fps=\s*(\d+(?:\.\d+)?)');
    final sizeRegex = RegExp(r'size=\s*(\d+)kB');
    final timeRegex = RegExp(r'time=(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)');
    final bitrateRegex = RegExp(r'bitrate=\s*(\d+(?:\.\d+)?)kbits/s');
    final speedRegex = RegExp(r'speed=\s*(\d+(?:\.\d+)?)x');
    
    final frameMatch = frameRegex.firstMatch(message);
    final fpsMatch = fpsRegex.firstMatch(message);
    final sizeMatch = sizeRegex.firstMatch(message);
    final timeMatch = timeRegex.firstMatch(message);
    final bitrateMatch = bitrateRegex.firstMatch(message);
    final speedMatch = speedRegex.firstMatch(message);
    
    if (frameMatch != null && timeMatch != null) {
      final frame = int.parse(frameMatch.group(1)!);
      final fps = fpsMatch != null ? double.parse(fpsMatch.group(1)!) : 0.0;
      final sizeKB = sizeMatch != null ? int.parse(sizeMatch.group(1)!) : 0;
      
      final hours = double.parse(timeMatch.group(1)!);
      final minutes = double.parse(timeMatch.group(2)!);
      final seconds = double.parse(timeMatch.group(3)!);
      final totalSeconds = hours * 3600 + minutes * 60 + seconds;
      
      final bitrate = bitrateMatch != null 
          ? double.parse(bitrateMatch.group(1)!) 
          : 0.0;
      final speed = speedMatch != null 
          ? double.parse(speedMatch.group(1)!) 
          : 1.0;
      
      return {
        'frame': frame,
        'fps': fps,
        'size': sizeKB,
        'time': totalSeconds,
        'bitrate': bitrate,
        'speed': speed,
      };
    }
  } catch (e) {
    // Ignore parse errors
  }
  return null;
}
```

### CRF Quality Mapping

```dart
int getCrfForQuality(String quality) {
  // CRF (Constant Rate Factor) values:
  // Lower = higher quality, larger file
  // Higher = lower quality, smaller file
  // Range: 0-51 (18-28 is typical for good quality)
  
  switch (quality) {
    case '360':
      return 28;  // Lower quality for smaller files
    case '480':
      return 26;
    case '720':
      return 24;  // Balanced quality
    case '1080':
      return 22;  // Higher quality
    default:
      return 24;  // Default to 720p quality
  }
}
```

---

## State Management

### Hive Persistence

**Download Record Model:**
```dart
@HiveType(typeId: 2)
class DownloadRecordHive extends HiveObject {
  @HiveField(0)
  String id;
  
  @HiveField(1)
  String animeTitle;
  
  @HiveField(2)
  String quality;
  
  @HiveField(3)
  String language;
  
  @HiveField(4)
  List<EpisodeTaskHive> episodeTasks;
  
  @HiveField(5)
  DateTime createdAt;
  
  @HiveField(6)
  DateTime? completedAt;
  
  @HiveField(7)
  String? directoryPath;
  
  @HiveField(8)
  String? backendTaskId;  // For job-based downloads
  
  // Computed properties
  double get averageProgress {
    if (episodeTasks.isEmpty) return 0.0;
    final total = episodeTasks.fold(0, (sum, ep) => sum + ep.progress);
    return total / episodeTasks.length;
  }
  
  DownloadStatus get overallStatus {
    if (episodeTasks.isEmpty) return DownloadStatus.pending;
    
    final allCompleted = episodeTasks.every((ep) => 
        ep.status == DownloadStatus.completed);
    if (allCompleted) return DownloadStatus.completed;
    
    final anyFailed = episodeTasks.any((ep) => 
        ep.status == DownloadStatus.failed);
    if (anyFailed) return DownloadStatus.failed;
    
    final anyRunning = episodeTasks.any((ep) => 
        ep.status == DownloadStatus.running);
    if (anyRunning) return DownloadStatus.running;
    
    return DownloadStatus.pending;
  }
}

@HiveType(typeId: 1)
class EpisodeTaskHive extends HiveObject {
  @HiveField(0)
  int episodeNumber;
  
  @HiveField(1)
  String taskId;
  
  @HiveField(2)
  int progress;  // 0-100
  
  @HiveField(3)
  int statusIndex;  // DownloadStatus enum index
  
  @HiveField(4)
  String? fileName;
  
  @HiveField(5)
  String? savedDir;
  
  @HiveField(6)
  String? filePath;
  
  @HiveField(7)
  String? m3u8Url;  // Stored for resume capability
  
  @HiveField(8)
  bool isPaused;
  
  @HiveField(9)
  int reEncodeProgress;  // 0-100
  
  @HiveField(10)
  String? errorMessage;
  
  DownloadStatus get status => DownloadStatus.values[statusIndex];
  set status(DownloadStatus s) => statusIndex = s.index;
}
```

**Initialization:**
```dart
Future<void> initializeHive() async {
  await Hive.initFlutter();
  
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(EpisodeTaskHiveAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(DownloadRecordHiveAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(DownloadStatusAdapter());
  }
  
  await Hive.openBox<DownloadRecordHive>('downloads_box_v1');
}
```

**Saving Download Record:**
```dart
Future<void> saveDownloadRecord(DownloadRecordHive record) async {
  final box = Hive.box<DownloadRecordHive>('downloads_box_v1');
  await box.put(record.id, record);
}
```

**Loading Download Records:**
```dart
List<DownloadRecordHive> loadDownloadRecords() {
  final box = Hive.box<DownloadRecordHive>('downloads_box_v1');
  return box.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
```

### Episode-Level Progress Tracking

**Progress Update:**
```dart
Future<void> updateEpisodeProgress({
  required String recordId,
  required int episodeNumber,
  required int progress,
  DownloadStatus? status,
}) async {
  final box = Hive.box<DownloadRecordHive>('downloads_box_v1');
  final record = box.get(recordId);
  
  if (record != null) {
    final episode = record.episodeTasks.firstWhere(
      (ep) => ep.episodeNumber == episodeNumber,
    );
    
    episode.progress = progress;
    if (status != null) {
      episode.status = status;
    }
    
    await box.put(recordId, record);
  }
}
```

### Resume Capability Implementation

**Resume Detection:**
```dart
Future<int> detectResumePoint({
  required String workDir,
  required bool isMjpeg,
}) async {
  if (isMjpeg) {
    // Count existing frame files
    final dir = Directory(workDir);
    if (await dir.exists()) {
      final frames = dir.listSync()
          .where((f) => f.path.contains('frame_') && f.path.endsWith('.jpg'))
          .length;
      return frames;
    }
  } else {
    // Count lines in concat.txt
    final concatFile = File('$workDir/concat.txt');
    if (await concatFile.exists()) {
      final lines = await concatFile.readAsLines();
      return lines.where((l) => l.trim().startsWith("file '")).length;
    }
  }
  return 0;
}
```

**M3U8 URL Persistence:**
```dart
Future<void> persistM3u8Url(String workDir, String m3u8Url) async {
  final urlFile = File('$workDir/m3u8_url.txt');
  await urlFile.writeAsString(m3u8Url, flush: true);
}

Future<String?> recoverM3u8Url(String workDir) async {
  final urlFile = File('$workDir/m3u8_url.txt');
  if (await urlFile.exists()) {
    return await urlFile.readAsString();
  }
  return null;
}
```

---

## Complete Implementation Guide

This section provides a step-by-step guide to implement M3U8 handling in a new Flutter app.

### Step 1: Add Required Dependencies

**pubspec.yaml:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # HTTP and networking
  http: ^1.1.0
  dio: ^5.4.0
  
  # Encryption
  encrypt: ^5.0.1
  
  # FFmpeg (choose based on platform)
  ffmpeg_kit_flutter_new: ^5.1.0  # For mobile
  # OR use native Process.start for Windows
  
  # Storage
  path_provider: ^2.1.1
  hive: ^2.2.0
  hive_flutter: ^1.1.0
  
  # Utilities
  path: ^1.8.3
```

### Step 2: Create M3U8 Service Class

**lib/services/m3u8_service.dart:**
```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:dio/dio.dart';

class M3u8Service {
  // Throughput estimator (from earlier section)
  // EpisodeControl (from earlier section)
  // M3u8Parser (from earlier section)
  // SegmentDownloader (from earlier section)
  
  Future<String> downloadM3u8({
    required String m3u8Url,
    required String outputPath,
    required String quality,
    required Function(double) onDownloadProgress,
    required Function(double) onReencodeProgress,
    required Function(String) onStatus,
  }) async {
    // Implementation from Phase 1-6
  }
}
```

### Step 3: Create Download Provider

**lib/providers/download_provider.dart:**
```dart
import 'package:flutter/foundation.dart';
import '../services/m3u8_service.dart';
import '../services/api_service.dart';

class DownloadProvider extends ChangeNotifier {
  final M3u8Service _m3u8Service = M3u8Service();
  final ApiService _apiService = ApiService();
  
  List<DownloadTask> _downloads = [];
  
  Future<String?> startDownload({
    required String animeSession,
    required List<int> episodes,
    required String quality,
    required String language,
    required String animeTitle,
  }) async {
    try {
      // Get M3U8 links from backend
      final m3u8Data = await _apiService.scrapeM3u8Links(
        animeSession: animeSession,
        episodes: episodes,
        quality: quality,
        language: language,
      );
      
      // Process each episode
      final episodeLinks = m3u8Data['episode_links'] as Map<String, dynamic>;
      
      for (final entry in episodeLinks.entries) {
        final episode = int.parse(entry.key);
        final linkData = entry.value as Map<String, dynamic>;
        final m3u8Url = linkData['url'] as String;
        
        await _downloadEpisode(
          episode: episode,
          m3u8Url: m3u8Url,
          quality: quality,
          animeTitle: animeTitle,
        );
      }
      
      return 'success';
    } catch (e) {
      print('Download error: $e');
      return null;
    }
  }
  
  Future<void> _downloadEpisode({
    required int episode,
    required String m3u8Url,
    required String quality,
    required String animeTitle,
  }) async {
    final outputPath = await _getOutputPath(animeTitle, episode, quality);
    
    await _m3u8Service.downloadM3u8(
      m3u8Url: m3u8Url,
      outputPath: outputPath,
      quality: quality,
      onDownloadProgress: (progress) {
        // Update UI
        notifyListeners();
      },
      onReencodeProgress: (progress) {
        // Update UI
        notifyListeners();
      },
      onStatus: (status) {
        print('Episode $episode: $status');
      },
    );
  }
  
  Future<String> _getOutputPath(String title, int episode, String quality) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    return '${dir.path}/${safeTitle}_E${episode}_${quality}p.mp4';
  }
}
```

### Step 4: Initialize Services

**lib/main.dart:**
```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/download_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  // Register adapters...
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DownloadScreen(),
    );
  }
}
```

### Step 5: Create UI

**lib/screens/download_screen.dart:**
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';

class DownloadScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('M3U8 Downloads')),
      body: Consumer<DownloadProvider>(
        builder: (context, provider, child) {
          return ListView.builder(
            itemCount: provider.downloads.length,
            itemBuilder: (context, index) {
              final task = provider.downloads[index];
              return ListTile(
                title: Text(task.animeTitle),
                subtitle: LinearProgressIndicator(
                  value: task.progress / 100.0,
                ),
                trailing: Text('${task.progress.toStringAsFixed(1)}%'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Start download
          context.read<DownloadProvider>().startDownload(
            animeSession: 'session123',
            episodes: [1, 2, 3],
            quality: '720',
            language: 'eng',
            animeTitle: 'Test Anime',
          );
        },
        child: Icon(Icons.download),
      ),
    );
  }
}
```

### Step 6: Handle Platform-Specific FFmpeg

**Windows:**
```dart
// Ensure ffmpeg.exe is in PATH or provide full path
final process = await Process.start(
  'ffmpeg.exe',
  ['-i', 'input.m3u8', 'output.mp4'],
);
```

**Mobile:**
```dart
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';

final session = await FFmpegKit.execute(
  '-i input.m3u8 output.mp4'
);
```

### Step 7: Error Handling

**Add comprehensive error handling:**
```dart
try {
  await downloadM3u8(...);
} on HttpException catch (e) {
  print('HTTP error: $e');
  // Handle network errors
} on FormatException catch (e) {
  print('Parse error: $e');
  // Handle parsing errors
} catch (e) {
  print('Unknown error: $e');
  // Handle other errors
}
```

### Step 8: Add Pause/Resume Support

**Implement controls:**
```dart
class DownloadController {
  final EpisodeControl control = EpisodeControl();
  
  void pause() {
    control.paused = true;
  }
  
  void resume() {
    control.resume();
  }
  
  void cancel() {
    control.cancel();
  }
}
```

---

## Best Practices

### 1. Error Handling

- **Network Errors:** Implement retry logic with exponential backoff
- **Parse Errors:** Validate M3U8 content before processing
- **FFmpeg Errors:** Check exit codes and provide fallback commands
- **Storage Errors:** Verify disk space before starting downloads

### 2. Performance Optimization

- **Concurrent Downloads:** Limit concurrent downloads (e.g., max 2 per record)
- **Memory Management:** Process segments in chunks, avoid loading all into memory
- **Progress Updates:** Throttle progress callbacks to avoid UI lag

### 3. Resume Capability

- **Persist M3U8 URLs:** Save URLs in sidecar files for recovery
- **Track Progress:** Use Hive or similar for persistent state
- **Verify Files:** Check file integrity before resuming

### 4. User Experience

- **Progress Feedback:** Show both download and re-encode progress
- **ETA Display:** Calculate and display accurate ETAs
- **Error Messages:** Provide clear, actionable error messages
- **Notifications:** Notify users of completion/failures

### 5. Code Organization

- **Separation of Concerns:** Keep parsing, downloading, and encoding separate
- **Service Layer:** Use service classes for business logic
- **State Management:** Use Provider/Riverpod for UI state
- **Error Recovery:** Implement graceful degradation

### 6. Testing

- **Unit Tests:** Test parsing, encryption, and progress calculation
- **Integration Tests:** Test full download pipeline
- **Error Scenarios:** Test network failures, invalid URLs, etc.

---

## Summary

This guide covers the complete M3U8 handling implementation in Flutter:

1. **Backend Integration:** Three methods to get M3U8 links (scraping, job-based, polling)
2. **Processing Pipeline:** 6 phases from fetch to final MP4
3. **Stream Detection:** Automatic detection of 3 stream types
4. **Core Implementation:** Parsing, encryption, downloading, progress tracking
5. **FFmpeg Integration:** Platform-specific handling and progress parsing
6. **State Management:** Hive persistence and resume capability
7. **Implementation Guide:** Step-by-step guide for new apps

The system is designed to be robust, resumable, and user-friendly, handling various stream formats automatically while providing detailed progress feedback.

