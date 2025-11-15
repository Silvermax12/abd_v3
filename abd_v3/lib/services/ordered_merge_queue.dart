import 'dart:io';

/// Manages ordered merging of segments to ensure correct output order
/// even when segments complete out of order
class OrderedMergeQueue {
  final String outputDir;
  final int totalSegments;
  final Map<int, String> _completedSegments = {}; // index -> file path
  final int maxQueueSize;
  int _nextExpectedIndex = 0;
  
  OrderedMergeQueue({
    required this.outputDir,
    required this.totalSegments,
    this.maxQueueSize = 10,
  });
  
  /// Add a completed segment (may complete out of order)
  void addSegment(int index, String segmentFilePath) {
    if (index < 0 || index >= totalSegments) {
      throw ArgumentError('Segment index $index out of range [0, $totalSegments)');
    }
    
    _completedSegments[index] = segmentFilePath;
    
    // Prevent queue from growing too large (backpressure)
    if (_completedSegments.length > maxQueueSize) {
      // If we have too many buffered segments, wait for merge to catch up
      // This shouldn't happen often, but provides safety
    }
  }
  
  /// Get the next segment in order that's ready to merge
  String? getNextReadySegment() {
    if (_completedSegments.containsKey(_nextExpectedIndex)) {
      final path = _completedSegments.remove(_nextExpectedIndex)!;
      _nextExpectedIndex++;
      return path;
    }
    return null;
  }
  
  /// Check if next expected segment is ready
  bool isNextReady() {
    return _completedSegments.containsKey(_nextExpectedIndex);
  }
  
  /// Get all segments that can be merged in order (up to next gap)
  List<String> getReadySegments() {
    final ready = <String>[];
    
    while (_completedSegments.containsKey(_nextExpectedIndex)) {
      final path = _completedSegments.remove(_nextExpectedIndex)!;
      ready.add(path);
      _nextExpectedIndex++;
    }
    
    return ready;
  }
  
  /// Check if all segments are ready
  bool isComplete() {
    return _nextExpectedIndex >= totalSegments;
  }
  
  /// Get progress (how many segments merged so far)
  int get mergedCount => _nextExpectedIndex;
  
  /// Get buffered count (segments waiting for their turn)
  int get bufferedCount => _completedSegments.length;
  
  /// Get all segments as ordered list (waiting for all to complete)
  /// Use this for final merge when all segments are downloaded
  List<String> getAllSegmentsInOrder() {
    final segments = <String>[];
    for (int i = 0; i < totalSegments; i++) {
      final segmentPath = _completedSegments[i];
      if (segmentPath == null) {
        throw StateError('Segment $i not found in queue');
      }
      segments.add(segmentPath);
    }
    return segments;
  }
  
  /// Validate that all segments exist before merge
  Future<bool> validateAllSegments() async {
    for (int i = 0; i < totalSegments; i++) {
      final segmentPath = _completedSegments[i];
      if (segmentPath == null) {
        print('⚠️ Segment $i missing from merge queue');
        return false;
      }
      final file = File(segmentPath);
      if (!await file.exists()) {
        print('⚠️ Segment file not found: $segmentPath');
        return false;
      }
    }
    return true;
  }
}

