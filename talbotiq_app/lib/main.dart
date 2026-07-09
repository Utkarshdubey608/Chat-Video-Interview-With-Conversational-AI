// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_store.dart';
import 'features/recruiter/store/recruiter_store.dart';
import 'features/recruiter/services/recruiter_gemini_service.dart';
import 'core/theme/app_theme.dart';
import 'views/main_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.loadFromPrefs();

  // Recruiter module state — separate store, own SharedPreferences key, so it
  // stays fully isolated from the protected video-interview AppStore.
  final recruiterStore = RecruiterStore();
  await recruiterStore.load();

  // The recruiter module reuses the app's existing Gemini key (read-only) for
  // scoring; keep it in sync when the user edits it in Settings.
  recruiterGeminiService.setKey(store.geminiKey);
  store.addListener(() => recruiterGeminiService.setKey(store.geminiKey));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: recruiterStore),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<AppStore>(context);
    return MaterialApp(
      title: 'TalbotIQ AI Screenings',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: store.themeMode,
      home: const MainLayout(),
    );
  }
}
