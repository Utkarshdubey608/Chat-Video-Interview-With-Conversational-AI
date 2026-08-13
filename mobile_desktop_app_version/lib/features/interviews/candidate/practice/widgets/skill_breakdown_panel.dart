// lib/features/interviews/candidate/practice/widgets/skill_breakdown_panel.dart
//
// The five dimensions the scorecard actually measures, with the evidence behind
// each one.
//
// These are REAL values: `ATSScorecard.communicationScore` and friends are scored
// 1-10 by the analysis pass, each carrying an evidence summary and an explicit
// `cannotAssess` flag. That matters because the app's older
// `DimensionScoresPanel` renders derived numbers instead — communication = the
// overall score, confidence = overall + 4, vocabulary = a hardcoded 75 — which
// look measured but are not. Practising against invented feedback is worse than
// getting none, so this panel only ever shows what was assessed, and says so
// plainly when a dimension could not be.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/interviews/candidate/practice/practice_formatters.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'package:talbotiq/shared/models/app_models.dart';

class SkillBreakdownPanel extends StatelessWidget {
  const SkillBreakdownPanel({super.key, required this.scorecard});

  final ATSScorecard scorecard;

  /// Label → dimension, in the order a candidate most benefits from reading.
  List<(String, ScoredDimension)> get _dimensions => [
        ('Communication', scorecard.communicationScore),
        ('Problem solving', scorecard.problemSolvingScore),
        ('Technical depth', scorecard.technicalDepthScore),
        ('Engagement', scorecard.engagementScore),
        ('Consistency', scorecard.consistencyScore),
      ];

  @override
  Widget build(BuildContext context) {
    final assessed = _dimensions.where((d) => !d.$2.cannotAssess).toList();
    final skipped = _dimensions.where((d) => d.$2.cannotAssess).toList();

    return RecruiterPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < assessed.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            _DimensionRow(label: assessed[i].$1, dimension: assessed[i].$2),
          ],
          if (assessed.isNotEmpty && skipped.isNotEmpty)
            const SizedBox(height: 20),
          if (skipped.isNotEmpty) _NotAssessed(dimensions: skipped),
        ],
      ),
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({required this.label, required this.dimension});

  final String label;
  final ScoredDimension dimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = dimensionPercent(dimension.score);
    final colour = scoreColor(context, percent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${dimension.score}/10',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colour,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
        if (dimension.evidenceSummary.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            dimension.evidenceSummary.trim(),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        // "weak"/"insufficient" evidence means the score rests on very little.
        // Saying so stops a candidate over-reading a single number.
        if (_isThinEvidence) ...[
          const SizedBox(height: 6),
          Text(
            'Based on limited evidence — treat this as a rough signal.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  bool get _isThinEvidence {
    final level = dimension.evidenceLevel.trim().toLowerCase();
    return level == 'weak' || level == 'insufficient';
  }
}

class _NotAssessed extends StatelessWidget {
  const _NotAssessed({required this.dimensions});

  final List<(String, ScoredDimension)> dimensions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Not assessed',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (label, dimension) in dimensions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                dimension.cannotAssessReason?.trim().isNotEmpty == true
                    ? '$label — ${dimension.cannotAssessReason!.trim()}'
                    : '$label — not enough was said to judge this.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
