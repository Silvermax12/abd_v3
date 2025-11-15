import 'package:hive/hive.dart';

part 'download_task_model.g.dart';

@HiveType(typeId: 2)
enum DownloadStatus {
  @HiveField(0)
  queued,
  @HiveField(1)
  downloading,
  @HiveField(2)
  paused,
  @HiveField(3)
  completed,
  @HiveField(4)
  failed,
  @HiveField(5)
  cancelled,
  @HiveField(6)
  processing, // FFmpeg processing
  @HiveField(7)
  fetchingM3u8, // Fetching m3u8 link
}

@HiveType(typeId: 3)
class DownloadTask extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String m3u8Url;

  @HiveField(2)
  final String animeTitle;

  @HiveField(3)
  final String episodeTitle;

  @HiveField(4)
  final int episodeNumber;

  @HiveField(5)
  final String resolution;

  @HiveField(6)
  final String outputPath;

  @HiveField(7)
  DownloadStatus status;

  @HiveField(8)
  double progress; // 0.0 to 1.0

  @HiveField(9)
  int downloadedBytes;

  @HiveField(10)
  int? totalBytes;

  @HiveField(11)
  double speedMBps; // MB per second

  @HiveField(12)
  int? etaSeconds;

  @HiveField(13)
  String? errorMessage;

  @HiveField(14)
  DateTime createdAt;

  @HiveField(15)
  DateTime? completedAt;

  @HiveField(16)
  final String animeSession;

  @HiveField(17)
  final String episodeSession;

  DownloadTask({
    required this.id,
    required this.m3u8Url,
    required this.animeTitle,
    required this.episodeTitle,
    required this.episodeNumber,
    required this.resolution,
    required this.outputPath,
    required this.animeSession,
    required this.episodeSession,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speedMBps = 0.0,
    this.etaSeconds,
    this.errorMessage,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get fileName =>
      '${animeTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}_E${episodeNumber.toString().padLeft(2, '0')}_${resolution}p.mp4';

  String get displayProgress => '${progress * 100}%';

  String get displaySpeed => '${speedMBps.toStringAsFixed(2)} MB/s';

  String get displayETA {
    if (etaSeconds == null) return '--:--';
    final duration = Duration(seconds: etaSeconds!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String get displaySize {
    final bytes = totalBytes ?? downloadedBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${bytes / 1024} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${bytes / (1024 * 1024)} MB';
    }
    return '${bytes / (1024 * 1024 * 1024)} GB';
  }

  bool get canPause =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;

  bool get canResume =>
      status == DownloadStatus.paused || status == DownloadStatus.failed;

  bool get canCancel => status != DownloadStatus.completed &&
      status != DownloadStatus.cancelled;

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;

  bool get isCompleted => status == DownloadStatus.completed;

  bool get isFailed => status == DownloadStatus.failed;

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speedMBps,
    int? etaSeconds,
    String? errorMessage,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id,
      m3u8Url: m3u8Url,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
      episodeNumber: episodeNumber,
      resolution: resolution,
      outputPath: outputPath,
      animeSession: animeSession,
      episodeSession: episodeSession,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedMBps: speedMBps ?? this.speedMBps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'm3u8Url': m3u8Url,
      'animeTitle': animeTitle,
      'episodeTitle': episodeTitle,
      'episodeNumber': episodeNumber,
      'resolution': resolution,
      'outputPath': outputPath,
      'animeSession': animeSession,
      'episodeSession': episodeSession,
      'status': status.toString(),
      'progress': progress,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
      'speedMBps': speedMBps,
      'etaSeconds': etaSeconds,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}

