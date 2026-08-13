// lib/features/interviews/candidate/practice/widgets/question_feedback_panel.dart
//
// Per-question feedback: what was asked, how the answer landed, and what to do
// differently.
//
// `ATSScorecard.perQuestionAnalysis` was already being generated and persisted —
// and rendered nowhere in the app. For a PRACTICE run it is the most useful thing
// in the whole report: an overall score tells someone they did badly, this tells
// them which answer to redo.
//
// Collapsed by default, one card per question, because a full report is long and
// nobody reads ten expanded blocks. `dominantEmotions` / `emotionalConsistency`
// are deliberately not shown — they came from the discontinued prosody pipeline
// and are empty on every new run.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/interviews/candidate/practice/practice_formatters.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'package:talbotiq/shared/models/app_models.dart';

class QuestionFeedbackPanel extends StatelessWidget {
  const QuestionFeedbackPanel({super.key, required this.analyses});

  final List<PerQuestionAnalysis> analyses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < analyses.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _QuestionCard(analysis: analyses[i], number: i + 1),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.analysis, required this.number});

  final PerQuestionAnalysis analysis;
  final int number;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _expanded = false;

  /// The answer's average across the three per-answer dimensions, on the 0-100
  /// scale the rest of the report colours by. Null when none were assessed.
  int? get _answerScore {
    final scored = [
      widget.analysis.relevanceScore,
      widget.analysis.clarityScore,
      widget.analysis.depthScore,
    ].where((d) => !d.cannotAssess).toList();
    if (scored.isEmpty) return null;
    final total = scored.fold<int>(0, (sum, d) => sum + d.score);
    return dimensionPercent((total / scored.length).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = widget.analysis;
    final score = _answerScore;
    final colour =
        score == null ? theme.colorScheme.onSurfaceVariant : scoreColor(context, score);

    return RecruiterPanel(
      padding: const EdgeInsets.all(16),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _numberChip(theme, colour),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      analysis.questionText.trim().isEmpty
                          ? 'Question ${widget.number}'
                          : analysis.questionText.trim(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                    ),
                    if (score != null) ...[
                      const SizedBox(height: 6),
                      RecruiterBadge(text: '$score / 100', color: colour),
                    ],
                  ],
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 16),
            if (analysis.answerSummary.trim().isNotEmpty) ...[
              _label(theme, 'Your answer'),
              const SizedBox(height: 4),
              Text(analysis.answerSummary.trim(),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            _scoreRow(context, 'Relevance', analysis.relevanceScore),
            _scoreRow(context, 'Clarity', analysis.clarityScore),
            _scoreRow(context, 'Depth', analysis.depthScore),
            if (analysis.strengths.isNotEmpty) ...[
              const SizedBox(height: 12),
              _bullets(
                context,
                'What worked',
                analysis.strengths,
                Icons.check_circle_outline,
                theme.colorScheme.primary,
              ),
            ],
            // Presented as "to work on" rather than the model's "red flags":
            // this is the candidate's own practice review, not a recruiter's
            // hiring note about them.
            if (analysis.redFlags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _bullets(
                context,
                'To work on',
                analysis.redFlags,
                Icons.trending_up,
                warningColor(context),
              ),
            ],
            if (_transcriptCaveat != null) ...[
              const SizedBox(height: 12),
              Text(
                _transcriptCaveat!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Shown when the transcript for this answer was poor — otherwise a candidate
  /// blames themselves for what was really a speech-recognition problem.
  String? get _transcriptCaveat {
    final quality = widget.analysis.transcriptQuality.trim().toLowerCase();
    if (quality.isEmpty || quality == 'good' || quality == 'high') return null;
    final note = widget.analysis.transcriptQualityNote.trim();
    return note.isNotEmpty
        ? 'Transcript note: $note'
        : 'The transcript for this answer was unclear, so this feedback may be '
            'less reliable.';
  }

  Widget _numberChip(ThemeData theme, Color colour) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Text(
          '${widget.number}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colour,
          ),
        ),
      );

  Widget _label(ThemeData theme, String text) => Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      );

  Widget _scoreRow(BuildContext context, String label, ScoredDimension d) {
    final theme = Theme.of(context);
    if (d.cannotAssess) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                'Not assessed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final percent = dimensionPercent(d.score);
    final colour = scoreColor(context, percent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${d.score}/10',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.bold, color: colour),
          ),
        ],
      ),
    );
  }

  Widget _bullets(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
    Color colour,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(theme, title),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 15, color: colour),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
