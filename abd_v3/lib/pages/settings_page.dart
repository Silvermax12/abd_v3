import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Download Settings Section
          _buildSectionHeader('Download Settings'),
          _buildPreferredQualityTile(context, ref, settingsState),
          _buildMaxConcurrentDownloadsTile(context, ref, settingsState),
          _buildDownloadLocationTile(context, ref, settingsState),
          _buildFFmpegTile(context, ref, settingsState),
          if (settingsState.useFFmpeg)
            _buildFFmpegQualityTile(context, ref, settingsState),

          const Divider(),

          // Appearance Settings Section
          _buildSectionHeader('Appearance'),
          _buildThemeModeTile(context, ref, settingsState),

          const Divider(),

          // Storage Settings Section
          _buildSectionHeader('Storage & Cache'),
          _buildCacheInfoTile(context, ref),
          _buildClearCacheTile(context, ref),

          const Divider(),

          // About Section
          _buildSectionHeader('About'),
          _buildAboutTile(context),
          _buildResetSettingsTile(context, ref),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildPreferredQualityTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.high_quality),
      title: const Text('Preferred Quality'),
      subtitle: Text('${settings.preferredQuality}p'),
      onTap: () async {
        final quality = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select Preferred Quality'),
            children: ['1080', '720', '480', '360'].map((q) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(context, q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${q}p',
                    style: TextStyle(
                      fontWeight: q == settings.preferredQuality
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
        if (quality != null) {
          await ref.read(settingsProvider.notifier).setPreferredQuality(quality);
        }
      },
    );
  }

  Widget _buildMaxConcurrentDownloadsTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.cloud_download),
      title: const Text('Max Concurrent Downloads'),
      subtitle: Text('${settings.maxConcurrentDownloads} downloads at once'),
      onTap: () async {
        final value = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select Max Downloads'),
            children: [1, 2, 3].map((v) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(context, v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$v download${v > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontWeight: v == settings.maxConcurrentDownloads
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
        if (value != null) {
          await ref
              .read(settingsProvider.notifier)
              .setMaxConcurrentDownloads(value);
        }
      },
    );
  }

  Widget _buildDownloadLocationTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: const Text('Download Location'),
      subtitle: Text(settings.downloadPath ?? 'Default location'),
      onTap: () async {
        final selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select Download Directory',
          initialDirectory: settings.downloadPath,
        );

        if (selectedDirectory != null) {
          await ref.read(settingsProvider.notifier).setDownloadPath(selectedDirectory);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Download location set to: $selectedDirectory')),
            );
          }
        }
      },
      trailing: settings.downloadPath != null
          ? IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Reset to default',
              onPressed: () async {
                await ref.read(settingsProvider.notifier).setDownloadPath('');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Download location reset to default')),
                  );
                }
              },
            )
          : null,
    );
  }

  Widget _buildFFmpegTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.video_settings),
      title: const Text('Use FFmpeg'),
      subtitle: const Text('Re-encode and merge video segments'),
      value: settings.useFFmpeg,
      onChanged: (value) {
        ref.read(settingsProvider.notifier).setUseFFmpeg(value);
      },
    );
  }

  Widget _buildFFmpegQualityTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('FFmpeg Preset'),
      subtitle: Text(settings.ffmpegQuality.toUpperCase()),
      onTap: () async {
        final quality = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select FFmpeg Preset'),
            children: [
              'ultrafast',
              'fast',
              'medium',
              'slow',
            ].map((q) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(context, q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.toUpperCase(),
                        style: TextStyle(
                          fontWeight: q == settings.ffmpegQuality
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      Text(
                        _getFFmpegPresetDescription(q),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
        if (quality != null) {
          await ref.read(settingsProvider.notifier).setFFmpegQuality(quality);
        }
      },
    );
  }

  String _getFFmpegPresetDescription(String preset) {
    switch (preset) {
      case 'ultrafast':
        return 'Fastest, lower quality';
      case 'fast':
        return 'Fast, good quality (recommended)';
      case 'medium':
        return 'Balanced speed and quality';
      case 'slow':
        return 'Slower, best quality';
      default:
        return '';
    }
  }

  Widget _buildThemeModeTile(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.palette),
      title: const Text('Theme'),
      subtitle: Text(_getThemeModeLabel(settings.themeMode)),
      onTap: () async {
        final mode = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select Theme'),
            children: ['light', 'dark', 'system'].map((m) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(context, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _getThemeModeLabel(m),
                    style: TextStyle(
                      fontWeight:
                          m == settings.themeMode ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
        if (mode != null) {
          await ref.read(settingsProvider.notifier).setThemeMode(mode);
        }
      },
    );
  }

  String _getThemeModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      case 'system':
        return 'System Default';
      default:
        return mode;
    }
  }

  Widget _buildCacheInfoTile(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(settingsProvider.notifier).getCacheSize(),
      builder: (context, snapshot) {
        final sizeStr = snapshot.hasData
            ? _formatBytes(snapshot.data!)
            : 'Calculating...';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Cache Size'),
          subtitle: Text(sizeStr),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildClearCacheTile(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.delete_sweep, color: Colors.orange),
      title: const Text('Clear Cache'),
      subtitle: const Text('Remove cached anime and episode data'),
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Cache'),
            content: const Text(
              'This will clear all cached anime and episode data. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm == true && context.mounted) {
          await ref.read(settingsProvider.notifier).clearCache();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cache cleared')),
            );
          }
        }
      },
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info),
      title: const Text('About'),
      subtitle: const Text('Anime Batch Downloader v1.0.0'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: 'Anime Batch Downloader',
          applicationVersion: '1.0.0',
          applicationLegalese:
              '© 2024\n\nThis app is for educational and personal use only. Users are responsible for how they use this tool.',
        );
      },
    );
  }

  Widget _buildResetSettingsTile(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.restart_alt, color: Colors.red),
      title: const Text('Reset Settings'),
      subtitle: const Text('Restore all settings to default values'),
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reset Settings'),
            content: const Text(
              'This will reset all settings to their default values. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reset', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm == true && context.mounted) {
          await ref.read(settingsProvider.notifier).resetSettings();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings reset to defaults')),
            );
          }
        }
      },
    );
  }
}

