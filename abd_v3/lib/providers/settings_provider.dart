import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/preferences_service.dart';
import '../storage/hive_service.dart';

// Provider for PreferencesService
final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  return PreferencesService.instance;
});

// Provider for HiveService
final hiveServiceProvider = Provider<HiveService>((ref) {
  return HiveService.instance;
});

// State for settings
class SettingsState {
  final String preferredQuality;
  final String themeMode;
  final bool autoDownload;
  final int maxConcurrentDownloads;
  final String? downloadPath;
  final bool shouldShowDisclaimer;
  final bool useFFmpeg;
  final String ffmpegQuality;

  SettingsState({
    required this.preferredQuality,
    required this.themeMode,
    required this.autoDownload,
    required this.maxConcurrentDownloads,
    this.downloadPath,
    required this.shouldShowDisclaimer,
    required this.useFFmpeg,
    required this.ffmpegQuality,
  });

  SettingsState copyWith({
    String? preferredQuality,
    String? themeMode,
    bool? autoDownload,
    int? maxConcurrentDownloads,
    String? downloadPath,
    bool? shouldShowDisclaimer,
    bool? useFFmpeg,
    String? ffmpegQuality,
  }) {
    return SettingsState(
      preferredQuality: preferredQuality ?? this.preferredQuality,
      themeMode: themeMode ?? this.themeMode,
      autoDownload: autoDownload ?? this.autoDownload,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadPath: downloadPath ?? this.downloadPath,
      shouldShowDisclaimer: shouldShowDisclaimer ?? this.shouldShowDisclaimer,
      useFFmpeg: useFFmpeg ?? this.useFFmpeg,
      ffmpegQuality: ffmpegQuality ?? this.ffmpegQuality,
    );
  }
}

// Notifier for settings
class SettingsNotifier extends StateNotifier<SettingsState> {
  final PreferencesService _prefsService;
  final HiveService _hiveService;

  SettingsNotifier(this._prefsService, this._hiveService)
      : super(SettingsState(
          preferredQuality: _prefsService.preferredQuality,
          themeMode: _prefsService.themeMode,
          autoDownload: _prefsService.autoDownload,
          maxConcurrentDownloads: _prefsService.maxConcurrentDownloads,
          downloadPath: _prefsService.downloadPath,
          shouldShowDisclaimer: _prefsService.shouldShowDisclaimer,
          useFFmpeg: _prefsService.useFFmpeg,
          ffmpegQuality: _prefsService.ffmpegQuality,
        ));

  Future<void> setPreferredQuality(String quality) async {
    await _prefsService.setPreferredQuality(quality);
    state = state.copyWith(preferredQuality: quality);
  }

  Future<void> setThemeMode(String mode) async {
    await _prefsService.setThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setAutoDownload(bool value) async {
    await _prefsService.setAutoDownload(value);
    state = state.copyWith(autoDownload: value);
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    await _prefsService.setMaxConcurrentDownloads(value);
    state = state.copyWith(maxConcurrentDownloads: value);
  }

  Future<void> setDownloadPath(String path) async {
    await _prefsService.setDownloadPath(path);
    state = state.copyWith(downloadPath: path);
  }

  Future<void> setShowDisclaimer(bool value) async {
    await _prefsService.setShowDisclaimer(value);
    state = state.copyWith(shouldShowDisclaimer: value);
  }

  Future<void> setUseFFmpeg(bool value) async {
    await _prefsService.setUseFFmpeg(value);
    state = state.copyWith(useFFmpeg: value);
  }

  Future<void> setFFmpegQuality(String quality) async {
    await _prefsService.setFFmpegQuality(quality);
    state = state.copyWith(ffmpegQuality: quality);
  }

  Future<void> clearCache() async {
    await _hiveService.clearAllCache();
  }

  Future<void> clearExpiredCache() async {
    await _hiveService.clearExpiredCache();
  }

  Future<int> getCacheSize() async {
    return await _hiveService.getCacheSizeInBytes();
  }

  Future<void> resetSettings() async {
    await _prefsService.clearAll();
    state = SettingsState(
      preferredQuality: '720',
      themeMode: 'system',
      autoDownload: false,
      maxConcurrentDownloads: 2,
      downloadPath: null,
      shouldShowDisclaimer: true,
      useFFmpeg: true,
      ffmpegQuality: 'fast',
    );
  }
}

// Provider for settings
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final prefsService = ref.watch(preferencesServiceProvider);
  final hiveService = ref.watch(hiveServiceProvider);
  return SettingsNotifier(prefsService, hiveService);
});

