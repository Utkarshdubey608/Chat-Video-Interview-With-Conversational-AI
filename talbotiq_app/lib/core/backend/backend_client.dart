// lib/core/backend/backend_client.dart
//
// A thin, authenticated client for the future secure backend (Firebase Cloud
// Functions / Cloud Run). It sits on top of [ApiClient] (which owns timeout +
// transient-retry + typed [ApiException]) and adds exactly two backend-specific
// concerns:
//
//   1. Base-URL construction from [GatewayConfig.functionsBaseUrl], so every
//      gateway targets `/<functionsBaseUrl>/api/...` without repeating the host.
//   2. Firebase auth: it attaches the caller's Firebase ID token as
//      `Authorization: Bearer <token>` on every request, matching the server's
//      Admin-SDK verification described in shared/types.ts (AuthContext).
//
// This is ADDITIVE SCAFFOLDING. Until functions/ are deployed and
// [GatewayConfig.functionsBaseUrl] is set, gateways guard their calls behind
// [GatewayConfig.useSecureBackend] and never reach this client.
//
// No state, no side effects beyond the HTTP call. JSON encode/decode only.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import '../net/api_client.dart';
import '../security/gateway_config.dart';

/// Thin wrapper over [ApiClient] that builds authenticated JSON requests
/// against the deployed HTTPS functions. Throws [ApiException] on transport
/// failures (from [ApiClient]) and on non-2xx responses / decode failures.
class BackendClient {
  BackendClient({ApiClient? apiClient, FirebaseAuth? auth})
      : _api = apiClient ?? ApiClient(),
        _auth = auth ?? FirebaseAuth.instance;

  final ApiClient _api;
  final FirebaseAuth _auth;

  /// Base URL of the deployed functions, e.g.
  /// `https://<region>-<project>.cloudfunctions.net`.
  ///
  /// TODO(deploy): this resolves from [GatewayConfig.functionsBaseUrl], which
  /// is empty until you pass `--dart-define=FUNCTIONS_BASE_URL=...` at build
  /// time. While empty, [_resolveBase] throws a clear [StateError] and no
  /// request is attempted.
  String get _baseUrl => GatewayConfig.functionsBaseUrl;

  /// GET `<base>/<path>` with an auth header, decoding a JSON object body.
  ///
  /// [path] is joined to the base (leading slash optional). [query] is
  /// appended as URL query parameters when provided.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query);
    final headers = await _authHeaders();
    final resp = await _api.get(uri, headers: headers);
    return _decode(resp.statusCode, resp.body);
  }

  /// POST `<base>/<path>` with an auth header and a JSON-encoded [body],
  /// decoding a JSON object response.
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query);
    final headers = await _authHeaders(json: true);
    final resp = await _api.post(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(resp.statusCode, resp.body);
  }

  /// Resolves the base URL or fails loudly. Kept separate so both verbs and
  /// any future ones share one guard.
  String _resolveBase() {
    final base = _baseUrl.trim();
    if (base.isEmpty) {
      // TODO(deploy): set FUNCTIONS_BASE_URL (see GatewayConfig.functionsBaseUrl).
      throw StateError(
        'Backend not configured — deploy functions/ and set FUNCTIONS_BASE_URL',
      );
    }
    return base;
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final base = _resolveBase();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// Builds request headers, attaching the Firebase ID token when a user is
  /// signed in. A missing token is NOT fatal here — the server decides whether
  /// the route requires auth and returns 401/403, which [ApiException] flags
  /// via [ApiException.isAuthError].
  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await _auth.currentUser?.getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Turns a raw HTTP response into a decoded JSON map or an [ApiException].
  /// Mirrors the server's `ApiError { error: string }` shape (shared/types.ts)
  /// so the message surfaced to callers comes from the backend when available.
  Map<String, dynamic> _decode(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) {
      if (body.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        // Some endpoints may return a bare array/scalar; wrap for a stable
        // map return type.
        return <String, dynamic>{'data': decoded};
      } on FormatException catch (e) {
        throw ApiException('Malformed response from backend: ${e.message}',
            statusCode: statusCode);
      }
    }
    // Non-2xx: try to lift the server's { error } message, else generic.
    String message = 'Request failed';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } on FormatException {
      // ignore — fall back to the generic message + status code
    }
    throw ApiException(message, statusCode: statusCode);
  }

  void close() => _api.close();
}
