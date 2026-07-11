// lib/features/recruiter/views/runner/conversation_runner_page.dart
//
// On-device candidate runner for the conversational (chatbot) track. A single
// kiosk page that flows through the controller's stages:
// welcome → [résumé step, adaptive only] → system check → chat → scoring →
// completion. Adaptive templates ground the interviewer in the candidate's
// résumé; timed conversational mode shows a thinking/answer countdown.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../widgets/custom_buttons.dart';
import '../../../../widgets/custom_inputs.dart';
import '../../controllers/conversation_runner_controller.dart';
import '../../engine/conversation_engine.dart';
import '../../models/recruiter_models.dart';
import '../../services/recruiter_gemini_service.dart';
import '../../store/recruiter_store.dart';
import '../report_page.dart';
import '../widgets/recruiter_ui.dart';

class ConversationRunnerPage extends StatefulWidget {
  final InterviewSession session;
  final InterviewTemplate template;
  const ConversationRunnerPage({
    super.key,
    required this.session,
    required this.template,
  });

  @override
  State<ConversationRunnerPage> createState() => _ConversationRunnerPageState();
}

class _ConversationRunnerPageState extends State<ConversationRunnerPage> {
  ConversationRunnerController? _c;
  final _answerCtrl = TextEditingController();
  String? _lastTurnId;
  bool _systemCheckAck = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c ??= ConversationRunnerController(
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

  void _syncAnswerField(ConversationRunnerController c) {
    final id = c.engine.awaitingInterviewer?.id;
    if (id != _lastTurnId) {
      _lastTurnId = id;
      final draft = c.engine.awaitingInterviewer?.draft ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _answerCtrl.value = TextEditingValue(text: draft);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return PopScope(
      canPop: c.stage != ConvStage.running,
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
            case ConvStage.welcome:
              return _WelcomeScreen(
                template: widget.template,
                adaptive: c.isAdaptive,
                onContinue: c.goToWelcomeNext,
              );
            case ConvStage.resume:
              return _ResumeScreen(onReady: c.setResumeText);
            case ConvStage.systemCheck:
              return _SystemCheckScreen(
                acked: _systemCheckAck,
                starting: c.starting,
                onAck: (v) => setState(() => _systemCheckAck = v),
                onBegin: c.begin,
              );
            case ConvStage.running:
              _syncAnswerField(c);
              return _ChatStage(
                controller: c,
                template: widget.template,
                answerCtrl: _answerCtrl,
              );
            case ConvStage.scoring:
              return const _ScoringScreen();
            case ConvStage.finished:
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

// ── Welcome ──────────────────────────────────────────────────────────────────
class _WelcomeScreen extends StatelessWidget {
  final InterviewTemplate template;
  final bool adaptive;
  final VoidCallback onContinue;
  const _WelcomeScreen(
      {required this.template, required this.adaptive, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timed = isTimedTemplate(template);
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
                  Text('Conversational interview',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    template.branding.welcomeMessage ??
                        'This is a back-and-forth conversation. Answer naturally — the interviewer may ask follow-ups.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _rule(context, Icons.chat_bubble_outline,
                      'A conversational interviewer asks one question at a time.'),
                  if (adaptive)
                    _rule(context, Icons.description_outlined,
                        'Questions are tailored to your résumé, which you’ll provide next.'),
                  if (timed)
                    _rule(context, Icons.timer_outlined,
                        'Each question is timed: ${template.conversationTiming!.thinkingSeconds}s to think, ${template.conversationTiming!.perQuestionSeconds}s to answer.')
                  else
                    _rule(context, Icons.self_improvement,
                        'Take your time — this conversation is untimed.'),
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

// ── Résumé step (adaptive only) ───────────────────────────────────────────────
class _ResumeScreen extends StatefulWidget {
  final ValueChanged<String> onReady;
  const _ResumeScreen({required this.onReady});

  @override
  State<_ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<_ResumeScreen> {
  final _textCtrl = TextEditingController();
  String? _fileName;
  bool _extracting = false;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    if (!recruiterGeminiService.enabled) {
      setState(() => _error =
          'Extracting text from a PDF needs a Gemini key. Add one in Settings, or paste your résumé text below.');
      return;
    }
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() => _error = 'PDF is larger than 10 MB.');
      return;
    }
    setState(() {
      _extracting = true;
      _error = null;
      _fileName = f.name;
    });
    try {
      final text = await recruiterGeminiService.extractResumeText(
          pdfBase64: base64Encode(bytes));
      setState(() {
        _extracting = false;
        _textCtrl.text = text;
      });
    } catch (e) {
      setState(() {
        _extracting = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canContinue = _textCtrl.text.trim().length >= 30;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
          title: const Text('Your résumé'),
          backgroundColor: theme.colorScheme.surface),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The interviewer tailors its questions to your background. Upload a PDF résumé or paste the text below.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: _fileName ?? 'Choose PDF résumé',
                  variant: ButtonVariant.outline,
                  isLoading: _extracting,
                  icon: const Icon(Icons.upload_file, size: 18),
                  onPressed: _extracting ? () {} : _pickPdf,
                ),
                const SizedBox(height: 16),
                CustomInputField(
                  label: 'Résumé text',
                  placeholder: 'Paste your résumé text here…',
                  controller: _textCtrl,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: theme.colorScheme.error, fontSize: 13)),
                  ),
                const SizedBox(height: 20),
                CustomButton(
                  text: 'Continue',
                  onPressed: canContinue
                      ? () => widget.onReady(_textCtrl.text)
                      : () {},
                ),
                if (!canContinue)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Add at least a few lines of résumé text to continue.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
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

// ── System check ──────────────────────────────────────────────────────────────
class _SystemCheckScreen extends StatelessWidget {
  final bool acked;
  final bool starting;
  final ValueChanged<bool> onAck;
  final VoidCallback onBegin;
  const _SystemCheckScreen(
      {required this.acked,
      required this.starting,
      required this.onAck,
      required this.onBegin});

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
                        'I understand this is a conversational interview and I should answer naturally.'),
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: "I'm ready — begin",
                    isLoading: starting,
                    onPressed: (acked && !starting) ? onBegin : () {},
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

// ── Chat stage ────────────────────────────────────────────────────────────────
class _ChatStage extends StatelessWidget {
  final ConversationRunnerController controller;
  final InterviewTemplate template;
  final TextEditingController answerCtrl;

  const _ChatStage({
    required this.controller,
    required this.template,
    required this.answerCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final engine = c.engine;
    final now = DateTime.now().millisecondsSinceEpoch;

    final timed = engine.isTimed;
    final phase = engine.phase(now);
    final thinking = timed && phase == ConvPhase.thinking;
    final remaining = engine.remainingSeconds(now);
    final total = engine.totalPhaseSeconds(now);
    final warning = timed &&
        remaining <= (template.conversationTiming?.warningThresholdSeconds ?? 15);

    final canType = !c.sending && !thinking;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RecruiterBadge(
                    text:
                        'Question ${engine.progressCurrent} of ${engine.plannedQuestionCount}',
                    color: theme.colorScheme.secondary,
                  ),
                  if (timed && phase != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            thinking ? Icons.lightbulb_outline : Icons.timer,
                            size: 16,
                            color: warning
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '${thinking ? 'Think' : 'Answer'} · ${remaining}s',
                          style: TextStyle(
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.bold,
                              color: warning
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (timed && phase != null && total > 0)
              LinearProgressIndicator(
                value: (remaining / total).clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation(
                    warning ? theme.colorScheme.error : theme.colorScheme.primary),
              ),
            // Transcript
            Expanded(
              child: ListView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (c.sending) _typingBubble(context),
                  ...engine.transcript.reversed
                      .map((t) => _bubble(context, t)),
                ],
              ),
            ),
            // Input
            _inputBar(context, canType, thinking, warning),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, ConvTurn t) {
    final theme = Theme.of(context);
    final isInterviewer = t.role == 'interviewer';
    final bg = isInterviewer
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primary.withValues(alpha: 0.16);
    return Align(
      alignment:
          isInterviewer ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isInterviewer ? 4 : 16),
            bottomRight: Radius.circular(isInterviewer ? 16 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isInterviewer && t.isFollowUp)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('FOLLOW-UP',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              ),
            Text(
              t.content.isEmpty ? '(no answer)' : t.content,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _typingBubble(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.secondary)),
            const SizedBox(width: 10),
            Text('Interviewer is typing…',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(
      BuildContext context, bool canType, bool thinking, bool warning) {
    final theme = Theme.of(context);
    final integrity = template.integrity;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thinking)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 16, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Take a moment to think before answering.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  if (template.conversationTiming?.allowSkipThinking == true)
                    TextButton(
                      onPressed: controller.skipThinking,
                      child: const Text('Start now'),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: answerCtrl,
                  enabled: canType,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  enableInteractiveSelection: !integrity.disableCopy,
                  contextMenuBuilder: integrity.disablePasteInAnswers
                      ? (ctx, state) => const SizedBox.shrink()
                      : null,
                  onChanged: controller.saveDraft,
                  decoration: InputDecoration(
                    hintText: thinking
                        ? 'Thinking time…'
                        : 'Type your answer…',
                    filled: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(
                enabled: canType,
                onSend: () {
                  final text = answerCtrl.text;
                  controller.submit(text);
                },
              ),
            ],
          ),
          if (warning)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Time almost up — your answer will auto-submit.',
                  style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onSend;
  const _SendButton({required this.enabled, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: enabled
          ? theme.colorScheme.primary
          : theme.colorScheme.primary.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onSend : null,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.send, size: 20, color: Colors.white),
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

// ── Completion ────────────────────────────────────────────────────────────────
class _CompletionScreen extends StatelessWidget {
  final String sessionId;
  final bool degraded;
  const _CompletionScreen({required this.sessionId, required this.degraded});

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
                Text('The conversation has been scored.',
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
