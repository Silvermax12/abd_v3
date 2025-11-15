import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/anime_search_provider.dart';
import '../widgets/anime_card.dart';
import 'episode_list_page.dart';

class AnimeSearchPage extends ConsumerStatefulWidget {
  const AnimeSearchPage({super.key});

  @override
  ConsumerState<AnimeSearchPage> createState() => _AnimeSearchPageState();
}

class _AnimeSearchPageState extends ConsumerState<AnimeSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      ref.read(animeSearchProvider.notifier).search(query);
      _searchFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(animeSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime Search'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search anime...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(animeSearchProvider.notifier).clearResults();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onSubmitted: (_) => _performSearch(),
              onChanged: (value) => setState(() {}),
            ),
          ),

          // Results
          Expanded(
            child: _buildBody(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AnimeSearchState state) {
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...'),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error: ${state.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(animeSearchProvider.notifier).clearError();
                if (state.lastQuery != null) {
                  ref.read(animeSearchProvider.notifier).search(
                        state.lastQuery!,
                        useCache: false,
                      );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.results.isEmpty && state.lastQuery == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Search for anime',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (state.results.isEmpty && state.lastQuery != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No results found for "${state.lastQuery}"',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final anime = state.results[index];
        return AnimeCard(
          anime: anime,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EpisodeListPage(anime: anime),
              ),
            );
          },
        );
      },
    );
  }
}

