// lib/views/main_layout.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_store.dart';
import '../widgets/custom_buttons.dart';
import '../core/services/tavus_service.dart';
import '../features/recruiter/store/recruiter_store.dart';
import '../features/recruiter/views/sessions_page.dart';
import '../features/recruiter/views/templates_page.dart';
import '../features/recruiter/views/question_sets_page.dart';
import 'setup_page.dart';
import 'interview_page.dart';
import 'results_page.dart';
import 'settings_page.dart';

/// The app shell. The bottom navigation is DYNAMIC per active platform:
///
///   Video Interview:   [ Video Interview ▾ ] [ Interview ] [ Results ] [ Settings ]
///   Recruiter Platform:[ Recruiter Platform ▾ ] [ Templates ] [ Question Sets ] [ Settings ]
///
/// Tab 0 is the platform switcher AND the platform's home. The video flow is
/// unchanged — tab 0 is the original SetupPage, and its `navigateTo('/interview')`
/// still selects the Interview tab (index 1). The active platform is persisted
/// in RecruiterStore.
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  // ── Video-flow navigation (protected — behavior preserved verbatim) ───────
  void _handleNavigate(BuildContext context, String targetRoute, AppStore store) {
    if (store.interviewActive && store.currentRoute == '/interview' && targetRoute != '/interview') {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Leave Interview?'),
            content: const Text(
              'Leaving this page will disconnect the active video session. '
              'Are you sure you want to leave and end the interview?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ),
              CustomButton(
                text: 'Leave & End',
                variant: ButtonVariant.danger,
                onPressed: () async {
                  Navigator.pop(context);
                  store.setInterviewActive(false);
                  if (store.currentConversation != null && store.currentConversation!.conversationUrl.isNotEmpty) {
                    try {
                      await tavusService.endConversation(store.currentConversation!.conversationId);
                    } catch (e) {
                      debugPrint('Tavus end conversation error: $e');
                    }
                  }
                  store.navigateTo(targetRoute);
                },
              ),
            ],
          );
        },
      );
    } else {
      store.navigateTo(targetRoute);
    }
  }

  int _getCurrentIndex(String route) {
    switch (route) {
      case '/setup':
        return 0;
      case '/interview':
        return 1;
      case '/results':
        return 2;
      case '/settings':
        return 3;
      default:
        return 0;
    }
  }

  // ── Platform switching ────────────────────────────────────────────────────
  void _goHome(BuildContext context, bool isRecruiter, AppStore store,
      RecruiterStore recruiter) {
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(0);
    } else {
      _handleNavigate(context, '/setup', store);
    }
  }

  void _goSettings(BuildContext context, bool isRecruiter, AppStore store,
      RecruiterStore recruiter) {
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(3);
    } else {
      _handleNavigate(context, '/settings', store);
    }
  }

  void _onTabSelected(BuildContext context, int index, bool isRecruiter,
      AppStore store, RecruiterStore recruiter) {
    if (index == 0) {
      _openPlatformSelector(context, store, recruiter);
      return;
    }
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(index);
    } else {
      const routes = ['/setup', '/interview', '/results', '/settings'];
      _handleNavigate(context, routes[index], store);
    }
  }

  void _openPlatformSelector(
      BuildContext context, AppStore store, RecruiterStore recruiter) {
    final isRecruiter = recruiter.slot0Feature == FeatureSlot.recruiter;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Switch platform',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              _PlatformOption(
                icon: Icons.videocam,
                title: 'Video Interview',
                subtitle: 'Live AI avatar screening',
                selected: !isRecruiter,
                onTap: () {
                  Navigator.pop(ctx);
                  recruiter.setSlot0Feature(FeatureSlot.videoInterview);
                  store.navigateTo('/setup');
                },
              ),
              _PlatformOption(
                icon: Icons.work_outline,
                title: 'Recruiter Platform',
                subtitle: 'Sessions, templates & question sets',
                selected: isRecruiter,
                onTap: () {
                  Navigator.pop(ctx);
                  recruiter.setSlot0Feature(FeatureSlot.recruiter);
                  recruiter.setRecruiterTabIndex(0);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Desktop pill (matches original visual language) ───────────────────────
  Widget _navPill(BuildContext context, String label, bool isActive,
      VoidCallback onTap) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 48,
      alignment: Alignment.center,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);
    final recruiter = Provider.of<RecruiterStore>(context);
    final bool isRecruiter = recruiter.slot0Feature == FeatureSlot.recruiter;
    final double width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 800;

    final int selectedIndex = isRecruiter
        ? recruiter.recruiterTabIndex
        : _getCurrentIndex(store.currentRoute);

    // IndexedStack children per active platform. Tab 3 (Settings) is shared.
    final List<Widget> pages = isRecruiter
        ? const [
            SessionsPage(),
            TemplatesPage(),
            QuestionSetsPage(),
            SettingsPage(),
          ]
        : const [
            SetupPage(),
            InterviewPage(),
            ResultsPage(),
            SettingsPage(),
          ];

    final String platformLabel =
        isRecruiter ? 'Recruiter Platform' : 'Video Interview';

    // Labels for tabs 1-3 differ per platform; tab 0 is the platform switcher.
    final List<String> tailLabels = isRecruiter
        ? ['Templates', 'Question Sets', 'Settings']
        : ['Interview', 'Results', 'Settings'];
    final List<IconData> tailIcons = isRecruiter
        ? [Icons.dashboard_customize, Icons.library_books, Icons.settings]
        : [Icons.video_call, Icons.analytics, Icons.settings];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isMobile ? 64 : 80),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
          alignment: Alignment.center,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Brand Logo wordmark → platform home
                InkWell(
                  onTap: () => _goHome(context, isRecruiter, store, recruiter),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.transparent,
                          backgroundImage: AssetImage('assets/logo.jpg'),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'TalbotIQ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Nav Links pills row (desktop only) — mirrors the dynamic tabs.
                if (!isMobile)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _navPill(context, '$platformLabel ▾', selectedIndex == 0,
                            () => _openPlatformSelector(context, store, recruiter)),
                        for (int i = 0; i < tailLabels.length; i++)
                          _navPill(context, tailLabels[i], selectedIndex == i + 1,
                              () => _onTabSelected(context, i + 1, isRecruiter,
                                  store, recruiter)),
                      ],
                    ),
                  )
                else
                  const Spacer(),

                // Right stats
                Row(
                  children: [
                    if (store.interviewActive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.1),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    if (store.tavusKey.isEmpty) ...[
                      OutlinedButton(
                        onPressed: () =>
                            _goSettings(context, isRecruiter, store, recruiter),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.amber.shade900.withValues(alpha: 0.08),
                          side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(
                          isMobile ? 'Key Required' : 'Add API Key →',
                          style: TextStyle(
                            color: theme.brightness == Brightness.dark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // Profile avatar initial circle
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'TE',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => _onTabSelected(
                  context, index, isRecruiter, store, recruiter),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.swap_horiz),
                  label: '$platformLabel ▾',
                ),
                NavigationDestination(icon: Icon(tailIcons[0]), label: tailLabels[0]),
                NavigationDestination(icon: Icon(tailIcons[1]), label: tailLabels[1]),
                NavigationDestination(icon: Icon(tailIcons[2]), label: tailLabels[2]),
              ],
            )
          : null,
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
    );
  }
}

class _PlatformOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PlatformOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant),
      title: Text(title,
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? theme.colorScheme.primary : null)),
      subtitle: Text(subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
