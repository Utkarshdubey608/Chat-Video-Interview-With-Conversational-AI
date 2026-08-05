// test/backend_client_test.dart
//
// Phase 6: the app's door to the backend. No Firebase and no network — the HTTP
// layer is a stub and the ID token is injected, so what is under test is our own
// behaviour: that every request carries a bearer token, that the backend's error
// envelope becomes a showable message, and that a Live grant is parsed safely.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/core/net/live_token.dart';

/// Captures what was sent and replies with whatever the test set up.
class _StubHttp extends http.BaseClient {
  int status = 200;
  String body = '{}';
  final List<http.BaseRequest> requests = [];
  List<int>? lastBody;

  http.BaseRequest get last => requests.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) lastBody = request.bodyBytes;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// A client with the token injected, so no Firebase is needed.
BackendClient buildClient(
  http.Client stub, {
  String baseUrl = 'https://backend.test',
}) =>
    BackendClient(
      client: ApiClient(client: stub, maxRetries: 0),
      baseUrl: baseUrl,
      tokenProvider: () async => 'test-id-token',
    );

void main() {
  late _StubHttp stub;
  late BackendClient client;

  setUp(() {
    stub = _StubHttp();
    client = buildClient(stub);
  });

  group('LiveTokenGrant', () {
    Map<String, dynamic> json({
      String token = 'auth_tokens/abc',
      String? connectBy,
      String? expiresAt,
    }) =>
        {
          'token': token,
          'wsUrl': 'wss://generativelanguage.googleapis.com/ws/Constrained',
          'model': 'models/gemini-live',
          'expiresAt': expiresAt ??
              DateTime.now().toUtc().add(const Duration(minutes: 30)).toIso8601String(),
          'connectBy': connectBy ??
              DateTime.now().toUtc().add(const Duration(minutes: 2)).toIso8601String(),
        };

    test('puts the token in the query string, not a header', () {
      // Browsers cannot set headers on a WebSocket, so this is the only form
      // that works on Flutter web.
      final grant = LiveTokenGrant.fromJson(json());
      expect(grant.socketUri.queryParameters['access_token'],
          'auth_tokens/abc');
      expect(grant.socketUri.scheme, 'wss');
    });

    test('a token needing escaping survives the round trip', () {
      final grant = LiveTokenGrant.fromJson(json(token: 'auth_tokens/a+b/c=d'));
      expect(grant.socketUri.queryParameters['access_token'],
          'auth_tokens/a+b/c=d');
    });

    test('rejects a grant with no token or url', () {
      expect(() => LiveTokenGrant.fromJson({'model': 'x'}),
          throwsA(isA<FormatException>()));
      expect(() => LiveTokenGrant.fromJson({'token': 'x'}),
          throwsA(isA<FormatException>()));
    });

    test('a past connect window reads as stale', () {
      final grant = LiveTokenGrant.fromJson(json(
        connectBy:
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
      ));
      expect(grant.isStale, isTrue);
    });

    test('a missing timestamp fails closed rather than never expiring', () {
      // Reading a missing connectBy as "valid forever" would send the client at
      // a socket Google refuses, with no useful error.
      final grant = LiveTokenGrant.fromJson({
        'token': 't',
        'wsUrl': 'wss://x/y',
      });
      expect(grant.isStale, isTrue);
      expect(grant.remaining, Duration.zero);
    });

    test('toString never leaks the token', () {
      final grant = LiveTokenGrant.fromJson(json(token: 'super-secret-token'));
      expect(grant.toString(), isNot(contains('super-secret-token')));
    });
  });

  group('authentication', () {
    test('every request carries the bearer token', () async {
      stub.body = '{"ok": true}';
      await client.getJson('/health');
      expect(stub.last.headers['Authorization'], 'Bearer test-id-token');
    });

    test('a POST sends JSON with the right content type', () async {
      stub.body = '{"ok": true}';
      await client.postJson('/api/gemini/generate', body: {'contents': []});
      expect(stub.last.headers['Content-Type'], contains('application/json'));
      expect(utf8.decode(stub.lastBody!), '{"contents":[]}');
    });

    test('raw bytes are sent unchanged with the caller content type', () async {
      stub.body = '{"ok": true}';
      await client.postBytes(
        '/api/deepgram/transcribe',
        utf8.encode('RIFFfake'),
        contentType: 'audio/wav',
        query: {'language': 'en-US'},
      );
      expect(stub.last.headers['Content-Type'], 'audio/wav');
      expect(utf8.decode(stub.lastBody!), 'RIFFfake');
      expect(stub.last.url.queryParameters['language'], 'en-US');
    });
  });

  group('error translation', () {
    test('the backend detail becomes the message', () async {
      stub
        ..status = 503
        ..body = jsonEncode({
          'detail': 'Tavus is not configured on the server. Set TAVUS_API_KEY…',
          'provider': 'Tavus',
        });

      await expectLater(
        client.getJson('/api/tavus/personas'),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', contains('TAVUS_API_KEY'))
            .having((e) => e.provider, 'provider', 'Tavus')
            .having((e) => e.isNotConfigured, 'isNotConfigured', isTrue)),
      );
    });

    test('401 is classified so callers do not offer a pointless retry', () async {
      stub
        ..status = 401
        ..body = jsonEncode({'detail': 'Invalid or expired sign-in.'});
      await expectLater(
        client.getJson('/health'),
        throwsA(isA<BackendException>()
            .having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });

    test('429 is classified as rate limited', () async {
      stub
        ..status = 429
        ..body = jsonEncode({'detail': 'Too many requests.'});
      await expectLater(
        client.postJson('/api/gemini/generate'),
        throwsA(isA<BackendException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
      );
    });

    test('a non-JSON error body still yields a usable message', () async {
      stub
        ..status = 502
        ..body = '<html>Bad Gateway</html>';
      await expectLater(
        client.getJson('/health'),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', contains('502'))),
      );
    });

    test('a 200 with a non-JSON body is an error, not silent success', () async {
      stub.body = 'not json';
      await expectLater(
        client.getJson('/health'),
        throwsA(isA<BackendException>()),
      );
    });
  });

  group('configuration', () {
    test('an unconfigured backend explains how to fix it', () async {
      // A release build with no --dart-define must fail with instructions, not
      // a confusing network error against an empty host.
      final unconfigured = buildClient(stub, baseUrl: '');
      expect(unconfigured.isConfigured, isFalse);
      await expectLater(
        unconfigured.getJson('/health'),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', contains('BACKEND_BASE_URL'))),
      );
      // Nothing may have been sent.
      expect(stub.requests, isEmpty);
    });

    test('a token is fetched fresh for each request', () async {
      var calls = 0;
      final counted = BackendClient(
        client: ApiClient(client: stub, maxRetries: 0),
        baseUrl: 'https://backend.test',
        tokenProvider: () async {
          calls++;
          return 'token-$calls';
        },
      );
      await counted.getJson('/health');
      await counted.getJson('/health');
      // Caching here would reintroduce the expiry bugs the SDK avoids.
      expect(calls, 2);
      expect(stub.last.headers['Authorization'], 'Bearer token-2');
    });
  });

  group('providerReadiness', () {
    test('maps the health payload', () async {
      stub.body = jsonEncode({
        'status': 'ok',
        'providers': {'gemini': true, 'tavus': false},
      });
      expect(await client.providerReadiness(),
          {'gemini': true, 'tavus': false});
    });

    test('a failure returns empty rather than taking a screen down', () async {
      stub
        ..status = 500
        ..body = '{}';
      expect(await client.providerReadiness(), isEmpty);
    });
  });
}
