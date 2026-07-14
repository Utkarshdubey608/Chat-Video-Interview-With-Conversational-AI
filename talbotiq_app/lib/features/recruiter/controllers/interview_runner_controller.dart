// lib/features/recruiter/controllers/interview_runner_controller.dart
//
// Drives one on-device timed interview: a 1s Timer advances the pure
// RunnerEngine, app-lifecycle changes are logged as integrity events, and on
// completion the session is assembled, scored (Gemini if a key is set, else the
// deterministic heuristic), and persisted to RecruiterStore.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/scoring_engine.dart';
import '../engine/timing_engine.dart';
import '../models/recruiter_models.dart';
import '../services/recruiter_gemini_service.dart';
import '../store/recruiter_store.dart';

enum RunnerStage { welcome, systemCheck, running, scoring, finished }

class InterviewRunnerController extends ChangeNotifier
    with WidgetsBindingObserver {
  final InterviewSession session;
  final InterviewTemplate template;
  final RecruiterStore store;

  late final RunnerEngine engine;
  RunnerStage stage = RunnerStage.welcome;

  Timer? _timer;
  final List<IntegrityEvent> _integrityEvents = [];
  int _tabSwitchCount = 0;
  bool _immersive = false;
  bool _disposed = false; // set in dispose(); gates post-await continuations
  bool _submitting = false; // an answer submit + advance is in flight

  ResultReport? report;
  String? scoringError;

  InterviewRunnerController({
    required this.session,
    required this.template,
    required this.store,
  }) {
    engine = RunnerEngine.fromQuestions(session.questions, template.timing);
    WidgetsBinding.instance.addObserver(this);
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  int get tabSwitchCount => _tabSwitchCount;
  int get maxTabSwitchWarnings => template.integrity.maxTabSwitchWarnings;

  // ── Lifecycle-based integrity (mobile equivalent of tab-switch detection) ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (stage != RunnerStage.running) return;
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

  // ── Flow control ────────────────────────────────────────────────────────
  void goToSystemCheck() {
    stage = RunnerStage.systemCheck;
    notifyListeners();
  }

  void begin() {
    if (template.integrity.enforceFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _immersive = true;
    }
    engine.begin(_now);
    stage = RunnerStage.running;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  void _onTick() {
    final changed = engine.tick(_now);
    if (engine.completed) {
      _finish();
    } else if (changed) {
      notifyListeners();
    } else {
      // Still notify so the countdown UI updates every second.
      notifyListeners();
    }
  }

  void skipPrep() {
    engine.skipPrep(_now);
    notifyListeners();
  }

  void saveDraft(String text) => engine.saveDraft(text);

  /// True while a submit is advancing to the next question — the runner page
  /// disables the submit button on this to stop a double-tap skipping a
  /// question / duplicating the answer.
  bool get submitting => _submitting;

  void submitAnswer(String text) {
    if (_submitting) return;
    if (engine.current == null) return;
    _submitting = true;
    engine.submitAnswer(_now, text);
    if (engine.completed) {
      // Guard stays set — the page moves to the scoring stage.
      _finish();
    } else {
      notifyListeners();
      // Release only after the next question's frame is built, so a
      // same-frame double-tap can't submit (and skip) the next question.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        _submitting = false;
      });
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _timer = null;
    _restoreChrome();
    stage = RunnerStage.scoring;
    notifyListeners();

    // Assemble the completed session from the engine's runtime state.
    final completedSession = session.copyWith(
      status: SessionStatus.completed,
      questions: engine.questions.map((q) => q.toSessionQuestion()).toList(),
      currentIndex: engine.currentIndex,
      startedAt: engine.startedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(engine.startedAt!)
              .toIso8601String()
          : null,
      completedAt: DateTime.now().toIso8601String(),
      integrityEvents: _integrityEvents,
      tabSwitchCount: _tabSwitchCount,
    );
    store.upsertSession(completedSession);

    // Score: Gemini when a key is present, else deterministic heuristic.
    ResultReport result;
    try {
      if (recruiterGeminiService.enabled) {
        final raw = await recruiterGeminiService.scoreWithGemini(
            completedSession, template);
        result = assembleFromGemini(completedSession, template, raw);
      } else {
        result = heuristicReport(completedSession, template);
      }
    } catch (e) {
      scoringError = e.toString();
      result = heuristicReport(completedSession, template);
    }

    if (_disposed) return;
    store.putReport(result);
    report = result;
    stage = RunnerStage.finished;
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
