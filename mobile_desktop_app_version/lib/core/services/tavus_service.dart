// lib/core/services/tavus_service.dart
import 'package:flutter/foundation.dart';

import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/shared/models/app_models.dart';

/// True when a stored transcript turn is Tavus-injected CONFIGURATION rather
/// than spoken dialogue — the interviewer system prompt, or a context block
/// Tavus prepends to the conversation (e.g. the "user's timezone is unknown"
/// temporal reference).
///
/// Legacy shim + belt-and-braces. `_transcriptEntryFromItem` drops
/// `system`-role messages at parse time, but (a) results saved before that fix
/// already have them persisted as `avatar` turns, and (b) Tavus does not label
/// every injected block with a `system` role. The two transcript views filter
/// with this on render.
///
/// Matching is intentionally conservative so a genuinely long interviewer
/// answer is never hidden: the big system prompt needs BOTH bulk and a marker,
/// while the short injected context blocks are matched on their own
/// distinctive, machine-generated phrasing.
bool isNonDialogueTurn(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;

  // Short, machine-generated context blocks — matched on phrasing alone.
  const contextMarkers = [
    "user's timezone is unknown",
    'current date and time at the',
    'If temporal information becomes relevant',
    'start of the conversation** in different timezones',
  ];
  for (final m in contextMarkers) {
    if (t.contains(m)) return true;
  }

  // The full interviewer system prompt — needs bulk AND a marker.
  if (t.length < 400) return false;
  const promptMarkers = [
    'INTERVIEW SCRIPT',
    'STRICT RULES',
    'spoken aloud via TTS',
    'live video conference call',
    'Do NOT invent, add, skip, reorder',
    'You are Alex',
  ];
  for (final m in promptMarkers) {
    if (t.contains(m)) return true;
  }
  return false;
}

class TavusService {
  // Shared transport: request timeout + 429/5xx backoff-retry. POSTs are never
  // retried on timeout (ApiClient treats them as non-idempotent) so we never
  // risk a duplicate Tavus conversation create.
  TavusService({BackendClient? backend}) : _injectedBackend = backend;

  /// Null in production so the shared client resolves lazily — building one at
  /// import time would touch Firebase before it is initialised.
  final BackendClient? _injectedBackend;
  BackendClient get _backend => _injectedBackend ?? backendClient;

  /// Custom + stock replicas.
  ///
  /// The merge, de-duplication and `replica_type` labelling now happen on the
  /// backend (it makes both upstream calls and tolerates either one failing), so
  /// this is a single request.
  Future<List<TavusReplica>> listReplicas() async {
    final data = await _backend.getJson('/api/tavus/replicas');
    final list = data['data'];
    if (list is! List) return [];
    return list.map((item) => TavusReplica.fromJson(item)).toList();
  }

  Future<List<TavusPersona>> listPersonas() async {
    final data = await _backend.getJson('/api/tavus/personas');
    final list = data['data'];
    if (list is! List) return [];
    return list.map((item) => TavusPersona.fromJson(item)).toList();
  }

  /// Starts an avatar conversation.
  ///
  /// The response carries the Daily room URL the device joins directly, so the
  /// candidate's media never passes through our backend — only the create call
  /// does, because that is what needs the Tavus key.
  Future<TavusConversation> createConversation(
    Map<String, dynamic> payload,
  ) async {
    final body =
        await _backend.postJson('/api/tavus/conversations', body: payload);
    return TavusConversation.fromJson(body);
  }

  Future<TavusConversation> getConversation(String id) async {
    final body = await _backend.getJson('/api/tavus/conversations/$id');
    return TavusConversation.fromJson(body);
  }

