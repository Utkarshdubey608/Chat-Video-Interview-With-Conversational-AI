// lib/features/interviews/recruiter/widgets/recruiter_action_bar.dart
//
// The labelled action row that sits under a recruiter screen's app bar.
//
// Replaces the icon-only `AppBar.actions` these screens used to carry. Five
// unlabelled glyphs in a row asked a recruiter to remember which one published
// results and which one deleted the test — and both of those are irreversible.
// A label costs a little vertical space and removes the guess.
//
// Shared rather than copied per screen: the three visual states (available,
// unavailable, destructive) are the part worth getting right once.

import 'package:flutter/material.dart';

/// One action in a [RecruiterActionBar].
class RecruiterAction {
  final String label;
  final IconData icon;

  /// Null disables the action — it stays visible but greyed, so a recruiter can
  /// see it exists and is simply not available yet.
  final VoidCallback? onPressed;

  /// Tints the button with the error colour. For actions that destroy data.
  final bool destructive;

  const RecruiterAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });
}

class RecruiterActionBar extends StatelessWidget {
  /// In order of how often they are used, NOT how prominent they are. Put any
  /// destructive action last so it is never adjacent to the one meant instead.
  final List<RecruiterAction> actions;

  const RecruiterActionBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'ACTIONS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          // Wrap, not Row: on a narrow phone this reflows to a second line instead
          // of clipping the last button off the edge, which is how an action becomes
          // invisible.
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions) _ActionPill(action: action),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  final RecruiterAction action;
  const _ActionPill({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = action.onPressed != null;
    final accent = action.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final color = enabled ? accent : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: color.withValues(alpha: enabled ? 0.10 : 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: BorderSide(color: color.withValues(alpha: enabled ? 0.32 : 0.15)),
      ),
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(
                action.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}