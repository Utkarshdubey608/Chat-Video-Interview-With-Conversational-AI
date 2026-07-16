// lib/features/recruiter/controllers/conversation_runner_controller.dart
//
// Drives one on-device conversational (chatbot) interview. Owns the pure
// ConversationEngine, an optional 1s timer for timed conversational mode
// (thinking→answer→auto-submit), app-lifecycle integrity logging, and — on
// completion — assembles + scores the transcript (Gemini if a key is set, else
// the deterministic heuristic) and persists it to RecruiterStore.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/conversation_engine.dart';
import '../models/recruiter_models.dart';
import '../services/recruiter_gemini_service.dart';
import '../store/recruiter_store.dart';

enum ConvStage { welcome, resume, systemCheck, readiness, running, scoring, finished }

/// A display-only interviewer acknowledgment bubble ("Thanks — got it.") shown
/// between the candidate's answer and the next question. Purely presentational:
/// it is NOT part of the engine transcript and never reaches scoring.
class ChatAck {
  final String id;
  final String text;
  final int createdAt; // epoch ms
  const ChatAck({required this.id, required this.text, required this.createdAt});
}

class ConversationRunnerController extends ChangeNotifier
    with WidgetsBindingObserver {
  final InterviewSession session;
  final InterviewTemplate template;
  final RecruiterStore store;

  /// When set, these questions are used instead of looking up the template's
  /// fixedQuestionSetId in [store]. Lets a caller (e.g. the candidate flow
  /// launching a Firestore Interview) run the chat engine without persisting a
  /// QuestionSet into the recruiter store.
  final List<FixedQuestion>? fixedQuestionsOverride;

  /// Optional hook fired once scoring completes, with the finished session and
  /// its report — used to mirror results to another store (e.g. Firestore).
  final void Function(InterviewSession completedSession, ResultReport report)?
      onFinished;

  late ConversationEngine engine;
  ConvStage stage = ConvStage.welcome;

  String _resumeText;
  bool starting = false; // begin() in flight
  bool sending = false; // producing the next interviewer turn
  String? error;
  bool _disposed = false; // set in dispose(); gates post-await continuations

  Timer? _timer;
  final List<IntegrityEvent> _integrityEvents = [];
  int _tabSwitchCount = 0;
  bool _immersive = false;

  ResultReport? report;
  String? scoringError;

  // ── Chat polish (thinking floor + varied acknowledgments) ──────────────────

  /// Minimum time the animated "Thinking…" indicator stays visible before an
  /// interviewer turn is revealed, so it never flickers on a fast response.
  static const Duration _thinkingFloor = Duration(milliseconds: 1400);

  /// How long the acknowledgment bubble shows on its own before the next
  /// question is revealed.
  static const Duration _ackDwell = Duration(milliseconds: 900);

  /// Varied acknowledgments shown as a brief interviewer bubble after each
  /// answer. Never repeated twice in a row (see [_pushAck]).
  static const List<String> _ackPhrases = [
    'Thanks — got it.',
    'Great, noted.',
    'That makes sense.',
    'Perfect, thank you.',
    'Appreciate that — noted.',
    'Lovely, thanks for sharing.',
  ];
  int _lastAckIndex = -1;
  final Random _rng = Random();

  /// Display-only acknowledgment bubbles (not part of the engine transcript).
  final List<ChatAck> ackBubbles = [];

  /// Time-of-day greeting derived from the candidate's local clock, e.g.
  /// "Good morning" / "Good afternoon" / "Good evening".
  String get greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String? get candidateName {
    final n = session.candidateName.trim();
    return n.isEmpty ? null : n;
  }

  ConversationRunnerController({
    required this.session,
    required this.template,
    required this.store,
    this.fixedQuestionsOverride,
    this.onFinished,
  }) : _resumeText = session.resumeText ?? '' {
    engine = ConversationEngine(
      template: template,
      fixedQuestions: _resolveFixedQuestions(),
      resumeText: _resumeText,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  /// Fixed questions for the engine: the caller-provided override if any,
  /// otherwise the template's referenced question set from [store].
  List<FixedQuestion> _resolveFixedQuestions() {
    if (fixedQuestionsOverride != null) return fixedQuestionsOverride!;
    final set = template.fixedQuestionSetId != null
        ? store.questionSetById(template.fixedQuestionSetId!)
        : null;
    return set?.questions ?? const [];
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  bool get isAdaptive => template.questionSource == QuestionSource.adaptive;
  bool get needsResume => isAdaptive && _resumeText.trim().isEmpty;
  bool get isTimed => engine.isTimed;

  int get tabSwitchCount => _tabSwitchCount;
  int get maxTabSwitchWarnings => template.integrity.maxTabSwitchWarnings;

  String get resumeText => _resumeText;

  // ── Integrity (app-switch detection) ──────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (stage != ConvStage.running) return;
    if (!template.integrity.detectTabSwitch) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _tabSwitchCount++;
      if (template.integrity.logEvents) {
        _integrityEvents.add(IntegrityEvent(
          type: 'window_blur',
          at: DateTime.now().toIso8601String(),
        ));
      }
      notifyListeners();
    }
  }

  // ── Flow ──────────────────────────────────────────────────────────────────
  void goToWelcomeNext() {
    stage = needsResume ? ConvStage.resume : ConvStage.systemCheck;
    notifyListeners();
  }

  /// Called by the résumé step once text has been captured (paste or PDF).
  void setResumeText(String text) {
    _resumeText = text.trim();
    // Rebuild the engine with the résumé bound in.
    engine = ConversationEngine(
      template: template,
      fixedQuestions: _resolveFixedQuestions(),
      resumeText: _resumeText,
    );
    stage = ConvStage.systemCheck;
    notifyListeners();
  }

  /// System check acknowledged → show the "Are you ready?" readiness step.
  /// Questioning does not start until the candidate confirms (see [begin]).
  void goToReadiness() {
    stage = ConvStage.readiness;
    notifyListeners();
  }

  Future<void> begin() async {
    if (starting) return;
    starting = true;
    error = null;
    if (template.integrity.enforceFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _immersive = true;
    }
    stage = ConvStage.running;
    notifyListeners();
    final startedMs = _now;
    try {
      await engine.begin(_now);
    } catch (e) {
      if (_disposed) return;
      error = e.toString().replaceAll('Exception: ', '');
      starting = false;
      _restoreChrome();
      stage = ConvStage.welcome;
      notifyListeners();
      return;
    }
    if (_disposed) return;
    // Hold the "Thinking…" indicator for its minimum floor before revealing the
    // first question, then re-arm timed windows so the floor never eats a timer.
    await _ensureThinkingFloor(startedMs);
    if (_disposed) return;
    starting = false;
    if (engine.completed) {
      await _finish();
      return;
    }
    _rearmTimedAwaiting();
    if (isTimed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
    notifyListeners();
  }

  void _onTick() {
    if (stage != ConvStage.running) return;
    final expired = engine.advanceTiming(_now);
    if (expired) {
      final draft = engine.awaitingInterviewer?.draft ?? '';
      _submit(draft, autoAdvanced: true);
    } else {
      notifyListeners(); // refresh the countdown
    }
  }

  void skipThinking() {
    if (engine.skipThinking(_now)) notifyListeners();
  }

  void saveDraft(String text) => engine.saveDraft(text);

  void submit(String text) => _submit(text, autoAdvanced: false);

  Future<void> _submit(String text, {required bool autoAdvanced}) async {
    if (sending || stage != ConvStage.running) return;
    final startedMs = _now;
    sending = true;
    notifyListeners();
    try {
      await engine.submitAnswer(_now, text, autoAdvanced: autoAdvanced);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (_disposed) return;

    // Keep the animated "Thinking…" indicator up for its minimum floor so it
    // never flickers, even when the next turn is produced instantly.
    await _ensureThinkingFloor(startedMs);
    if (_disposed) return;

    if (engine.completed) {
      sending = false;
      await _finish();
      return;
    }

    // Brief, varied acknowledgment bubble before the next question is revealed
    // (mirrors the website's "thanks, got it" beat). The question card keeps
    // showing "Thinking…" while the acknowledgment dwells.
    _pushAck();
    notifyListeners();
    await Future<void>.delayed(_ackDwell);
    if (_disposed) return;

    // Start the next question's timed windows now, at reveal — not back when the
    // engine appended the turn — so the acknowledgment beat never eats a timer.
    _rearmTimedAwaiting();
    sending = false;
    notifyListeners();
  }

  /// Hold until at least [_thinkingFloor] has elapsed since [startMs].
  Future<void> _ensureThinkingFloor(int startMs) async {
    final remaining = _thinkingFloor.inMilliseconds - (_now - startMs);
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }
  }

  /// Re-arm the awaiting turn's timed thinking/answer window to start now, so a
  /// reveal delay (thinking floor + acknowledgment) doesn't count against it.
  /// Mirrors the engine's own arming logic; only touches runtime timestamps.
  void _rearmTimedAwaiting() {
    if (!isTimed) return;
    final ct = template.conversationTiming;
    final turn = engine.awaitingInterviewer;
    if (ct == null || turn == null || turn.questionIndex == null) return;
    final now = _now;
    if (ct.thinkingSeconds > 0) {
      turn.thinkingStartedAt = now;
      turn.answerStartedAt = null;
    } else {
      turn.thinkingStartedAt = null;
      turn.answerStartedAt = now;
    }
  }

  /// Append a display-only acknowledgment bubble, never repeating the last one.
  void _pushAck() {
    var idx = _rng.nextInt(_ackPhrases.length);
    if (_ackPhrases.length > 1 && idx == _lastAckIndex) {
      idx = (idx + 1) % _ackPhrases.length;
    }
    _lastAckIndex = idx;
    ackBubbles.add(ChatAck(
      id: 'ack_${DateTime.now().microsecondsSinceEpoch}',
      text: _ackPhrases[idx],
      createdAt: _now,
    ));
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _timer = null;
    _restoreChrome();
    stage = ConvStage.scoring;
    notifyListeners();

    final completedSession = engine.toSession(
      session,
      markCompleted: true,
      integrityEvents: _integrityEvents,
      tabSwitchCount: _tabSwitchCount,
    );
    store.upsertSession(completedSession);

    final groups = primaryQuestionGroups(completedSession.transcript ?? []);
    ResultReport result;
    try {
      if (recruiterGeminiService.enabled) {
        final raw = await recruiterGeminiService.scoreConversationWithGemini(
            completedSession, template);
        result = assembleConversationReport(
            completedSession, template, raw, groups);
      } else {
        result = conversationHeuristicReport(completedSession, template, groups);
      }
    } catch (e) {
      scoringError = e.toString();
      result = conversationHeuristicReport(completedSession, template, groups);
    }

    if (_disposed) return;
    store.putReport(result);
    report = result;
    onFinished?.call(completedSession, result);
    stage = ConvStage.finished;
    notifyListeners();
  }

  void _restoreChrome() {
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _immersive = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _restoreChrome();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
