import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static PreferencesService? _instance;
  static PreferencesService get instance {
    _instance ??= PreferencesService._();
    return _instance!;
  }

  PreferencesService._();

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('PreferencesService not initialized. Call initialize() first.');
    }
    return _prefs!;
  }

  // Keys
  static const String _keyPreferredQuality = 'preferred_quality';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyAutoDownload = 'auto_download';
  static const String _keyMaxConcurrentDownloads = 'max_concurrent_downloads';
  static const String _keyDownloadPath = 'download_path';
  static const String _keyShowDisclaimer = 'show_disclaimer';
  static const String _keyUseFFmpeg = 'use_ffmpeg';
  static const String _keyFFmpegQuality = 'ffmpeg_quality';

  // Preferred Quality (e.g., "1080", "720", "480", "360")
  String get preferredQuality => prefs.getString(_keyPreferredQuality) ?? '720';
  
  Future<void> setPreferredQuality(String quality) async {
    await prefs.setString(_keyPreferredQuality, quality);
  }

  // Theme Mode ("light", "dark", "system")
  String get themeMode => prefs.getString(_keyThemeMode) ?? 'system';
  
  Future<void> setThemeMode(String mode) async {
    await prefs.setString(_keyThemeMode, mode);
  }

  // Auto Download
  bool get autoDownload => prefs.getBool(_keyAutoDownload) ?? false;
  
  Future<void> setAutoDownload(bool value) async {
    await prefs.setBool(_keyAutoDownload, value);
  }

  // Max Concurrent Downloads (1-3)
  int get maxConcurrentDownloads => prefs.getInt(_keyMaxConcurrentDownloads) ?? 2;
  
  Future<void> setMaxConcurrentDownloads(int value) async {
    await prefs.setInt(_keyMaxConcurrentDownloads, value);
  }

  // Download Path
  String? get downloadPath => prefs.getString(_keyDownloadPath);
  
  Future<void> setDownloadPath(String path) async {
    await prefs.setString(_keyDownloadPath, path);
  }

  // Show Disclaimer (first launch)
  bool get shouldShowDisclaimer => prefs.getBool(_keyShowDisclaimer) ?? true;
  
  Future<void> setShowDisclaimer(bool value) async {
    await prefs.setBool(_keyShowDisclaimer, value);
  }

  // Use FFmpeg for re-encoding
  bool get useFFmpeg => prefs.getBool(_keyUseFFmpeg) ?? true;
  
  Future<void> setUseFFmpeg(bool value) async {
    await prefs.setBool(_keyUseFFmpeg, value);
  }

  // FFmpeg Quality preset ("ultrafast", "fast", "medium", "slow")
  String get ffmpegQuality => prefs.getString(_keyFFmpegQuality) ?? 'fast';
  
  Future<void> setFFmpegQuality(String quality) async {
    await prefs.setString(_keyFFmpegQuality, quality);
  }

  // Clear all preferences
  Future<void> clearAll() async {
    await prefs.clear();
  }

  // Get all settings as a map for debugging
  Map<String, dynamic> getAllSettings() {
    return {
      'preferredQuality': preferredQuality,
      'themeMode': themeMode,
      'autoDownload': autoDownload,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'downloadPath': downloadPath,
      'shouldShowDisclaimer': shouldShowDisclaimer,
      'useFFmpeg': useFFmpeg,
      'ffmpegQuality': ffmpegQuality,
    };
  }
}

