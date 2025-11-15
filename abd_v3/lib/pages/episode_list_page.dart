import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../providers/episode_list_provider.dart';
import '../widgets/episode_tile.dart';
import '../widgets/quality_selector_modal.dart';

class EpisodeListPage extends ConsumerStatefulWidget {
  final Anime anime;

  const EpisodeListPage({super.key, required this.anime});

  @override
  ConsumerState<EpisodeListPage> createState() => _EpisodeListPageState();
}

class _EpisodeListPageState extends ConsumerState<EpisodeListPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load episodes on init
    Future.microtask(() {
      ref.read(episodeListProvider(widget.anime.session).notifier).loadEpisodes();
    });

    // Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      // Load more when 90% scrolled
      ref.read(episodeListProvider(widget.anime.session).notifier).loadEpisodes();
    }
  }

  Future<void> _loadAll() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Loading all episodes...'),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, child) {
                    return const Text(
                      'This may take a moment',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    await ref
        .read(episodeListProvider(widget.anime.session).notifier)
        .loadAllEpisodes();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodeState = ref.watch(episodeListProvider(widget.anime.session));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.anime.title,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              '${episodeState.episodes.length} episodes',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (episodeState.hasMore)
            IconButton(
              icon: const Icon(Icons.download_for_offline),
              tooltip: 'Load All Episodes',
              onPressed: episodeState.isLoading ? null : _loadAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: episodeState.isLoading
                ? null
                : () {
                    ref
                        .read(episodeListProvider(widget.anime.session).notifier)
                        .loadEpisodes(refresh: true);
                  },
          ),
        ],
      ),
      body: _buildBody(episodeState),
    );
  }

  Widget _buildBody(EpisodeListState state) {
    if (state.episodes.isEmpty && state.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading episodes...'),
          ],
        ),
      );
    }

    if (state.episodes.isEmpty && state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Error: ${state.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                ref
                    .read(episodeListProvider(widget.anime.session).notifier)
                    .loadEpisodes(refresh: true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.episodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_filter_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No episodes found'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(episodeListProvider(widget.anime.session).notifier)
            .loadEpisodes(refresh: true);
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: state.episodes.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.episodes.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final episode = state.episodes[index];
          return EpisodeTile(
            episode: episode,
            onTap: () {
              _showQualitySelector(episode.session);
            },
          );
        },
      ),
    );
  }

  void _showQualitySelector(String episodeSession) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return QualitySelectorModal(
          animeSession: widget.anime.session,
          episodeSession: episodeSession,
          animeTitle: widget.anime.title,
        );
      },
    );
  }
}

