// lib/features/interviews/services/evaluation_retry_service.dart
//
// Retrying AI scoring for the candidates whose evaluation failed.
//
// Exists because a failed evaluation used to be a dead end that had to be
// cleared one candidate at a time from the review screen. The recruiter's actual
// question is "which of these has no score, and can you just try again" — this
// answers it for a whole round in one action.
//
// Two rules it will not break:
//
//   1. It only touches interviews whose stored `evaluatedBy` is EMPTY. A result
//      a recruiter already wrote by hand, or one the AI produced successfully, is
//      never overwritten by a retry.
//   2. A retry that fails leaves the failure recorded, with the NEW error. It
//      never falls back to a heuristic or a zero — that is the whole point of the
//      change this file is part of.
//
// The scorer is injected so this is testable without Gemini: the production
// wiring passes `geminiService.regenerateFromResponses`.

import 'package:flutter/foundation.dart';

import 'package:talbotiq/core/services/gemini_service.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

/// Re-scores stored raw answers. Matches `GeminiService.regenerateFromResponses`.
typedef ResponseScorer = Future<RegeneratedResult> Function({
  required String jobRole,
  required List<Map<String, dynamic>> responses,
});

/// What happened to one candidate.
class RetryOutcome {
  final Interview interview;

  /// Null when the retry succeeded.
  final String? error;

  const RetryOutcome({required this.interview, this.error});

  bool get succeeded => error == null;
}

/// What happened overall. Reported honestly — a partial success is not a success.
class RetryReport {
  final List<RetryOutcome> outcomes;

  const RetryReport(this.outcomes);

  int get total => outcomes.length;
  int get scored => outcomes.where((o) => o.succeeded).length;
  int get failed => total - scored;

  bool get allSucceeded => failed == 0 && total > 0;

  /// One sentence fit to put in front of a recruiter.
  String get summary {
    if (total == 0) return 'Nothing needed re-scoring.';
    if (allSucceeded) {
      return 'Scored $scored candidate(s). Review and publish when ready.';
    }
    if (scored == 0) {
      final first = outcomes.firstWhere((o) => !o.succeeded);
      return 'All $failed retry attempt(s) failed. ${first.error}';
    }
    return 'Scored $scored, still failing $failed. '
        'Their answers are kept — you can retry again or evaluate manually.';
  }
}

class EvaluationRetryService {
  EvaluationRetryService({
    required InterviewRepository repository,
    ResponseScorer? scorer,
  })  : _repo = repository,
        _scorer = scorer ?? geminiService.regenerateFromResponses;

  final InterviewRepository _repo;
  final ResponseScorer _scorer;

  /// Re-scores every retryable candidate of a test, or of one round.
  ///
  /// [onProgress] fires after each candidate so a long run can show movement
  /// rather than a spinner that looks stuck at twenty candidates.
  Future<RetryReport> retryAll({
    required String recruiterId,
    required String testId,
    String? roundId,
    void Function(int done, int total)? onProgress,
  }) async {
    final pending = await _repo.fetchRetryableEvaluations(
      recruiterId: recruiterId,
      testId: testId,
      roundId: roundId,
    );
    return retryEach(pending, onProgress: onProgress);
  }

  /// Re-scores [interviews], skipping any that are not retryable.
  ///
  /// Sequential on purpose. These calls are billed and rate-limited per user
  /// (see the backend's `RateLimitGenerate`); firing thirty in parallel would
  /// trip that limit and turn a recoverable queue into thirty fresh failures.
  Future<RetryReport> retryEach(
    List<Interview> interviews, {
    void Function(int done, int total)? onProgress,
  }) async {
    final targets = interviews.where((i) => i.canRetryEvaluation).toList();
    final outcomes = <RetryOutcome>[];

    for (var idx = 0; idx < targets.length; idx++) {
      final interview = targets[idx];
      try {
        final result = await _scorer(
          jobRole: interview.title,
          responses: interview.storedResponses,
        );
        await _repo.saveResult(interview.id, {
          'overallScore': result.overallScore,
          'summary': result.summary,
          'recommendation': result.recommendation,
          'strengths': result.strengths,
          'improvements': result.improvements,
          'evaluatedBy': 'ai',
          // Cleared EXPLICITLY rather than by relying on the write replacing the
          // old map. Real Firestore does replace a map-valued field on update,
          // but fake_cloud_firestore deep-merges it — so "the old error goes
          // away on its own" held in production and not in tests, which is
          // exactly the kind of difference that hides a stale failure banner.
          'evaluationError': '',
          // The answers stay, so a later retry (or a manual review) still has
          // them.
          'responses': interview.storedResponses,
        });
        outcomes.add(RetryOutcome(interview: interview));
      } catch (e) {
        final message = e.toString().replaceAll('Exception: ', '');
        debugPrint('retry scoring failed for ${interview.id}: $message');
        // Record the NEW reason, keeping the answers. Deliberately still no
        // score — a failed retry must not leave a fabricated number behind.
        try {
          await _repo.completeWithoutScore(
            interview.id,
            error: message,
            responses: interview.storedResponses,
          );
        } catch (writeError) {
          debugPrint('could not record retry failure: $writeError');
        }
        outcomes.add(RetryOutcome(interview: interview, error: message));
      } finally {
        onProgress?.call(idx + 1, targets.length);
      }
    }

    return RetryReport(outcomes);
  }
}
