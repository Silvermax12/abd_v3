import 'dart:async';
import 'network_monitor.dart';

/// Manages adaptive concurrency based on network health and memory constraints
class AdaptiveConcurrencyManager {
  final NetworkMonitor networkMonitor;
  final int minConcurrency;
  final int maxConcurrency;
  final int initialConcurrency;
  
  int _currentConcurrency;
  Timer? _adjustmentTimer;
  
  // Memory management
  int _currentMemoryUsage = 0; // in bytes
  int _maxMemoryUsage = 50 * 1024 * 1024; // 50MB default
  
  AdaptiveConcurrencyManager({
    required this.networkMonitor,
    this.minConcurrency = 1,
    this.maxConcurrency = 8,
    this.initialConcurrency = 4,
  }) : _currentConcurrency = initialConcurrency;
  
  /// Get current allowed concurrency
  int get currentConcurrency => _currentConcurrency;
  
  /// Get semaphore-like permit system for concurrency control
  Future<T> withPermit<T>(Future<T> Function() operation) async {
    // This is a simplified version - in practice, you'd use a proper semaphore
    // For now, we rely on the caller to manage concurrency using this limit
    return await operation();
  }
  
  /// Adjust concurrency based on network health and memory
  void adjustConcurrency() {
    int newConcurrency = _currentConcurrency;
    
    // Check memory pressure first
    if (_currentMemoryUsage > _maxMemoryUsage * 0.8) {
      // Reduce due to memory pressure
      newConcurrency = (_currentConcurrency * 0.7).floor();
      if (newConcurrency < minConcurrency) {
        newConcurrency = minConcurrency;
      }
    } else if (networkMonitor.shouldReduceConcurrency()) {
      // Reduce due to poor network
      newConcurrency = _currentConcurrency - 1;
      if (newConcurrency < minConcurrency) {
        newConcurrency = minConcurrency;
      }
    } else if (networkMonitor.shouldIncreaseConcurrency() && 
               _currentMemoryUsage < _maxMemoryUsage * 0.5) {
      // Increase due to good network and available memory
      newConcurrency = _currentConcurrency + 1;
      if (newConcurrency > maxConcurrency) {
        newConcurrency = maxConcurrency;
      }
    }
    
    if (newConcurrency != _currentConcurrency) {
      final old = _currentConcurrency;
      _currentConcurrency = newConcurrency;
      print('🔄 Adjusted concurrency: $old -> $_currentConcurrency');
    }
  }
  
  /// Start periodic adjustment timer
  void startAutoAdjustment({Duration interval = const Duration(seconds: 5)}) {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = Timer.periodic(interval, (_) {
      adjustConcurrency();
    });
  }
  
  /// Stop automatic adjustment
  void stopAutoAdjustment() {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = null;
  }
  
  /// Record memory usage for a segment
  void recordMemoryUsage(int bytes) {
    _currentMemoryUsage += bytes;
  }
  
  /// Release memory usage for a segment
  void releaseMemoryUsage(int bytes) {
    _currentMemoryUsage = (_currentMemoryUsage - bytes).clamp(0, double.infinity).toInt();
  }
  
  /// Get current memory usage
  int get currentMemoryUsage => _currentMemoryUsage;
  
  /// Get memory limit
  int get maxMemoryUsage => _maxMemoryUsage;
  
  /// Check if memory pressure is high
  bool get isMemoryPressureHigh => _currentMemoryUsage > _maxMemoryUsage * 0.8;
  
  /// Set memory limits
  void setMemoryLimits({int? maxUsage}) {
    if (maxUsage != null) {
      _maxMemoryUsage = maxUsage;
    }
  }
  
  /// Dispose resources
  void dispose() {
    stopAutoAdjustment();
  }
}

