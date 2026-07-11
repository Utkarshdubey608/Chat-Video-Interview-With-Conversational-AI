import 'package:flutter/material.dart';

/// Wrapper grid layout that manages responsive column formatting
/// for statistical indicator cards.
class GridPaperResult extends StatelessWidget {
  final List<Widget> children;

  const GridPaperResult({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final crossCount = box.maxWidth > 750
            ? 4
            : (box.maxWidth > 480 ? 2 : 1);
        final double aspectRatio = box.maxWidth > 750
            ? 1.5
            : (box.maxWidth > 480 ? 1.8 : 3.0);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}

/// A stylized KPI statistical card container displaying specific metrics,
/// values, and corresponding metadata descriptions.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String subTitle;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subTitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
