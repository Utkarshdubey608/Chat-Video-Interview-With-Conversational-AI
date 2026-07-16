// lib/features/recruiter/views/report_page.dart
//
// Native port of the recruiter ReportPage — scored candidate report with an
// overall gauge, per-KPI bars, strengths/improvements, and a per-question
// accordion. Reads the ResultReport from RecruiterStore. Reuses the app's
// existing CircularScoreRing.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/widgets/response_widgets.dart';
import 'package:talbotiq/features/recruiter/engine/conversation_engine.dart';
import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/features/recruiter/views/report_pdf.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';

class ReportPage extends StatelessWidget {
  final String sessionId;
  const ReportPage({super.key, required this.sessionId});

  String _kpiLabel(InterviewTemplate? template, String kpiId) {
    if (template == null) return kpiId;
    for (final k in template.rubric.kpis) {
      if (k.id == kpiId) return k.label;
    }
    return kpiId;
  }

  Color _scoreColor(BuildContext context, double score) {
    final scheme = Theme.of(context).colorScheme;
    if (score >= 75) return scheme.primary;
    if (score >= 55) return const Color(0xFFE4C270);
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<RecruiterStore>();
    final session = store.sessionById(sessionId);
    final report = store.reportFor(sessionId);
    final template =
        session != null ? store.templateById(session.templateId) : null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Interview Report'),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          if (session != null && report != null)
            IconButton(
              tooltip: 'Export / share PDF',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _exportPdf(context, session, template, report),
            ),
        ],
      ),
      body: (session == null || report == null)
          ? const RecruiterEmptyState(
              icon: Icons.hourglass_empty,
              title: 'No report yet',
              description: 'This interview has not been scored.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RecruiterPageHeader(
                        kicker: 'AI Interview',
                        title: session.candidateName.isEmpty
                            ? 'Candidate'
                            : session.candidateName,
                        subtitle:
                            '${template?.name ?? ''} · ${TrackType.label(session.track)}',
                      ),
                      const SizedBox(height: 20),
                      if (report.degraded == true) _degradedBanner(context),
                      _summaryCard(context, report),
                      const SizedBox(height: 16),
                      if (template != null)
                        _kpiCard(context, template.rubric, report),
                      const SizedBox(height: 16),
                      if (_isConversation(session))
                        _conversationBreakdown(
                            context, session, template, report)
                      else
                        _perQuestionCard(context, session, template, report),
                      if (session.tabSwitchCount > 0) ...[
                        const SizedBox(height: 16),
                        _integrityCard(context, session),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _degradedBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE4C270).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFFE4C270).withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE4C270), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Heuristic scoring (no Gemini key). Add a Gemini key in Settings for content-aware scoring.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, ResultReport report) {
    final theme = Theme.of(context);
    final rec = report.recommendation != null
        ? Recommendation.label(report.recommendation!)
        : '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircularScoreRing(
                  score: report.overallScore.round(),
                  verdict: rec,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Overall fit',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text('${report.overallScore.round()} / 100',
                          style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _scoreColor(context, report.overallScore))),
                      const SizedBox(height: 4),
                      RecruiterBadge(
                          text: rec,
                          color: _scoreColor(context, report.overallScore)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(report.summary, style: theme.textTheme.bodyMedium),
            if ((report.strengths ?? []).isNotEmpty) ...[
              const SizedBox(height: 16),
              _bulletList(context, 'Strengths', report.strengths!,
                  theme.colorScheme.primary, Icons.add),
            ],
            if ((report.improvements ?? []).isNotEmpty) ...[
              const SizedBox(height: 12),
              _bulletList(context, 'Areas to improve', report.improvements!,
                  const Color(0xFFE4C270), Icons.arrow_forward),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bulletList(BuildContext context, String title, List<String> items,
      Color color, IconData icon) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...items.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(s,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13))),
                ],
              ),
            )),
      ],
    );
  }

  Widget _kpiCard(
      BuildContext context, KpiRubric rubric, ResultReport report) {
    final theme = Theme.of(context);
    final enabled = rubric.kpis.where((k) => k.enabled).toList();
    final entries = enabled
        .map((k) => MapEntry(k.label, report.kpiAverages[k.id] ?? 0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KPI Scores',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // KPI profile radar (needs ≥3 axes to read as a shape). Painter
            // expects a 0–1 scale, so normalise the 0–100 averages.
            if (enabled.length >= 3) ...[
              EmotionRadarChart(
                categoryScores: {
                  for (final k in enabled)
                    k.label:
                        ((report.kpiAverages[k.id] ?? 0).toDouble() / 100.0)
                            .clamp(0.0, 1.0),
                },
              ),
              const SizedBox(height: 20),
            ],
            ...entries.map((e) => _kpiBar(context, e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _kpiBar(BuildContext context, String label, double value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontSize: 13))),
              Text('${value.round()}',
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      color: _scoreColor(context, value))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.08),
              valueColor:
                  AlwaysStoppedAnimation(_scoreColor(context, value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perQuestionCard(BuildContext context, InterviewSession session,
      InterviewTemplate? template, ResultReport report) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('Per-question breakdown',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            for (int i = 0; i < session.questions.length; i++)
              _questionTile(context, i, session.questions[i], template,
                  report.perQuestion),
          ],
        ),
      ),
    );
  }

  Widget _questionTile(BuildContext context, int index, SessionQuestion q,
      InterviewTemplate? template, List<PerQuestionResult> perQuestion) {
    final theme = Theme.of(context);
    PerQuestionResult? pq;
    for (final p in perQuestion) {
      if (p.questionId == q.id) {
        pq = p;
        break;
      }
    }
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Text('Q${index + 1}. ${q.text}',
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: q.autoSubmitted
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt, size: 13, color: theme.colorScheme.secondary),
              const SizedBox(width: 4),
              Text('auto-submitted',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11)),
            ])
          : null,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            q.answerText != null && q.answerText!.trim().isNotEmpty
                ? q.answerText!
                : '(no answer provided)',
            style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 10),
        if (pq != null && pq.kpiScores.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pq.kpiScores.entries.map((e) {
              final label = _kpiLabel(template, e.key);
              return RecruiterBadge(
                text: '$label ${e.value.round()}',
                color: _scoreColor(context, e.value),
              );
            }).toList(),
          ),
        if (pq != null) ...[
          const SizedBox(height: 10),
          Text(pq.feedback,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
        ],
      ],
    );
  }

  Future<void> _exportPdf(BuildContext context, InterviewSession session,
      InterviewTemplate? template, ResultReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildReportPdf(
          session: session, template: template, report: report);
      final safeName = (session.candidateName.isEmpty
              ? 'candidate'
              : session.candidateName)
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'report_$safeName.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export PDF: $e')),
      );
    }
  }

  bool _isConversation(InterviewSession session) =>
      session.questions.isEmpty &&
      session.transcript != null &&
      session.transcript!.isNotEmpty;

  Widget _conversationBreakdown(BuildContext context, InterviewSession session,
      InterviewTemplate? template, ResultReport report) {
    final theme = Theme.of(context);
    final groups = primaryQuestionGroups(session.transcript ?? []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('Conversation breakdown',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            for (int i = 0; i < groups.length; i++)
              _conversationTile(
                  context, i, groups[i], template, report.perQuestion),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(BuildContext context, int displayIndex,
      PrimaryQuestionGroup g, InterviewTemplate? template,
      List<PerQuestionResult> perQuestion) {
    final theme = Theme.of(context);
    PerQuestionResult? pq;
    for (final p in perQuestion) {
      if (p.questionId == 'q${g.index}') {
        pq = p;
        break;
      }
    }
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Text('Q${displayIndex + 1}. ${g.question}',
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: g.autoAdvanced
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt, size: 13, color: theme.colorScheme.secondary),
              const SizedBox(width: 4),
              Text('auto-advanced (time expired)',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11)),
            ])
          : null,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            g.answer.trim().isNotEmpty ? g.answer : '(no answer provided)',
            style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 10),
        if (pq != null && pq.kpiScores.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pq.kpiScores.entries.map((e) {
              return RecruiterBadge(
                text: '${_kpiLabel(template, e.key)} ${e.value.round()}',
                color: _scoreColor(context, e.value),
              );
            }).toList(),
          ),
        if (pq != null) ...[
          const SizedBox(height: 10),
          Text(pq.feedback,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
        ],
      ],
    );
  }

  Widget _integrityCard(BuildContext context, InterviewSession session) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Integrity: ${session.tabSwitchCount} app-switch event(s) logged during the interview.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
