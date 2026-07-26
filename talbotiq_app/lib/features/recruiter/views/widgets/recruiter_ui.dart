// lib/features/recruiter/views/widgets/recruiter_ui.dart
//
// Small shared presentational helpers for the recruiter module, styled to
// match the app's design system (Card + 24px padding, Inter type, theme
// colors). Mirrors the web platform's PageHeader / EmptyState / Badge.

import 'package:flutter/material.dart';

class RecruiterPageHeader extends StatelessWidget {
  final String kicker;
  final String title;
  final String? subtitle;
  final Widget? action;

  const RecruiterPageHeader({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class RecruiterEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const RecruiterEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
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
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class RecruiterBadge extends StatelessWidget {
  final String text;
  final Color color;

  const RecruiterBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Maps a session status string to a theme-appropriate color.
Color statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case 'completed':
      return scheme.primary;
    case 'in_progress':
      return scheme.secondary;
    case 'system_check':
      return warningColor(context);
    case 'expired':
      return scheme.error;
    case 'created':
    default:
      return scheme.onSurfaceVariant;
  }
}

/// Theme-aware amber for "warning"/mid-band states.
///
/// A single hardcoded amber cannot serve both themes: the light shade used
/// previously (0xFFE4C270) only reaches ~3:1 contrast on the light theme's
/// white surfaces, so mid-band scores and warning banners read as washed out
/// there. Dark keeps the light amber; light mode drops to a deeper one.
Color warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE4C270)
        : const Color(0xFFB45309);

/// Shared 0-100 score → colour banding, so every surface that shows a score
/// (report page, history list, badges) agrees on the thresholds and stays
/// theme-correct in both modes.
Color scoreColor(BuildContext context, num score) {
  final scheme = Theme.of(context).colorScheme;
  if (score >= 75) return scheme.primary;
  if (score >= 55) return warningColor(context);
  return scheme.error;
}

/// The recruiter dashboard's standard content card.
///
/// This is the analytics page's panel treatment, promoted to a shared widget
/// so every recruiter surface matches: a translucent fill over the scaffold
/// (rather than an opaque card colour), a hairline border, generous radius,
/// and no elevation/shadow.
class RecruiterPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const RecruiterPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
    if (onTap == null) return decorated;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: decorated,
    );
  }
}

/// Section heading used between panels. Matches the analytics page: primary
/// colour, bold, with the 12px gap to its content supplied by the caller.
class RecruiterSectionTitle extends StatelessWidget {
  final String text;
  const RecruiterSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Compact metric tile: icon chip, label, large value, optional footnote.
class RecruiterStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? footnote;
  final Color? color;

  const RecruiterStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.footnote,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return RecruiterPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: c),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Wrap-based responsive tile grid: aims for ~[targetTileWidth] per tile and
/// clamps to 2-5 per row, so it degrades cleanly on phones and tablets
/// without a GridView's fixed aspect ratios.
class RecruiterResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double targetTileWidth;
  const RecruiterResponsiveGrid({
    super.key,
    required this.children,
    this.targetTileWidth = 170,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        var perRow = (maxW / targetTileWidth).floor();
        if (perRow < 2) perRow = 2;
        if (perRow > 5) perRow = 5;
        const spacing = 12.0;
        final tileW = (maxW - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in children) SizedBox(width: tileW, child: c),
          ],
        );
      },
    );
  }
}
