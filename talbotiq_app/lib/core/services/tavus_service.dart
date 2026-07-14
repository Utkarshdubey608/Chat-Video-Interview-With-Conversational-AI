// lib/core/services/tavus_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../net/api_client.dart';
import '../../models/app_models.dart';

class TavusService {
  // Shared transport: request timeout + 429/5xx backoff-retry. POSTs are never
  // retried on timeout (ApiClient treats them as non-idempotent) so we never
  // risk a duplicate Tavus conversation create.
  final ApiClient _api = ApiClient();

  String _apiKey = '';

  void setKey(String key) {
    _apiKey = key;
  }

  String getKey() => _apiKey;

  // Headers for GET/DELETE requests. Only sends the api key — adding
  // 'Content-Type' to a GET makes the browser's CORS preflight ask Tavus to
  // allow the 'content-type' request header, which it doesn't on the list
  // endpoints. That preflight failure is why replicas/personas silently fail
  // to load on Flutter web (the JS web app never sends Content-Type on GET).
  Map<String, String> _authHeaders() {
    return {'x-api-key': _apiKey};
  }

  // Headers for requests that carry a JSON body (POST).
  Map<String, String> _headers() {
    return {'x-api-key': _apiKey, 'Content-Type': 'application/json'};
  }

  // Merges custom and stock replicas
  Future<List<TavusReplica>> listReplicas() async {
    if (_apiKey.isEmpty) return [];

    try {
      final customUrl = Uri.parse('https://tavusapi.com/v2/replicas');
      final stockUrl = Uri.parse(
        'https://tavusapi.com/v2/replicas?replica_type=stock',
      );

      final results = await Future.wait([
        _api
            .get(customUrl, headers: _authHeaders())
            .catchError((e) => http.Response('{"data":[]}', 500)),
        _api
            .get(stockUrl, headers: _authHeaders())
            .catchError((e) => http.Response('{"data":[]}', 500)),
      ]);

      final List<TavusReplica> replicas = [];
      final Set<String> seenIds = {};

      bool customSuccess = false;
      bool stockSuccess = false;
      String? customError;
      String? stockError;

      // Parse custom replicas
      if (results[0].statusCode == 200) {
        customSuccess = true;
        try {
          final body = jsonDecode(results[0].body);
          final list = (body is List) ? body : (body['data'] as List?);
          if (list != null) {
            for (var item in list) {
              final replica = TavusReplica.fromJson(item);
              replicas.add(replica);
              seenIds.add(replica.replicaId);
            }
          }
        } catch (e) {
          customError = 'Failed to parse custom replicas: $e';
        }
      } else {
        try {
          final errBody = jsonDecode(results[0].body);
          customError =
              errBody?['message'] ??
              errBody?['error'] ??
              'HTTP ${results[0].statusCode}';
        } catch (_) {
          customError = 'HTTP ${results[0].statusCode}';
        }
      }

      // Parse stock replicas
      if (results[1].statusCode == 200) {
        stockSuccess = true;
        try {
          final body = jsonDecode(results[1].body);
          final list = (body is List) ? body : (body['data'] as List?);
          if (list != null) {
            for (var item in list) {
              final replica = TavusReplica.fromJson({
                ...item as Map,
                'replica_type': 'stock',
              });
              if (!seenIds.contains(replica.replicaId)) {
                replicas.add(replica);
                seenIds.add(replica.replicaId);
              }
            }
          }
        } catch (e) {
          stockError = 'Failed to parse stock replicas: $e';
        }
      } else {
        try {
          final errBody = jsonDecode(results[1].body);
          stockError =
              errBody?['message'] ??
              errBody?['error'] ??
              'HTTP ${results[1].statusCode}';
        } catch (_) {
          stockError = 'HTTP ${results[1].statusCode}';
        }
      }

      // If both endpoints failed, throw the relevant errors
      if (!customSuccess && !stockSuccess) {
        throw Exception(
          'Custom replicas: $customError | Stock replicas: $stockError',
        );
      }

      return replicas;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<TavusPersona>> listPersonas() async {
    if (_apiKey.isEmpty) return [];

    final url = Uri.parse('https://tavusapi.com/v2/personas');
    final http.Response response;
    try {
      response = await _api.get(url, headers: _authHeaders());
    } on ApiException catch (e) {
      throw Exception('Failed to load personas: ${e.message}');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      // Tavus may return either a top-level list or a { "data": [...] } wrapper,
      // exactly like the replicas endpoint.
      final list = (body is List) ? body : (body is Map ? body['data'] as List? : null);
      if (list != null) {
        return list.map((item) => TavusPersona.fromJson(item)).toList();
      }
      return [];
    } else {
      Map? errBody;
      try {
        errBody = jsonDecode(response.body) as Map?;
      } catch (_) {}
      throw Exception(
        errBody?['message'] ??
            errBody?['error'] ??
            'HTTP ${response.statusCode}',
      );
    }
  }

  Future<TavusConversation> createConversation(
    Map<String, dynamic> payload,
  ) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations');

    final http.Response response;
    try {
      response = await _api.post(
        url,
        headers: _headers(),
        body: jsonEncode(payload),
      );
    } on ApiException catch (e) {
      throw Exception('Failed to create conversation: ${e.message}');
    }

    if (kDebugMode) {
      print("debug: create conversation status: ${response.statusCode}");
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return TavusConversation.fromJson(body);
    } else {
      Map? errBody;
      try {
        errBody = jsonDecode(response.body) as Map?;
      } catch (_) {}
      final msg =
          errBody?['message'] ??
          errBody?['error'] ??
          errBody?['detail'] ??
          'HTTP ${response.statusCode}';
      throw Exception(msg);
    }
  }

  Future<TavusConversation> getConversation(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id');
    try {
      final response = await _api.get(url, headers: _authHeaders());
      if (kDebugMode) {
        print('debug: GET response status: ${response.statusCode}');
        final bodyPreview = response.body.length > 1000
            ? response.body.substring(0, 1000) + '...'
            : response.body;
        print('debug: GET response body: $bodyPreview');
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return TavusConversation.fromJson(body);
      } else {
        throw Exception(
          'Failed to load conversation: HTTP ${response.statusCode}',
        );
      }
    } on ApiException catch (e) {
      throw Exception('Failed to load conversation: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('debug: getConversation error: $e');
      rethrow;
    }
  }

  Future<List<TranscriptEntry>> getConversationTranscript(String id) async {
    // Tavus exposes the server-side transcript through the conversation object
    // with ?verbose=true (in the `events` array as application.transcription_ready),
    // not via a /transcript sub-path. _parseTranscriptResponse handles that shape,
    // and getLiveTranscript() already uses the same endpoint.
    final url = Uri.parse(
      'https://tavusapi.com/v2/conversations/$id?verbose=true',
    );
    try {
      final response = await _api.get(url, headers: _authHeaders());
      if (kDebugMode) {
        print('debug: GET transcript status: ${response.statusCode}');
        final bodyPreview = response.body.length > 2000
            ? response.body.substring(0, 2000) + '...'
            : response.body;
        print('debug: GET transcript body preview: $bodyPreview');
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return _parseTranscriptResponse(body);
      } else {
        // Carry the status code so fetchTranscriptWithRetry can fast-fail on
        // auth / not-found instead of pointlessly retrying.
        throw ApiException('Failed to load transcript',
            statusCode: response.statusCode);
      }
    } catch (e) {
      if (kDebugMode) print('debug: getConversationTranscript error: $e');
      rethrow;
    }
  }

  /// Polls the conversation verbose endpoint until a non-empty transcript
  /// is returned or the max attempts are exhausted. Uses exponential backoff.
  Future<List<TranscriptEntry>> fetchTranscriptWithRetry(
    String id, {
    int maxAttempts = 18,
    Duration initialDelay = const Duration(seconds: 5),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxAttempts) {
      attempt++;
      try {
        if (kDebugMode) print('debug: fetchTranscriptWithRetry attempt $attempt for $id');
        final entries = await getConversationTranscript(id);
        if (entries.isNotEmpty) {
          if (kDebugMode) print('debug: transcript available on attempt $attempt (entries: ${entries.length})');
          return entries;
        }
        if (kDebugMode) print('debug: transcript empty on attempt $attempt, will retry after ${delay.inSeconds}s');
      } on ApiException catch (e) {
        // Auth failures and a missing conversation will never resolve by
        // retrying — surface them immediately. Only empty results, rate limits
        // (429) and server errors (5xx) are worth polling for.
        if (e.isAuthError || e.statusCode == 404) rethrow;
        if (kDebugMode) print('debug: fetchTranscriptWithRetry transient error on attempt $attempt: ${e.message}');
      } catch (e) {
        if (kDebugMode) print('debug: fetchTranscriptWithRetry error on attempt $attempt: $e');
      }

      if (attempt >= maxAttempts) break;
      await Future.delayed(delay);
      // increase delay by 1.5x, capped to avoid unbounded growth
      final nextMs = (delay.inMilliseconds * 1.5).round();
      delay = Duration(milliseconds: nextMs.clamp(1000, 60000));
    }

    throw Exception('Transcript not available after $maxAttempts attempts');
  }

  Future<List<TranscriptEntry>> getLiveTranscript(String id) async {
    final url = Uri.parse(
      'https://tavusapi.com/v2/conversations/$id?verbose=true',
    );
    try {
      final response = await _api.get(url, headers: _authHeaders());
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return _parseTranscriptResponse(body);
      } else {
        throw Exception('Failed to load live transcript: HTTP ${response.statusCode}');
      }
    } on ApiException catch (e) {
      throw Exception('Failed to load live transcript: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('debug: getLiveTranscript error: $e');
      rethrow;
    }
  }

  List<TranscriptEntry> _parseTranscriptResponse(dynamic body) {
    final List<TranscriptEntry> entries = [];
    final dynamic data = body is Map ? body['data'] : null;
    final dynamic directList = body is List
        ? body
        : body is Map
        ? body['transcript'] ?? (data is Map ? data['transcript'] : null)
        : null;

    if (directList is List) {
      for (final item in directList) {
        final entry = _transcriptEntryFromItem(item);
        if (entry != null) entries.add(entry);
      }
    }

    if (entries.isNotEmpty || body is! Map) return entries;

    final events = body['events'] ?? (data is Map ? data['events'] : null);
    if (events is List) {
      for (final event in events) {
        final props = event is Map ? (event['properties'] ?? event) : null;
        final type = event is Map
            ? (event['event_type'] ?? event['type'] ?? '')
            : '';

        if (type == 'application.transcription_ready' &&
            props is Map &&
            props['transcript'] is List) {
          for (final item in props['transcript']) {
            final entry = _transcriptEntryFromItem(item);
            if (entry != null) entries.add(entry);
          }
        } else if (type == 'conversation.utterance' ||
            type == 'conversation.utterance.streaming') {
          final entry = _transcriptEntryFromItem(props);
          if (entry != null) entries.add(entry);
        }
      }
    } else if (events is Map) {
      final transcriptionReady = events['application.transcription_ready'];
      final list = transcriptionReady is Map
          ? transcriptionReady['transcript']
          : null;
      if (list is List) {
        for (final item in list) {
          final entry = _transcriptEntryFromItem(item);
          if (entry != null) entries.add(entry);
        }
      }
    }

    return entries;
  }

  TranscriptEntry? _transcriptEntryFromItem(dynamic item) {
    if (item is! Map) return null;

    final String text =
        (item['content'] ?? item['text'] ?? item['message'] ?? '')
            .toString()
            .trim();
    if (text.isEmpty) return null;

    final String rawRole =
        (item['role'] ?? item['speaker'] ?? item['participant_type'] ?? 'user')
            .toString()
            .toLowerCase();
    final String role =
        (rawRole == 'user' ||
            rawRole == 'candidate' ||
            rawRole == 'participant' ||
            rawRole == 'human')
        ? 'candidate'
        : 'avatar';

    return TranscriptEntry(
      role: role,
      text: text,
      timestamp: _parseTranscriptTimestamp(
        item['timestamp'] ?? item['created_at'] ?? item['start_time'],
      ),
      questionIdx: 0,
    );
  }

  int _parseTranscriptTimestamp(dynamic value) {
    if (value is num) {
      // Tavus transcript timestamps are usually ISO strings, but some event
      // streams use seconds. Millisecond epochs are already much larger.
      return value > 100000000000 ? value.round() : (value * 1000).round();
    }

    if (value is String && value.trim().isNotEmpty) {
      final numeric = num.tryParse(value);
      if (numeric != null) return _parseTranscriptTimestamp(numeric);

      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }

    return DateTime.now().millisecondsSinceEpoch;
  }

  Future<String?> getConversationRecordingUri(String id) async {
    final url = Uri.parse(
      'https://tavusapi.com/v2/conversations/$id?verbose=true',
    );
    try {
      if (kDebugMode) print('debug: GET (recording uri) $url');
      final response = await _api.get(url, headers: _authHeaders());
      if (kDebugMode) {
        print('debug: GET recording uri status: ${response.statusCode}');
        final bodyPreview = response.body.length > 2000
            ? response.body.substring(0, 2000) + '...'
            : response.body;
        print('debug: GET recording uri body preview: $bodyPreview');
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final events =
            body['events'] ??
            (body['data'] != null ? body['data']['events'] : null);
        if (events is List) {
          for (var event in events) {
            if (event['event_type'] == 'application.recording_ready') {
              final props = event['properties'];
              if (props != null && props['storage_uri'] != null) {
                if (kDebugMode) print('debug: found storage_uri: ${props['storage_uri']}');
                return props['storage_uri'].toString();
              }
            }
          }
        }
      }
      return null;
    } on ApiException catch (e) {
      throw Exception('Failed to load recording URI: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('debug: getConversationRecordingUri error: $e');
      rethrow;
    }
  }

  // Ends the live call but KEEPS the conversation record and its server-side
  // transcript. This must POST to the /end action — a DELETE on the
  // conversation permanently destroys the record (and the transcript with it),
  // which would leave the results page with nothing to fetch.
  Future<void> endConversation(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id/end');
    try {
      if (kDebugMode) print('debug: POST $url');
      final response = await _api.post(url, headers: _headers());
      if (kDebugMode) {
        print('debug: POST endConversation status: ${response.statusCode}');
      }

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
          'Failed to end conversation: HTTP ${response.statusCode}',
        );
      }
    } on ApiException catch (e) {
      throw Exception('Failed to end conversation: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('debug: endConversation error: $e');
      rethrow;
    }
  }

  /// Overwrites the live conversation's context mid-call (e.g. to feed the
  /// avatar the next interview question). POSTs a conversation.overwrite_context
  /// interaction and throws on any non-2xx so the caller can react.
  Future<void> sendInteraction(String conversationId, String text) async {
    final url = Uri.parse(
      'https://tavusapi.com/v2/conversations/$conversationId/interactions',
    );
    final http.Response response;
    try {
      response = await _api.post(
        url,
        headers: _authHeaders(),
        body: jsonEncode({
          'message_type': 'conversation',
          'event_type': 'conversation.overwrite_context',
          'conversation_id': conversationId,
          'properties': {'context': text},
        }),
      );
    } on ApiException catch (e) {
      throw Exception('Failed to send interaction: ${e.message}');
    }

    if (kDebugMode) {
      print('debug: POST sendInteraction status: ${response.statusCode}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to send interaction: HTTP ${response.statusCode}',
      );
    }
  }
}

final tavusService = TavusService();
