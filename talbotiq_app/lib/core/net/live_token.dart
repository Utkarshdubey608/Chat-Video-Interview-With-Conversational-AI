// lib/core/net/live_token.dart
//
// A grant returned by `POST /api/rt/gemini-token`: permission to open exactly
// one Gemini Live session, with the session's configuration already sealed in.
//
// The candidate's device connects STRAIGHT to Google with this — the backend is
// never in the audio path, so the voice interview has no added latency and no
// server-side socket to keep alive. What makes that safe is that the token
// carries the whole `BidiGenerateContentSetup` (model, voice, interviewer
// instruction), and Google ignores whatever setup the client sends. A tampered
// build cannot rewrite the interview it is about to take.
//
// Two consequences for callers:
//
//   * Mint immediately before connecting. [connectBy] is short by design.
//   * Do not send a systemInstruction / model / voice in the setup frame. It is
//     discarded, so sending one is at best noise and at worst a false sense that
//     the client is in control of the session.

/// Immutable result of a mint. Times are UTC.
class LiveTokenGrant {
  const LiveTokenGrant({
    required this.token,
    required this.wsUrl,
    required this.model,
    required this.expiresAt,
    required this.connectBy,
  });

  /// The ephemeral token, in Google's `auth_tokens/…` resource form. A bearer
  /// credential: never log it, never persist it.
  final String token;

  /// The Live endpoint to open. Supplied by the server rather than hardcoded
  /// here — token-authenticated Live lives on a different API version from the
  /// minting endpoint, and that should be changeable without a new app build.
  final String wsUrl;

  /// The model the session is locked to. Informational; the client cannot change
  /// it by sending a different one.
  final String model;

  /// When the session itself stops being valid. Derived server-side from the
  /// interview's duration plus a grace period.
  final DateTime expiresAt;

  /// The deadline for OPENING the session. Distinct from [expiresAt] and much
  /// sooner — a grant left unused for a couple of minutes is dead even though
  /// the session window has barely started.
  final DateTime connectBy;

  factory LiveTokenGrant.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] as String?)?.trim() ?? '';
    final wsUrl = (json['wsUrl'] as String?)?.trim() ?? '';
    if (token.isEmpty || wsUrl.isEmpty) {
      throw const FormatException(
        'The server did not return a usable Live token grant.',
      );
    }
    return LiveTokenGrant(
      token: token,
      wsUrl: wsUrl,
      model: (json['model'] as String?)?.trim() ?? '',
      expiresAt: _parseUtc(json['expiresAt']),
      connectBy: _parseUtc(json['connectBy']),
    );
  }

  /// The URL to actually open.
  ///
  /// The token rides in a query parameter because that is the form Google
  /// documents for ephemeral tokens, and the only one available on Flutter web
  /// — browsers cannot set an `Authorization` header on a WebSocket.
  Uri get socketUri => Uri.parse(
        '$wsUrl?access_token=${Uri.encodeQueryComponent(token)}',
      );

  /// True once the connect window has closed. Check before opening a socket that
  /// was minted a while ago; mint a fresh grant instead of connecting.
  bool get isStale => DateTime.now().toUtc().isAfter(connectBy);

  /// How long the session may run from now. Zero if already expired.
  Duration get remaining {
    final left = expiresAt.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Never includes the token — this type is safe to print.
  @override
  String toString() =>
      'LiveTokenGrant(model: $model, connectBy: $connectBy, expiresAt: $expiresAt)';

  static DateTime _parseUtc(Object? value) {
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    // A missing timestamp must not read as "valid forever": treat it as already
    // past so callers re-mint rather than opening a socket that Google refuses.
    return DateTime.now().toUtc();
  }
}
