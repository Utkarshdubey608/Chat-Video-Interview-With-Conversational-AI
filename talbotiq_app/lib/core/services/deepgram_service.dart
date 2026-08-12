// lib/core/services/deepgram_service.dart
//
// Post-interview transcription of a locally-recorded file, plus the pace/filler
// analysis derived from any transcript.
//
// Deepgram is a FALLBACK: primary transcripts come from Tavus (verbose
// conversation polling) for video and Gemini Live for voice. This runs only when
// the device captured its own .wav — native platforms — and the pipeline needs a
// transcript from it.
//
// The Deepgram key lives on the backend; audio is POSTed to
// `/api/deepgram/transcribe` and the response shape is Deepgram's own, so the
// word-level slicing below is unchanged.
//
// There is no live-transcription path here. The old `buildWsUrl()` was never
// called, and `testConnection()` only existed to power a Settings button that no
// longer exists — both are gone rather than left as dead code.

import 'package:flutter/foundation.dart';

import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/shared/models/app_models.dart';

class DeepgramService {
  DeepgramService({BackendClient? backend}) : _injectedBackend = backend;

  /// Null in production so the shared client is resolved lazily — constructing
  /// one at import time would touch Firebase before it is initialised.
  final BackendClient? _injectedBackend;
  BackendClient get _backend => _injectedBackend ?? backendClient;

  static final Set<String> fillerWords = {
    'um', 'uh', 'hmm', 'er', 'erm', 'ah', 'like', 'basically', 'literally',
    'actually', 'right', 'okay', 'so', 'you know', 'i mean', 'kind of', 'sort of',
  };

  int countFillers(String text) {
    if (text.isEmpty) return 0;
    final words =
        text.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), '').split(RegExp(r'\s+'));
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
    return entries.where((e) => e.role == 'candidate').fold(
        0,
        (acc, e) =>
            acc + e.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
  }

  int calcWpm(List<TranscriptEntry> entries) {
    final candidate = entries.where((e) => e.role == 'candidate').toList();
    if (candidate.length < 2) return 0;
    final durationMs = candidate.last.timestamp - candidate.first.timestamp;
    if (durationMs <= 0) return 0;
    final words = countWords(entries);
    return ((words / durationMs) * 60000).round();
  }

  /// Maps a full language name (as chosen on the interview, e.g. 'Spanish') to a
  /// Deepgram language code. Unknown/unsupported languages fall back to 'en-US'
  /// so transcription still runs (English-biased) rather than erroring out.
  static String localeFor(String language) {
    switch (language.trim().toLowerCase()) {
      case 'english':
        return 'en-US';
      case 'spanish':
        return 'es';
      case 'french':
        return 'fr';
      case 'german':
        return 'de';
      case 'hindi':
        return 'hi';
      case 'portuguese':
        return 'pt';
      case 'italian':
        return 'it';
      case 'japanese':
        return 'ja';
      case 'mandarin':
      case 'chinese':
        return 'zh';
      case 'dutch':
        return 'nl';
      case 'korean':
        return 'ko';
      default:
        return 'en-US';
    }
  }

  /// Transcribe a locally-recorded audio file (e.g. the candidate's .wav) via the
  /// backend's Deepgram proxy.
  ///
  /// When [recordingStartTimestamp] and [questionTimestamps] are provided
  /// (both epoch-ms wall-clock values — see AppStore), the response's
  /// word-level timings are sliced into one TranscriptEntry PER QUESTION, so a
  /// recruiter reviewing per-question responses sees each answer under the
  /// right question instead of the whole call collapsed into question 1.
  /// Falls back to a single combined entry (questionIdx 0) when that slicing
  /// isn't possible (missing timestamps, or no words matched any window) —
  /// this must never regress to returning nothing.
  Future<List<TranscriptEntry>> transcribeFromFile(
    List<int> bytes, {
    String model = 'nova-3',
    String language = 'en-US',
    String contentType = 'audio/wav',
    int? recordingStartTimestamp,
    List<int> questionTimestamps = const [],
    int questionCount = 0,
  }) async {
    if (bytes.isEmpty) return [];

    if (kDebugMode) {
      debugPrint('debug: transcribe via backend (${bytes.length} bytes)');
    }

    final data = await _backend.postBytes(
      '/api/deepgram/transcribe',
      bytes,
      contentType: contentType,
      query: {'model': model, 'language': language},
    );

    final alternative =
        data['results']?['channels']?[0]?['alternatives']?[0] as Map?;
    String transcript = '';
    try {
      transcript = alternative?['transcript'] ?? '';
    } catch (_) {
      transcript = '';
    }

    if (transcript.isEmpty) return [];

    final wordsJson = alternative?['words'] as List?;
    if (recordingStartTimestamp != null &&
        questionTimestamps.isNotEmpty &&
        questionCount > 0 &&
        wordsJson != null &&
        wordsJson.isNotEmpty) {
      final sliced = _sliceByQuestion(
        wordsJson,
        recordingStartTimestamp: recordingStartTimestamp,
        questionTimestamps: questionTimestamps,
        questionCount: questionCount,
      );
      if (sliced.isNotEmpty) return sliced;
    }

    return [
      TranscriptEntry(
        role: 'candidate',
        text: transcript,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        questionIdx: 0,
      ),
    ];
  }

  /// Groups Deepgram's word-level timings into one TranscriptEntry per
  /// question, using [questionTimestamps] (wall-clock epoch ms, one push per
  /// question-index change plus a leading "interview became active" marker —
  /// see AppStore.setCurrentQuestionIdx/setInterviewActive) converted to
  /// seconds-from-recording-start via [recordingStartTimestamp].
  List<TranscriptEntry> _sliceByQuestion(
    List wordsJson, {
    required int recordingStartTimestamp,
    required List<int> questionTimestamps,
    required int questionCount,
  }) {
    // questionTimestamps carries exactly one extra LEADING entry (the
    // interview-active marker pushed just before question 0's own push) —
    // drop it so position i lines up with the real start of question i.
    final extra = questionTimestamps.length - questionCount;
    final starts =
        extra > 0 ? questionTimestamps.sublist(extra) : questionTimestamps;
    if (starts.isEmpty) return [];

    // Convert each question's start to seconds elapsed since the recording
    // actually began (clamped to 0 — the first question may be marked
    // fractionally before the recorder finished starting).
    final startSecs = starts
        .map((ts) =>
            ((ts - recordingStartTimestamp) / 1000.0).clamp(0.0, double.infinity))
        .toList();

    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <TranscriptEntry>[];
    for (var idx = 0; idx < questionCount; idx++) {
      if (idx >= startSecs.length) break;
      final start = startSecs[idx];
      final end =
          (idx + 1) < startSecs.length ? startSecs[idx + 1] : double.infinity;

      final wordsInWindow = wordsJson.where((w) {
        final wStart = (w is Map ? w['start'] as num? : null)?.toDouble();
        return wStart != null && wStart >= start && wStart < end;
      }).map((w) {
        final m = w as Map;
        return (m['punctuated_word'] ?? m['word'] ?? '').toString();
      }).where((s) => s.isNotEmpty);

      final text = wordsInWindow.join(' ').trim();
      if (text.isEmpty) continue;
      entries.add(TranscriptEntry(
        role: 'candidate',
        text: text,
        timestamp: now + idx,
        questionIdx: idx,
      ));
    }
    return entries;
  }
}

final deepgramService = DeepgramService();
