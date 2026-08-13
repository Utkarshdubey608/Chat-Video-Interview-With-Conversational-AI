// lib/features/interviews/candidate/candidate_shell.dart
//
// Candidate primary-navigation shell.
//
// Mobile/web: unchanged — the original 4 destinations (Home, Practice,
// History, Settings) behind the shared AdaptiveNavScaffold (bottom bar on
// narrow windows, sidebar rail on wide ones). Nothing in this file changes
// that code path.
//
// Desktop: mirrors RecruiterShell's exact pattern — a horizontal
// DesktopTopNav (Home, Practice, History) replaces the sidebar, and Settings
// moves into the profile menu instead of being a fourth tab, so this is the
// same product family as the recruiter desktop shell. Each hosted page
// (CandidateHome, PracticePage, PracticeHistoryPage) renders without its own
// local AppBar on desktop — the top nav's profile menu owns the single
// Logout affordance — but still runs 100% its own existing body/state/logic;
// only the "do I show my own AppBar" decision is isDesktopPlatform-gated
// inside each of those files.

import 'package:flutter/material.dart';

import 'package:talbotiq/core/utils/desktop_platform.dart';
import 'package:talbotiq/shared/widgets/adaptive_nav_scaffold.dart';
import 'package:talbotiq/shared/widgets/desktop_profile_menu.dart';
import 'package:talbotiq/shared/widgets/desktop_top_nav.dart';
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

  static const _mobileItems = [
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

  static const _mobilePages = [
    CandidateHome(),
    PracticePage(),
    PracticeHistoryPage(),
    _CandidateSettingsTab(),
  ];

  static const _desktopNavItems = [
    DesktopTopNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    DesktopTopNavItem(
        icon: Icons.smart_toy_outlined, activeIcon: Icons.smart_toy, label: 'Practice'),
    DesktopTopNavItem(
        icon: Icons.history_outlined, activeIcon: Icons.history_rounded, label: 'History'),
  ];

  static const _desktopPages = [
    CandidateHome(),
    PracticePage(),
    PracticeHistoryPage(),
  ];

  // Settings is a top-nav tab on mobile but lives in the profile menu on
  // desktop (mirroring RecruiterShell) — same overlay-flag pattern, shown in
  // place of whichever tab was active.
  bool _settingsOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) {
      return AdaptiveNavScaffold(
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
        items: _mobileItems,
        body: IndexedStack(index: _index, children: _mobilePages),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          DesktopTopNav(
            // No tab is "active" while Settings is showing — see the
            // matching comment in RecruiterShell.
            currentIndex: _settingsOpen ? -1 : _index,
            onSelect: (i) => setState(() {
              _index = i;
              _settingsOpen = false;
            }),
            items: _desktopNavItems,
            trailing: DesktopProfileMenu(
              roleLabel: 'Candidate',
              onOpenSettings: () => setState(() => _settingsOpen = true),
            ),
          ),
          Expanded(
            child: _settingsOpen
                ? const _CandidateSettingsTab()
                : IndexedStack(index: _index, children: _desktopPages),
          ),
        ],
      ),
    );
  }
}

/// Wraps the shared [SettingsPage] with a titled bar + Logout for the
/// candidate. Mobile/web keep that AppBar; desktop shows the settings
/// content directly — the top nav's profile menu already owns Logout there,
/// so a second one would be a duplicate affordance (mirrors
/// RecruiterShell's `_RecruiterSettingsTab`).
class _CandidateSettingsTab extends StatelessWidget {
  const _CandidateSettingsTab();

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return const SettingsPage(role: AppRole.candidate);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [LogoutButton(), SizedBox(width: 4)],
      ),
      body: const SettingsPage(role: AppRole.candidate),
    );
  }
}