  /// The server-side transcript, read from the conversation's verbose form.
  ///
  /// Tavus exposes it through the conversation object (in the `events` array as
  /// application.transcription_ready), not a /transcript sub-path.
  ///
  /// Lets [BackendException] propagate rather than wrapping it: it carries the
  /// status code, and [fetchTranscriptWithRetry] needs that to tell a transient
  /// "not ready yet" from a permanent "bad id".
  Future<List<TranscriptEntry>> getConversationTranscript(String id) async {
    final body = await _backend.getJson('/api/tavus/conversations/$id/verbose');
    final parsed = _parseTranscriptResponse(body);
    if (kDebugMode) {
      debugPrint(
        'debug: [Tavus] parsed ${parsed.length} transcript entries:\n'
        '${parsed.map((e) => '  [${e.role}] ${e.text}').join('\n')}',
      );
    }
    return parsed;
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
      } on BackendException catch (e) {
        // Only empty results, rate limits (429) and server errors (5xx) are
        // worth polling for. Every other 4xx is a permanent answer — a bad id, a
        // malformed request — and will still be wrong on attempt 18, so surface
        // it immediately instead of burning ~2 minutes of backoff. (This is what
        // turned a single "400 Invalid conversation_id" into an 18-attempt retry
        // storm in the logs.)
        //
        // 503 is included as permanent: from the backend it means Tavus is not
        // configured on the server, which no amount of polling will change.
        final code = e.statusCode;
        final permanent =
            code != null && code >= 400 && code < 500 && code != 429;
        if (e.isAuthError || e.isNotConfigured || permanent) rethrow;
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
    final body = await _backend.getJson('/api/tavus/conversations/$id/verbose');
    return _parseTranscriptResponse(body);
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

  // Stopwords stripped before comparing an avatar utterance to a scripted
  // question, so matching keys on the distinctive nouns/verbs ("pressure",
  // "deadlines") rather than words nearly every question shares ("how",
  // "do", "you").
  static const Set<String> _stopWords = {
    'a', 'an', 'the', 'is', 'are', 'do', 'does', 'did', 'you', 'your',
    'to', 'of', 'and', 'in', 'on', 'for', 'me', 'i', 'we', 'us', 'it',
    'that', 'this', 'with', 'how', 'what', 'where', 'when', 'why', 'who',
    'have', 'has', 'had', 'can', 'could', 'would', 'will', 'tell', 'about',
    'be', 'or', 'as', 'from', 'yourself',
  };

  Set<String> _significantTokens(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .toSet();

  /// Jaccard similarity (0-1) between two strings' significant tokens.
  double _similarity(String a, String b) {
    final ta = _significantTokens(a);
    final tb = _significantTokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0.0;
    final intersection = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  /// Assigns each entry's `questionIdx` by walking the transcript in its
  /// actual conversational order and fuzzy-matching each avatar utterance
  /// against [questions] to detect when a new question starts — candidate
  /// lines are attributed to whichever question most recently matched.
  ///
  /// This replaces an earlier wall-clock-timestamp-bucketing approach that
  /// compared entry timestamps against `AppStore.questionTimestamps` (when
  /// the *local UI* advanced to each question). That signal turned out to be
  /// unreliable in practice: the local UI's pacing (manual next/prev taps, or
  /// a fixed auto-advance timer) has no real connection to when Tavus's
  /// avatar actually asked each question in the live call, so timestamp
  /// bucketing could — and did, in testing — dump an entire session's answers
  /// into one question's bucket while leaving the rest blank. Using the
  /// transcript's own chronological avatar/candidate ordering (ground truth
  /// from the actual conversation) instead of a disconnected local proxy is
  /// far more robust.
  List<TranscriptEntry> sliceTranscriptByQuestion(
    List<TranscriptEntry> entries,
    List<String> questions,
  ) {
    if (entries.isEmpty || questions.isEmpty) return entries;

    // Minimum token-overlap ratio for an avatar line to count as "asking"
    // a given question rather than small talk ("Thanks for sharing that.").
    const matchThreshold = 0.34;

    var currentIdx = 0;
    final result = <TranscriptEntry>[];
    for (final e in entries) {
      if (e.role == 'avatar') {
        // Only consider questions at or after the current one — the avatar
        // moves forward through the script, never backward, so this also
        // guards against a stray high-overlap match to an already-asked
        // question re-appearing (e.g. in a wrap-up remark).
        var bestIdx = -1;
        var bestScore = 0.0;
        for (var i = currentIdx; i < questions.length; i++) {
          final score = _similarity(e.text, questions[i]);
          if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
          }
        }
        if (bestIdx != -1 && bestScore >= matchThreshold) {
          currentIdx = bestIdx;
        }
      }
      result.add(TranscriptEntry(
        text: e.text,
        role: e.role,
        timestamp: e.timestamp,
        questionIdx: currentIdx,
      ));
    }
    return result;
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

    // Tavus returns the conversation's SYSTEM INSTRUCTION as a `system`-role
    // message inside the transcript. It is configuration, not dialogue, so
    // drop it — the role mapping below sends anything non-user to 'avatar',
    // which previously rendered the entire interviewer prompt (persona rules,
    // the question script, guardrails) into the candidate-visible transcript.
    const nonDialogueRoles = {'system', 'context', 'developer', 'tool'};
    if (nonDialogueRoles.contains(rawRole)) return null;

    // Tavus does not label every injected block with a `system` role (its
    // temporal/timezone context arrives as a normal turn), so also drop
    // anything that reads as configuration. Keeps it out of storage entirely
    // rather than relying only on the render-time filter.
    if (isNonDialogueTurn(text)) return null;

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

  /// The stored recording's URI, once Tavus has published one.
  ///
  /// Returns null while the recording is still processing — absence is a normal
  /// state here, not an error.
  Future<String?> getConversationRecordingUri(String id) async {
    final body = await _backend.getJson('/api/tavus/conversations/$id/verbose');
    final events =
        body['events'] ?? (body['data'] != null ? body['data']['events'] : null);
    if (events is! List) return null;

    for (final event in events) {
      if (event is! Map) continue;
      if (event['event_type'] != 'application.recording_ready') continue;
      final uri = (event['properties'] as Map?)?['storage_uri'];
      if (uri != null) return uri.toString();
    }
    return null;
  }

  /// Ends the live call but KEEPS the conversation record and its server-side
  /// transcript.
  ///
  /// The backend POSTs to Tavus's /end action, never DELETE — a DELETE destroys
  /// the record and the transcript with it, leaving the results page with
  /// nothing to fetch.
  Future<void> endConversation(String id) async {
    await _backend.postJson('/api/tavus/conversations/$id/end');
  }

  /// Overwrites the live conversation's context mid-call (e.g. to feed the
  /// avatar the next interview question). Throws so the caller can react.
  Future<void> sendInteraction(String conversationId, String text) async {
    await _backend.postJson(
      '/api/tavus/conversations/$conversationId/interactions',
      body: {'text': text},
    );
  }
}

final tavusService = TavusService();
