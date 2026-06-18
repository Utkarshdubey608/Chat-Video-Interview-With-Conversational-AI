// lib/core/services/tavus_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/app_models.dart';

class TavusService {
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
    return {
      'x-api-key': _apiKey,
    };
  }

  // Headers for requests that carry a JSON body (POST).
  Map<String, String> _headers() {
    return {
      'x-api-key': _apiKey,
      'Content-Type': 'application/json',
    };
  }

  // Merges custom and stock replicas
  Future<List<TavusReplica>> listReplicas() async {
    if (_apiKey.isEmpty) return [];

    try {
      final customUrl = Uri.parse('https://tavusapi.com/v2/replicas');
      final stockUrl = Uri.parse('https://tavusapi.com/v2/replicas?replica_type=stock');

      final results = await Future.wait([
        http.get(customUrl, headers: _authHeaders()).catchError((e) => http.Response('{"data":[]}', 500)),
        http.get(stockUrl, headers: _authHeaders()).catchError((e) => http.Response('{"data":[]}', 500)),
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
          customError = errBody?['message'] ?? errBody?['error'] ?? 'HTTP ${results[0].statusCode}';
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
          stockError = errBody?['message'] ?? errBody?['error'] ?? 'HTTP ${results[1].statusCode}';
        } catch (_) {
          stockError = 'HTTP ${results[1].statusCode}';
        }
      }

      // If both endpoints failed, throw the relevant errors
      if (!customSuccess && !stockSuccess) {
        throw Exception('Custom replicas: $customError | Stock replicas: $stockError');
      }

      return replicas;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<TavusPersona>> listPersonas() async {
    if (_apiKey.isEmpty) return [];

    final url = Uri.parse('https://tavusapi.com/v2/personas');
    final response = await http.get(url, headers: _authHeaders());

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'] as List?;
      if (list != null) {
        return list.map((item) => TavusPersona.fromJson(item)).toList();
      }
      return [];
    } else {
      final errBody = jsonDecode(response.body);
      throw Exception(errBody?['message'] ?? errBody?['error'] ?? 'HTTP ${response.statusCode}');
    }
  }

  Future<TavusConversation> createConversation(Map<String, dynamic> payload) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations');

    print("debug: Creating conversation with payload:");
    print(url.toString());
    print(jsonEncode(payload));
    print(_headers());

    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode(payload),
    );

    print("debug: Received response:");
    print("Status code: ${response.body}");

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return TavusConversation.fromJson(body);
    } else {
      Map? errBody;
      try {
        errBody = jsonDecode(response.body) as Map?;
      } catch (_) {}
      final msg = errBody?['message'] ?? errBody?['error'] ?? errBody?['detail'] ?? 'HTTP ${response.statusCode}';
      throw Exception(msg);
    }
  }

  Future<TavusConversation> getConversation(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id');
    final response = await http.get(url, headers: _authHeaders());

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return TavusConversation.fromJson(body);
    } else {
      throw Exception('Failed to load conversation: HTTP ${response.statusCode}');
    }
  }

  Future<List<TranscriptEntry>> getConversationTranscript(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id?verbose=true');
    final response = await http.get(url, headers: _authHeaders());

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List<TranscriptEntry> entries = [];

      // Extract events array/object
      final events = body['events'] ?? (body['data'] != null ? body['data']['events'] : null);
      
      if (events is List) {
        for (var event in events) {
          final type = event['event_type'] ?? '';
          
          if (type == 'application.transcription_ready') {
            final props = event['properties'] ?? event;
            final list = props['transcript'] as List?;
            if (list != null) {
              for (var item in list) {
                final String rawRole = (item['role'] ?? 'user').toString().toLowerCase();
                final String role = (rawRole == 'user' || rawRole == 'candidate' || rawRole == 'participant') ? 'candidate' : 'avatar';
                final String text = item['content'] ?? item['text'] ?? '';
                final int timestamp = item['timestamp'] != null
                    ? (item['timestamp'] is num 
                        ? (item['timestamp'] * 1000).round()
                        : (DateTime.tryParse(item['timestamp'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch))
                    : DateTime.now().millisecondsSinceEpoch;

                entries.add(TranscriptEntry(
                  role: role,
                  text: text,
                  timestamp: timestamp,
                  questionIdx: 0,
                ));
              }
            }
          } else if (type == 'conversation.utterance' || type == 'conversation.utterance.streaming') {
            final props = event['properties'] ?? event;
            final String rawRole = (props['role'] ?? 'user').toString().toLowerCase();
            final String role = (rawRole == 'user' || rawRole == 'candidate' || rawRole == 'participant') ? 'candidate' : 'avatar';
            final String text = props['text'] ?? props['content'] ?? '';
            final int timestamp = props['timestamp'] != null
                ? (props['timestamp'] is num
                    ? (props['timestamp'] * 1000).round()
                    : (DateTime.tryParse(props['timestamp'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch))
                : DateTime.now().millisecondsSinceEpoch;

            entries.add(TranscriptEntry(
              role: role,
              text: text,
              timestamp: timestamp,
              questionIdx: 0,
            ));
          }
        }
      } else if (events is Map) {
        final transcriptionReady = events['application.transcription_ready'];
        if (transcriptionReady != null) {
          final list = transcriptionReady['transcript'] as List?;
          if (list != null) {
            for (var item in list) {
              final String rawRole = (item['role'] ?? 'user').toString().toLowerCase();
              final String role = (rawRole == 'user' || rawRole == 'candidate' || rawRole == 'participant') ? 'candidate' : 'avatar';
              final String text = item['content'] ?? item['text'] ?? '';
              final int timestamp = item['timestamp'] != null
                  ? (item['timestamp'] is num 
                      ? (item['timestamp'] * 1000).round()
                      : (DateTime.tryParse(item['timestamp'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch))
                  : DateTime.now().millisecondsSinceEpoch;

              entries.add(TranscriptEntry(
                role: role,
                text: text,
                timestamp: timestamp,
                questionIdx: 0,
              ));
            }
          }
        }
      }
      
      // Fallback: check if there is a direct transcript field
      final directList = body['transcript'] ?? (body['data'] != null ? body['data']['transcript'] : null);
      if (directList is List && entries.isEmpty) {
        for (var item in directList) {
          final String rawRole = (item['role'] ?? 'user').toString().toLowerCase();
          final String role = (rawRole == 'user' || rawRole == 'candidate' || rawRole == 'participant') ? 'candidate' : 'avatar';
          final String text = item['content'] ?? item['text'] ?? '';
          final int timestamp = item['timestamp'] != null
              ? (item['timestamp'] is num 
                  ? (item['timestamp'] * 1000).round()
                  : (DateTime.tryParse(item['timestamp'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch))
              : DateTime.now().millisecondsSinceEpoch;

          entries.add(TranscriptEntry(
            role: role,
            text: text,
            timestamp: timestamp,
            questionIdx: 0,
          ));
        }
      }

      return entries;
    } else {
      throw Exception('Failed to load transcript: HTTP ${response.statusCode}');
    }
  }

  Future<String?> getConversationRecordingUri(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id?verbose=true');
    final response = await http.get(url, headers: _authHeaders());

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final events = body['events'] ?? (body['data'] != null ? body['data']['events'] : null);
      if (events is List) {
        for (var event in events) {
          if (event['event_type'] == 'application.recording_ready') {
            final props = event['properties'];
            if (props != null && props['storage_uri'] != null) {
              return props['storage_uri'].toString();
            }
          }
        }
      }
    }
    return null;
  }

  Future<void> endConversation(String id) async {
    final url = Uri.parse('https://tavusapi.com/v2/conversations/$id');
    final response = await http.delete(url, headers: _authHeaders());

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to end conversation: HTTP ${response.statusCode}');
    }
  }
}

final tavusService = TavusService();
