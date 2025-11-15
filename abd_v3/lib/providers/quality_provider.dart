import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/quality_option_model.dart';
import '../services/anime_web_scraper.dart';

// Provider for AnimeWebScraper
final animeWebScraperProvider = Provider<AnimeWebScraper>((ref) {
  return AnimeWebScraper();
});

// State for quality options
class QualityState {
  final List<QualityOption> options;
  final bool isLoading;
  final String? error;
  final String? extractedM3U8;
  final bool isExtractingM3U8;

  QualityState({
    this.options = const [],
    this.isLoading = false,
    this.error,
    this.extractedM3U8,
    this.isExtractingM3U8 = false,
  });

  QualityState copyWith({
    List<QualityOption>? options,
    bool? isLoading,
    String? error,
    String? extractedM3U8,
    bool? isExtractingM3U8,
  }) {
    return QualityState(
      options: options ?? this.options,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      extractedM3U8: extractedM3U8 ?? this.extractedM3U8,
      isExtractingM3U8: isExtractingM3U8 ?? this.isExtractingM3U8,
    );
  }
}

// Notifier for quality options
class QualityNotifier extends StateNotifier<QualityState> {
  final AnimeWebScraper _scraper;
  final String animeSession;
  final String episodeSession;

  QualityNotifier(this._scraper, this.animeSession, this.episodeSession)
      : super(QualityState());

  Future<void> loadQualities() async {
    debugPrint('QualityProvider[${animeSession}_$episodeSession]: Starting loadQualities - setting loading state');
    state = state.copyWith(isLoading: true, error: null, options: []);
    debugPrint('QualityProvider[${animeSession}_$episodeSession]: State updated to loading=true, now calling scraper');

    try {
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: Loading qualities for anime: $animeSession, episode: $episodeSession');
      final qualities = await _scraper.getQualities(animeSession, episodeSession);
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: Scraper returned ${qualities.length} quality options');
      for (final q in qualities) {
        debugPrint('  - ${q.label} (src: ${q.src.isNotEmpty ? "HAS_URL" : "NO_URL"}, resolution: ${q.resolution})');
      }
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: Setting state with qualities, loading=false');
      state = state.copyWith(
        options: qualities,
        isLoading: false,
      );
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: State updated successfully - options: ${state.options.length}');
    } catch (e) {
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: Error loading qualities: $e');
      debugPrint('QualityProvider[${animeSession}_$episodeSession]: Setting error state');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<String?> extractM3U8(QualityOption quality, {int maxRetries = 3}) async {
    debugPrint('QualityProvider: extractM3U8 called for ${quality.label} with maxRetries=$maxRetries');
    state = state.copyWith(isExtractingM3U8: true, error: null);

    int attempt = 0;
    Exception? lastError;

    while (attempt < maxRetries) {
      attempt++;
      try {
        debugPrint('QualityProvider: M3U8 extraction attempt $attempt/$maxRetries...');
        
        // Try direct extraction
        final m3u8 = await _scraper.extractM3U8Direct(
          animeSession,
          episodeSession,
          quality,
        );

        debugPrint('QualityProvider: M3U8 extraction completed successfully: ${m3u8.substring(0, math.min(50, m3u8.length))}...');
        state = state.copyWith(
          extractedM3U8: m3u8,
          isExtractingM3U8: false,
        );

        return m3u8;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('QualityProvider: M3U8 extraction attempt $attempt/$maxRetries failed: $e');
        
        if (attempt < maxRetries) {
          // Exponential backoff: 2s, 4s, 8s
          final delaySeconds = math.pow(2, attempt).toInt();
          debugPrint('QualityProvider: Retrying in $delaySeconds seconds...');
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    }

    // All retries exhausted
    debugPrint('QualityProvider: All M3U8 extraction attempts failed after $maxRetries tries');
    state = state.copyWith(
      isExtractingM3U8: false,
      error: lastError?.toString() ?? 'Failed to extract M3U8 after $maxRetries attempts',
    );
    return null;
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void reset() {
    state = QualityState();
  }
}

// Family provider for quality options
final qualityProvider = StateNotifierProvider.family<QualityNotifier,
    QualityState, String>((ref, key) {
  final scraper = ref.watch(animeWebScraperProvider);
  final parts = key.split('_');
  if (parts.length != 2) {
    throw ArgumentError('Invalid quality provider key: $key');
  }
  return QualityNotifier(
    scraper,
    parts[0], // animeSession
    parts[1], // episodeSession
  );
});

