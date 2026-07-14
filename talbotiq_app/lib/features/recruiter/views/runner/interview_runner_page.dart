// lib/features/recruiter/views/runner/interview_runner_page.dart
//
// The on-device candidate interview runner for the fixed / timed (chat) track.
// A single kiosk page that switches through the controller's stages:
// welcome → system check → question stage (timed) → scoring → completion.
// Integrity (app-switch logging, optional immersive fullscreen, no-paste
// answer field) is applied per the template's IntegrityConfig.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../widgets/custom_buttons.dart';
import '../../controllers/interview_runner_controller.dart';
import '../../engine/timing_engine.dart';
import '../../models/recruiter_models.dart';
import '../../store/recruiter_store.dart';
import '../report_page.dart';
import '../widgets/recruiter_ui.dart';

class InterviewRunnerPage extends StatefulWidget {
  final InterviewSession session;
  final InterviewTemplate template;
  const InterviewRunnerPage({
    super.key,
    required this.session,
    required this.template,
  });

  @override
  State<InterviewRunnerPage> createState() => _InterviewRunnerPageState();
}

class _InterviewRunnerPageState extends State<InterviewRunnerPage> {
  InterviewRunnerController? _c;
  final _answerCtrl = TextEditingController();
  String? _lastQuestionId;
  bool _systemCheckAck = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c ??= InterviewRunnerController(
      session: widget.session,
      template: widget.template,
      store: Provider.of<RecruiterStore>(context, listen: false),
    );
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    _c?.dispose();
    super.dispose();
  }

  void _syncAnswerField(InterviewRunnerController c) {
    final id = c.engine.current?.id;
    if (id != _lastQuestionId) {
      _lastQuestionId = id;
      final draft = c.engine.current?.draft ?? '';
      // Defer to avoid mutating the controller during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _answerCtrl.value = TextEditingValue(text: draft);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return PopScope(
      canPop: c.stage != RunnerStage.running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmLeave();
        if (leave == true) navigator.pop();
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          switch (c.stage) {
            case RunnerStage.welcome:
              return _WelcomeScreen(
                template: widget.template,
                onContinue: c.goToSystemCheck,
              );
            case RunnerStage.systemCheck:
              return _SystemCheckScreen(
                acked: _systemCheckAck,
                onAck: (v) => setState(() => _systemCheckAck = v),
                onBegin: c.begin,
              );
            case RunnerStage.running:
              _syncAnswerField(c);
              return _QuestionStage(
                controller: c,
                template: widget.template,
                answerCtrl: _answerCtrl,
              );
            case RunnerStage.scoring:
              return const _ScoringScreen();
            case RunnerStage.finished:
              return _CompletionScreen(
                sessionId: widget.session.id,
                degraded: c.report?.degraded == true,
              );
          }
        },
      ),
    );
  }

  Future<bool?> _confirmLeave() {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave interview?'),
        content: const Text(
            'The interview is in progress. Leaving will abandon it without a score.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          CustomButton(
            text: 'Leave',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }
}

// ── Welcome ──────────────────────────────────────────────────────────────
class _WelcomeScreen extends StatelessWidget {
  final InterviewTemplate template;
  final VoidCallback onContinue;
  const _WelcomeScreen({required this.template, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.branding.companyName.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  Text('Welcome to your interview',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    template.branding.welcomeMessage ??
                        'Find a quiet spot, take a breath, and answer naturally.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _rule(context, Icons.timer_outlined,
                      'Each question is timed: ${template.timing.prepSeconds}s to prepare, ${template.timing.answerSeconds}s to answer.'),
                  _rule(context, Icons.lock_clock,
                      'Answers auto-submit when time runs out. You cannot go back.'),
                  _rule(context, Icons.looks_one_outlined,
                      'Questions are shown one at a time.'),
                  const SizedBox(height: 28),
                  CustomButton(text: 'Continue', onPressed: onContinue),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rule(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ── System check ────────────────────────────────────────────────────────
class _SystemCheckScreen extends StatelessWidget {
  final bool acked;
  final ValueChanged<bool> onAck;
  final VoidCallback onBegin;
  const _SystemCheckScreen(
      {required this.acked, required this.onAck, required this.onBegin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
          title: const Text('System check'),
          backgroundColor: theme.colorScheme.surface),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _check(context, 'You have a stable internet connection'),
                  _check(context, "You're in a quiet, well-lit space"),
                  _check(context, 'You have enough time to finish uninterrupted'),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: acked,
                    onChanged: (v) => onAck(v ?? false),
                    title: const Text(
                        'I understand the interview is timed and I cannot go back.'),
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: "I'm ready — begin",
                    onPressed: acked ? onBegin : () {},
                  ),
                  if (!acked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Tick the box above to begin.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _check(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ── Question stage (timed) ────────────────────────────────────────────────
class _QuestionStage extends StatelessWidget {
  final InterviewRunnerController controller;
  final InterviewTemplate template;
  final TextEditingController answerCtrl;

  const _QuestionStage({
    required this.controller,
    required this.template,
    required this.answerCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = controller.engine;
    final q = engine.current;
    if (q == null) return const _ScoringScreen();

    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = engine.remainingSeconds(now);
    final totalPhase = engine.totalPhaseSeconds();
    final phase = engine.phase;
    final isPrep = phase == RunnerPhase.prep;
    final warning = remaining <= template.timing.warningThresholdSeconds;
    final integrity = template.integrity;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RecruiterBadge(
                    text: isPrep ? 'PREPARE' : 'ANSWER',
                    color: isPrep
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.primary,
                  ),
                  Text(
                    'Question ${engine.progressCurrent} of ${engine.total}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Countdown(
                remaining: remaining,
                total: totalPhase,
                warning: warning,
              ),
              const SizedBox(height: 20),
              Text(q.text,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (isPrep)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 40, color: theme.colorScheme.secondary),
                      const SizedBox(height: 12),
                      Text('Take a moment to structure your answer (STAR).',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 20),
                      if (template.timing.allowSkipPrep)
                        CustomButton(
                          text: 'Start answering now',
                          variant: ButtonVariant.outline,
                          onPressed: controller.skipPrep,
                        ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: answerCtrl,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          enableInteractiveSelection: !integrity.disableCopy,
                          contextMenuBuilder: integrity.disablePasteInAnswers
                              ? (ctx, state) => const SizedBox.shrink()
                              : null,
                          onChanged: controller.saveDraft,
                          decoration: const InputDecoration(
                            hintText: 'Type your answer…',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomButton(
                              text: engine.progressCurrent >= engine.total
                                  ? 'Submit & finish'
                                  : 'Submit & continue',
                              isLoading: controller.submitting,
                              onPressed: controller.submitting
                                  ? () {}
                                  : () =>
                                      controller.submitAnswer(answerCtrl.text),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (warning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Time almost up — your answer will auto-submit.',
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  final int remaining;
  final int total;
  final bool warning;
  const _Countdown(
      {required this.remaining, required this.total, required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning ? theme.colorScheme.error : theme.colorScheme.primary;
    final value = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    return Center(
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Text('$remaining',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Scoring ────────────────────────────────────────────────────────────────
class _ScoringScreen extends StatelessWidget {
  const _ScoringScreen();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Scoring your interview…', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

// ── Completion ──────────────────────────────────────────────────────────────
class _CompletionScreen extends StatelessWidget {
  final String sessionId;
  final bool degraded;
  const _CompletionScreen(
      {required this.sessionId, required this.degraded});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('All done — thank you!',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('The interview has been scored.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                CustomButton(
                  text: 'View report',
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ReportPage(sessionId: sessionId),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Back to sessions',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
