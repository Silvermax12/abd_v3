import 'package:hive/hive.dart';

part 'episode_model.g.dart';

@HiveType(typeId: 1)
class Episode extends HiveObject {
  @HiveField(0)
  final String session;

  @HiveField(1)
  final int number;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String? thumbnail;

  @HiveField(4)
  final String? snapshot;

  @HiveField(5)
  final String? duration;

  @HiveField(6)
  final String animeSession;

  @HiveField(7)
  final DateTime cachedAt;

  Episode({
    required this.session,
    required this.number,
    required this.title,
    required this.animeSession,
    this.thumbnail,
    this.snapshot,
    this.duration,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  factory Episode.fromJson(Map<String, dynamic> json, String animeSession) {
    return Episode(
      session: json['session'] as String,
      number: _parseEpisodeNumber(json['episode']),
      title: json['title'] as String? ?? 'Episode ${json['episode']}',
      animeSession: animeSession,
      thumbnail: json['snapshot'] as String?,
      snapshot: json['snapshot'] as String?,
      duration: json['duration'] as String?,
    );
  }

  static int _parseEpisodeNumber(dynamic episode) {
    if (episode is int) return episode;
    if (episode is String) {
      return int.tryParse(episode) ?? 0;
    }
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'session': session,
      'number': number,
      'title': title,
      'thumbnail': thumbnail,
      'snapshot': snapshot,
      'duration': duration,
      'animeSession': animeSession,
    };
  }

  bool get isCacheExpired {
    final expiryDuration = const Duration(days: 7);
    return DateTime.now().difference(cachedAt) > expiryDuration;
  }
}

