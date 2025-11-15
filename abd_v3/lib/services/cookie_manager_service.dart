import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CookieManagerService {
  static CookieManagerService? _instance;
  static CookieManagerService get instance {
    _instance ??= CookieManagerService._();
    return _instance!;
  }

  CookieManagerService._();

  HeadlessInAppWebView? _backgroundWebView;
  Timer? _refreshTimer;
  bool _isInitialized = false;
  Map<String, String> _cookies = {};
  
  static const String baseUrl = 'https://animepahe.si';
  static const Duration refreshInterval = Duration(minutes: 30);
  static const String cookieStorageKey = 'animepahe_cookies';

  // Initialize the background WebView and establish session
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kDebugMode) {
      print('CookieManager: Initializing background WebView session...');
    }

    // Load cached cookies first
    await _loadCachedCookies();

    // Start background WebView to maintain session
    await _startBackgroundSession();

    // Setup periodic refresh
    _startRefreshTimer();

    _isInitialized = true;
  }

  // Start background WebView session
  Future<void> _startBackgroundSession() async {
    try {
      final completer = Completer<void>();

      _backgroundWebView = HeadlessInAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          clearCache: false,
          cacheEnabled: true,
          incognito: false,
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ),
        initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
        onLoadStop: (controller, url) async {
          if (kDebugMode) {
            print('CookieManager: Page loaded, extracting cookies...');
          }

          // Wait a bit for cookies to be set
          await Future.delayed(const Duration(seconds: 2));

          // Extract cookies
          await _extractCookies();

          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onReceivedError: (controller, request, error) {
          if (kDebugMode) {
            print('CookieManager: Load error - ${error.description}');
          }
          if (!completer.isCompleted) {
            completer.completeError('Failed to load page');
          }
        },
      );

      await _backgroundWebView!.run();
      
      // Wait for initial load
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (kDebugMode) {
            print('CookieManager: Initial load timeout, using cached cookies');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('CookieManager: Error starting background session - $e');
      }
    }
  }

  // Extract cookies from WebView
  Future<void> _extractCookies() async {
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(baseUrl));

      _cookies.clear();
      for (final cookie in cookies) {
        _cookies[cookie.name] = cookie.value;
      }

      // Save to cache
      await _saveCookies();

      if (kDebugMode) {
        print('CookieManager: Extracted ${_cookies.length} cookies');
      }
    } catch (e) {
      if (kDebugMode) {
        print('CookieManager: Error extracting cookies - $e');
      }
    }
  }

  // Save cookies to SharedPreferences
  Future<void> _saveCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookiesJson = json.encode(_cookies);
      await prefs.setString(cookieStorageKey, cookiesJson);
      await prefs.setInt('${cookieStorageKey}_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) {
        print('CookieManager: Error saving cookies - $e');
      }
    }
  }

  // Load cached cookies from SharedPreferences
  Future<void> _loadCachedCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookiesJson = prefs.getString(cookieStorageKey);
      final timestamp = prefs.getInt('${cookieStorageKey}_timestamp');

      if (cookiesJson != null && timestamp != null) {
        // Check if cookies are less than 2 hours old
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age < const Duration(hours: 2).inMilliseconds) {
          _cookies = Map<String, String>.from(json.decode(cookiesJson));
          if (kDebugMode) {
            print('CookieManager: Loaded ${_cookies.length} cached cookies');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('CookieManager: Error loading cached cookies - $e');
      }
    }
  }

  // Start periodic refresh timer
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      refreshSession();
    });
  }

  // Refresh session by reloading page
  Future<void> refreshSession() async {
    if (!_isInitialized || _backgroundWebView == null) return;

    try {
      if (kDebugMode) {
        print('CookieManager: Refreshing session...');
      }

      // Reload the page to refresh cookies
      await _backgroundWebView!.webViewController?.reload();
      
      // Wait a bit and extract cookies again
      await Future.delayed(const Duration(seconds: 3));
      await _extractCookies();
    } catch (e) {
      if (kDebugMode) {
        print('CookieManager: Error refreshing session - $e');
      }
    }
  }

  // Get cookies as HTTP header string
  String getCookieHeader() {
    if (_cookies.isEmpty) {
      return '';
    }
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  // Get cookies as Map
  Map<String, String> getCookies() {
    return Map.from(_cookies);
  }

  // Get HTTP headers with cookies and browser simulation
  Map<String, String> getHeaders() {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate, br',
      'Referer': baseUrl,
      'Origin': baseUrl,
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
    };

    final cookieHeader = getCookieHeader();
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    return headers;
  }

  // Check if session is ready
  bool get isReady => _isInitialized && _cookies.isNotEmpty;

  // Wait until session is ready
  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 20)}) async {
    final startTime = DateTime.now();
    while (!isReady) {
      if (DateTime.now().difference(startTime) > timeout) {
        throw Exception('Session initialization timeout');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // Dispose resources
  Future<void> dispose() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    if (_backgroundWebView != null) {
      await _backgroundWebView!.dispose();
      _backgroundWebView = null;
    }

    _isInitialized = false;
    if (kDebugMode) {
      print('CookieManager: Disposed');
    }
  }

  // Pause session (to save memory when app is in background)
  Future<void> pause() async {
    _refreshTimer?.cancel();
    if (_backgroundWebView != null) {
      await _backgroundWebView!.dispose();
      _backgroundWebView = null;
    }
    if (kDebugMode) {
      print('CookieManager: Paused (memory saved)');
    }
  }

  // Resume session
  Future<void> resume() async {
    if (_isInitialized) {
      await _startBackgroundSession();
      _startRefreshTimer();
      if (kDebugMode) {
        print('CookieManager: Resumed');
      }
    }
  }
}

