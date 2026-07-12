// lib/features/recruiter/controllers/conversation_runner_controller.dart
//
// Drives one on-device conversational (chatbot) interview. Owns the pure
// ConversationEngine, an optional 1s timer for timed conversational mode
// (thinking→answer→auto-submit), app-lifecycle integrity logging, and — on
// completion — assembles + scores the transcript (Gemini if a key is set, else
// the deterministic heuristic) and persists it to RecruiterStore.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/conversation_engine.dart';
import '../models/recruiter_models.dart';
import '../services/recruiter_gemini_service.dart';
import '../store/recruiter_store.dart';

enum ConvStage { welcome, resume, systemCheck, running, scoring, finished }

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

  Timer? _timer;
  final List<IntegrityEvent> _integrityEvents = [];
  int _tabSwitchCount = 0;
  bool _immersive = false;

  ResultReport? report;
  String? scoringError;

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
    try {
      await engine.begin(_now);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
      starting = false;
      _restoreChrome();
      stage = ConvStage.welcome;
      notifyListeners();
      return;
    }
    starting = false;
    if (engine.completed) {
      await _finish();
      return;
    }
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
    sending = true;
    notifyListeners();
    try {
      await engine.submitAnswer(_now, text, autoAdvanced: autoAdvanced);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    sending = false;
    if (engine.completed) {
      await _finish();
    } else {
      // Re-arm timed phase timestamps already handled inside the engine.
      notifyListeners();
    }
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
    _timer?.cancel();
    _restoreChrome();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
