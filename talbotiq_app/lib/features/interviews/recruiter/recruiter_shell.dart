// lib/features/interviews/recruiter/recruiter_shell.dart
//
// Recruiter primary-navigation shell. Hosts the recruiter's top-level
// destinations (Home, Analytics, Settings) in an IndexedStack — so each keeps
// its state while switching — and overlays the shared FloatingNavBar. The
// individual pages keep their own app bars (title + Logout); this shell owns
// only the navigation chrome.

import 'package:flutter/material.dart';

import 'package:talbotiq/shared/widgets/floating_nav_bar.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/settings/settings_page.dart';
import 'package:talbotiq/features/recruiter/analytics/analytics_page.dart';
import 'package:talbotiq/features/interviews/recruiter/recruiter_home.dart';

class RecruiterShell extends StatefulWidget {
  const RecruiterShell({super.key});

  @override
  State<RecruiterShell> createState() => _RecruiterShellState();
}

class _RecruiterShellState extends State<RecruiterShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: IndexedStack(
        index: _index,
        children: const [
          RecruiterHome(),
          AnalyticsPage(),
          _RecruiterSettingsTab(),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
        items: const [
          FloatingNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home'),
          FloatingNavItem(
              icon: Icons.analytics_outlined,
              activeIcon: Icons.analytics_rounded,
              label: 'Analytics'),
          FloatingNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: 'Settings'),
        ],
      ),
    );
  }
}

/// Wraps the shared [SettingsPage] (which has no app bar of its own) with a
/// titled bar + Logout, and enables the recruiter-only cloud-sync card.
class _RecruiterSettingsTab extends StatelessWidget {
  const _RecruiterSettingsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [LogoutButton(), SizedBox(width: 4)],
      ),
      body: const SettingsPage(showCloudSync: true),
    );
  }
}
