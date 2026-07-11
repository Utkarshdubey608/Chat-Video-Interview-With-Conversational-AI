// lib/features/recruiter/views/sessions_page.dart
//
// Native port of the recruiter SessionsPage — create candidate interview
// sessions and review their status/score. On a self-contained device there is
// no share-link; "Start" runs the interview on this device (runner arrives in
// Phase 3). Creating a fixed-source session snapshots the set's questions into
// the session, mirroring the web backend's POST /sessions behavior.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_buttons.dart';
import '../models/recruiter_models.dart';
import '../store/recruiter_store.dart';
import 'report_page.dart';
import 'runner/conversation_runner_page.dart';
import 'runner/interview_runner_page.dart';
import 'widgets/recruiter_ui.dart';

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  void _startSession(
      BuildContext context, RecruiterStore store, InterviewSession s) {
    final template = store.templateById(s.templateId);
    if (template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This session\'s template is missing.')),
      );
      return;
    }
    // Timed Q&A (chat): a fixed set of questions snapshotted into the session.
    if (s.track == TrackType.chat) {
      if (s.questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This session has no questions. Attach a question set to its template.')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InterviewRunnerPage(session: s, template: template),
        ),
      );
      return;
    }

    // Conversational (chatbot / video-avatar): a back-and-forth transcript.
    // Fixed-source conversational needs a non-empty question set; adaptive
    // collects the résumé inside the runner.
    if (template.questionSource == QuestionSource.fixed) {
      final set = template.fixedQuestionSetId != null
          ? store.questionSetById(template.fixedQuestionSetId!)
          : null;
      if (set == null || set.questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This template\'s question set is empty. Attach a set with questions.')),
        );
        return;
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConversationRunnerPage(session: s, template: template),
      ),
    );
  }

  void _viewReport(BuildContext context, String sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportPage(sessionId: sessionId)),
    );
  }

  Future<void> _createSession(BuildContext context, RecruiterStore store) async {
    if (store.templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a template first.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _NewSessionDialog(store: store),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RecruiterStore>();
    final sessions = store.sessions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecruiterPageHeader(
            kicker: 'AI Interview',
            title: 'Sessions',
            subtitle: 'Create and review candidate interviews.',
            action: CustomButton(
              text: 'New',
              height: 40,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => _createSession(context, store),
            ),
          ),
          const SizedBox(height: 20),
          if (sessions.isEmpty)
            const RecruiterEmptyState(
              icon: Icons.mic_none,
              title: 'No sessions yet',
              description: 'Create a session to run an interview on this device.',
            )
          else
            ...sessions.map((s) => _SessionCard(
                  session: s,
                  templateName:
                      store.templateById(s.templateId)?.name ?? 'Unknown template',
                  score: store.reportFor(s.id)?.overallScore,
                  hasReport: store.reportFor(s.id) != null,
                  onStart: () => _startSession(context, store, s),
                  onViewReport: () => _viewReport(context, s.id),
                  onDelete: () => store.deleteSession(s.id),
                )),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final InterviewSession session;
  final String templateName;
  final double? score;
  final bool hasReport;
  final VoidCallback onStart;
  final VoidCallback onViewReport;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.templateName,
    required this.score,
    required this.hasReport,
    required this.onStart,
    required this.onViewReport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.candidateName.isEmpty
                            ? 'Unnamed candidate'
                            : session.candidateName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (session.candidateEmail.isNotEmpty)
                        Text(session.candidateEmail,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                RecruiterBadge(
                  text: SessionStatus.label(session.status),
                  color: statusColor(context, session.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$templateName · ${TrackType.label(session.track)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (score != null) ...[
                  RecruiterBadge(
                    text: 'Score ${score!.round()}',
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                // Actions flow to a second line on narrow screens instead of
                // overflowing horizontally.
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasReport)
                        CustomButton(
                          text: 'View report',
                          variant: ButtonVariant.secondary,
                          height: 36,
                          onPressed: onViewReport,
                        ),
                      CustomButton(
                        text: hasReport ? 'Re-run' : 'Start',
                        variant: hasReport
                            ? ButtonVariant.outline
                            : ButtonVariant.primary,
                        height: 36,
                        onPressed: onStart,
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: theme.colorScheme.error),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  final RecruiterStore store;
  const _NewSessionDialog({required this.store});

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  late String _templateId;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _templateId = widget.store.templates.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _create() {
    final store = widget.store;
    final template = store.templateById(_templateId);
    if (template == null) return;

    // Snapshot fixed-set questions into the session (mirrors POST /sessions).
    List<SessionQuestion> questions = [];
    if (template.questionSource == QuestionSource.fixed &&
        template.fixedQuestionSetId != null) {
      final set = store.questionSetById(template.fixedQuestionSetId!);
      questions = (set?.questions ?? [])
          .map((q) => SessionQuestion(
                id: recruiterId('sq'),
                text: q.text,
                category: q.category,
                idealAnswerNotes: q.idealAnswerNotes,
              ))
          .toList();
    }

    final now = DateTime.now().toIso8601String();
    store.upsertSession(InterviewSession(
      id: recruiterId('sess'),
      templateId: template.id,
      track: template.track,
      candidateName: _nameController.text.trim(),
      candidateEmail: _emailController.text.trim(),
      status: SessionStatus.created,
      questions: questions,
      createdAt: now,
      mode: template.mode,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Template', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _templateId,
              isExpanded: true,
              items: widget.store.templates
                  .map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.name} (${t.questionSource})',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _templateId = v ?? _templateId),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Candidate name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Candidate email'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        CustomButton(text: 'Create session', height: 40, onPressed: _create),
      ],
    );
  }
}
