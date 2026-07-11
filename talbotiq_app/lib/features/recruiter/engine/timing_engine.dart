// lib/features/recruiter/engine/timing_engine.dart
//
// Pure-Dart port of talbotiq-platform `server/services/timing.ts` for the
// fixed / timed (chat) track. On a single device there is no untrusted client,
// but the wall-clock-authoritative state machine is preserved verbatim so
// timing behaves identically (idempotent tick, prep→answer→auto-submit→advance).
// No Flutter imports — unit-testable.

import '../models/recruiter_models.dart';

enum RunnerPhase { prep, answer }

class RunnerQuestion {
  final String id;
  final String text;
  final String? category;
  final String? idealAnswerNotes;

  int? prepStartedAt; // epoch ms
  int? answerStartedAt;
  int? submittedAt;
  String answerText = '';
  String draft = '';
  bool autoSubmitted = false;

  RunnerQuestion({
    required this.id,
    required this.text,
    this.category,
    this.idealAnswerNotes,
  });

  factory RunnerQuestion.fromSession(SessionQuestion q) => RunnerQuestion(
        id: q.id,
        text: q.text,
        category: q.category,
        idealAnswerNotes: q.idealAnswerNotes,
      );

  SessionQuestion toSessionQuestion() => SessionQuestion(
        id: id,
        text: text,
        category: category,
        idealAnswerNotes: idealAnswerNotes,
        prepStartedAt: _iso(prepStartedAt),
        answerStartedAt: _iso(answerStartedAt),
        submittedAt: _iso(submittedAt),
        answerText: answerText,
        autoSubmitted: autoSubmitted,
        draft: draft,
      );
}

String? _iso(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();

/// Runtime state machine for one timed interview. Drive [tick] on a 1s timer.
class RunnerEngine {
  final List<RunnerQuestion> questions;
  final TimingConfig timing;

  int currentIndex = 0;
  int? startedAt;
  bool completed = false;

  RunnerEngine({required this.questions, required this.timing});

  factory RunnerEngine.fromQuestions(
          List<SessionQuestion> qs, TimingConfig timing) =>
      RunnerEngine(
        questions: qs.map(RunnerQuestion.fromSession).toList(),
        timing: timing,
      );

  RunnerQuestion? get current =>
      currentIndex < questions.length ? questions[currentIndex] : null;

  int get total => questions.length;

  void begin(int nowMs) {
    startedAt = nowMs;
    if (questions.isNotEmpty) questions[0].prepStartedAt = nowMs;
  }

  void _autoSubmit(RunnerQuestion q, int whenMs) {
    if (q.answerText.isEmpty) q.answerText = q.draft;
    q.submittedAt = whenMs;
    q.autoSubmitted = true;
  }

  void _startNext(int whenMs) {
    currentIndex += 1;
    final next = current;
    if (next != null) {
      next.prepStartedAt = whenMs;
    } else {
      completed = true;
    }
  }

  /// Advance through every phase boundary already elapsed. Idempotent.
  /// Returns true if anything changed.
  bool tick(int nowMs) {
    if (completed) return false;
    bool mutated = false;

    final cap = timing.totalTimeCapSeconds;
    if (cap != null && startedAt != null && nowMs >= startedAt! + cap * 1000) {
      final c = current;
      if (c != null && c.submittedAt == null) _autoSubmit(c, nowMs);
      completed = true;
      return true;
    }

    int guard = 0;
    while (guard++ < 10000) {
      final q = current;
      if (q == null) {
        completed = true;
        mutated = true;
        break;
      }
      if (q.submittedAt != null) {
        _startNext(q.submittedAt!);
        mutated = true;
        continue;
      }
      if (q.prepStartedAt == null) break;

      if (q.answerStartedAt == null) {
        final prepDeadline = q.prepStartedAt! + timing.prepSeconds * 1000;
        if (nowMs >= prepDeadline) {
          q.answerStartedAt = prepDeadline;
          mutated = true;
          continue;
        }
        break;
      }

      final answerDeadline = q.answerStartedAt! + timing.answerSeconds * 1000;
      if (nowMs >= answerDeadline) {
        _autoSubmit(q, answerDeadline);
        _startNext(answerDeadline);
        mutated = true;
        continue;
      }
      break;
    }
    return mutated;
  }

  /// Candidate can start answering before prep runs out.
  void skipPrep(int nowMs) {
    final q = current;
    if (q != null &&
        q.prepStartedAt != null &&
        q.answerStartedAt == null &&
        timing.allowSkipPrep) {
      q.answerStartedAt = nowMs;
    }
  }

  /// Manual submit of the current answer.
  void submitAnswer(int nowMs, String text) {
    final q = current;
    if (q == null) return;
    // Ensure we're in the answer phase before accepting a submit.
    q.answerStartedAt ??= nowMs;
    q.answerText = text;
    q.submittedAt = nowMs;
    _startNext(nowMs);
  }

  void saveDraft(String text) {
    current?.draft = text;
  }

  RunnerPhase? get phase {
    final q = current;
    if (completed || q == null) return null;
    if (q.answerStartedAt != null) return RunnerPhase.answer;
    return RunnerPhase.prep;
  }

  int totalPhaseSeconds() =>
      phase == RunnerPhase.answer ? timing.answerSeconds : timing.prepSeconds;

  /// Seconds remaining in the current phase (>= 0).
  int remainingSeconds(int nowMs) {
    final q = current;
    if (completed || q == null) return 0;
    if (q.answerStartedAt != null) {
      final rem =
          timing.answerSeconds - (nowMs - q.answerStartedAt!) / 1000.0;
      return rem < 0 ? 0 : rem.ceil();
    }
    if (q.prepStartedAt != null) {
      final rem = timing.prepSeconds - (nowMs - q.prepStartedAt!) / 1000.0;
      return rem < 0 ? 0 : rem.ceil();
    }
    return timing.prepSeconds;
  }

  int get progressCurrent =>
      (currentIndex + 1) < total ? currentIndex + 1 : total;
}
