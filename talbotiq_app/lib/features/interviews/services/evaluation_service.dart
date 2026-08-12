// lib/features/interviews/services/evaluation_service.dart
//
// Handing a finished interview to the server to be scored.
//
// The device used to call Gemini itself, wait for a full scorecard, and then
// write the result. Two things were wrong with that, and the second is what
// actually broke:
//
//   * THE CANDIDATE WAITED. They sat on a spinner while a model worked, at the
//     exact moment they most want to be told they are finished.
//   * A LONG GENERATION COULD NOT SURVIVE THE ROUND TRIP. The request asked for
//     up to 20,000 output tokens and was held open device → gateway → backend →
//     Google. The gateway in front of the backend cuts a request well before such
//     a generation finishes and answers 504, and `ApiClient` retries 429 and 503
//     but NOT 504 — so a single gateway timeout ended the evaluation for good.
//     The recruiter's "regenerate" kept working only because it asks for 4,000
//     tokens off a compact prompt and finishes inside the window, which is why
//     re-scoring a failed candidate succeeded on a transcript that had just
//     failed.
//
// So this posts the answers and returns. The server acknowledges in
// milliseconds, scores in the background, and writes the result itself with the
// Admin SDK. A successful return here means THE ANSWERS ARE STORED — not that a
// score exists yet; the result appears on the interview document shortly after,
// and a scoring failure is recorded there with no score for the recruiter's
// one-tap retry to pick up.

import 'package:talbotiq/core/net/backend_client.dart';

/// The server's acknowledgement of a submission.
class EvaluationAck {
  /// `scoring` — accepted, a background task is working on it.
  /// `stored_without_score` — accepted, but there was too little said to score,
  /// and that was recorded instead of a number invented from silence.
  final String status;

  /// How many question/answer pairs the server kept after cleaning.
  final int responses;

  const EvaluationAck({required this.status, required this.responses});

  /// Whether a score should be expected to appear shortly.
  bool get isScoring => status == 'scoring';

  factory EvaluationAck.fromJson(Map<String, dynamic> json) => EvaluationAck(
        status: (json['status'] as String?)?.trim() ?? 'scoring',
        responses: (json['responses'] as num?)?.toInt() ?? 0,
      );
}

class EvaluationService {
  EvaluationService({BackendClient? backend}) : _injectedBackend = backend;

  final BackendClient? _injectedBackend;
  BackendClient get _backend => _injectedBackend ?? backendClient;

  bool get enabled => _backend.isConfigured;

  /// Submits a finished interview's answers for scoring.
  ///
  /// Sends ONLY the answers. No score, no prompt, no model — all three are
  /// resolved server-side from the interview document, so a tampered client
  /// cannot choose the number it is given.
  ///
  /// Throws [BackendException] if the answers could not be stored, which IS worth
  /// surfacing: it is the one failure that loses the candidate's work.
  Future<EvaluationAck> submit({
    required String interviewId,
    required List<Map<String, dynamic>> responses,
  }) async {
    final json = await _backend.postJson(
      '/api/interviews/$interviewId/evaluate',
      body: {'responses': responses},
    );
    return EvaluationAck.fromJson(json);
  }
}

final evaluationService = EvaluationService();
