class AppConstants {
  // API
  static const String baseOrigin = "https://animepahe.si";
  static const String apiBase = "$baseOrigin/api";

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 15);
  static const Duration webViewTimeout = Duration(seconds: 20);

  // Download
  static const int maxConcurrentDownloads = 2;
  static const int maxConcurrentWebViews = 1;

  // Cache
  static const int maxAnimeCacheEntries = 100;
  static const int maxEpisodeCacheEntries = 500;
  static const Duration cacheExpiry = Duration(days: 7);

  // Quality options
  static const List<String> availableQualities = ['1080', '720', '480', '360'];

  // FFmpeg presets
  static const List<String> ffmpegPresets = [
    'ultrafast',
    'fast',
    'medium',
    'slow',
  ];

  // App info
  static const String appName = 'Anime Batch Downloader';
  static const String appVersion = '1.0.0';
  static const String appLegalese =
      '© 2024\n\nThis app is for educational and personal use only. '
      'Users are responsible for how they use this tool.';
}

