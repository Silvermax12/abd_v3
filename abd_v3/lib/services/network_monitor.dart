/// Tracks network health metrics in real-time for adaptive download behavior
class NetworkMonitor {
  final List<RequestResult> _results = [];
  final int historySize;
  
  NetworkMonitor({this.historySize = 20});
  
  /// Record a request result (success or failure with timing)
  void recordResult(bool success, Duration responseTime) {
    _results.add(RequestResult(
      success: success,
      responseTime: responseTime,
      timestamp: DateTime.now(),
    ));
    
    // Keep only recent history
    if (_results.length > historySize) {
      _results.removeAt(0);
    }
  }
  
  /// Get success rate (0.0 to 1.0)
  double get successRate {
    if (_results.isEmpty) return 1.0;
    final successCount = _results.where((r) => r.success).length;
    return successCount / _results.length;
  }
  
  /// Get average response time
  Duration get averageResponseTime {
    if (_results.isEmpty) return Duration(seconds: 1);
    
    final totalMs = _results
        .map((r) => r.responseTime.inMilliseconds)
        .reduce((a, b) => a + b);
    final avgMs = totalMs / _results.length;
    
    return Duration(milliseconds: avgMs.round());
  }
  
  /// Get health score (0.0 to 1.0) - combination of success rate and response time
  double getHealthScore() {
    if (_results.isEmpty) return 1.0;
    
    final sr = successRate;
    final avgRt = averageResponseTime;
    
    // Penalize slow responses (consider > 5s as poor)
    final rtScore = avgRt.inMilliseconds > 5000
        ? (10000 - avgRt.inMilliseconds) / 10000.0
        : 1.0;
    
    // Combine success rate (70% weight) and response time (30% weight)
    return (sr * 0.7) + (rtScore * 0.3);
  }
  
  /// Check if concurrency should be reduced based on network health
  bool shouldReduceConcurrency() {
    if (_results.length < 5) return false; // Need minimum samples
    
    final health = getHealthScore();
    final sr = successRate;
    
    // Reduce if health is poor (< 0.6) or success rate is very low (< 0.5)
    return health < 0.6 || sr < 0.5;
  }
  
  /// Check if concurrency can be increased (network is healthy)
  bool shouldIncreaseConcurrency() {
    if (_results.length < 10) return false; // Need more samples to increase
    
    final health = getHealthScore();
    final sr = successRate;
    final avgRt = averageResponseTime;
    
    // Increase if health is good (> 0.8), success rate is high (> 0.9), and response time is reasonable (< 2s)
    return health > 0.8 && sr > 0.9 && avgRt.inSeconds < 2;
  }
  
  /// Check if network is in poor condition
  bool isNetworkPoor() {
    return successRate < 0.5;
  }
  
  /// Reset all metrics
  void reset() {
    _results.clear();
  }
  
  /// Get recent retry frequency (ratio of failed requests that were retried)
  double getRetryFrequency() {
    if (_results.isEmpty) return 0.0;
    // This is simplified - in practice, you'd track retry attempts separately
    final failureCount = _results.where((r) => !r.success).length;
    return failureCount / _results.length;
  }
}

/// Result of a single network request
class RequestResult {
  final bool success;
  final Duration responseTime;
  final DateTime timestamp;
  
  RequestResult({
    required this.success,
    required this.responseTime,
    required this.timestamp,
  });
}

