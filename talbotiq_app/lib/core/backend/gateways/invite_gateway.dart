// lib/core/backend/gateways/invite_gateway.dart
//
// Bulk-invite gateway: parse an uploaded candidate file into rows, then create
// one interview per candidate. Mirrors the website's POST /api/invites/extract
// and POST /api/invites endpoints (shared/types.ts).
//
// ADDITIVE SCAFFOLDING — not wired into any screen yet. Until functions/ are
// deployed and GatewayConfig is configured, calls fail fast with a clear
// StateError.

import 'dart:convert';

import '../../security/gateway_config.dart';
import '../backend_client.dart';
import '../dtos.dart';

/// Contract for bulk-invite operations.
abstract class InviteGateway {
  /// Parse candidate rows out of an uploaded file (CSV / Excel / PDF / text).
  /// [fileBytes] is the raw file content; [fileName] carries the extension the
  /// server uses to pick a parser.
  Future<ExtractCandidatesResult> extractCandidates({
    required List<int> fileBytes,
    required String fileName,
  });

  /// Create one interview per candidate and (optionally) email them.
  Future<CreateInvitesResult> createInvites(CreateInvitesRequest request);
}

/// HTTP implementation backed by [BackendClient].
class HttpInviteGateway implements InviteGateway {
  HttpInviteGateway(this._client);

  final BackendClient _client;

  static const String _extractPath = '/api/invites/extract';
  static const String _createPath = '/api/invites';

  @override
  Future<ExtractCandidatesResult> extractCandidates({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm the server accepts base64 file content in a JSON
    // body at POST /api/invites/extract (vs. multipart). Adjust to
    // ApiClient.sendMultipart if the deployed function expects multipart/form-data.
    final json = await _client.postJson(_extractPath, body: {
      'fileName': fileName,
      'contentBase64': base64Encode(fileBytes),
    });
    return ExtractCandidatesResult.fromJson(json);
  }

  @override
  Future<CreateInvitesResult> createInvites(
      CreateInvitesRequest request) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): verify POST /api/invites path + auth (recruiter role) once
    // functions/ is live.
    final json = await _client.postJson(_createPath, body: request.toJson());
    return CreateInvitesResult.fromJson(json);
  }
}
