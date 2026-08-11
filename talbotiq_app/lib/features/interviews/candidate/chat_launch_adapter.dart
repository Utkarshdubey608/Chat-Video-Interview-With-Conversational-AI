// lib/features/interviews/candidate/chat_launch_adapter.dart
//
// Bridges the focused Firestore `Interview` model to the existing recruiter chat
// runner. It builds ephemeral (in-memory) InterviewTemplate + InterviewSession
// objects plus a FixedQuestion list from the Interview, then returns a
// ConversationRunnerPage wired to run them. Questions are passed via the
// controller's `fixedQuestionsOverride` so no persisted QuestionSet is needed;
// the ephemeral template is upserted into RecruiterStore only so the runner's
// built-in "View report" (ReportPage) can resolve it. On completion the report
// is mirrored back to the Interview doc in Firestore.

import 'package:flutter/widgets.dart';

import 'package:talbotiq/features/recruiter/engine/conversation_engine.dart';
import 'package:talbotiq/features/recruiter/engine/defaults.dart';
import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/features/recruiter/views/runner/conversation_runner_page.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

Widget buildChatRunnerPage({
  required Interview interview,
  required InterviewRepository repository,
  required RecruiterStore recruiterStore,
}) {
  final now = DateTime.now().toIso8601String();
  final templateId = 'tpl_${interview.id}';
  final sessionId =
      'ses_${interview.id}_${DateTime.now().microsecondsSinceEpoch}';

  final isAdaptive = interview.adaptive;

  // Optional per-question countdown. When the recruiter enabled it, run the
  // conversation in the existing timed mode (thinking→answer→auto-submit);
  // otherwise keep the untimed conversational behaviour unchanged.
  final ct = interview.chatTimer;
  final bool isTimed = ct != null && ct['enabled'] == true;
  final ConversationTimingConfig? timing = isTimed
      ? ConversationTimingConfig(
          perQuestionSeconds:
              (ct['perQuestionSeconds'] as num?)?.toInt() ?? 120,
          thinkingSeconds: (ct['thinkingSeconds'] as num?)?.toInt() ?? 0,
          allowSkipThinking: true,
          allowEarlySubmit: ct['allowEarlySubmit'] as bool? ?? true,
          warningThresholdSeconds:
              (ct['warningThresholdSeconds'] as num?)?.toInt() ?? 15,
        )
      : null;
  final String convMode =
      isTimed ? InterviewMode.timed : InterviewMode.conversational;

  // Fixed-track questions (empty/ignored for the adaptive track).
  final fixed = <FixedQuestion>[
    for (int i = 0; i < interview.questions.length; i++)
      FixedQuestion(id: 'q$i', text: interview.questions[i]),
  ];

  // Adaptive config: the recruiter's stored config wins, but the interview
  // title backfills the role when the config doesn't set one.
  final AdaptiveConfig? adaptiveCfg = isAdaptive
      ? AdaptiveConfig.fromJson({
          'role': interview.title,
          ...?interview.adaptiveConfig,
          'language': interview.language,
        })
      : null;

  final template = InterviewTemplate(
    id: templateId,
    name: interview.title,
    role: interview.title,
    track: TrackType.chatbot,
    questionSource:
        isAdaptive ? QuestionSource.adaptive : QuestionSource.fixed,
    timing: defaultTiming(),
    rubric: defaultRubric(),
    integrity: interview.integrity != null
        ? IntegrityConfig.fromJson(interview.integrity!)
        : defaultIntegrity(),
    branding: interview.branding != null
        ? BrandingConfig.fromJson(interview.branding!)
        : defaultBranding(),
    mode: convMode,
    adaptive: adaptiveCfg,
    conversationTiming: timing,
    createdAt: now,
    updatedAt: now,
  );

  // Upsert the ephemeral template so ReportPage (opened from the completion
  // screen) can resolve session.templateId. The runner also upserts the
  // finished session itself.
  //
  // IMPORTANT: this notifies RecruiterStore's listeners, so this function must
  // NEVER be called from inside a build (e.g. straight from a
  // MaterialPageRoute `builder:`) — that throws "setState() or
  // markNeedsBuild() called during build" and the route fails to render.
  // Call it first, then push the returned widget. See candidate_home's
  // _launchChat.
  recruiterStore.upsertTemplate(template);

  final session = InterviewSession(
    id: sessionId,
    templateId: templateId,
    track: TrackType.chatbot,
    candidateName: interview.candidateName ?? _localPart(interview.candidateEmail),
    candidateEmail: interview.candidateEmail,
    status: SessionStatus.created,
    // Adaptive generates its own questions; fixed carries the recruiter's set.
    questions: isAdaptive
        ? const []
        : [
            for (final fq in fixed)
              SessionQuestion(
                id: fq.id,
                text: fq.text,
                category: fq.category,
                idealAnswerNotes: fq.idealAnswerNotes,
              ),
          ],
    createdAt: now,
    mode: convMode,
  );

  return ConversationRunnerPage(
    session: session,
    template: template,
    // Only pin fixed questions for the fixed track; adaptive lets the engine
    // generate them (résumé-grounded via the runner's built-in résumé step).
    fixedQuestionsOverride: isAdaptive ? null : fixed,
    candidateMode: true,
    // Recruiter-configured whole-interview limit; null = no cap.
    maxDurationSeconds:
        interview.durationMinutes > 0 ? interview.durationMinutes * 60 : null,
    onFinished: (completedSession, report, scoringError) {
      // Mirror the same integrity signal the video track writes, so the
      // recruiter's evaluate screen surfaces "left the app N times" for chat
      // interviews too. Only written when it actually happened.
      final integrity = completedSession.tabSwitchCount > 0
          ? {'leftAppCount': completedSession.tabSwitchCount}
          : null;
      final responses = [
        for (final g in primaryQuestionGroups(completedSession.transcript ?? []))
          {'question': g.question, 'answer': g.answer},
      ];

      // A DEGRADED report is the heuristic fallback: its scores come from answer
      // LENGTH, not content (see conversationHeuristicReport). It used to be
      // stored as `evaluatedBy: 'ai'`, which showed the recruiter a fabricated
      // number indistinguishable from a real evaluation and let it be published
      // to the candidate. Store the failure instead — no score, the reason, and
      // the raw answers so the recruiter can retry scoring in one tap.
      if (report.degraded == true) {
        repository.completeWithoutScore(
          interview.id,
          error: scoringError?.trim().isNotEmpty == true
              ? scoringError!.trim()
              // No exception means the scorer was never reachable in the first
              // place, which is a configuration problem, not a transient one.
              : 'AI scoring was unavailable, so no score was produced.',
          responses: responses,
          integrity: integrity,
        );
        return;
      }

      // Store an UNPUBLISHED canonical result so the recruiter can review,
      // edit and publish it. The candidate does not see it yet.
      repository.completeWithResult(interview.id, {
        'overallScore': report.overallScore.round(),
        'summary': report.summary,
        'recommendation': report.recommendation ?? '',
        'strengths': report.strengths ?? const <String>[],
        'improvements': report.improvements ?? const <String>[],
        'evaluatedBy': 'ai',
        'detail': report.toJson(),
        if (integrity != null) 'integrity': integrity,
        'responses': responses,
      });
    },
  );
}

String _localPart(String email) {
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : email;
}
