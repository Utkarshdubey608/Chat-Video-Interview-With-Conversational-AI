// lib/features/interviews/candidate/candidate_shell.dart
//
// Candidate primary-navigation shell. Mirrors RecruiterShell: hosts the
// candidate's top-level destinations (Home, Practice, Settings) in an
// IndexedStack and overlays the shared FloatingNavBar. The candidate Settings
// tab never exposes cloud key-sync (that is a recruiter-only action).

import 'package:flutter/material.dart';

import 'package:talbotiq/shared/widgets/floating_nav_bar.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/settings/settings_page.dart';
import 'package:talbotiq/features/interviews/candidate/candidate_home.dart';
import 'package:talbotiq/features/interviews/candidate/practice_page.dart';

class CandidateShell extends StatefulWidget {
  const CandidateShell({super.key});

  @override
  State<CandidateShell> createState() => _CandidateShellState();
}

class _CandidateShellState extends State<CandidateShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: IndexedStack(
        index: _index,
        children: const [
          CandidateHome(),
          PracticePage(),
          _CandidateSettingsTab(),
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
              icon: Icons.smart_toy_outlined,
              activeIcon: Icons.smart_toy,
              label: 'Practice'),
          FloatingNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: 'Settings'),
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
      body: const SettingsPage(),
    );
  }
}
