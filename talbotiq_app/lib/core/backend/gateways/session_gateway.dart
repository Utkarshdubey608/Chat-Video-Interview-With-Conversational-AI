// lib/core/backend/gateways/session_gateway.dart
//
// Candidate-session lifecycle gateway. Mirrors the website's session endpoints
// (shared/types.ts: CreateSessionRequest, CandidateSessionState,
// SubmitAnswerRequest, SaveDraftRequest, AvatarStartResponse).
//
// The candidate state is returned as a decoded map for now (CandidateSessionState
// is not yet modelled as a DTO — it is added when the candidate flow is wired).
// avatarStart returns the typed AvatarStartResponse since it is small + stable.
//
// ADDITIVE SCAFFOLDING — not wired into any screen yet.

import '../../security/gateway_config.dart';
import '../backend_client.dart';
import '../dtos.dart';

/// Contract for the candidate-facing interview session lifecycle.
abstract class SessionGateway {
  /// Create a session for a candidate against a template.
  /// Mirrors POST /api/sessions (CreateSessionRequest).
  Future<Map<String, dynamic>> createSession({
    required String templateId,
    required CandidateRef candidate,
    String? track,
  });

  /// Fetch the candidate-safe view of the current session state.
  /// Mirrors GET /api/sessions/:id (CandidateSessionState).
  Future<Map<String, dynamic>> getCandidateState(String sessionId);

  /// Submit the answer to the CURRENT question (anti-tamper: [questionId] must
  /// equal the current question). Mirrors POST /api/sessions/:id/answer
  /// (SubmitAnswerRequest). Returns the next CandidateSessionState.
  Future<Map<String, dynamic>> submitAnswer({
    required String sessionId,
    required String questionId,
    String? answerText,
    String? videoUrl,
  });

  /// Auto-save the in-progress draft for a question.
  /// Mirrors POST /api/sessions/:id/draft (SaveDraftRequest).
  Future<void> saveDraft({
    required String sessionId,
    required String questionId,
    required String draft,
  });

  /// Start the live Tavus avatar conversation for a video_avatar session.
  /// Mirrors POST /sessions/:id/avatar/start (AvatarStartResponse).
  Future<AvatarStartResponse> avatarStart(String sessionId);
}

/// HTTP implementation backed by [BackendClient].
class HttpSessionGateway implements SessionGateway {
  HttpSessionGateway(this._client);

  final BackendClient _client;

  @override
  Future<Map<String, dynamic>> createSession({
    required String templateId,
    required CandidateRef candidate,
    String? track,
  }) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm POST /api/sessions path + response shape.
    return _client.postJson('/api/sessions', body: {
      'templateId': templateId,
      'candidate': candidate.toJson(),
      if (track != null) 'track': track,
    });
  }

  @override
  Future<Map<String, dynamic>> getCandidateState(String sessionId) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm GET /api/sessions/:id returns CandidateSessionState.
    return _client.getJson('/api/sessions/$sessionId');
  }

  @override
  Future<Map<String, dynamic>> submitAnswer({
    required String sessionId,
    required String questionId,
    String? answerText,
    String? videoUrl,
  }) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm POST /api/sessions/:id/answer path + response shape.
    return _client.postJson('/api/sessions/$sessionId/answer', body: {
      'questionId': questionId,
      if (answerText != null) 'answerText': answerText,
      if (videoUrl != null) 'videoUrl': videoUrl,
    });
  }

  @override
  Future<void> saveDraft({
    required String sessionId,
    required String questionId,
    required String draft,
  }) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm POST /api/sessions/:id/draft path (SaveDraftRequest).
    await _client.postJson('/api/sessions/$sessionId/draft', body: {
      'questionId': questionId,
      'draft': draft,
    });
  }

  @override
  Future<AvatarStartResponse> avatarStart(String sessionId) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm POST /sessions/:id/avatar/start path once Tavus
    // wiring is live server-side.
    final json = await _client.postJson('/api/sessions/$sessionId/avatar/start');
    return AvatarStartResponse.fromJson(json);
  }
}
