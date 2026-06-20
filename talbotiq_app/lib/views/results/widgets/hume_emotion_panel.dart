import 'package:flutter/material.dart';
import '../../../models/app_models.dart';
import '../../../widgets/response_widgets.dart';

/// Panel showcasing emotional intelligence insights powered by Hume AI prosody analytics.
class HumeEmotionPanel extends StatelessWidget {
  final HumeSessionResult? humeResult;
  final String humeKey;
  final String? humeJobId;
  final bool isMobile;

  const HumeEmotionPanel({
    super.key,
    required this.humeResult,
    required this.humeKey,
    required this.humeJobId,
    required this.isMobile,
  });

  /// Horizontal percentage indicator bar for Hume emotional categories.
  Widget _buildHumeCategoryRow(
    BuildContext context,
    String label,
    double val,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: val.clamp(0.0, 1.0),
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
          const SizedBox(width: 12),
          Text(
            '${(val * 100).round()}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  /// Individual question container summarizing dominant emotions and confidence score.
  Widget _buildQuestionDetails(
    BuildContext context,
    QuestionEmotionSummary q,
    int index,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.02),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dominant: ${q.dominant}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Confidence: ${(q.avgCategoryScores['positive_high']! * 100).round()}%',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentHumeResult = humeResult;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HUME AI · PROSODY ANALYSIS',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emotional Intelligence Report',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (currentHumeResult != null)
                SentimentArc(
                  score: currentHumeResult.compositeScore,
                  label: 'Emotion Score',
                ),
            ],
          ),
          const SizedBox(height: 24),

          if (currentHumeResult != null) ...[
            LayoutBuilder(
              builder: (context, radarBox) {
                final isWide = radarBox.maxWidth > 600;
                final radarWidget = SizedBox(
                  width: 260,
                  height: 260,
                  child: EmotionRadarChart(
                    categoryScores: currentHumeResult.overallCategoryScores,
                  ),
                );

                final breakdownWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category Breakdown',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildHumeCategoryRow(
                      context,
                      'High Positive',
                      currentHumeResult.overallCategoryScores['positive_high'] ?? 0.0,
                      theme.colorScheme.primary,
                    ),
                    _buildHumeCategoryRow(
                      context,
                      'Calm Positive',
                      currentHumeResult.overallCategoryScores['positive_calm'] ?? 0.0,
                      theme.colorScheme.primary,
                    ),
                    _buildHumeCategoryRow(
                      context,
                      'Cognitive',
                      currentHumeResult.overallCategoryScores['cognitive'] ?? 0.0,
                      theme.colorScheme.secondary,
                    ),
                    _buildHumeCategoryRow(
                      context,
                      'Social',
                      currentHumeResult.overallCategoryScores['social'] ?? 0.0,
                      Colors.purpleAccent,
                    ),
                    _buildHumeCategoryRow(
                      context,
                      'Negative',
                      currentHumeResult.overallCategoryScores['negative'] ?? 0.0,
                      theme.colorScheme.error,
                    ),
                    _buildHumeCategoryRow(
                      context,
                      'Disengaged',
                      currentHumeResult.overallCategoryScores['disengagement'] ?? 0.0,
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    children: [
                      radarWidget,
                      const SizedBox(width: 40),
                      Expanded(child: breakdownWidget),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      radarWidget,
                      const SizedBox(height: 20),
                      breakdownWidget,
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Question-by-Question Voice Analysis',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: !isMobile ? 2 : 1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 96,
              ),
              itemCount: currentHumeResult.perQuestion.length,
              itemBuilder: (context, idx) {
                return _buildQuestionDetails(
                  context,
                  currentHumeResult.perQuestion[idx],
                  idx,
                );
              },
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 40.0,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.mic_off,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Prosody voice analysis was not captured.',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      humeKey.isEmpty
                          ? 'Add a Hume API key in Settings to analyze emotional tone.'
                          : 'Make sure candidate speaks clearly during session.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
