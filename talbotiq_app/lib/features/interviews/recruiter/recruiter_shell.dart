// lib/features/interviews/recruiter/recruiter_shell.dart
//
// Recruiter primary-navigation shell. Hosts the recruiter's top-level
// destinations in an IndexedStack — so each keeps its state while switching.
//
// Mobile/web: unchanged — the original 3 destinations (Home, Analytics,
// Settings) behind the shared AdaptiveNavScaffold (bottom bar on narrow
// windows, sidebar rail on wide ones, from the earlier desktop-enablement
// pass). Nothing in this file changes that code path.
//
// Desktop: a horizontal DesktopTopNav (Home, Library, Analytics, Settings)
// replaces the sidebar entirely, per the redesign brief. Each hosted page
// (RecruiterHome, AnalyticsPage, the Settings tab) renders without its own
// local AppBar when running under this top nav — the top nav's profile menu
// now owns the single Logout affordance — so there's exactly one bar of
// chrome, not two stacked. Each page still renders 100% its own existing
// body/state/logic; only the "do I show my own AppBar" decision is
// isDesktopPlatform-gated inside each of those files.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:talbotiq/core/theme/desktop_tokens.dart';
import 'package:talbotiq/core/utils/desktop_platform.dart';
import 'package:talbotiq/shared/widgets/adaptive_nav_scaffold.dart';
import 'package:talbotiq/shared/widgets/desktop_top_nav.dart';
import 'package:talbotiq/shared/widgets/floating_nav_bar.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/auth/app_role.dart';
import 'package:talbotiq/features/settings/settings_page.dart';
import 'package:talbotiq/features/recruiter/analytics/analytics_page.dart';
import 'package:talbotiq/features/recruiter/views/management/recruiter_library_page.dart';
import 'package:talbotiq/features/interviews/recruiter/recruiter_home.dart';

class RecruiterShell extends StatefulWidget {
  const RecruiterShell({super.key});

  @override
  State<RecruiterShell> createState() => _RecruiterShellState();
}

class _RecruiterShellState extends State<RecruiterShell> {
  int _index = 0;

  static const _mobileItems = [
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
  ];

  static const _mobilePages = [
    RecruiterHome(),
    AnalyticsPage(),
    _RecruiterSettingsTab(),
  ];

  static const _desktopNavItems = [
    DesktopTopNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    DesktopTopNavItem(
        icon: Icons.folder_special_outlined,
        activeIcon: Icons.folder_special,
        label: 'Library'),
    DesktopTopNavItem(
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics_rounded,
        label: 'Analytics'),
    DesktopTopNavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Settings'),
  ];

  static const _desktopPages = [
    RecruiterHome(),
    RecruiterLibraryPage(),
    AnalyticsPage(),
    _RecruiterSettingsTab(),
  ];

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
            currentIndex: _index,
            onSelect: (i) => setState(() => _index = i),
            items: _desktopNavItems,
            trailing: _RecruiterProfileMenu(
              onOpenSettings: () => setState(() => _index = 3),
            ),
          ),
          Expanded(child: IndexedStack(index: _index, children: _desktopPages)),
        ],
      ),
    );
  }
}

/// Avatar + email + role + dropdown (Settings, Sign out) for the top-right of
/// the desktop nav. Shows the account's email address — never the Firebase
/// `displayName` field, which recruiter accounts don't reliably set (e.g. a
/// Google-linked account may carry the provider name "Google" there instead
/// of anything the recruiter recognizes) — so the email is the one value
/// that's always correct and always theirs.
class _RecruiterProfileMenu extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _RecruiterProfileMenu({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    final label = email.isNotEmpty ? email : 'Recruiter';
    final initial = label.isNotEmpty ? label[0].toUpperCase() : 'R';

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, DesktopTokens.topNavHeight - 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesktopTokens.cardRadius),
      ),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            onOpenSettings();
            break;
          case 'signout':
            LogoutButton.signOut(context);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('Recruiter',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, size: 18),
            SizedBox(width: 10),
            Text('Settings'),
          ]),
        ),
        PopupMenuItem(
          value: 'signout',
          child: Row(children: [
            Icon(Icons.logout, size: 18, color: scheme.error),
            const SizedBox(width: 10),
            Text('Sign out', style: TextStyle(color: scheme.error)),
          ]),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary.withValues(alpha: 0.15),
            child: Text(initial,
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('Recruiter',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Wraps the shared [SettingsPage] (which has no app bar of its own).
/// Mobile/web keep a titled AppBar + Logout; desktop shows the settings
/// content directly — the top nav's profile menu already owns Logout there,
/// so a second one would be a duplicate affordance.
class _RecruiterSettingsTab extends StatelessWidget {
  const _RecruiterSettingsTab();

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return const SettingsPage(role: AppRole.recruiter);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [LogoutButton(), SizedBox(width: 4)],
      ),
      body: const SettingsPage(role: AppRole.recruiter),
    );
  }
}
