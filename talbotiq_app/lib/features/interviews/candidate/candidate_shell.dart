// lib/features/interviews/candidate/candidate_shell.dart
//
// Candidate primary-navigation shell. Mirrors RecruiterShell: hosts the
// candidate's top-level destinations (Home, Practice, History, Settings) in an
// IndexedStack and overlays the shared FloatingNavBar.

import 'package:flutter/material.dart';

import 'package:talbotiq/shared/widgets/adaptive_nav_scaffold.dart';
import 'package:talbotiq/shared/widgets/floating_nav_bar.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/auth/app_role.dart';
import 'package:talbotiq/features/settings/settings_page.dart';
import 'package:talbotiq/features/interviews/candidate/candidate_home.dart';
import 'package:talbotiq/features/interviews/candidate/practice_page.dart';
import 'package:talbotiq/features/interviews/candidate/practice_history_page.dart';

class CandidateShell extends StatefulWidget {
  const CandidateShell({super.key});

  @override
  State<CandidateShell> createState() => _CandidateShellState();
}

class _CandidateShellState extends State<CandidateShell> {
  int _index = 0;

  static const _items = [
    FloatingNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home'),
    FloatingNavItem(
        icon: Icons.smart_toy_outlined,
        activeIcon: Icons.smart_toy,
        label: 'Practice'),
    FloatingNavItem(
        icon: Icons.history_outlined,
        activeIcon: Icons.history_rounded,
        label: 'History'),
    FloatingNavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveNavScaffold(
      currentIndex: _index,
      onSelect: (i) => setState(() => _index = i),
      items: _items,
      body: IndexedStack(
        index: _index,
        children: const [
          CandidateHome(),
          PracticePage(),
          PracticeHistoryPage(),
          _CandidateSettingsTab(),
        ],
      ),
    );
  }
}

/// Wraps the shared [SettingsPage] with a titled bar + Logout for the candidate.
class _CandidateSettingsTab extends StatelessWidget {
  const _CandidateSettingsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [LogoutButton(), SizedBox(width: 4)],
      ),
      body: const SettingsPage(role: AppRole.candidate),
    );
  }
}
