import 'package:flutter/material.dart';

/// Panel displaying communication, confidence, stress management, etc. dimension metrics.
class DimensionScoresPanel extends StatelessWidget {
  final int overallScore;
  final int fillers;

  const DimensionScoresPanel({
    super.key,
    required this.overallScore,
    required this.fillers,
  });

  /// Helper to map integer scores to corresponding theme indicator colors.
  Color _getScoreColor(BuildContext context, int score) {
    final theme = Theme.of(context);
    if (score >= 85) return theme.colorScheme.primary;
    if (score >= 70) return theme.colorScheme.secondary;
    return theme.colorScheme.error;
  }

  /// Individual horizontal progress row for a dimension score.
  Widget _buildDimensionProgress(
    BuildContext context,
    String label,
    int score,
  ) {
    final theme = Theme.of(context);
    final color = _getScoreColor(context, score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (score / 100.0).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dimension Scores',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildDimensionProgress(
              context,
              'Communication',
              overallScore,
            ),
            _buildDimensionProgress(
              context,
              'Confidence',
              overallScore + 4,
            ),
            _buildDimensionProgress(
              context,
              'Engagement',
              overallScore - 2,
            ),
            _buildDimensionProgress(
              context,
              'Vocabulary',
              75,
            ),
            _buildDimensionProgress(
              context,
              'Stress Mgmt',
              overallScore + 2,
            ),
            _buildDimensionProgress(
              context,
              'Articulation',
              (100 - fillers * 5).clamp(40, 100),
            ),
          ],
        ),
      ),
    );
  }
}
