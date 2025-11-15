import 'package:hive_flutter/hive_flutter.dart';
import '../models/anime_model.dart';
import '../models/episode_model.dart';
import '../models/download_task_model.dart';

class HiveService {
  static const String animeCacheBox = 'animeCache';
  static const String episodeCacheBox = 'episodeCache';
  static const String downloadQueueBox = 'downloadQueue';

  static HiveService? _instance;
  static HiveService get instance {
    _instance ??= HiveService._();
    return _instance!;
  }

  HiveService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize Hive
    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AnimeAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EpisodeAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DownloadStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(DownloadTaskAdapter());
    }

    // Open boxes
    await Hive.openBox<Anime>(animeCacheBox);
    await Hive.openBox<Episode>(episodeCacheBox);
    await Hive.openBox<DownloadTask>(downloadQueueBox);

    _initialized = true;
  }

  // Anime Cache operations
  Box<Anime> get animeBox => Hive.box<Anime>(animeCacheBox);

  Future<void> cacheAnime(String query, List<Anime> animes) async {
    final box = animeBox;
    for (final anime in animes) {
      await box.put('${query}_${anime.session}', anime);
    }
  }

  List<Anime> getCachedAnime(String query) {
    final box = animeBox;
    final results = <Anime>[];

    for (final key in box.keys) {
      if (key.toString().startsWith('${query}_')) {
        final anime = box.get(key);
        if (anime != null && !anime.isCacheExpired) {
          results.add(anime);
        }
      }
    }

    return results;
  }

  // Episode Cache operations
  Box<Episode> get episodeBox => Hive.box<Episode>(episodeCacheBox);

  Future<void> cacheEpisodes(String animeSession, List<Episode> episodes) async {
    final box = episodeBox;
    for (final episode in episodes) {
      await box.put('${animeSession}_${episode.session}', episode);
    }
  }

  List<Episode> getCachedEpisodes(String animeSession) {
    final box = episodeBox;
    final results = <Episode>[];

    for (final key in box.keys) {
      if (key.toString().startsWith('${animeSession}_')) {
        final episode = box.get(key);
        if (episode != null && !episode.isCacheExpired) {
          results.add(episode);
        }
      }
    }

    // Sort by episode number
    results.sort((a, b) => a.number.compareTo(b.number));
    return results;
  }

  // Download Queue operations
  Box<DownloadTask> get downloadBox => Hive.box<DownloadTask>(downloadQueueBox);

  Future<void> saveDownloadTask(DownloadTask task) async {
    await downloadBox.put(task.id, task);
  }

  Future<void> updateDownloadTask(DownloadTask task) async {
    await downloadBox.put(task.id, task);
  }

  Future<void> deleteDownloadTask(String taskId) async {
    await downloadBox.delete(taskId);
  }

  DownloadTask? getDownloadTask(String taskId) {
    return downloadBox.get(taskId);
  }

  List<DownloadTask> getAllDownloadTasks() {
    return downloadBox.values.toList();
  }

  List<DownloadTask> getActiveDownloadTasks() {
    return downloadBox.values
        .where((task) => task.isActive)
        .toList();
  }

  List<DownloadTask> getQueuedDownloadTasks() {
    return downloadBox.values
        .where((task) => task.status == DownloadStatus.queued)
        .toList();
  }

  // Cache management
  Future<void> clearExpiredCache() async {
    // Clear expired anime
    final animeBox = this.animeBox;
    final animeKeysToDelete = <dynamic>[];
    for (final key in animeBox.keys) {
      final anime = animeBox.get(key);
      if (anime != null && anime.isCacheExpired) {
        animeKeysToDelete.add(key);
      }
    }
    for (final key in animeKeysToDelete) {
      await animeBox.delete(key);
    }

    // Clear expired episodes
    final episodeBox = this.episodeBox;
    final episodeKeysToDelete = <dynamic>[];
    for (final key in episodeBox.keys) {
      final episode = episodeBox.get(key);
      if (episode != null && episode.isCacheExpired) {
        episodeKeysToDelete.add(key);
      }
    }
    for (final key in episodeKeysToDelete) {
      await episodeBox.delete(key);
    }
  }

  Future<void> clearAllCache() async {
    await animeBox.clear();
    await episodeBox.clear();
  }

  Future<int> getCacheSizeInBytes() async {
    int totalSize = 0;

    try {
      // Note: This is approximate, actual implementation would need file system access
      totalSize = animeBox.length * 1024 + 
                  episodeBox.length * 512 + 
                  downloadBox.length * 2048;
    } catch (e) {
      // Ignore errors
    }

    return totalSize;
  }

  // Limit cache size
  Future<void> limitCacheSize({int maxAnimeEntries = 100, int maxEpisodeEntries = 500}) async {
    // Limit anime cache
    final animeBox = this.animeBox;
    if (animeBox.length > maxAnimeEntries) {
      final entriesToDelete = animeBox.length - maxAnimeEntries;
      final keys = animeBox.keys.take(entriesToDelete).toList();
      for (final key in keys) {
        await animeBox.delete(key);
      }
    }

    // Limit episode cache
    final episodeBox = this.episodeBox;
    if (episodeBox.length > maxEpisodeEntries) {
      final entriesToDelete = episodeBox.length - maxEpisodeEntries;
      final keys = episodeBox.keys.take(entriesToDelete).toList();
      for (final key in keys) {
        await episodeBox.delete(key);
      }
    }
  }

  Future<void> close() async {
    await Hive.close();
    _initialized = false;
  }
}

