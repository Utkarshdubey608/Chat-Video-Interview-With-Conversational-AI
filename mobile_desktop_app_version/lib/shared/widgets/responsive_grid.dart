// lib/shared/widgets/responsive_grid.dart
//
// A LayoutBuilder + Wrap grid that fits as many tiles as the available width
// allows (clamped between [minPerRow] and [maxPerRow]), each tile getting an
// equal share of the width. Promoted out of analytics_page.dart's private
// `_ResponsiveGrid` so the same behavior is available to every desktop
// dashboard/card grid instead of re-implementing it per page.

import 'package:flutter/material.dart';

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double tileMinWidth;
  final double spacing;
  final int minPerRow;
  final int maxPerRow;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.tileMinWidth = 170,
    this.spacing = 12,
    this.minPerRow = 2,
    this.maxPerRow = 5,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        var perRow = (maxW / tileMinWidth).floor();
        if (perRow < minPerRow) perRow = minPerRow;
        if (perRow > maxPerRow) perRow = maxPerRow;
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
