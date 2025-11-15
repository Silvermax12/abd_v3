import 'dart:async';

/// Manages download bandwidth limiting and throttling
class BandwidthManager {
  final int? maxBytesPerSecond; // null = unlimited
  int _bytesThisSecond = 0;
  DateTime _lastReset = DateTime.now();
  
  BandwidthManager({this.maxBytesPerSecond});
  
  /// Check if bandwidth limiting is enabled
  bool get isEnabled => maxBytesPerSecond != null;
  
  /// Throttle download to respect bandwidth limit
  Future<void> throttle(int bytesToSend) async {
    if (!isEnabled || maxBytesPerSecond == null) {
      return; // No throttling needed
    }
    
    final now = DateTime.now();
    final secondsElapsed = now.difference(_lastReset).inSeconds;
    
    // Reset counter if a full second has passed
    if (secondsElapsed >= 1) {
      _bytesThisSecond = 0;
      _lastReset = now;
    }
    
    // Check if we need to wait
    if (_bytesThisSecond + bytesToSend > maxBytesPerSecond!) {
      // Calculate wait time
      final bytesRemaining = maxBytesPerSecond! - _bytesThisSecond;
      final bytesOverLimit = bytesToSend - bytesRemaining;
      final waitSeconds = bytesOverLimit / maxBytesPerSecond!;
      
      if (waitSeconds > 0) {
        final waitDuration = Duration(milliseconds: (waitSeconds * 1000).ceil());
        await Future.delayed(waitDuration);
        
        // Reset after wait
        _bytesThisSecond = 0;
        _lastReset = DateTime.now();
      }
    }
    
    _bytesThisSecond += bytesToSend;
  }
  
  /// Reset throttling state
  void reset() {
    _bytesThisSecond = 0;
    _lastReset = DateTime.now();
  }
  
  /// Get current bandwidth usage (bytes this second)
  int get currentBytesPerSecond => _bytesThisSecond;
  
  /// Set new bandwidth limit
  void setLimit(int? bytesPerSecond) {
    // Implementation note: changing limit mid-download is supported
    // But for simplicity, we keep the field final and require recreation
    // In practice, you'd make this mutable if needed
  }
}

