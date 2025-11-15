import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../services/anime_api_service.dart';

// Provider for AnimeApiService
final animeApiServiceProvider = Provider<AnimeApiService>((ref) {
  return AnimeApiService();
});

// State for anime search
class AnimeSearchState {
  final List<Anime> results;
  final bool isLoading;
  final String? error;
  final String? lastQuery;

  AnimeSearchState({
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.lastQuery,
  });

  AnimeSearchState copyWith({
    List<Anime>? results,
    bool? isLoading,
    String? error,
    String? lastQuery,
  }) {
    return AnimeSearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lastQuery: lastQuery ?? this.lastQuery,
    );
  }
}

// Notifier for anime search
class AnimeSearchNotifier extends StateNotifier<AnimeSearchState> {
  final AnimeApiService _apiService;

  AnimeSearchNotifier(this._apiService) : super(AnimeSearchState());

  Future<void> search(String query, {bool useCache = true}) async {
    if (query.trim().isEmpty) {
      state = AnimeSearchState(results: [], error: null);
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final results = await _apiService.search(query, useCache: useCache);
      state = state.copyWith(
        results: results,
        isLoading: false,
        lastQuery: query,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        results: [],
      );
    }
  }

  void clearResults() {
    state = AnimeSearchState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider for anime search
final animeSearchProvider =
    StateNotifierProvider<AnimeSearchNotifier, AnimeSearchState>((ref) {
  final apiService = ref.watch(animeApiServiceProvider);
  return AnimeSearchNotifier(apiService);
});

