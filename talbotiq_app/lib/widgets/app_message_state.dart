// lib/widgets/app_message_state.dart
//
// Shared centered "empty / message" state: an icon, a title, and a subtitle,
// centered with consistent spacing. Used by the candidate + recruiter home
// screens and analytics for empty/error placeholders, so the identical
// composition isn't re-declared per screen.

import 'package:flutter/material.dart';

class AppMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const AppMessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
