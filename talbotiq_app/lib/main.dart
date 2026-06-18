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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppStore(),
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
      initialRoute: '/setup',
      onGenerateRoute: (RouteSettings settings) {
        Widget page;
        String routeName = settings.name ?? '/setup';

        switch (routeName) {
          case '/setup':
            page = const SetupPage();
            break;
          case '/interview':
            page = const InterviewPage();
            break;
          case '/results':
            page = const ResultsPage();
            break;
          case '/settings':
            page = const SettingsPage();
            break;
          default:
            page = const SetupPage();
            routeName = '/setup';
        }

        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MainLayout(
            currentRoute: routeName,
            child: page,
          ),
          transitionDuration: Duration.zero, // Fast switch to match SPA web feel
        );
      },
    );
  }
}
