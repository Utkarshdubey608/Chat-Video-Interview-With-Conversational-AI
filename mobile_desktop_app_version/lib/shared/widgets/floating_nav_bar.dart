// lib/shared/widgets/floating_nav_bar.dart
//
// A modern, theme-aware floating bottom navigation bar. It renders as a rounded
// "pill" that hovers above the scaffold background (margins + soft shadow), and
// each destination animates into an expanding icon+label pill when selected —
// matching the app's pill / circular design language (see AppColors + theme).
//
// Chrome-less and reusable: hand it a list of [FloatingNavItem]s, the current
// index and an onSelect callback. It carries no navigation logic of its own.

import 'dart:ui';
import 'package:flutter/material.dart';

/// One destination in a [FloatingNavBar].
class FloatingNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  const FloatingNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<FloatingNavItem> items;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 72, // Taller touch targets
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.85), // Theme-adaptive translucent background!
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _NavButton(
                        item: items[i],
                        selected: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // The selected destination needs room for its label, so it gets more of
    // the bar's width than the icon-only unselected destinations.
    return Expanded(
      flex: selected ? 3 : 2,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          highlightColor: cs.primary.withValues(alpha: 0.05),
          splashColor: cs.primary.withValues(alpha: 0.1),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn,
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 14 : 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      selected ? (item.activeIcon ?? item.icon) : item.icon,
                      color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6), // Theme-adaptive unselected color!
                      size: 22,
                    ),
                  ),
                  // Flexible + fade guards against overflow on narrow screens;
                  // the extra flex on the selected slot keeps it from ever
                  // actually clipping in practice.
                  Flexible(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.fastOutSlowIn,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
