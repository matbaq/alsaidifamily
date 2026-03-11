import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'widgets/splash_screen.dart';
import 'screens/family_tree_page.dart';
import 'controllers/access_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AccessController(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;
  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        _isDarkMode = prefs.getBool('isDarkMode') ?? false;
        _themeLoaded = true;
      });
    } catch (e) {
      debugPrint('Theme load error: $e');
      if (!mounted) return;

      setState(() {
        _isDarkMode = false;
        _themeLoaded = true;
      });
    }
  }

  Future<void> _toggleTheme(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', value);
    } catch (e) {
      debugPrint('Theme save error: $e');
    }

    if (!mounted) return;
    setState(() {
      _isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'عائلة الصايدي',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1e3c72),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1e3c72),
          brightness: Brightness.dark,
        ),
      ),
      home: !_themeLoaded
          ? const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      )
          : SplashScreen(
        child: FamilyTreePage(
          isDarkMode: _isDarkMode,
          onThemeToggle: _toggleTheme,
        ),
      ),
    );
  }
}