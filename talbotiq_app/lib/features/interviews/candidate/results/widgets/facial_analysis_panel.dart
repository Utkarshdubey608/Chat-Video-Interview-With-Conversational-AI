import 'package:flutter/material.dart';

import 'package:talbotiq/shared/models/app_models.dart';

/// Panel showcasing facial analysis results (on-device FaceFit / ML Kit).
///
/// When a real [FacialSessionSummary] is present (`totalFrames > 0`) it renders
/// the attention/smile/looking-away/usable-frame metrics, a data-quality badge,
/// and the integrity/engagement/concern flags. Otherwise it keeps the original
/// "No Facial signals captured" placeholder.
class FacialAnalysisPanel extends StatelessWidget {
  /// The captured session summary. Null (or `totalFrames == 0`) shows the
  /// placeholder.
  final FacialSessionSummary? summary;

  const FacialAnalysisPanel({super.key, this.summary});

  bool get _hasData => (summary?.totalFrames ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Facial Analysis (On-device FaceFit)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (_hasData) _buildResults(context, theme, summary!) else _buildPlaceholder(theme),
      ],
    );
  }

  // ── Placeholder (no capture) ────────────────────────────────────────────
  Widget _buildPlaceholder(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.videocam_off,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Facial signals captured for this session.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'The pre-call attention check was skipped or camera access '
                    'was unavailable.',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results ─────────────────────────────────────────────────────────────
  Widget _buildResults(
    BuildContext context,
    ThemeData theme,
    FacialSessionSummary s,
  ) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PRE-CALL ATTENTION CHECK',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                ),
              ),
              _qualityBadge(theme, s.dataQuality),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.dataQualityNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Metric tiles — wrap responsively.
          LayoutBuilder(
            builder: (context, box) {
              final twoCol = box.maxWidth > 460;
              final tileW = twoCol ? (box.maxWidth - 12) / 2 : box.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metricTile(theme, tileW, 'Attention',
                      s.sessionAvgAttention, cs.primary, Icons.visibility_outlined),
                  _metricTile(theme, tileW, 'Positive affect (smile)',
                      s.sessionAvgSmile, cs.secondary, Icons.sentiment_satisfied_alt_outlined),
                  _metricTile(theme, tileW, 'Looked away',
                      s.overallLookingAwayPercent, cs.error, Icons.visibility_off_outlined),
                  _metricTile(theme, tileW, 'Usable frames',
                      s.usableFramePercent, cs.tertiary, Icons.check_circle_outline),
                ],
              );
            },
          ),

          const SizedBox(height: 8),
          Text(
            '${s.usableFrames} of ${s.totalFrames} frames usable',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontFamily: 'Courier',
            ),
          ),

          _flagSection(theme, 'Integrity', s.integrityFlags, cs.error,
              Icons.gpp_maybe_outlined),
          _flagSection(theme, 'Engagement', s.engagementFlags, cs.primary,
              Icons.emoji_people_outlined),
          _flagSection(theme, 'Concerns', s.concernFlags, cs.error,
              Icons.warning_amber_outlined),
        ],
      ),
    );
  }

  Widget _metricTile(
    ThemeData theme,
    double width,
    String label,
    double percent,
    Color color,
    IconData icon,
  ) {
    final cs = theme.colorScheme;
    final v = (percent / 100.0).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.02),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${percent.round()}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: cs.outline.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityBadge(ThemeData theme, String quality) {
    final cs = theme.colorScheme;
    Color c;
    switch (quality) {
      case 'high':
        c = Colors.green;
        break;
      case 'medium':
        c = cs.primary;
        break;
      case 'low':
        c = Colors.orange;
        break;
      default:
        c = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        'DATA: ${quality.toUpperCase()}',
        style: TextStyle(
          color: c,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
        ),
      ),
    );
  }

  Widget _flagSection(
    ThemeData theme,
    String title,
    List<String> flags,
    Color color,
    IconData icon,
  ) {
    if (flags.isEmpty) return const SizedBox.shrink();
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...flags.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
