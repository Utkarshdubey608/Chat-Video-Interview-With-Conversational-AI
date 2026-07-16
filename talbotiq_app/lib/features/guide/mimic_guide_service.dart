// lib/features/guide/mimic_guide_service.dart
//
// "Mimic Guide" — the in-app AI HELP ASSISTANT for TalbotIQ recruiters. It is a
// product-help chat (NOT an interview / scoring feature): it explains how to use
// templates, question sets, sessions, scoring and reports.
//
// It mirrors the exact Gemini REST approach used by
// lib/features/recruiter/services/recruiter_gemini_service.dart — raw
// generateContent over the shared [ApiClient] (request timeout + 429/503
// backoff), key travelling in the x-goog-api-key header, ```json-safe parsing.
// The Gemini key is the app's single existing key: we read it from
// [recruiterGeminiService], which AppStore keeps in sync on every change, so the
// guide is enabled exactly when the rest of the Gemini features are.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';

/// One chat turn in the guide conversation.
class GuideMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const GuideMessage({required this.role, required this.text});

  bool get isUser => role == 'user';
}

class MimicGuideService {
  MimicGuideService({RecruiterGeminiService? keySource})
      : _keySource = keySource ?? recruiterGeminiService;

  // Shared transport: request timeout + conservative 429/503 backoff so a
  // stalled Gemini host can never hang the help chat indefinitely.
  final ApiClient _api = ApiClient();

  // The guide has no key of its own — it reuses the app's single Gemini key,
  // which AppStore pushes into recruiterGeminiService on every change.
  final RecruiterGeminiService _keySource;

  final String _model = 'gemini-2.5-flash';

  // Standard Gemini safety thresholds, matching the other services.
  static const List<Map<String, String>> _safetySettings = [
    {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_ONLY_HIGH'},
    {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_ONLY_HIGH'},
    {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_ONLY_HIGH'},
    {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_ONLY_HIGH'},
  ];

  /// The guide is available exactly when a Gemini key is configured.
  bool get enabled => _keySource.enabled;

  static const String _systemInstruction = '''
You are "Mimic Guide", the friendly in-app product help assistant for TalbotIQ — an AI-powered recruiting and interview platform. You help RECRUITERS learn how to use the app.

Scope of what you help with:
- Interview templates: creating them, setting the role/seniority, and editing the scoring rubric (KPIs).
- Question sets: writing questions, generating them from a candidate résumé, and organising fixed vs. adaptive/conversational interviews.
- Sessions: running an interview (fixed/timed track or the adaptive conversational track), and what happens during a session.
- Scoring: how KPI-based scoring works, what the recommendation (strong_yes / yes / maybe / no) means, and that scoring is AI-assisted and meant to support — not replace — human judgement.
- Reports: reading a candidate's scorecard, per-question feedback, strengths/concerns, and exporting/sharing a report.
- Settings: where to add API keys (Gemini, Tavus, Deepgram, Hume) and configure the platform.

Style:
- Be concise, warm and practical. Prefer short paragraphs and numbered steps for "how do I…" questions.
- Use plain text only — no markdown headings, tables or code fences. Simple numbered or dashed lists are fine.
- If a question is outside TalbotIQ product help (general trivia, coding help, personal advice), gently redirect: say you are the TalbotIQ product guide and offer a relevant thing you can help with instead.
- Never invent features. If you are unsure whether a specific capability exists, say so and suggest checking the relevant section of the app rather than guessing.
- Never ask the user for API keys, passwords or candidate personal data.
''';

  /// Send one chat turn. [history] is the full running conversation, oldest
  /// first, with the user's newest message as the last entry. Returns the
  /// assistant's reply text. Throws [Exception] with a user-facing message on
  /// missing key / transport / empty-response errors.
  Future<String> sendMessage(List<GuideMessage> history) async {
    final key = _keySource.getKey();
    if (key.isEmpty) {
      throw Exception(
          'No Gemini API key configured. Add one in Settings → API Credentials to use the guide.');
    }
    if (history.isEmpty) {
      throw Exception('Nothing to send.');
    }

    final contents = history
        .map((m) => {
              'role': m.isUser ? 'user' : 'model',
              'parts': [
                {'text': m.text}
              ],
            })
        .toList();

    final body = {
      'systemInstruction': {
        'parts': [
          {'text': _systemInstruction}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.5,
        'maxOutputTokens': 1200,
      },
      'safetySettings': _safetySettings,
    };

    // Key travels in the x-goog-api-key header, never in the URL, so it can't
    // leak into request logs / proxies / crash traces.
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent');

    final http.Response response;
    try {
      response = await _api.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
        },
        body: jsonEncode(body),
      );
    } on ApiException catch (e) {
      throw Exception(_friendlyError(e.statusCode, e.message));
    }

    if (response.statusCode != 200) {
      throw Exception(_friendlyError(response.statusCode, response.body));
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
          'The guide received an unreadable response. Please try again.');
    }

    // Empty-but-present candidates/parts (MAX_TOKENS, safety block) must not
    // throw via [0] — treat them as an empty reply.
    String? text;
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = candidates[0]?['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is List && parts.isNotEmpty) {
        final t = parts[0]?['text'];
        if (t is String) text = t;
      }
    }
    if (text == null || text.trim().isEmpty) {
      throw Exception(
          'The guide could not produce a reply this time. Please rephrase and try again.');
    }
    return text.trim();
  }

  String _friendlyError(int? status, String? body) {
    final msg = (body ?? '').toLowerCase();
    if (status == 400 && (msg.contains('api key') || msg.contains('api_key'))) {
      return 'Gemini rejected the API key. Check it in Settings → API Credentials (valid keys start with "AIza").';
    }
    if (status == 429 || msg.contains('quota') || msg.contains('rate')) {
      return 'Gemini rate limit / quota reached. Wait a moment and try again.';
    }
    if (msg.contains('safety') || msg.contains('blocked')) {
      return 'The guide blocked that request for safety reasons. Try rephrasing.';
    }
    return 'The guide request failed (${status ?? 'no connection'}). Please try again.';
  }
}

final mimicGuideService = MimicGuideService();
