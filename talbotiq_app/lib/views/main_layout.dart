// lib/views/main_layout.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/colors.dart';
import '../providers/app_store.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  Widget _buildNavLink(BuildContext context, String label, String route) {
    final bool isActive = currentRoute == route;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () {
          if (!isActive) {
            Navigator.pushReplacementNamed(context, route);
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : AppColors.textMuted,
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
    final store = Provider.of<AppStore>(context);
    final double width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 800;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isMobile ? 64 : 80),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundDarker,
            border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1.0)),
          ),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
          alignment: Alignment.center,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Brand Logo wordmark
                InkWell(
                  onTap: () => Navigator.pushReplacementNamed(context, '/setup'),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.eco, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TalbotIQ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Nav Links pills row (only on desktop)
                if (!isMobile)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNavLink(context, 'Setup', '/setup'),
                        _buildNavLink(context, 'Interview', '/interview'),
                        _buildNavLink(context, 'Results', '/results'),
                        _buildNavLink(context, 'Settings', '/settings'),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
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
                        onPressed: () => Navigator.pushReplacementNamed(context, '/settings'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.amber.shade900.withOpacity(0.1),
                          side: BorderSide(color: Colors.amber.shade700.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(
                          isMobile ? 'Key Required' : 'Add API Key →',
                          style: TextStyle(color: Colors.amber.shade400, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Profile avatar initial circle
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'SN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
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
          ? BottomNavigationBar(
              backgroundColor: AppColors.backgroundDarker,
              selectedItemColor: AppColors.accent,
              unselectedItemColor: AppColors.textMuted,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              type: BottomNavigationBarType.fixed,
              currentIndex: _getCurrentIndex(currentRoute),
              onTap: (index) {
                final routes = ['/setup', '/interview', '/results', '/settings'];
                Navigator.pushReplacementNamed(context, routes[index]);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Setup'),
                BottomNavigationBarItem(icon: Icon(Icons.video_call), label: 'Interview'),
                BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Results'),
                BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
              ],
            )
          : null,
      body: child,
    );
  }
}
