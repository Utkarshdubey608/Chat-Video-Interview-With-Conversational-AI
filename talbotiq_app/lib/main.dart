// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_store.dart';
import 'core/theme/app_theme.dart';
import 'views/main_layout.dart';
import 'views/setup_page.dart';
import 'views/interview_page.dart';
import 'views/results_page.dart';
import 'views/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.loadFromPrefs();
  runApp(
    ChangeNotifierProvider.value(
      value: store,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalbotIQ AI Screenings',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to Dark mode matching premium React look
      home: const MainLayout(),
    );
  }
}
