import 'dart:async';
import 'dart:collection';
import 'package:http/http.dart' as http;

/// Pool of reusable HTTP clients for efficient connection management
class HttpClientPool {
  final int maxSize;
  final Queue<http.Client> _availableClients = Queue<http.Client>();
  final Set<http.Client> _activeClients = <http.Client>{};
  
  HttpClientPool({this.maxSize = 8});
  
  /// Acquire a client from the pool (or create one if needed)
  Future<http.Client> acquire() async {
    // Return available client if pool not at capacity
    if (_availableClients.isNotEmpty && _activeClients.length < maxSize) {
      final client = _availableClients.removeFirst();
      _activeClients.add(client);
      return client;
    }
    
    // Create new client if under max size
    if (_activeClients.length < maxSize) {
      final client = http.Client();
      _activeClients.add(client);
      return client;
    }
    
    // Wait for a client to become available
    // Simple implementation: wait a bit and retry
    await Future.delayed(Duration(milliseconds: 100));
    return acquire();
  }
  
  /// Release a client back to the pool
  void release(http.Client client) {
    if (_activeClients.contains(client)) {
      _activeClients.remove(client);
      // Reuse client if pool has capacity
      if (_availableClients.length < maxSize) {
        _availableClients.add(client);
      } else {
        // Close excess clients
        client.close();
      }
    }
  }
  
  /// Close all clients in the pool
  void closeAll() {
    for (final client in _availableClients) {
      client.close();
    }
    _availableClients.clear();
    
    for (final client in _activeClients) {
      client.close();
    }
    _activeClients.clear();
  }
  
  /// Get current pool statistics
  Map<String, int> getStats() {
    return {
      'available': _availableClients.length,
      'active': _activeClients.length,
      'total': _availableClients.length + _activeClients.length,
      'maxSize': maxSize,
    };
  }
  
  /// Adjust pool size based on desired concurrency
  void adjustPoolSize(int desiredConcurrency) {
    // If desired concurrency is less than maxSize, we can reduce pool
    // But we'll keep clients alive for reuse - just don't create more
    // The actual adjustment happens naturally through acquire/release
  }
}

