import 'dart:async';
import 'dart:io';

/// Error types for classification
enum ErrorType {
  retryableNetwork,    // Timeouts, connection failures
  retryableServer,     // 5xx errors, rate limits
  nonRetryableClient,  // 4xx errors (except 408, 429)
  nonRetryableAuth,    // 401, 403
  permanent,           // 404, etc.
}

/// Retry configuration based on error type
class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;
  final bool shouldRetry;
  
  RetryConfig({
    required this.maxRetries,
    required this.baseDelay,
    required this.shouldRetry,
  });
  
  static RetryConfig noRetry() => RetryConfig(
    maxRetries: 0,
    baseDelay: Duration.zero,
    shouldRetry: false,
  );
}

/// Classifies errors and provides appropriate retry strategies
class ErrorClassifier {
  /// Classify an error and determine retry strategy
  static ErrorType classifyError(dynamic error, int? statusCode) {
    // Network-level errors (timeouts, connection issues)
    if (error is TimeoutException) {
      return ErrorType.retryableNetwork;
    }
    if (error is SocketException) {
      return ErrorType.retryableNetwork;
    }
    if (error is HttpException) {
      // Some HTTP exceptions are network-related
      return ErrorType.retryableNetwork;
    }
    
    // HTTP status code-based classification
    if (statusCode != null) {
      // Retryable HTTP errors
      if (statusCode == 408 || statusCode == 429) {
        return ErrorType.retryableNetwork;
      }
      
      // Server errors (5xx) - retryable
      if (statusCode >= 500 && statusCode < 600) {
        return ErrorType.retryableServer;
      }
      
      // Authentication errors (4xx) - non-retryable
      if (statusCode == 401 || statusCode == 403) {
        return ErrorType.nonRetryableAuth;
      }
      
      // Client errors (4xx) - mostly non-retryable
      if (statusCode >= 400 && statusCode < 500) {
        return ErrorType.nonRetryableClient;
      }
      
      // Success codes (2xx) - shouldn't be an error, but treat as permanent
      if (statusCode >= 200 && statusCode < 300) {
        return ErrorType.permanent;
      }
    }
    
    // Default: treat as permanent error
    return ErrorType.permanent;
  }
  
  /// Get retry configuration for an error type
  static RetryConfig getRetryConfig(ErrorType errorType) {
    switch (errorType) {
      case ErrorType.retryableNetwork:
        return RetryConfig(
          maxRetries: 5,
          baseDelay: Duration(seconds: 1),
          shouldRetry: true,
        );
      case ErrorType.retryableServer:
        return RetryConfig(
          maxRetries: 3,
          baseDelay: Duration(seconds: 2),
          shouldRetry: true,
        );
      case ErrorType.nonRetryableClient:
      case ErrorType.nonRetryableAuth:
      case ErrorType.permanent:
        return RetryConfig.noRetry();
    }
  }
  
  /// Classify error and get retry config in one call
  static RetryConfig classifyAndGetConfig(dynamic error, int? statusCode) {
    final errorType = classifyError(error, statusCode);
    return getRetryConfig(errorType);
  }
  
  /// Check if error should be retried
  static bool shouldRetry(dynamic error, int? statusCode) {
    final config = classifyAndGetConfig(error, statusCode);
    return config.shouldRetry;
  }
}

