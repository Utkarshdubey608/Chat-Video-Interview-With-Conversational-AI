// lib/features/interviews/candidate/voice_launch.dart
//
// Launches a real-time VOICE interview (Gemini Live) for an assigned Interview.
//
// Mints a short-lived session token from the backend, runs the VoiceStage, and —
// on completion — scores the captured transcript with the same Gemini analysis
// pipeline the video track uses, writing an UNPUBLISHED result to Firestore (the
// recruiter reviews + publishes).
//
// The interviewer's system instruction is NOT built here any more. It is
// assembled server-side (backend/app/voice.py) and sealed into the token, so a
// tampered client cannot rewrite the interview it is taking.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/services/gemini_live_service.dart';
import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/core/net/live_token.dart';
import 'package:talbotiq/core/services/gemini_service.dart';
import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/candidate/voice_stage.dart';

Future<void> launchVoiceInterview({
  required BuildContext context,
  required Interview interview,
}) async {
  final store = context.read<AppStore>();
  final repo = context.read<InterviewRepository>();

  // Minted immediately before connecting: the grant's connect window is short,
  // and the whole session config (model, voice, interviewer instruction) is
  // sealed inside it server-side.
  final LiveTokenGrant grant;
  try {
    grant = await backendClient.mintLiveToken(interviewId: interview.id);
  } on BackendException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VoiceStage(
        grant: grant,
        companyName: interview.recruiterName ?? 'TalbotIQ',
        // Recruiter-configured limit; null (none set) keeps the service default.
        maxDuration: interview.durationMinutes > 0
            ? Duration(minutes: interview.durationMinutes)
            : null,
        // Fire-and-forget scoring on graceful completion; the candidate never
        // sees the score. Completion (a placeholder result, upgraded if/when
        // scoring succeeds) is written unconditionally in _scoreAndStore.
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

  // The attempt has started — count it, then restore the candidate's own
  // keys. Best-effort/unawaited, so it must catch its own errors — an
  // unawaited Future's rejection is otherwise an uncaught async error (e.g.
  // if Firestore is unreachable), regardless of any try/catch around the
  // caller's `await launchVoiceInterview(...)`.
  repo
      .incrementAttempt(interview.id)
      .catchError((e) => debugPrint('incrementAttempt failed: $e'));
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
  // The candidate finished the call — mark it completed with an empty/
  // unscored placeholder immediately, before attempting AI scoring below.
  // Mirrors the video track's fix (see candidate_video_shell.dart): scoring
  // can fail, or the transcript can be too short to score, but the candidate
  // genuinely completed the interview and must not be offered a "fresh"
  // relaunch that silently burns another attempt with nothing to show for
  // the first one. `evaluatedBy: ''` tells the recruiter's review screen
  // nothing has scored this yet, so they can evaluate it manually.
  try {
    await repo.completeWithResult(interview.id, {
      'overallScore': 0,
      'summary': '',
      'recommendation': '',
      'strengths': const <String>[],
      'improvements': const <String>[],
      'evaluatedBy': '',
    });
  } catch (_) {
    // Placeholder write failed (e.g. offline) — fall through and still try
    // the real scoring attempt below.
  }

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
    // Too little was said to score meaningfully. Do NOT just bail: returning
    // here left the blank placeholder written at the top of this function, so
    // the recruiter opened an empty evaluation form with no score, no answers
    // and no explanation — which is why voice results appeared to "not show up"
    // at all. Write the raw responses plus the reason instead, so the recruiter
    // sees what happened and can evaluate manually or regenerate.
    if (combined.length < 30) {
      try {
        await repo.completeWithResult(interview.id, {
          'overallScore': 0,
          'summary': '',
          'recommendation': '',
          'strengths': const <String>[],
          'improvements': const <String>[],
          'evaluatedBy': '',
          'evaluationError':
              'No usable spoken answers were captured (only '
              '${combined.length} character(s) of speech). The microphone may '
              'have been muted or blocked, or the candidate did not answer.',
          'responsesApproximate': true,
          'responses': [
            for (var idx = 0; idx < interview.questions.length; idx++)
              {
                'question': interview.questions[idx],
                'answer': idx < scored.length ? scored[idx] : '',
              },
          ],
        });
      } catch (_) {
        // Offline: the placeholder already marks it completed.
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    // NOTE: per-question voice attribution is APPROXIMATE on-device — the
    // website aligns each answer to a specific planned question server-side
    // (voiceFlow: VAD turn boundaries + token-overlap matching against the
    // question plan); on-device we have no equivalent alignment step, and VAD
    // can occasionally split one spoken answer across two captions, which
    // would shift every following index by one. A previous revision mapped
    // questionIdx=i and hit exactly that shift — but the actual cause was the
    // candidate's leading "yes, I'm ready" caption being counted as answer #1
    // (pushing every real answer down by one), which is now stripped ABOVE via
    // _isReadinessReply before this list is built. With that fixed,
    // position-based attribution is correct in the common case (one turn per
    // question) and only degrades for the rare mid-answer VAD split — same as
    // before. Hardcoding questionIdx=0 for every entry (as this used to do)
    // was strictly worse: it fed the analyzer a transcript where every answer
    // belongs to question 1 and every other question shows "no spoken answer
    // captured", corrupting the per-question evidence behind the overall
    // score/recommendation, not just an unused breakdown.
    final transcript = <TranscriptEntry>[
      for (var i = 0; i < scored.length; i++)
        TranscriptEntry(
          text: scored[i],
          role: 'candidate',
          timestamp: now + i,
          questionIdx: i,
        ),
    ];

    final sc = await geminiService.analyze(
      candidateName: interview.candidateName ?? '',
      jobRole: interview.title,
      interviewDurationSeconds: interview.durationMinutes * 60,
      transcript: transcript,
      questions: interview.questions,
      wpm: 0,
      totalFillers: 0,
      facialSummary: null,
    );

    await repo.completeWithResult(interview.id, {
      'overallScore': sc.overallFitScore ?? 0,
      'summary': sc.hiringRecommendationRationale,
      'recommendation': mapHiringRecommendationToCanonical(sc.hiringRecommendation),
      'strengths': sc.topStrengths,
      'improvements': sc.topConcerns,
      'evaluatedBy': 'ai',
      'detail': sc.toJson(),
      // Best-effort only: paired by position, not real attribution (see the
      // NOTE above on why voice has no reliable per-question mapping).
      'responsesApproximate': true,
      'responses': [
        // Iterate to the LONGER of the two lengths so every planned question
        // still appears (blank answer if unanswered — matching the video/chat
        // reference's completeness) instead of silently dropping trailing
        // unanswered questions, while any answer beyond the plan is still
        // preserved as an "Additional response".
        for (var idx = 0;
            idx < interview.questions.length || idx < scored.length;
            idx++)
          {
            'question': idx < interview.questions.length
                ? interview.questions[idx]
                : 'Additional response',
            'answer': idx < scored.length ? scored[idx] : '',
          },
      ],
    });
  } catch (e) {
    // Scoring failed (network, bad key, safety block...). Mirror the video
    // track's fallback (candidate_video_shell._maybeSubmitFallbackOnFailure):
    // still hand the recruiter the RAW responses plus the error, so their
    // "Regenerate Results" button — which is gated on `responses` being
    // non-empty — is actually usable. Without this the recruiter got a blank
    // placeholder with no way to see what was said or re-score it.
    try {
      final scored = List<String>.from(responses);
      if (scored.isNotEmpty && _isReadinessReply(scored.first)) {
        scored.removeAt(0);
      }
      await repo.completeWithResult(interview.id, {
        'overallScore': 0,
        'summary': '',
        'recommendation': '',
        'strengths': const <String>[],
        'improvements': const <String>[],
        'evaluatedBy': '',
        'evaluationError': e.toString().replaceAll('Exception: ', ''),
        'responsesApproximate': true,
        'responses': [
          for (var idx = 0;
              idx < interview.questions.length || idx < scored.length;
              idx++)
            {
              'question': idx < interview.questions.length
                  ? interview.questions[idx]
                  : 'Additional response',
              'answer': idx < scored.length ? scored[idx] : '',
            },
        ],
      });
    } catch (_) {
      // Even the fallback write failed (offline). The placeholder from the top
      // of this function already marks the interview completed, so the
      // recruiter can still evaluate it manually.
    }
  }
}
