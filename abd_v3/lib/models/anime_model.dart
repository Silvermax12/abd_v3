import 'package:hive/hive.dart';

part 'anime_model.g.dart';

@HiveType(typeId: 0)
class Anime extends HiveObject {
  @HiveField(0)
  final String session;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? poster;

  @HiveField(3)
  final String? type;

  @HiveField(4)
  final int? episodes;

  @HiveField(5)
  final String? status;

  @HiveField(6)
  final String? year;

  @HiveField(7)
  final String? season;

  @HiveField(8)
  final DateTime cachedAt;

  Anime({
    required this.session,
    required this.title,
    this.poster,
    this.type,
    this.episodes,
    this.status,
    this.year,
    this.season,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      session: json['session'] as String,
      title: json['title'] as String,
      poster: json['poster'] as String?,
      type: json['type'] as String?,
      episodes: json['episodes'] as int?,
      status: json['status'] as String?,
      year: json['year']?.toString(),
      season: json['season'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session': session,
      'title': title,
      'poster': poster,
      'type': type,
      'episodes': episodes,
      'status': status,
      'year': year,
      'season': season,
    };
  }

  bool get isCacheExpired {
    final expiryDuration = const Duration(days: 7);
    return DateTime.now().difference(cachedAt) > expiryDuration;
  }
}

