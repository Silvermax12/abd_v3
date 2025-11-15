import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/episode_model.dart';
import '../services/anime_api_service.dart';
import 'anime_search_provider.dart';

// State for episode list
class EpisodeListState {
  final List<Episode> episodes;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final bool hasMore;

  EpisodeListState({
    this.episodes = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
  });

  EpisodeListState copyWith({
    List<Episode>? episodes,
    bool? isLoading,
    String? error,
    int? currentPage,
    bool? hasMore,
  }) {
    return EpisodeListState(
      episodes: episodes ?? this.episodes,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// Notifier for episode list
class EpisodeListNotifier extends StateNotifier<EpisodeListState> {
  final AnimeApiService _apiService;
  final String animeSession;

  EpisodeListNotifier(this._apiService, this.animeSession)
      : super(EpisodeListState());

  Future<void> loadEpisodes({bool refresh = false}) async {
    if (refresh) {
      state = EpisodeListState(isLoading: true);
    } else if (state.isLoading || !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final page = refresh ? 1 : state.currentPage;
      final newEpisodes = await _apiService.getEpisodes(
        animeSession,
        page: page,
        useCache: page == 1,
      );

      if (refresh) {
        state = state.copyWith(
          episodes: newEpisodes,
          isLoading: false,
          currentPage: 1,
          hasMore: newEpisodes.isNotEmpty,
        );
      } else {
        state = state.copyWith(
          episodes: [...state.episodes, ...newEpisodes],
          isLoading: false,
          currentPage: page + 1,
          hasMore: newEpisodes.isNotEmpty,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadAllEpisodes({
    void Function(int current, int total)? onProgress,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final allEpisodes = await _apiService.getAllEpisodes(
        animeSession,
        onProgress: onProgress,
      );

      state = state.copyWith(
        episodes: allEpisodes,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Family provider for episode list by anime session
final episodeListProvider = StateNotifierProvider.family<EpisodeListNotifier,
    EpisodeListState, String>((ref, animeSession) {
  final apiService = ref.watch(animeApiServiceProvider);
  return EpisodeListNotifier(apiService, animeSession);
});

