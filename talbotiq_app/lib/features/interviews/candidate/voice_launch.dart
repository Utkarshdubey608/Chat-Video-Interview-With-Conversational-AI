// lib/features/interviews/candidate/voice_launch.dart
//
// Launches a real-time VOICE interview (Gemini Live) for an assigned Interview.
// Applies the recruiter's org Gemini key in-memory, builds the interviewer
// system instruction from the interview's questions/prompt/language, runs the
// VoiceStage, and — on completion — scores the captured transcript with the same
// Gemini analysis pipeline the video track uses, writing an UNPUBLISHED result
// to Firestore (the recruiter reviews + publishes).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/gemini_live_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_store.dart';
import '../../app_config/app_config_service.dart';
import '../../recruiter/voice/voice_catalog.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';
import 'voice_stage.dart';

Future<void> launchVoiceInterview({
  required BuildContext context,
  required Interview interview,
}) async {
  final store = context.read<AppStore>();
  final repo = context.read<InterviewRepository>();
  final appConfig = context.read<AppConfigService>();

  // Apply the org keys in-memory (Gemini key drives both the Live call and the
  // post-interview scoring). Never persisted to the candidate's Settings.
  await appConfig.applyForRecruiter(interview.recruiterId, store,
      overrides: interview.keyOverrides);
  if (!context.mounted) return;

  final geminiKey = store.geminiKey.trim();
  if (geminiKey.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Voice interview isn’t available yet — the recruiter has not configured a Gemini key.'),
    ));
    await store.reloadApiKeysFromPrefs();
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VoiceStage(
        apiKey: geminiKey,
        systemInstruction: _buildVoiceSystemInstruction(interview),
        companyName: interview.recruiterName ?? 'TalbotIQ',
        voiceName: interview.voiceName,
        // Fire-and-forget scoring on graceful completion; the candidate never
        // sees the score. A failed/short interview stays retakeable.
        onFinished: (state, responses) {
          if (state == GeminiLiveState.ended) {
            _scoreAndStore(
              store: store,
              repo: repo,
              interview: interview,
              responses: responses,
            );
          }
        },
      ),
    ),
  );

  // The attempt has started — count it, then restore the candidate's own keys.
  repo.incrementAttempt(interview.id);
  await store.reloadApiKeysFromPrefs();
}

String _buildVoiceSystemInstruction(Interview interview) {
  final questions = interview.questions;
  final b = StringBuffer();
  // Adopt the recruiter-chosen interviewer persona style, if any.
  final persona = interview.voicePersonaId == null
      ? null
      : VoiceCatalog.personaById(interview.voicePersonaId!);
  if (persona != null) {
    b.writeln(persona.stylePrompt);
  }
  b
    ..writeln(
        'You are a professional AI voice interviewer for the role: "${interview.title}".')
    ..writeln('Conduct the interview entirely in ${interview.language}.')
    ..writeln(
        'Greet the candidate warmly, briefly confirm they are ready, then ask ONLY the '
        'planned questions below, one at a time, in order, with short natural acknowledgments '
        'between answers. Never reveal upcoming questions, never say question numbers, and do '
        'not add questions beyond the plan. After the final question, thank the candidate warmly and end.');
  if (interview.prompt.trim().isNotEmpty) {
    b.writeln('\nInterviewer guidance: ${interview.prompt.trim()}');
  }
  if (questions.isNotEmpty) {
    b.writeln('\nPlanned questions (ask in this order):');
    for (var i = 0; i < questions.length; i++) {
      b.writeln('${i + 1}. ${questions[i]}');
    }
  }
  return b.toString();
}

/// True if [text] looks like the candidate's opening readiness acknowledgment
/// ("Yes, I'm ready", "Sure, let's go", "Ready") rather than a real answer.
/// Bounded to short lines so a genuine answer that merely contains "yes" is
/// never discarded.
bool _isReadinessReply(String text) {
  final t = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return false;
  final wordCount = t.split(' ').where((w) => w.isNotEmpty).length;
  if (wordCount > 8) return false; // too long to be a bare readiness reply
  return RegExp(
    r'\b(ready|yes|yeah|yep|yup|sure|okay|ok|absolutely|of course|lets go|'
    r'let s go|go ahead|i am|i m|all set|sounds good|ready to begin)\b',
  ).hasMatch(t);
}

Future<void> _scoreAndStore({
  required AppStore store,
  required InterviewRepository repo,
  required Interview interview,
  required List<String> responses,
}) async {
  try {
    // Drop an obvious leading readiness/short-affirmation reply ("Yes, I'm
    // ready") if present. The Live model always opens with "are you ready?", so
    // the candidate's first caption is typically that acknowledgment — scoring
    // it as a real answer (and shifting every subsequent answer by one) would
    // corrupt the transcript. Only the FIRST line, and only when it is short
    // and affirmation-shaped, is dropped.
    final scored = List<String>.from(responses);
    if (scored.isNotEmpty && _isReadinessReply(scored.first)) {
      scored.removeAt(0);
    }

    final combined = scored.join(' ').trim();
    // Not enough was said to score meaningfully — leave the interview
    // in-progress/retakeable rather than writing a placeholder result.
    if (combined.length < 30) return;

    geminiService.setKey(store.geminiKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    // NOTE: per-question voice attribution is APPROXIMATE on-device. The website
    // aligns each answer to a specific planned question server-side (voiceFlow:
    // VAD turn boundaries + token-overlap matching against the question plan).
    // On-device we have no reliable per-caption→question map — VAD can split one
    // spoken answer across several captions and blur across question boundaries —
    // so we deliberately do NOT fabricate a false ordinal map (the old
    // questionIdx=i mapping mis-attributed every answer once the readiness reply
    // was counted). Instead we assign a stable, non-misleading index (0) and let
    // the analyzer score the HOLISTIC transcript, which is sound for the overall
    // fit score even without honest per-question attribution.
    final transcript = <TranscriptEntry>[
      for (var i = 0; i < scored.length; i++)
        TranscriptEntry(
          text: scored[i],
          role: 'candidate',
          timestamp: now + i,
          questionIdx: 0,
        ),
    ];

    final sc = await geminiService.analyze(
      candidateName: interview.candidateName ?? '',
      jobRole: interview.title,
      interviewDurationSeconds: interview.durationMinutes * 60,
      transcript: transcript,
      questions: interview.questions,
      humeResult: null,
      wpm: 0,
      totalFillers: 0,
      facialSummary: null,
    );

    await repo.completeWithResult(interview.id, {
      'overallScore': sc.overallFitScore ?? 0,
      'summary': sc.hiringRecommendationRationale,
      'recommendation': sc.hiringRecommendation,
      'strengths': sc.topStrengths,
      'improvements': sc.topConcerns,
      'evaluatedBy': 'ai',
      'detail': sc.toJson(),
    });
  } catch (_) {
    // Scoring failed (no/short answers, network, key) — leave the interview
    // retakeable instead of persisting a bad result.
  }
}
