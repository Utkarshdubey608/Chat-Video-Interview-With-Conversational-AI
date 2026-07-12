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

import '../../recruiter/engine/defaults.dart';
import '../../recruiter/models/recruiter_models.dart';
import '../../recruiter/store/recruiter_store.dart';
import '../../recruiter/views/runner/conversation_runner_page.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';

Widget buildChatRunnerPage({
  required Interview interview,
  required InterviewRepository repository,
  required RecruiterStore recruiterStore,
}) {
  final now = DateTime.now().toIso8601String();
  final templateId = 'tpl_${interview.id}';
  final sessionId =
      'ses_${interview.id}_${DateTime.now().microsecondsSinceEpoch}';

  final fixed = <FixedQuestion>[
    for (int i = 0; i < interview.questions.length; i++)
      FixedQuestion(id: 'q$i', text: interview.questions[i]),
  ];

  final template = InterviewTemplate(
    id: templateId,
    name: interview.title,
    role: interview.title,
    track: TrackType.chatbot,
    questionSource: QuestionSource.fixed,
    timing: defaultTiming(),
    rubric: defaultRubric(),
    integrity: defaultIntegrity(),
    branding: defaultBranding(),
    mode: InterviewMode.conversational,
    createdAt: now,
    updatedAt: now,
  );

  // Upsert the ephemeral template so ReportPage (opened from the completion
  // screen) can resolve session.templateId. The runner also upserts the
  // finished session itself.
  recruiterStore.upsertTemplate(template);

  final session = InterviewSession(
    id: sessionId,
    templateId: templateId,
    track: TrackType.chatbot,
    candidateName: interview.candidateName ?? _localPart(interview.candidateEmail),
    candidateEmail: interview.candidateEmail,
    status: SessionStatus.created,
    questions: [
      for (final fq in fixed)
        SessionQuestion(
          id: fq.id,
          text: fq.text,
          category: fq.category,
          idealAnswerNotes: fq.idealAnswerNotes,
        ),
    ],
    createdAt: now,
    mode: InterviewMode.conversational,
  );

  return ConversationRunnerPage(
    session: session,
    template: template,
    fixedQuestionsOverride: fixed,
    candidateMode: true,
    onFinished: (completedSession, report) {
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
      });
    },
  );
}

String _localPart(String email) {
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : email;
}
