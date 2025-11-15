# Anime Batch Downloader

A Flutter-based anime batch downloader that interacts with AnimePahe's public API to search, browse, and download anime episodes with quality selection and FFmpeg processing support.

## Features

✅ **Search & Browse**
- Search anime by name with cached results
- View detailed anime information
- Browse episode lists with lazy loading and pagination

✅ **Quality Selection**
- Multiple quality options (1080p, 720p, 480p, 360p)
- Audio and fansub information
- Automatic m3u8 link extraction

✅ **Download Management**
- Max 2 concurrent downloads (configurable)
- Pause, resume, and cancel support
- Real-time progress tracking with speed and ETA
- FFmpeg integration for video processing
- Queue management with automatic processing

✅ **Storage & Caching**
- Hive database for anime and episode caching
- SharedPreferences for user settings
- Automatic cache expiration (7 days)
- Manual cache clearing option

✅ **Modern UI**
- Material 3 design
- Dark and light theme support
- Responsive layouts
- Progress indicators and error handling

✅ **Cross-Platform**
- Android (API 21+)
- Windows Desktop

## Architecture

The app follows a clean architecture pattern with:

- **Models**: Data classes with Hive type adapters
- **Services**: API, web scraping, and download management
- **Providers**: Riverpod state management
- **Pages**: UI screens for search, episodes, downloads, and settings
- **Widgets**: Reusable components
- **Storage**: Hybrid caching (Hive + SharedPreferences)

### Key Components

| Component | Description |
|-----------|-------------|
| `AnimeApiService` | Handles API calls for searching and fetching episodes |
| `AnimeWebScraper` | Uses HeadlessInAppWebView to extract quality options and m3u8 links |
| `DownloadManager` | Manages concurrent downloads with FFmpeg processing |
| `HiveService` | Caching layer for anime and episode data |
| `PreferencesService` | User settings management |

## Technical Stack

- **Framework**: Flutter SDK 3.7+
- **State Management**: Riverpod 2.6+
- **Local Storage**: Hive 2.2+ & SharedPreferences 2.2+
- **Networking**: HTTP 1.1+ & Dio 5.4+
- **Web Scraping**: flutter_inappwebview 6.0+
- **Video Processing**: ffmpeg_kit_flutter 6.0+
- **Permissions**: permission_handler 11.0+

## Setup & Installation

### Prerequisites

- Flutter SDK 3.7.2 or higher
- Android SDK (API level 21+) for Android builds
- Visual Studio 2022 for Windows builds

### Installation Steps

1. **Clone the repository**
   ```bash
   cd abd_v3
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate Hive adapters**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   
   For Android:
   ```bash
   flutter run
   ```
   
   For Windows:
   ```bash
   flutter run -d windows
   ```

## Usage Flow

1. **Search Anime**
   - Enter anime name in the search bar
   - Browse results with posters and information
   - Tap to view episode list

2. **Select Episode**
   - Browse episodes with lazy loading
   - Tap an episode to view quality options
   - Load all episodes at once (optional)

3. **Choose Quality**
   - Select preferred resolution and audio
   - App extracts m3u8 link automatically
   - Download starts immediately

4. **Monitor Downloads**
   - View active, completed, and failed downloads
   - Track progress, speed, and ETA
   - Pause, resume, or cancel downloads

5. **Manage Settings**
   - Set preferred quality
   - Adjust concurrent downloads (1-3)
   - Configure FFmpeg settings
   - Clear cache

## Configuration

### Download Settings

- **Preferred Quality**: Default quality for downloads (360p - 1080p)
- **Max Concurrent Downloads**: Number of simultaneous downloads (1-3)
- **Use FFmpeg**: Enable/disable video re-encoding
- **FFmpeg Preset**: Quality vs speed tradeoff (ultrafast, fast, medium, slow)

### Storage

Default download location:
- **Android**: `/storage/emulated/0/Download/Animepahe Downloader/`
- **Windows**: `%USERPROFILE%\Downloads\Animepahe Downloader\`

Files are organized by anime title: `Anime Title/E01_720p.mp4`

## Performance

- **Memory Usage**: Stable under 2GB RAM
- **Caching**: Up to 100 anime and 500 episode entries
- **WebView**: Limited to 1 concurrent operation
- **Downloads**: Limited to 2 concurrent operations
- **Auto-cleanup**: WebView disposal after extraction

## Permissions (Android)

The app requests the following permissions:

- `INTERNET`: Network access for API calls
- `WRITE_EXTERNAL_STORAGE`: Save downloads (API ≤ 32)
- `READ_EXTERNAL_STORAGE`: Access downloads (API ≤ 32)
- `READ_MEDIA_VIDEO`: Access videos (API 33+)
- `MANAGE_EXTERNAL_STORAGE`: Extended storage access

## Error Handling

The app handles various error scenarios:

- Network timeouts (15s for API, 20s for WebView)
- Failed m3u8 extraction
- Storage permission denials
- Insufficient storage space
- Page load errors
- Download interruptions

## Legal Notice

⚠️ **Educational & Demo Use Only**

This application is provided for educational and demonstration purposes only. Users are solely responsible for how they use this tool. Please respect copyright laws and content creators' rights. Download only content you have rights to access.

## Contributing

This is a demonstration project showcasing Flutter development best practices including:

- Clean architecture
- State management with Riverpod
- Hybrid storage solutions
- Web scraping with headless browser
- Concurrent download management
- FFmpeg integration
- Material 3 UI/UX

## License

This project is provided for educational purposes. See LICENSE file for details.

## Troubleshooting

### Common Issues

**Build errors**
- Run `flutter clean` and `flutter pub get`
- Regenerate Hive adapters with build_runner

**M3U8 extraction fails**
- Check network connection
- Try different quality option
- Verify AnimePahe.si is accessible

**Downloads not starting**
- Check storage permissions
- Verify sufficient disk space
- Check concurrent download limit

**App crashes on Android**
- Verify minSdkVersion is 21+
- Check all permissions are granted
- Clear app data and cache

## Support

For issues, questions, or contributions, please refer to the project documentation or create an issue in the repository.

---

**Version**: 1.0.0  
**Platform**: Android (API 21+), Windows  
**Framework**: Flutter 3.7.2+
