// lib/main.dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:talbotiq/firebase_options.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';
import 'package:talbotiq/features/auth/auth_service.dart';
import 'package:talbotiq/features/app_config/app_config_service.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/core/deep_link/deep_link_service.dart';
import 'package:talbotiq/core/theme/app_theme.dart';
import 'package:talbotiq/features/app/splash_page.dart';

/// App-wide navigator key so the deep-link handler can drive navigation from
/// outside the widget tree (it lives for the whole app lifetime).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase powers auth + the recruiter→candidate interview assignments.
  // Requires `flutterfire configure` to generate firebase_options.dart; the
  // placeholder throws until then (see lib/firebase_options.dart).
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<InterviewRepository>(create: (_) => InterviewRepository()),
        Provider<AppConfigService>(create: (_) => AppConfigService()),
      ],
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
  final DeepLinkService _deepLinks = DeepLinkService();
  StreamSubscription<DeepLinkTarget>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  /// Wire both entry points:
  ///   - the cold-start link the app was launched with (getInitialTarget), and
  ///   - links that arrive while the app is already running (targetStream).
  /// Never throws: the service swallows platform errors and only emits valid,
  /// parsed targets, so a bad link can't break startup.
  Future<void> _initDeepLinks() async {
    _linkSub = _deepLinks.targetStream.listen(
      _handleTarget,
      onError: (Object e) => debugPrint('DeepLink stream error: $e'),
    );

    final initial = await _deepLinks.getInitialTarget();
    if (initial != null) _handleTarget(initial);
  }

  /// Parks the interview id for the candidate flow to consume after auth, then
  /// ensures the app is foregrounded on the home tree. We deliberately do NOT
  /// force-route to a candidate screen here: SplashPage → AuthGate already
  /// decides login vs. candidate/recruiter home based on auth + role. If the
  /// user is signed out, AuthGate shows login and the parked id persists until
  /// after sign-in (see PendingDeepLink consumption hook in candidate_home).
  void _handleTarget(DeepLinkTarget target) {
    PendingDeepLink.instance.set(target.interviewId);

    // Pop back to the root of the app so the AuthGate-driven home is visible.
    // Guarded: the navigator may not be mounted yet on a cold start (the
    // initial link is handled after the first frame in practice, but be safe).
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the theme mode drives MaterialApp; select on it so the whole app
    // tree doesn't rebuild on unrelated AppStore notifications (keys, session
    // config, integrity counters, etc.).
    final themeMode = context.select<AppStore, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'TalbotIQ AI Screenings',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashPage(),
    );
  }
}
