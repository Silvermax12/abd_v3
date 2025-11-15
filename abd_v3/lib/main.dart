import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage/hive_service.dart';
import 'storage/preferences_service.dart';
import 'services/download_manager.dart';
import 'services/cookie_manager_service.dart';
import 'providers/settings_provider.dart';
import 'pages/anime_search_page.dart';
import 'pages/downloads_page.dart';
import 'pages/settings_page.dart';
import 'widgets/disclaimer_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await _initializeServices();

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _initializeServices() async {
  try {
    // Initialize Hive
    await HiveService.instance.initialize();

    // Initialize SharedPreferences
    await PreferencesService.instance.initialize();

    // Initialize CookieManager (for API session)
    await CookieManagerService.instance.initialize();

    // Initialize DownloadManager
    await DownloadManager.instance.initialize();

    // Request permissions
    await _requestPermissions();
  } catch (e) {
    debugPrint('Error initializing services: $e');
  }
}

Future<void> _requestPermissions() async {
  // Request storage permissions
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }

  // For Android 13+ (API level 33+)
  if (await Permission.videos.isDenied) {
    await Permission.videos.request();
  }

  if (await Permission.manageExternalStorage.isDenied) {
    await Permission.manageExternalStorage.request();
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Anime Batch Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: _getThemeMode(settings.themeMode),
      home: const MainScreen(),
      routes: {
        '/downloads': (context) => const DownloadsPage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }

  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    AnimeSearchPage(),
    DownloadsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Show disclaimer on first launch
    Future.microtask(() {
      final settings = ref.read(settingsProvider);
      if (settings.shouldShowDisclaimer) {
        _showDisclaimer();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause/Resume cookie manager to save memory
    if (state == AppLifecycleState.paused) {
      CookieManagerService.instance.pause();
    } else if (state == AppLifecycleState.resumed) {
      CookieManagerService.instance.resume();
    }
  }

  void _showDisclaimer() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => DisclaimerDialog(
            onAccept: () {
              ref.read(settingsProvider.notifier).setShowDisclaimer(false);
              Navigator.pop(context);
            },
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
