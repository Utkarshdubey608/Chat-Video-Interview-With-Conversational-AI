// lib/shared/widgets/desktop_top_nav.dart
//
// Horizontal top navigation bar for the desktop recruiter shell, replacing
// the vertical NavigationRail sidebar on desktop only (AdaptiveNavScaffold
// — the sidebar rail — is untouched and still used for candidate/mobile/web
// navigation; this is a new, additive widget, not a modification of that
// one). Generic over its item list/selection so it isn't recruiter-specific
// itself; the recruiter-specific pieces (which items, the profile menu
// contents) are supplied by the caller.

import 'package:flutter/material.dart';
import 'package:talbotiq/core/theme/desktop_tokens.dart';
import 'package:talbotiq/shared/widgets/talbotiq_wordmark.dart';

class DesktopTopNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const DesktopTopNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

class DesktopTopNav extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<DesktopTopNavItem> items;

  /// The profile/avatar area on the right. Rendered as-is — this widget
  /// makes no assumption about what it contains beyond "goes on the right".
  final Widget trailing;

  const DesktopTopNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
    required this.trailing,
  });

  @override
  Size get preferredSize => const Size.fromHeight(DesktopTokens.topNavHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: DesktopTokens.topNavHeight,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 28),
          const TalbotiqWordmark(),
          const SizedBox(width: 40),
          for (var i = 0; i < items.length; i++)
            _NavTab(
              item: items[i],
              selected: i == currentIndex,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          trailing,
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  final DesktopTopNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({required this.item, required this.selected, required this.onTap});

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;

    final fg = selected
        ? scheme.primary
        : (_hovering ? scheme.onSurface : scheme.onSurfaceVariant);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _hovering && !selected
                      ? scheme.onSurface.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? (widget.item.activeIcon ?? widget.item.icon) : widget.item.icon,
                      size: 18,
                      color: fg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.item.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 2,
                width: selected ? 22 : 0,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
