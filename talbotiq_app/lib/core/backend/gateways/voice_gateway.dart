// lib/core/backend/gateways/voice_gateway.dart
//
// Voice gateway: fetch the browsable catalog of selectable voices + interviewer
// personas for the recruiter picker. Mirrors the website's GET /api/voices
// (shared/types.ts: VoiceCatalog).
//
// The realtime voice WS protocol (VoiceServerMessage / VoiceClientMessage) is
// intentionally NOT modelled here — it is a WebSocket concern, out of scope for
// this HTTP gateway layer.
//
// ADDITIVE SCAFFOLDING — not wired into any screen yet.

import '../../security/gateway_config.dart';
import '../backend_client.dart';
import '../dtos.dart';

/// Contract for the voice catalog.
abstract class VoiceGateway {
  /// Fetch the browsable voice + persona catalog.
  Future<VoiceCatalog> catalog();
}

/// HTTP implementation backed by [BackendClient].
class HttpVoiceGateway implements VoiceGateway {
  HttpVoiceGateway(this._client);

  final BackendClient _client;

  static const String _path = '/api/voices';

  @override
  Future<VoiceCatalog> catalog() async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm GET /api/voices returns VoiceCatalog once
    // functions/ is live.
    final json = await _client.getJson(_path);
    return VoiceCatalog.fromJson(json);
  }
}
