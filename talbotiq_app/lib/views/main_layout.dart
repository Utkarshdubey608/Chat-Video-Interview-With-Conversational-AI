// lib/views/main_layout.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_store.dart';
import '../widgets/custom_buttons.dart';
import '../core/services/tavus_service.dart';
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

  Widget _buildNavLink(BuildContext context, String label, String route, AppStore store) {
    final theme = Theme.of(context);
    final String currentRoute = store.currentRoute;
    final bool isActive = currentRoute == route;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 48, // Standardised touch target height
      alignment: Alignment.center,
      child: InkWell(
        onTap: () {
          if (!isActive) {
            _handleNavigate(context, route, store);
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);
    final String currentRoute = store.currentRoute;
    final double width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 800;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isMobile ? 64 : 80),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.12),
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
                // Brand Logo wordmark
                InkWell(
                  onTap: () => _handleNavigate(context, '/setup', store),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.transparent,
                          backgroundImage: const AssetImage('assets/logo.jpg'),
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

                // Nav Links pills row (only on desktop)
                if (!isMobile)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNavLink(context, 'Setup', '/setup', store),
                        _buildNavLink(context, 'Interview', '/interview', store),
                        _buildNavLink(context, 'Results', '/results', store),
                        _buildNavLink(context, 'Settings', '/settings', store),
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
                          color: theme.colorScheme.error.withOpacity(0.1),
                          border: Border.all(
                            color: theme.colorScheme.error.withOpacity(0.3),
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
                        onPressed: () => _handleNavigate(context, '/settings', store),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.amber.shade900.withOpacity(0.08),
                          side: BorderSide(color: Colors.amber.shade700.withOpacity(0.3)),
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
                        color: theme.colorScheme.primary.withOpacity(0.12),
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
              selectedIndex: _getCurrentIndex(currentRoute),
              onDestinationSelected: (index) {
                final routes = ['/setup', '/interview', '/results', '/settings'];
                _handleNavigate(context, routes[index], store);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.tune), label: 'Setup'),
                NavigationDestination(icon: Icon(Icons.video_call), label: 'Interview'),
                NavigationDestination(icon: Icon(Icons.analytics), label: 'Results'),
                NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
              ],
            )
          : null,
      body: IndexedStack(
        index: _getCurrentIndex(currentRoute),
        children: const [
          SetupPage(),
          InterviewPage(),
          ResultsPage(),
          SettingsPage(),
        ],
      ),
    );
  }
}
