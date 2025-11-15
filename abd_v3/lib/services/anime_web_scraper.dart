import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../models/quality_option_model.dart';
import 'cookie_manager_service.dart';

class AnimeWebScraper {
  static const String baseOrigin = "https://animepahe.si";
  static const Duration timeout = Duration(seconds: 120);

  HeadlessInAppWebView? _currentWebView;
  bool _isProcessing = false;
  bool _isDisposed = false;
  final Set<Completer<void>> _pendingOperations = {};

  // Lock to ensure only 1 concurrent WebView operation
  Future<T> _withLock<T>(Future<T> Function() operation) async {
    while (_isProcessing) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _isProcessing = true;
    try {
      return await operation();
    } finally {
      _isProcessing = false;
    }
  }

  // Check if WebView controller is still valid
  bool _isControllerValid(InAppWebViewController controller) {
    return !_isDisposed && _currentWebView != null;
  }

  // Get available qualities for an episode
  Future<List<QualityOption>> getQualities(
    String animeSession,
    String episodeSession,
  ) async {
    return await _withLock(() => _getQualitiesInternal(animeSession, episodeSession));
  }

  Future<List<QualityOption>> _getQualitiesInternal(
    String animeSession,
    String episodeSession,
  ) async {
    final completer = Completer<List<QualityOption>>();
    final playUrl = '$baseOrigin/play/$animeSession/$episodeSession';
    bool mainPageLoaded = false;

    // Ensure we have an authenticated session
    final cookieManager = CookieManagerService.instance;

    // Try to initialize if not ready (handles case where main.dart init failed)
    if (!cookieManager.isReady) {
      if (kDebugMode) {
        print('WebScraper: CookieManager not ready, attempting to initialize...');
      }
      try {
        await cookieManager.initialize();
      } catch (e) {
        if (kDebugMode) {
          print('WebScraper: CookieManager initialization failed: $e');
        }
        // Continue anyway - some sites work without cookies
      }
    }

    // Wait for session readiness with a shorter timeout
    try {
      await cookieManager.waitUntilReady(timeout: const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) {
        print('WebScraper: CookieManager waitUntilReady failed: $e');
      }
      // Continue anyway - we'll try without full session
    }

    try {
      if (kDebugMode) {
        print('WebScraper: Creating HeadlessInAppWebView for URL: $playUrl');
      }

      _currentWebView = HeadlessInAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useOnLoadResource: false,
          useShouldOverrideUrlLoading: false,
          useShouldInterceptRequest: false, // Not needed for quality extraction
          clearCache: false,
          cacheEnabled: true,
          incognito: false, // Allow cookies to persist
          userAgent:
              'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          // Additional settings to help with loading
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          disableDefaultErrorPage: false,
          supportMultipleWindows: false,
          allowContentAccess: true,
          databaseEnabled: true,
          domStorageEnabled: true,
          geolocationEnabled: false,
          mediaPlaybackRequiresUserGesture: false,
          safeBrowsingEnabled: false,
        ),
        initialUrlRequest: URLRequest(
          url: WebUri(playUrl),
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Cache-Control': 'max-age=0',
          },
        ), // Load play page directly with browser-like headers
        onLoadStop: (controller, url) async {
          try {
            final currentUrl = url.toString();

            if (currentUrl.contains('/play/')) {
              // Play page loaded, extract qualities
              mainPageLoaded = true;
              if (kDebugMode) {
                print('WebScraper: Play page loaded directly, extracting qualities...');
                print('WebScraper: Current URL: $currentUrl');
              }

              // Check if we're on DDoS protection page or got redirected
              final ddosCheck = await controller.evaluateJavascript(source: '''
              (function() {
                const title = document.title || '';
                const bodyText = document.body ? document.body.innerText : '';
                return title.toLowerCase().includes('ddos') ||
                       title.toLowerCase().includes('checking') ||
                       bodyText.includes('Checking your browser') ||
                       bodyText.includes('DDoS-Guard');
              })();
              ''');

              if (ddosCheck == true) {
                if (kDebugMode) {
                  print('WebScraper: On DDoS protection page, waiting and retrying...');
                }
                // Wait for DDoS protection to pass
                await Future.delayed(const Duration(seconds: 15));
                // Retry loading the page
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(playUrl)));
                return;
              }

              // Check if we got redirected to the main page (blocked)
              if (currentUrl == baseOrigin || currentUrl == '$baseOrigin/' || !currentUrl.contains('/play/')) {
                if (kDebugMode) {
                  print('WebScraper: Got redirected to main page, request was blocked. Retrying...');
                }
                await Future.delayed(const Duration(seconds: 3));
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(playUrl)));
                return;
              }

              // Wait for dynamic content to load and initialize
              if (kDebugMode) {
                print('WebScraper: Waiting 3 seconds for dynamic content to load...');
              }
              await Future.delayed(const Duration(seconds: 3));

              // Extract quality options - AnimePahe dropdown buttons are already visible
              if (kDebugMode) {
                print('WebScraper: Starting JavaScript quality extraction...');
              }

              dynamic result;
              try {
                result = await controller.evaluateJavascript(source: '''
(function() {
  try {
    console.log('Starting comprehensive quality extraction for AnimePahe...');

    const allQualities = [];

    // Method 1: Look for dropdown options (most common)
    console.log('Method 1: Looking for dropdown/select options...');
    const selectElements = document.querySelectorAll('select');
    for (const select of selectElements) {
      if (select.offsetWidth > 0 && select.offsetHeight > 0) {
        const options = Array.from(select.options);
        console.log('Found select with', options.length, 'options');

        for (const option of options) {
          const text = option.textContent.trim();
          if (/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i.test(text)) {
            const resolution = text.match(/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i)?.[1] || '';
            const parts = text.split('·').map(s => s.trim());
            const fansub = parts.length > 1 ? parts[0] : '';

            allQualities.push({
              src: '',
              fansub: fansub,
              resolution: resolution,
              audio: '',
              label: text
            });
          }
        }
      }
    }

    // Method 2: Look for AnimePahe dropdown menu buttons (most reliable)
    console.log('Method 2: Looking for AnimePahe dropdown menu buttons...');

    // First, try to expand the dropdown if it's collapsed
    const dropdownToggle = document.getElementById('fansubMenu');
    if (dropdownToggle) {
      console.log('Found dropdown toggle, clicking to expand...');
      try {
        dropdownToggle.click();
      } catch (e) {
        console.log('Error clicking dropdown toggle:', e);
      }
    }

    const dropdownMenu = document.getElementById('resolutionMenu');
    let dropdownButtons = [];

    if (dropdownMenu) {
      console.log('Found resolutionMenu dropdown');
      // Get all dropdown items, even if not visible (remove visibility filter)
      dropdownButtons = Array.from(dropdownMenu.querySelectorAll('button.dropdown-item, button[data-src]'));
      console.log('Found dropdown buttons (including hidden):', dropdownButtons.length);

      // Log details about each button
      dropdownButtons.forEach(function(btn, i) {
        const text = btn.textContent.trim();
        const visible = btn.offsetWidth > 0 && btn.offsetHeight > 0;
        const dataSrc = btn.getAttribute('data-src');
        console.log('Button ' + (i + 1) + ': "' + text + '" - Visible: ' + visible + ' - Has data-src: ' + !!dataSrc);
      });

      // Filter to only visible buttons (but log all first)
      dropdownButtons = dropdownButtons.filter(btn => btn.offsetWidth > 0 && btn.offsetHeight > 0);
      console.log('Found visible dropdown buttons:', dropdownButtons.length);
    }

    // If dropdown not found or no visible buttons, fall back to general search
    if (dropdownButtons.length === 0) {
      console.log('Dropdown not found or no visible buttons, falling back to general button search...');
      const allDropdownItems = Array.from(document.querySelectorAll('button.dropdown-item, button[data-src]'));
      console.log('All dropdown items on page:', allDropdownItems.length);

      dropdownButtons = allDropdownItems.filter(btn => {
        const text = btn.textContent || '';
        const hasDataSrc = btn.getAttribute('data-src');
        const hasResolution = /\\b(240p|360p|480p|720p|1080p|2160p)\\b/i.test(text);
        return (hasDataSrc || hasResolution) && btn.offsetWidth > 0 && btn.offsetHeight > 0;
      });
      console.log('Found fallback buttons with data-src or resolution:', dropdownButtons.length);
    }

    console.log('Total quality buttons found:', dropdownButtons.length);

    for (const btn of dropdownButtons) {
      const text = btn.textContent.trim();
      const resolution = btn.getAttribute('data-resolution') || text.match(/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i)?.[1] || '';
      const fansub = btn.getAttribute('data-fansub') || '';
      const audio = btn.getAttribute('data-audio') || '';
      const streamingUrl = btn.getAttribute('data-src') || '';

      console.log('Quality button:', text, 'Resolution:', resolution, 'Fansub:', fansub, 'URL:', streamingUrl ? 'FOUND' : 'MISSING');

      allQualities.push({
        src: streamingUrl,
        fansub: fansub,
        resolution: resolution,
        audio: audio,
        label: text
      });
    }

    // Method 2.5: If no dropdown buttons found, try general button search (legacy)
    if (dropdownButtons.length === 0) {
      console.log('Method 2.5: Legacy button search...');
      const legacyButtons = Array.from(document.querySelectorAll('button')).filter(btn => {
        const text = btn.textContent || '';
        return /\\b(240p|360p|480p|720p|1080p|2160p)\\b/i.test(text) && btn.offsetWidth > 0 && btn.offsetHeight > 0;
      });

      console.log('Found legacy buttons:', legacyButtons.length);

      for (const btn of legacyButtons) {
        const text = btn.textContent.trim();
        const resolution = text.match(/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i)?.[1] || '';
        const parts = text.split('·').map(s => s.trim());
        const fansub = parts.length > 1 ? parts[0] : '';
        const streamingUrl = btn.getAttribute('data-src') || '';

        console.log('Legacy button:', text, 'Streaming URL found:', streamingUrl ? 'YES' : 'NO');

        allQualities.push({
          src: streamingUrl,
          fansub: fansub,
          resolution: resolution,
          audio: '',
          label: text
        });
      }
    }

    // Method 3: Look for list items or divs that might contain qualities
    console.log('Method 3: Looking for list items and divs...');
    const listElements = Array.from(document.querySelectorAll('li, div, span, a')).filter(el => {
      const text = el.textContent || '';
      return /\\b(240p|360p|480p|720p|1080p|2160p)\\b/i.test(text) &&
             el.offsetWidth > 0 &&
             el.offsetHeight > 0 &&
             (el.onclick || el.getAttribute('data-value') || el.closest('select'));
    });

    console.log('Found list elements:', listElements.length);

    for (const el of listElements) {
      const text = el.textContent.trim();
      const resolution = text.match(/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i)?.[1] || '';
      const parts = text.split('·').map(s => s.trim());
      const fansub = parts.length > 1 ? parts[0] : '';

      // Avoid duplicates
      const isDuplicate = allQualities.some(q => q.label === text);
      if (!isDuplicate) {
        allQualities.push({
          src: '',
          fansub: fansub,
          resolution: resolution,
          audio: '',
          label: text
        });
      }
    }

    // Method 4: Look for any element with quality-related classes or data attributes
    console.log('Method 4: Looking for elements with quality-related attributes...');
    const qualityRelated = Array.from(document.querySelectorAll('[class*="quality"], [class*="resolution"], [data-quality], [data-resolution]')).filter(el => {
      const text = el.textContent || '';
      return text.length > 0 && el.offsetWidth > 0 && el.offsetHeight > 0;
    });

    console.log('Found quality-related elements:', qualityRelated.length);

    for (const el of qualityRelated) {
      const text = el.textContent.trim();
      if (/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i.test(text)) {
        const resolution = text.match(/\\b(240p|360p|480p|720p|1080p|2160p)\\b/i)?.[1] || '';
        const parts = text.split('·').map(s => s.trim());
        const fansub = parts.length > 1 ? parts[0] : '';

        // Avoid duplicates
        const isDuplicate = allQualities.some(q => q.label === text);
        if (!isDuplicate) {
          allQualities.push({
            src: '',
            fansub: fansub,
            resolution: resolution,
            audio: '',
            label: text
          });
        }
      }
    }

    // Remove duplicates based on label
    const uniqueQualities = allQualities.filter((quality, index, self) =>
      index === self.findIndex(q => q.label === quality.label)
    );

    // Sort by resolution (highest first)
    const resolutionOrder = { '2160p': 6, '1080p': 5, '720p': 4, '480p': 3, '360p': 2, '240p': 1 };
    uniqueQualities.sort((a, b) => {
      const aOrder = resolutionOrder[a.resolution] || 0;
      const bOrder = resolutionOrder[b.resolution] || 0;
      return bOrder - aOrder;
    });

    console.log('Final extracted quality items:', uniqueQualities.length, 'unique qualities');
    uniqueQualities.forEach(function(q, i) { console.log((i + 1) + '. ' + q.label + ' (' + q.resolution + ')'); });

    return uniqueQualities;

  } catch (e) {
    console.error('Error extracting qualities:', e);
    return [];
  }
})();
''');
              } catch (jsError) {
                if (kDebugMode) {
                  print('WebScraper: JavaScript evaluation failed: $jsError');
                }
                if (!completer.isCompleted) {
                  completer.completeError('JavaScript evaluation failed: $jsError');
                }
                return;
              }

              if (kDebugMode) {
                print('WebScraper: JavaScript execution completed');
                print('WebScraper: JavaScript returned ${result?.toString().length ?? 0} characters');
                print('WebScraper: Result type: ${result.runtimeType}');
                if (result == null) {
                  print('WebScraper: Result is NULL!');
                } else if (result is List) {
                  print('WebScraper: Result is list with ${result.length} items');
                  if (result.isNotEmpty) {
                    print('WebScraper: First item: ${result[0]}');
                    print('WebScraper: All items:');
                    for (final item in result) {
                      print('  - $item');
                    }
                  } else {
                    print('WebScraper: Result list is EMPTY!');
                  }
                } else {
                  print('WebScraper: Result is not a list: $result');
                }
              }

              if (result != null && result is List && !completer.isCompleted) {
                final qualities = <QualityOption>[];
                for (final item in result) {
                  if (item is Map) {
                    try {
                      final quality = QualityOption.fromJson(
                        Map<String, dynamic>.from(item),
                      );
                      // Resolution should already be set in JavaScript extraction
                      // Only add if it has meaningful data
                      if (quality.resolution.isNotEmpty || quality.label.isNotEmpty) {
                        qualities.add(quality);
                      }
                    } catch (e) {
                      if (kDebugMode) {
                        print('Error parsing quality option: $e for item: $item');
                      }
                    }
                  } else {
                    if (kDebugMode) {
                      print('WebScraper: Skipping non-Map item: $item (type: ${item.runtimeType})');
                    }
                  }
                }

                if (kDebugMode) {
                  print('WebScraper: Successfully parsed ${qualities.length} quality options');
                  for (final q in qualities) {
                    debugPrint('  - Label: "${q.label}", Resolution: "${q.resolution}", Src: "${q.src}"');
                  }
                }

                if (qualities.isNotEmpty) {
                  completer.complete(qualities);
                } else if (!completer.isCompleted) {
                  completer.completeError('No quality options found');
                }
              } else if (!completer.isCompleted) {
                if (result == null) {
                  completer.completeError('JavaScript returned null');
                } else if (result is! List) {
                  completer.completeError('JavaScript returned ${result.runtimeType} instead of List');
                } else {
                  completer.completeError('Failed to extract quality options - completer already completed');
                }
              }
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError('Error extracting qualities: $e');
            }
          }
        },
        onReceivedError: (controller, request, error) {
          // Only fail on errors for the main page URL, not for secondary resources
          final requestUrl = request.url.toString();

          // More specific check for main page URL
          final isMainPageUrl = requestUrl == playUrl ||
                               (requestUrl.contains('/play/') && requestUrl.contains(animeSession) && requestUrl.contains(episodeSession));

          if (kDebugMode) {
            print('WebScraper: Network error - URL: $requestUrl, Error: ${error.description}, Is main page: $isMainPageUrl');
            print('WebScraper: Expected playUrl: $playUrl');
          }

          // Only fail if it's an error loading the main page AND the page hasn't loaded successfully yet
          if (isMainPageUrl && !mainPageLoaded && !completer.isCompleted) {
            completer.completeError('Failed to load page: ${error.description}');
          }
          // Ignore errors for secondary resources (images, scripts, etc.)
        },
      );

      if (kDebugMode) {
        print('WebScraper: HeadlessInAppWebView created successfully');
      }

      await _currentWebView!.run();

      // Timeout handling
      if (kDebugMode) {
        print('WebScraper: Waiting for quality extraction to complete...');
      }
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          if (kDebugMode) {
            print('WebScraper: Quality extraction timed out after ${timeout.inSeconds} seconds');
          }
          throw Exception('Quality extraction timed out');
        },
      );

      return result;
    } finally {
      await _disposeWebView();
    }
  }

  // Extract m3u8 link for a specific quality
  Future<String> extractM3U8(
    String animeSession,
    String episodeSession,
    QualityOption quality,
  ) async {
    return await _withLock(() => _extractM3U8Internal(
          animeSession,
          episodeSession,
          quality,
        ));
  }

  Future<String> _extractM3U8Internal(
    String animeSession,
    String episodeSession,
    QualityOption quality,
  ) async {
    final completer = Completer<String>();
    final playUrl = '$baseOrigin/play/$animeSession/$episodeSession';
    String? foundM3U8;
    String? m3u8Content; // Store m3u8 content when intercepted

    // Ensure we have an authenticated session
    final cookieManager = CookieManagerService.instance;

    // Try to initialize if not ready (handles case where main.dart init failed)
    if (!cookieManager.isReady) {
      if (kDebugMode) {
        print('WebScraper: CookieManager not ready, attempting to initialize...');
      }
      try {
        await cookieManager.initialize();
      } catch (e) {
        if (kDebugMode) {
          print('WebScraper: CookieManager initialization failed: $e');
        }
        // Continue anyway - some sites work without cookies
      }
    }

    // Wait for session readiness with a shorter timeout
    try {
      await cookieManager.waitUntilReady(timeout: const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) {
        print('WebScraper: CookieManager waitUntilReady failed: $e');
      }
      // Continue anyway - we'll try without full session
    }

    try {
      _currentWebView = HeadlessInAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useOnLoadResource: true,
          useShouldOverrideUrlLoading: false,
          useShouldInterceptRequest: true, // Enable network request interception
          clearCache: false,
          cacheEnabled: true,
          incognito: false, // Allow cookies to persist
          userAgent:
              'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          // Additional settings to help with loading
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          disableDefaultErrorPage: false,
          supportMultipleWindows: false,
          allowContentAccess: true,
          databaseEnabled: true,
          domStorageEnabled: true,
          geolocationEnabled: false,
          mediaPlaybackRequiresUserGesture: false,
          safeBrowsingEnabled: false,
        ),
        initialUrlRequest: URLRequest(
          url: WebUri(playUrl),
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Cache-Control': 'max-age=0',
          },
        ), // Load play page directly with browser-like headers
        onLoadStop: (controller, url) async {
          try {
            final currentUrl = url.toString();

            if (currentUrl.contains('/play/')) {
              // Play page loaded directly, now click quality button
              if (kDebugMode) {
                print('WebScraper: Play page loaded directly for m3u8, clicking quality button...');
              }

              // Check if we're on DDoS protection page or got redirected
              final ddosCheck = await controller.evaluateJavascript(source: '''
              (function() {
                const title = document.title || '';
                const bodyText = document.body ? document.body.innerText : '';
                return title.toLowerCase().includes('ddos') ||
                       title.toLowerCase().includes('checking') ||
                       bodyText.includes('Checking your browser') ||
                       bodyText.includes('DDoS-Guard');
              })();
              ''');

              if (ddosCheck == true) {
                if (kDebugMode) {
                  print('WebScraper: On DDoS protection page during m3u8 extraction, waiting...');
                }
                // Wait for DDoS protection to pass
                await Future.delayed(const Duration(seconds: 15));
                // Reload the page to try again
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(playUrl)));
                return;
              }

              // Check if we got redirected to the main page (blocked)
              if (currentUrl == baseOrigin || currentUrl == '$baseOrigin/' || !currentUrl.contains('/play/')) {
                if (kDebugMode) {
                  print('WebScraper: Got redirected during m3u8 extraction, request was blocked. Retrying...');
                }
                await Future.delayed(const Duration(seconds: 3));
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(playUrl)));
                return;
              }

              // Wait a bit for dynamic content to load
              await Future.delayed(const Duration(seconds: 3));

              // Click the quality option - Updated for AnimePahe dropdown structure
              final clickScript = '''
(function() {
  try {
    console.log('Looking for quality button:', '${quality.label}');

    // First, try to find the button in the resolutionMenu dropdown (most reliable)
    const dropdownMenu = document.getElementById('resolutionMenu');
    let targetButton = null;

    if (dropdownMenu) {
      const dropdownButtons = Array.from(dropdownMenu.querySelectorAll('button.dropdown-item'));
      targetButton = dropdownButtons.find(btn => {
        const text = btn.textContent.trim();
        return text === '${quality.label}';
      });

      if (targetButton) {
        console.log('Found button in resolutionMenu dropdown');
      }
    }

    // If not found in dropdown, try general search
    if (!targetButton) {
      console.log('Button not found in dropdown, trying general search...');
      const allButtons = Array.from(document.querySelectorAll('button.dropdown-item'));
      targetButton = allButtons.find(btn => {
        const text = btn.textContent.trim();
        return text === '${quality.label}';
      });
    }

    // Final fallback to any button with matching text
    if (!targetButton) {
      console.log('Button not found in dropdown-item, trying any button...');
      const anyButtons = Array.from(document.querySelectorAll('button'));
      targetButton = anyButtons.find(btn => {
        const text = btn.textContent.trim();
        return text === '${quality.label}' && btn.offsetWidth > 0 && btn.offsetHeight > 0;
      });
    }

    if (targetButton) {
      console.log('Clicking quality button:', targetButton.textContent);
      console.log('Button data-src:', targetButton.getAttribute('data-src'));

      // Click the button
      if (targetButton.click) {
        targetButton.click();
      } else {
        targetButton.dispatchEvent(new Event('click', { bubbles: true }));
      }

      console.log('Successfully clicked quality button');
      return true;
    }

    console.log('No suitable quality button found with label:', '${quality.label}');
    console.log('Available dropdown buttons:', Array.from(document.querySelectorAll('button.dropdown-item')).map(btn => btn.textContent.trim()));

    return false;
  } catch (e) {
    console.error('Error clicking quality button:', e);
    return false;
  }
})();
''';

              final clicked = await controller.evaluateJavascript(source: clickScript);

              if (kDebugMode) {
                print('WebScraper: Click result: $clicked');
              }

              if (clicked != true) {
                if (!completer.isCompleted) {
                  completer.completeError('Failed to click quality button');
                }
                return;
              }

              if (kDebugMode) {
                print('WebScraper: Quality button clicked successfully, waiting for m3u8...');
              }

              // Wait for the m3u8 link to be captured
              await Future.delayed(const Duration(seconds: 3));

              // If m3u8 was found, try to capture it
              if (foundM3U8 != null) {
                if (kDebugMode) {
                  print('WebScraper: M3U8 URL found, attempting capture...');
                }
                await _captureM3u8ContentFromWebView(controller, foundM3U8!);
              }

              // If no m3u8 found via onLoadResource, try to extract it from the page directly
              if (foundM3U8 == null) {
                if (kDebugMode) {
                  print('WebScraper: No m3u8 found via resource loading, trying direct extraction...');
                }

                try {
                  final directM3U8 = await controller.evaluateJavascript(source: '''
(function() {
  try {
    console.log('Attempting direct m3u8 extraction after quality selection...');

    // Look for video elements and their sources
    const videoElements = document.querySelectorAll('video');
    for (const video of videoElements) {
      if (video.src && video.src.includes('.m3u8')) {
        console.log('Found m3u8 in video src:', video.src);
        return video.src;
      }
    }

    // Look for source elements within video tags
    const sourceElements = document.querySelectorAll('video source');
    for (const source of sourceElements) {
      const src = source.src || source.getAttribute('src');
      if (src && src.includes('.m3u8')) {
        console.log('Found m3u8 in video source:', src);
        return src;
      }
    }

    // Look for any elements with data-src or similar attributes containing m3u8
    const allElements = document.querySelectorAll('*');
    for (const el of allElements) {
      const src = el.src || el.getAttribute('data-src') || el.getAttribute('data-url') || el.getAttribute('data-link');
      if (src && src.includes('.m3u8')) {
        console.log('Found m3u8 in element attribute:', src);
        return src;
      }
    }

    // Only look for .m3u8 files in links
    const links = document.querySelectorAll('a[href]');
    for (const link of links) {
      const href = link.href;
      if (href && href.includes('.m3u8')) {
        console.log('Found m3u8 in link:', href);
        return href;
      }
    }

    console.log('No m3u8 found via direct extraction');
    return null;
  } catch (e) {
    console.error('Error in direct m3u8 extraction:', e);
    return null;
  }
})();
''');

                  if (directM3U8 != null && directM3U8 is String && directM3U8.isNotEmpty) {
                    if (kDebugMode) {
                      print('WebScraper: Direct extraction found m3u8: $directM3U8');
                    }
                    foundM3U8 = directM3U8;
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('WebScraper: Direct extraction failed: $e');
                  }
                }
              }

              if (foundM3U8 != null && !completer.isCompleted) {
                // Validate that we only return .m3u8 URLs
                if (foundM3U8!.contains('.m3u8')) {
                  // Final attempt to capture content
                  if (kDebugMode) {
                    print('WebScraper: Final attempt to capture m3u8 content before completing...');
                  }
                  // Wait a bit more for resource to fully load
                  await Future.delayed(const Duration(milliseconds: 1500));
                  
                  // Try multiple times if controller is still valid
                  if (_isControllerValid(controller)) {
                    await _captureM3u8ContentFromWebView(controller, foundM3U8!);
                    
                    // Try one more time with longer delay
                    if (kDebugMode) {
                      print('WebScraper: Retrying capture with longer delay...');
                    }
                    await Future.delayed(const Duration(milliseconds: 2000));
                    if (_isControllerValid(controller)) {
                      await _captureM3u8ContentFromWebView(controller, foundM3U8!);
                    }
                  }
                  
                  completer.complete(foundM3U8!);
                } else {
                  completer.completeError('Invalid URL captured (not .m3u8): $foundM3U8');
                }
              } else if (!completer.isCompleted) {
                completer.completeError('M3U8 link not found');
              }
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError('Error extracting m3u8: $e');
            }
          }
        },
        shouldInterceptRequest: (controller, request) async {
          // Monitor network requests for .m3u8 files only
          final requestUrl = request.url.toString();

          if (foundM3U8 == null && requestUrl.contains('.m3u8')) {
            if (kDebugMode) {
              print('WebScraper: Found m3u8 file: $requestUrl');
            }

            foundM3U8 = requestUrl;
            
            // Strategy 1: Try to intercept and fetch m3u8 content ourselves with proper headers
            try {
              final cookieManager = CookieManagerService.instance;
              final headers = _getHttpHeadersForM3u8(requestUrl, cookieManager);
              
              final response = await http.get(Uri.parse(requestUrl), headers: headers).timeout(
                const Duration(seconds: 15),
              );
              
              if (response.statusCode == 200 && response.body.isNotEmpty) {
                m3u8Content = response.body;
                if (kDebugMode) {
                  print('WebScraper: ✅ Captured m3u8 via direct HTTP (${m3u8Content!.length} bytes)');
                }
                await _analyzeM3U8ContentFromString(m3u8Content!);
                
                return WebResourceResponse(
                  data: Uint8List.fromList(response.bodyBytes),
                  contentType: 'application/vnd.apple.mpegurl',
                  statusCode: 200,
                  reasonPhrase: 'OK',
                  headers: response.headers,
                );
              }
            } catch (e) {
              if (kDebugMode) {
                print('WebScraper: ⚠️ Direct HTTP failed, will try WebView-based methods: $e');
              }
            }

            // Strategy 2: Let WebView load it, then capture via JavaScript
            // Try to capture immediately, and wait for it before completing
            // Track this operation to prevent disposal race condition
            final captureCompleter = Completer<void>();
            _pendingOperations.add(captureCompleter);
            
            // Wait a bit for the resource to load, then capture
            Future.delayed(const Duration(milliseconds: 1500), () async {
              try {
                if (_isControllerValid(controller)) {
                  await _captureM3u8ContentFromWebView(controller, requestUrl);
                } else if (kDebugMode) {
                  print('WebScraper: Skipping capture, controller disposed');
                }
              } catch (e) {
                if (kDebugMode) {
                  print('WebScraper: Error in async capture: $e');
                }
              } finally {
                _pendingOperations.remove(captureCompleter);
                if (!captureCompleter.isCompleted) {
                  captureCompleter.complete();
                }
              }
            });

            // Wait for capture to complete (or timeout) before completing the completer
            // This ensures content is cached before extraction completes
            try {
              await captureCompleter.future.timeout(
                const Duration(seconds: 3),
                onTimeout: () {
                  if (kDebugMode) {
                    print('WebScraper: Capture timeout, proceeding anyway');
                  }
                },
              );
            } catch (e) {
              if (kDebugMode) {
                print('WebScraper: Error waiting for capture: $e');
              }
            }

            if (!completer.isCompleted) {
              completer.complete(requestUrl);
            }
          }

          // Return null to allow the request to proceed normally
          return null;
        },
        onLoadResource: (controller, resource) async {
          // Backup: also monitor via onLoadResource for .m3u8 files only
          final resourceUrl = resource.url.toString();

            if (foundM3U8 == null && resourceUrl.contains('.m3u8')) {
            if (kDebugMode) {
              print('WebScraper: Found m3u8 via resource loading: $resourceUrl');
            }

            foundM3U8 = resourceUrl;
            
            // Try to fetch m3u8 content using JavaScript after WebView has loaded it
            // This works because the WebView has the proper network context
            // Track this operation to ensure we wait before completing
            final resourceCaptureCompleter = Completer<void>();
            _pendingOperations.add(resourceCaptureCompleter);
            
            try {
              // Wait a bit for the resource to fully load
              await Future.delayed(const Duration(milliseconds: 1000));
              
              if (!_isControllerValid(controller)) {
                if (kDebugMode) {
                  print('WebScraper: Controller disposed during onLoadResource capture');
                }
              } else {
                // Escape the URL for JavaScript
                final escapedUrl = resourceUrl.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
                
                // Use JavaScript fetch() within WebView context to get the content
                try {
                  final contentResult = await controller.evaluateJavascript(source: '''
                    (async function() {
                      try {
                        const response = await fetch('$escapedUrl', {
                          method: 'GET',
                          credentials: 'include',
                          cache: 'default'
                        });
                        if (!response.ok) {
                          return null;
                        }
                        const text = await response.text();
                        return text;
                      } catch (e) {
                        console.error('Failed to fetch m3u8 via JS:', e);
                        return null;
                      }
                    })();
                  ''').timeout(
                    const Duration(seconds: 10),
                    onTimeout: () {
                      if (kDebugMode) {
                        print('WebScraper: onLoadResource JS fetch timeout');
                      }
                      return null;
                    },
                  );
                  
                  if (contentResult != null && contentResult is String && contentResult.isNotEmpty) {
                    m3u8Content = contentResult;
                    if (kDebugMode) {
                      print('WebScraper: ✅ Captured m3u8 content via onLoadResource JS fetch (${m3u8Content!.length} bytes)');
                    }
                    // Analyze the content
                    await _analyzeM3U8ContentFromString(m3u8Content!);
                  } else {
                    // Fallback: try via _captureM3u8ContentFromWebView which has multiple methods
                    if (kDebugMode) {
                      print('WebScraper: JavaScript fetch returned null, trying _captureM3u8ContentFromWebView...');
                    }
                    if (_isControllerValid(controller)) {
                      await _captureM3u8ContentFromWebView(controller, resourceUrl);
                    }
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('WebScraper: Error in onLoadResource JS fetch: $e');
                  }
                  // Try capture method as fallback
                  if (_isControllerValid(controller)) {
                    await _captureM3u8ContentFromWebView(controller, resourceUrl);
                  }
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('WebScraper: Failed to fetch m3u8 content via onLoadResource: $e');
              }
              // Last resort: try capture method
              if (_isControllerValid(controller)) {
                await _captureM3u8ContentFromWebView(controller, resourceUrl);
              }
            } finally {
              _pendingOperations.remove(resourceCaptureCompleter);
              if (!resourceCaptureCompleter.isCompleted) {
                resourceCaptureCompleter.complete();
              }
            }

            // Wait a bit for capture to complete before completing the main completer
            try {
              await resourceCaptureCompleter.future.timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  if (kDebugMode) {
                    print('WebScraper: onLoadResource capture timeout, proceeding anyway');
                  }
                },
              );
            } catch (e) {
              if (kDebugMode) {
                print('WebScraper: Error waiting for onLoadResource capture: $e');
              }
            }

            if (!completer.isCompleted) {
              completer.complete(resourceUrl);
            }
          }
        },
        onReceivedError: (controller, request, error) {
          // Only fail if the main page request fails, not resource requests
          final url = request.url.toString();
          if (kDebugMode) {
            print('WebScraper: Resource failed to load: $url - ${error.description}');
          }

          // Don't fail the entire operation for resource loading errors
          // Only fail if it's the main page that failed to load
          if (url.contains('/play/') && !completer.isCompleted) {
            completer.completeError('Failed to load main page: ${error.description}');
          }
        },
      );

      await _currentWebView!.run();

      // Timeout handling
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          throw Exception('Connection is bad');
        },
      );

      return result;
    } finally {
      await _disposeWebView();
    }
  }

  // Extract m3u8 directly (alternative method)
  Future<String> extractM3U8Direct(
    String animeSession,
    String episodeSession,
    QualityOption quality,
  ) async {
    return await _withLock(() => _extractM3U8DirectInternal(
          animeSession,
          episodeSession,
          quality,
        ));
  }

  Future<String> _extractM3U8DirectInternal(
    String animeSession,
    String episodeSession,
    QualityOption quality,
  ) async {
    // Since we already have the streaming URL from data-src, just click and wait for m3u8
    // The click method will monitor network requests for .m3u8 URLs
    final result = await _extractM3U8Internal(animeSession, episodeSession, quality);

    // Ensure we only return .m3u8 URLs, not kwik.cx or other URLs
    if (!result.contains('.m3u8')) {
      throw Exception('Extraction returned non-m3u8 URL: $result');
    }

    return result;
  }


  Future<void> _disposeWebView() async {
    try {
      // Mark as disposed first to prevent new operations
      _isDisposed = true;
      
      // Wait for pending operations to complete (with timeout)
      if (_pendingOperations.isNotEmpty) {
        if (kDebugMode) {
          print('WebScraper: Waiting for ${_pendingOperations.length} pending operations...');
        }
        try {
          await Future.wait(
            _pendingOperations.map((c) => c.future),
            eagerError: false,
          ).timeout(const Duration(seconds: 5));
        } catch (e) {
          if (kDebugMode) {
            print('WebScraper: Some pending operations timed out: $e');
          }
        }
      }
      
      if (_currentWebView != null) {
        await _currentWebView!.dispose();
        _currentWebView = null;
      }
      
      _pendingOperations.clear();
    } catch (e) {
      if (kDebugMode) {
        print('Error disposing WebView: $e');
      }
    } finally {
      _isDisposed = false; // Reset for next operation
    }
  }

  // Capture m3u8 content from WebView using multiple JavaScript methods
  Future<void> _captureM3u8ContentFromWebView(InAppWebViewController controller, String m3u8Url) async {
    // Check if controller is still valid before proceeding
    if (!_isControllerValid(controller)) {
      if (kDebugMode) {
        print('WebScraper: Cannot capture m3u8, controller is disposed');
      }
      return;
    }

    if (kDebugMode) {
      print('WebScraper: Attempting to capture m3u8 content from WebView: $m3u8Url');
    }

    // Method 1: Try fetch() with credentials
    try {
      if (!_isControllerValid(controller)) return;
      
      final escapedUrl = m3u8Url.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      final contentResult = await controller.evaluateJavascript(source: '''
        (async function() {
          try {
            const response = await fetch('$escapedUrl', {
              method: 'GET',
              credentials: 'include',
              mode: 'cors',
              cache: 'default'
            });
            if (!response.ok) {
              return null;
            }
            const text = await response.text();
            return text;
          } catch (e) {
            console.error('Fetch failed:', e);
            return null;
          }
        })();
      ''');
      
      if (contentResult != null && contentResult is String && contentResult.isNotEmpty) {
        if (kDebugMode) {
          print('WebScraper: ✅ Captured m3u8 via fetch() (${contentResult.length} bytes)');
        }
        await _analyzeM3U8ContentFromString(contentResult);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('WebScraper: fetch() method failed: $e');
      }
      // Don't return, try next method
    }

    // Method 2: Try XMLHttpRequest (sometimes works when fetch() doesn't)
    try {
      if (!_isControllerValid(controller)) return;
      
      final escapedUrl = m3u8Url.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      final contentResult = await controller.evaluateJavascript(source: '''
        (function() {
          return new Promise(function(resolve, reject) {
            try {
              const xhr = new XMLHttpRequest();
              xhr.open('GET', '$escapedUrl', true);
              xhr.withCredentials = true;
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                  if (xhr.status === 200) {
                    resolve(xhr.responseText);
                  } else {
                    reject('XHR failed with status: ' + xhr.status);
                  }
                }
              };
              xhr.onerror = function() {
                reject('XHR error');
              };
              xhr.send();
            } catch (e) {
              reject(e.toString());
            }
          });
        })();
      ''');
      
      if (contentResult != null && contentResult is String && contentResult.isNotEmpty) {
        if (kDebugMode) {
          print('WebScraper: ✅ Captured m3u8 via XMLHttpRequest (${contentResult.length} bytes)');
        }
        await _analyzeM3U8ContentFromString(contentResult);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('WebScraper: XMLHttpRequest method failed: $e');
      }
    }

    if (kDebugMode) {
      print('WebScraper: ⚠️ All WebView capture methods failed, content will be fetched by download manager');
    }
  }

  // Get HTTP headers for m3u8 requests (similar to download_manager)
  Map<String, String> _getHttpHeadersForM3u8(String url, CookieManagerService cookieManager) {
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
      if (kDebugMode) {
        print('WebScraper: Could not get cookies for m3u8 request: $e');
      }
    }

    return headers;
  }

  // Analyze M3U8 content from string (for content already fetched)
  Future<void> _analyzeM3U8ContentFromString(String m3u8Content) async {
    if (kDebugMode) {
      print('WebScraper: M3U8 content length: ${m3u8Content.length} chars');
      print('WebScraper: First 300 chars: ${m3u8Content.substring(0, math.min(300, m3u8Content.length))}');
    }

    // Detect stream types (following m3u8_handling.md logic)
    final hasJpgExtensions = m3u8Content.contains('.jpg');
    final hasTsExtensions = m3u8Content.contains('.ts') || m3u8Content.contains('.m4s');
    final hasEncryption = m3u8Content.contains('#EXT-X-KEY:METHOD=AES-128');

    if (kDebugMode) {
      print('WebScraper: Stream analysis:');
      print('  - Contains .jpg files: $hasJpgExtensions');
      print('  - Contains .ts/.m4s files: $hasTsExtensions');
      print('  - Contains encryption: $hasEncryption');
    }

    // Determine stream type (following help.md patterns)
    final isEncryptedJpegOverHls = hasJpgExtensions && !hasTsExtensions && hasEncryption;
    final isTrueMjpegStream = hasJpgExtensions && !hasEncryption;
    final isStandardHlsStream = !isEncryptedJpegOverHls && !isTrueMjpegStream;

    if (kDebugMode) {
      if (isEncryptedJpegOverHls) {
        print('WebScraper: 🔐 Detected Encrypted JPEG-over-HLS streams');
        print('  Processing will require: Download encrypted segments, decrypt with AES-128, re-encode');
      } else if (isTrueMjpegStream) {
        print('WebScraper: 🖼️ Detected True MJPEG streams');
        print('  Processing will require: Download JPEG frames, assemble into video');
      } else if (isStandardHlsStream) {
        print('WebScraper: 📺 Detected Standard HLS streams');
        print('  Processing will require: Traditional HLS segment download and concatenation');
      }
    }
  }

  // Analyze M3U8 content for stream type detection (following m3u8_handling.md)
  Future<void> _analyzeM3U8Content(String m3u8Url) async {
    try {
      if (kDebugMode) {
        print('WebScraper: Analyzing M3U8 content from: $m3u8Url');
      }

      // Fetch M3U8 playlist content
      final response = await http.get(Uri.parse(m3u8Url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch M3U8: HTTP ${response.statusCode}');
      }

      final m3u8Content = response.body;
      await _analyzeM3U8ContentFromString(m3u8Content);

      // Additional server-based detection for known patterns
      if (m3u8Url.contains('vault-13.owocdn.top') || m3u8Url.contains('owocdn.top')) {
        if (kDebugMode) {
          print('WebScraper: 🎯 Detected owoCDN server (known for encrypted JPG streams)');
        }
      }

    } catch (e) {
      if (kDebugMode) {
        print('WebScraper: Error analyzing M3U8 content: $e');
      }
      // Don't rethrow - analysis failure shouldn't break M3U8 extraction
    }
  }

  // Cleanup
  Future<void> dispose() async {
    await _disposeWebView();
  }
}

