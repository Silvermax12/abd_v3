import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/anime_model.dart';
import '../models/episode_model.dart';
import '../storage/hive_service.dart';
import 'cookie_manager_service.dart';

class AnimeApiService {
  static const String baseOrigin = "https://animepahe.si";
  static const String apiBase = "$baseOrigin/api";

  final HiveService _hiveService = HiveService.instance;
  final CookieManagerService _cookieManager = CookieManagerService.instance;

  // Search anime
  Future<List<Anime>> search(String query, {bool useCache = true}) async {
    if (query.trim().isEmpty) {
      throw Exception('Search query cannot be empty');
    }

    // Check cache first
    if (useCache) {
      final cached = _hiveService.getCachedAnime(query);
      if (cached.isNotEmpty) {
        return cached;
      }
    }

    // Ensure session is ready
    await _cookieManager.waitUntilReady();

    // Retry logic with exponential backoff
    const maxRetries = 3;
    int attempt = 0;
    Exception? lastError;

    while (attempt < maxRetries) {
      attempt++;
      
      try {
        final url = Uri.parse('$apiBase?m=search&q=${Uri.encodeComponent(query)}');
        
        if (kDebugMode) {
          debugPrint('AnimeApiService: Search attempt $attempt/$maxRetries for query: $query');
        }
        
        final response = await http.get(
          url,
          headers: _cookieManager.getHeaders(),
        ).timeout(
          const Duration(seconds: 30), // Increased timeout to 30 seconds
          onTimeout: () {
            throw Exception('Search request timed out');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['data'] == null) {
            return [];
          }

          final List<Anime> animes = [];
          for (final item in data['data']) {
            try {
              animes.add(Anime.fromJson(item));
            } catch (e) {
              // Skip malformed items
              debugPrint('Error parsing anime item: $e');
            }
          }

          // Cache the results
          if (animes.isNotEmpty) {
            await _hiveService.cacheAnime(query, animes);
          }

          if (kDebugMode) {
            debugPrint('AnimeApiService: Search successful, found ${animes.length} results');
          }

          return animes;
        } else if (response.statusCode == 404) {
          return [];
        } else {
          throw Exception('Failed to search anime: HTTP ${response.statusCode}');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        if (kDebugMode) {
          debugPrint('AnimeApiService: Search attempt $attempt/$maxRetries failed: $e');
        }
        
        // If it's the last attempt, throw the error
        if (attempt >= maxRetries) {
          if (e.toString().contains('timed out')) {
            throw Exception('Search request timed out after $maxRetries attempts');
          }
          throw Exception('Network error after $maxRetries attempts: $e');
        }
        
        // Exponential backoff: 2s, 4s
        final delaySeconds = math.pow(2, attempt).toInt();
        if (kDebugMode) {
          debugPrint('AnimeApiService: Retrying search in $delaySeconds seconds...');
        }
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
    
    // Should never reach here, but just in case
    throw Exception('Search failed after $maxRetries attempts: ${lastError?.toString() ?? "Unknown error"}');
  }

  // Get episodes for an anime
  Future<List<Episode>> getEpisodes(
    String animeSession, {
    int page = 1,
    bool useCache = true,
  }) async {
    if (animeSession.trim().isEmpty) {
      throw Exception('Anime session cannot be empty');
    }

    // Check cache first (only for page 1)
    if (useCache && page == 1) {
      final cached = _hiveService.getCachedEpisodes(animeSession);
      if (cached.isNotEmpty) {
        return cached;
      }
    }

    // Ensure session is ready
    await _cookieManager.waitUntilReady();

    // Retry logic with exponential backoff
    const maxRetries = 3;
    int attempt = 0;
    Exception? lastError;

    while (attempt < maxRetries) {
      attempt++;
      
      try {
        final url = Uri.parse(
          '$apiBase?m=release&id=$animeSession&sort=episode_asc&page=$page',
        );
        
        if (kDebugMode) {
          debugPrint('AnimeApiService: GetEpisodes attempt $attempt/$maxRetries for anime: $animeSession, page: $page');
        }
        
        final response = await http.get(
          url,
          headers: _cookieManager.getHeaders(),
        ).timeout(
          const Duration(seconds: 30), // Increased timeout to 30 seconds
          onTimeout: () {
            throw Exception('Episode request timed out');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['data'] == null) {
            return [];
          }

          final List<Episode> episodes = [];
          for (final item in data['data']) {
            try {
              episodes.add(Episode.fromJson(item, animeSession));
            } catch (e) {
              debugPrint('Error parsing episode item: $e');
            }
          }

          // Cache the results (only for page 1)
          if (episodes.isNotEmpty && page == 1) {
            await _hiveService.cacheEpisodes(animeSession, episodes);
          }

          if (kDebugMode) {
            debugPrint('AnimeApiService: GetEpisodes successful, found ${episodes.length} episodes');
          }

          return episodes;
        } else if (response.statusCode == 404) {
          return [];
        } else {
          throw Exception('Failed to fetch episodes: HTTP ${response.statusCode}');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        if (kDebugMode) {
          debugPrint('AnimeApiService: GetEpisodes attempt $attempt/$maxRetries failed: $e');
        }
        
        // If it's the last attempt, throw the error
        if (attempt >= maxRetries) {
          if (e.toString().contains('timed out')) {
            throw Exception('Episode request timed out after $maxRetries attempts');
          }
          throw Exception('Network error after $maxRetries attempts: $e');
        }
        
        // Exponential backoff: 2s, 4s
        final delaySeconds = math.pow(2, attempt).toInt();
        if (kDebugMode) {
          debugPrint('AnimeApiService: Retrying getEpisodes in $delaySeconds seconds...');
        }
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
    
    // Should never reach here, but just in case
    throw Exception('GetEpisodes failed after $maxRetries attempts: ${lastError?.toString() ?? "Unknown error"}');
  }

  // Get all episodes (handling pagination)
  Future<List<Episode>> getAllEpisodes(
    String animeSession, {
    void Function(int current, int total)? onProgress,
  }) async {
    final allEpisodes = <Episode>[];
    int currentPage = 1;
    int totalPages = 1;

    // Ensure session is ready
    await _cookieManager.waitUntilReady();

    try {
      // Get first page to determine total pages
      final url = Uri.parse(
        '$apiBase?m=release&id=$animeSession&sort=episode_asc&page=$currentPage',
      );
      final response = await http.get(
        url,
        headers: _cookieManager.getHeaders(),
      ).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['data'] != null) {
          for (final item in data['data']) {
            try {
              allEpisodes.add(Episode.fromJson(item, animeSession));
            } catch (e) {
              debugPrint('Error parsing episode item: $e');
            }
          }
        }

        // Get total pages from response
        if (data['last_page'] != null) {
          totalPages = data['last_page'] as int;
        }

        onProgress?.call(currentPage, totalPages);

        // Fetch remaining pages
        for (currentPage = 2; currentPage <= totalPages; currentPage++) {
          final episodes = await getEpisodes(
            animeSession,
            page: currentPage,
            useCache: false,
          );
          allEpisodes.addAll(episodes);
          onProgress?.call(currentPage, totalPages);
        }

        // Cache all episodes
        if (allEpisodes.isNotEmpty) {
          await _hiveService.cacheEpisodes(animeSession, allEpisodes);
        }
      }
    } catch (e) {
      if (allEpisodes.isNotEmpty) {
        // Return partial results if we got some episodes
        return allEpisodes;
      }
      rethrow;
    }

    return allEpisodes;
  }
}

