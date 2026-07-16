// lib/core/backend/gateways/scoring_gateway.dart
//
// Scoring gateway: hand a completed interview transcript to the server, which
// runs the rubric-weighted scoring (Gemini over the transcript) and returns a
// ResultReport. Mirrors the website's server-side scoring (shared/types.ts:
// ResultReport). The result is returned as a decoded map for now — ResultReport
// is modelled as a DTO when the recruiter report screen is wired.
//
// ADDITIVE SCAFFOLDING — not wired into any screen yet.

import '../../security/gateway_config.dart';
import '../backend_client.dart';

/// Contract for interview scoring.
abstract class ScoringGateway {
  /// Score a completed interview from its transcript.
  ///
  /// [transcript] is the list of turns / answers to evaluate — passed through
  /// verbatim so the server owns the exact scoring shape. Returns the decoded
  /// ResultReport map (overallScore is computed server-side, never by the model).
  Future<Map<String, dynamic>> scoreInterview({
    required String interviewId,
    required List<Map<String, dynamic>> transcript,
  });
}

/// HTTP implementation backed by [BackendClient].
class HttpScoringGateway implements ScoringGateway {
  HttpScoringGateway(this._client);

  final BackendClient _client;

  @override
  Future<Map<String, dynamic>> scoreInterview({
    required String interviewId,
    required List<Map<String, dynamic>> transcript,
  }) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm the scoring path (e.g. POST /api/sessions/:id/score
    // or POST /api/score) and the ResultReport response shape once functions/
    // is live.
    return _client.postJson('/api/sessions/$interviewId/score', body: {
      'transcript': transcript,
    });
  }
}
