// lib/shared/widgets/section_header.dart
//
// Consistent "title (+ optional subtitle) with an optional trailing action"
// header, used at both the page level (e.g. "Analytics Overview") and the
// section level (e.g. "Interview Funnel") in the desktop redesign.

import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Page-level headers (28-32px per the design spec) vs. section-level
  /// headers (16-20px) inside a page — same widget, different scale.
  final bool isPageTitle;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.isPageTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = isPageTitle
        ? theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: titleStyle),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
