// lib/shared/widgets/desktop_card.dart
//
// The base surface for the desktop redesign's cards/panels: subtle border,
// low-contrast fill, tighter radius than the app's global CardTheme (which
// stays as-is for mobile/candidate screens — see DesktopTokens.cardRadius).
// Optional [title]/[trailing] give it the "clear title, clear metric
// hierarchy" header the design calls for without every caller re-building
// the same Row.

import 'package:flutter/material.dart';
import 'package:talbotiq/core/theme/desktop_tokens.dart';

class DesktopCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const DesktopCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(DesktopTokens.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}
