// lib/core/security/gateway_config.dart
//
// Feature switch + endpoint config for the server-side AI proxy. Until the
// Cloud Functions in functions/ are deployed, [useSecureBackend] stays false
// and the app uses the transitional client-direct path (documented in
// recruiter_credentials_repository.dart). Flip it — and set [functionsBaseUrl]
// — as the final deploy step, then tighten the recruiter_keys read rule.

class GatewayConfig {
  GatewayConfig._();

  /// When true, conversation creation + scoring are performed by the backend
  /// and no raw recruiter keys are ever read on-device.
  ///
  /// TODO(backend): set to true after deploying functions/ and configuring
  /// [functionsBaseUrl].
  static const bool useSecureBackend = bool.fromEnvironment(
    'USE_SECURE_BACKEND',
    defaultValue: false,
  );

  /// Base URL of the deployed HTTPS functions, e.g.
  /// https://<region>-<project>.cloudfunctions.net
  ///
  /// TODO(backend): provide via --dart-define=FUNCTIONS_BASE_URL=... at build.
  static const String functionsBaseUrl = String.fromEnvironment(
    'FUNCTIONS_BASE_URL',
    defaultValue: '',
  );

  /// Guard invoked at the top of every gateway call: until the backend is
  /// deployed and [useSecureBackend] is flipped on, fail fast with a clear
  /// message instead of hitting an unconfigured endpoint.
  static void ensureConfigured() {
    if (!useSecureBackend) {
      // TODO(deploy): flip USE_SECURE_BACKEND=true and set FUNCTIONS_BASE_URL.
      throw StateError(
        'Backend not configured — deploy functions/ and set FUNCTIONS_BASE_URL',
      );
    }
  }
}
