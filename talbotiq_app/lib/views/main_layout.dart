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

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

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
      case '/setup': return 0;
      case '/interview': return 1;
      case '/results': return 2;
      case '/settings': return 3;
      default: return 0;
    }
  }

  void _goHome(BuildContext context, bool isRecruiter, AppStore store, RecruiterStore recruiter) {
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(0);
    } else {
      _handleNavigate(context, '/setup', store);
    }
  }

  void _goSettings(BuildContext context, bool isRecruiter, AppStore store, RecruiterStore recruiter) {
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(3);
    } else {
      _handleNavigate(context, '/settings', store);
    }
  }

  void _onTabSelected(BuildContext context, int index, bool isRecruiter, AppStore store, RecruiterStore recruiter) {
    if (isRecruiter) {
      recruiter.setRecruiterTabIndex(index);
    } else {
      const routes = ['/setup', '/interview', '/results', '/settings'];
      _handleNavigate(context, routes[index], store);
    }
  }

  void _switchPlatform(BuildContext context, bool toRecruiter, AppStore store, RecruiterStore recruiter) {
    if (toRecruiter) {
      recruiter.setSlot0Feature(FeatureSlot.recruiter);
      recruiter.setRecruiterTabIndex(0);
    } else {
      recruiter.setSlot0Feature(FeatureSlot.videoInterview);
      store.navigateTo('/setup');
    }
  }

  Widget _navPill(BuildContext context, String label, IconData icon, bool isActive, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primaryContainer.withOpacity(0.4) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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

    final int selectedIndex = isRecruiter ? recruiter.recruiterTabIndex : _getCurrentIndex(store.currentRoute);

    final List<Widget> pages = isRecruiter
        ? const [SessionsPage(), TemplatesPage(), QuestionSetsPage(), SettingsPage()]
        : const [SetupPage(), InterviewPage(), ResultsPage(), SettingsPage()];

    final List<String> navLabels = isRecruiter
        ? ['Sessions', 'Templates', 'Question Sets', 'Settings']
        : ['Setup', 'Interview', 'Results', 'Settings'];
    final List<IconData> navIcons = isRecruiter
        ? [Icons.dashboard_outlined, Icons.dashboard_customize_outlined, Icons.library_books_outlined, Icons.settings_outlined]
        : [Icons.tune_rounded, Icons.video_call_outlined, Icons.analytics_outlined, Icons.settings_outlined];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isMobile ? 64 : 72),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.4),
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
                InkWell(
                  onTap: () => _goHome(context, isRecruiter, store, recruiter),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: [
 
                          const SizedBox(width: 10),
                          Text(
                            'TalbotIQ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                    
                      ],
                    ),
                  ),
                ),
                if (!isMobile)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < navLabels.length; i++)
                          _navPill(
                            context,
                            navLabels[i],
                            navIcons[i],
                            selectedIndex == i,
                            () => _onTabSelected(context, i, isRecruiter, store, recruiter),
                          ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                Row(
                  children: [
                    if (store.interviewActive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (store.tavusKey.isEmpty) ...[
                      OutlinedButton(
                        onPressed: () => _goSettings(context, isRecruiter, store, recruiter),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.amber.withOpacity(0.05),
                          side: BorderSide(color: Colors.amber.withOpacity(0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          isMobile ? 'Key Required' : 'Add API Key →',
                          style: TextStyle(
                            color: theme.brightness == Brightness.dark ? Colors.amber.shade300 : Colors.amber.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    _PlatformToggle(
                      isRecruiter: isRecruiter,
                      compact: isMobile,
                      onSelect: (toRecruiter) => _switchPlatform(context, toRecruiter, store, recruiter),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: isMobile
          ? FloatingBottomNavBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => _onTabSelected(context, index, isRecruiter, store, recruiter),
              labels: navLabels,
              icons: navIcons,
            )
          : null,
      body: FadeIndexedStack(
        index: selectedIndex,
        children: pages,
      ),
    );
  }
}

class _PlatformToggle extends StatelessWidget {
  final bool isRecruiter;
  final bool compact;
  final ValueChanged<bool> onSelect;

  const _PlatformToggle({
    required this.isRecruiter,
    required this.compact,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(theme, Icons.videocam_rounded, 'Interview', !isRecruiter, () => onSelect(false)),
          _segment(theme, Icons.work_outline_rounded, 'Recruiter', isRecruiter, () => onSelect(true)),
        ],
      ),
    );
  }

  Widget _segment(ThemeData theme, IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class FloatingBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final List<String> labels;
  final List<IconData> icons;

  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.labels,
    required this.icons,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        height: 64,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
         
        ),
        child: Row(
          children: List.generate(4, (index) {
            final bool isActive = selectedIndex == index;
            return Expanded(
              child: InkWell(
                onTap: () => onDestinationSelected(index),
                // Completely strips out native ink splashes/borders around items
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Colors.transparent, // Ensures no hidden backgrounds create box shapes
                      ),
                      child: Icon(
                        icons[index],
                        color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger cross-fades clean when moving tabs or changing platform architecture sets
    if (oldWidget.index != widget.index || oldWidget.children != widget.children) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}