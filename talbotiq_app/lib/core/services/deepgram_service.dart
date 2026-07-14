// lib/core/services/deepgram_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../net/api_client.dart';
import '../../models/app_models.dart';

class DeepgramService {
  // Shared transport: request timeout + 429/5xx backoff-retry, so a stalled or
  // throttled Deepgram host no longer hangs (or one-shot-fails) transcription.
  final ApiClient _api = ApiClient();

  String _apiKey = '';

  void setKey(String key) {
    _apiKey = key;
  }

  String getKey() => _apiKey;

  // The API key trimmed — used as the Deepgram WebSocket subprotocol token.
  String getTrimmedKey() => _apiKey.trim();

  // Streaming endpoint for real-time transcription. Audio is streamed as
  // WebM/Opus from a MediaRecorder (NOT raw PCM), so we do NOT declare
  // encoding/sample_rate — Deepgram auto-detects the Opus container.
  String buildWsUrl() {
    final params = {
      'model': 'nova-3',
      'language': 'en-US',
      'punctuate': 'true',
      'smart_format': 'true',
      'interim_results': 'true', // emit words before the silence — maximum capture
      'utterance_end_ms': '1000', // flush after 1s of silence
      'vad_events': 'true', // voice-activity events
      'filler_words': 'true', // um, uh, like, you know — critical for an ATS
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return 'wss://api.deepgram.com/v1/listen?$query';
  }

  static final Set<String> fillerWords = {
    'um', 'uh', 'hmm', 'er', 'erm', 'ah', 'like', 'basically', 'literally',
    'actually', 'right', 'okay', 'so', 'you know', 'i mean', 'kind of', 'sort of',
  };

  int countFillers(String text) {
    if (text.isEmpty) return 0;
    final words = text.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), '').split(RegExp(r'\s+'));
    int count = 0;
    
    // Count exact matches of individual filler words
    for (var w in words) {
      if (fillerWords.contains(w)) count++;
    }
    
    // Also scan for double-word phrases like 'you know', 'i mean', 'kind of', 'sort of'
    final lowerText = text.toLowerCase();
    final phrases = ['you know', 'i mean', 'kind of', 'sort of'];
    for (var phrase in phrases) {
      int index = 0;
      while (true) {
        index = lowerText.indexOf(phrase, index);
        if (index == -1) break;
        count++; // Increment count for phrase match
        index += phrase.length;
      }
    }

    return count;
  }

  int countWords(List<TranscriptEntry> entries) {
    return entries
        .where((e) => e.role == 'candidate')
        .fold(0, (acc, e) => acc + e.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
  }

  int calcWpm(List<TranscriptEntry> entries) {
    final candidate = entries.where((e) => e.role == 'candidate').toList();
    if (candidate.length < 2) return 0;
    final durationMs = candidate.last.timestamp - candidate.first.timestamp;
    if (durationMs <= 0) return 0;
    final words = countWords(entries);
    return ((words / durationMs) * 60000).round();
  }

  Future<Map<String, dynamic>> testConnection() async {
    if (_apiKey.isEmpty) {
      return {'ok': false, 'message': 'No API key set'};
    }
    try {
      // Direct call to Deepgram projects list to verify API Key
      final response = await _api.get(
        Uri.parse('https://api.deepgram.com/v1/projects'),
        headers: {
          'Authorization': 'Token $_apiKey',
        },
      );
      if (response.statusCode == 200) {
        return {'ok': true, 'message': 'Deepgram Nova-3 connected'};
      } else if (response.statusCode == 401) {
        return {'ok': false, 'message': 'Invalid API key (401)'};
      } else {
        return {'ok': false, 'message': 'HTTP ${response.statusCode}'};
      }
    } on ApiException catch (e) {
      return {'ok': false, 'message': e.message};
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }

  /// Transcribe an audio file available at a public URL using Deepgram's
  /// pre-recorded endpoint. Returns a list with a single TranscriptEntry
  /// containing the combined transcript text.
  Future<List<TranscriptEntry>> transcribeFromUrl(
    String audioUrl, {
    String model = 'nova-3',
    String language = 'en-US',
  }) async {
    if (_apiKey.isEmpty) throw Exception('No Deepgram API key set');

    final params = {
      'model': model,
      'language': language,
      'punctuate': 'true',
      'smart_format': 'true',
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final uri = Uri.parse('https://api.deepgram.com/v1/listen?$query');

    try {
      if (kDebugMode) print('debug: Deepgram transcribeFromUrl POST $uri');
      final body = jsonEncode({'url': audioUrl});
      final response = await _api.post(
        uri,
        headers: {
          'Authorization': 'Token $_apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (kDebugMode) {
        print('debug: Deepgram status: ${response.statusCode}');
        final preview = response.body.length > 1000
            ? response.body.substring(0, 1000) + '...'
            : response.body;
        print('debug: Deepgram body preview: $preview');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        String transcript = '';

        try {
          transcript = data['results']?['channels']?[0]?['alternatives']?[0]?['transcript'] ?? '';
        } catch (_) {
          transcript = data['results']?.toString() ?? '';
        }

        if (transcript.isEmpty) {
          return [];
        }

        final entry = TranscriptEntry(
          role: 'candidate',
          text: transcript,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          questionIdx: 0,
        );

        return [entry];
      } else {
        throw Exception('Deepgram transcription failed: HTTP ${response.statusCode}');
      }
    } on ApiException catch (e) {
      if (kDebugMode) print('debug: transcribeFromUrl error: ${e.message}');
      throw Exception('Deepgram transcription failed: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('debug: transcribeFromUrl error: $e');
      rethrow;
    }
  }

  /// Transcribe a locally-recorded audio file (e.g. the candidate's .wav) by
  /// POSTing its raw bytes to Deepgram's pre-recorded endpoint. Returns a list
  /// with a single TranscriptEntry containing the combined transcript text.
  Future<List<TranscriptEntry>> transcribeFromFile(
    List<int> bytes, {
    String model = 'nova-3',
    String language = 'en-US',
    String contentType = 'audio/wav',
  }) async {
    if (_apiKey.isEmpty) throw Exception('No Deepgram API key set');
    if (bytes.isEmpty) return [];

    final params = {
      'model': model,
      'language': language,
      'punctuate': 'true',
      'smart_format': 'true',
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final uri = Uri.parse('https://api.deepgram.com/v1/listen?$query');

    if (kDebugMode) {
      print('debug: Deepgram transcribeFromFile POST $uri (${bytes.length} bytes)');
    }
    // Raw-bytes POST (Deepgram pre-recorded accepts the audio as the body with a
    // Content-Type header) — kept identical; routed through ApiClient for the
    // timeout + 429/5xx backoff-retry.
    final http.Response response;
    try {
      response = await _api.post(
        uri,
        headers: {
          'Authorization': 'Token $_apiKey',
          'Content-Type': contentType,
        },
        body: bytes,
      );
    } on ApiException catch (e) {
      throw Exception('Deepgram transcription failed: ${e.message}');
    }

    if (kDebugMode) {
      print('debug: Deepgram (file) status: ${response.statusCode}');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Deepgram transcription failed: HTTP ${response.statusCode}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    String transcript = '';
    try {
      transcript =
          data['results']?['channels']?[0]?['alternatives']?[0]?['transcript'] ?? '';
    } catch (_) {
      transcript = '';
    }

    if (transcript.isEmpty) return [];

    return [
      TranscriptEntry(
        role: 'candidate',
        text: transcript,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        questionIdx: 0,
      ),
    ];
  }
}

final deepgramService = DeepgramService();
