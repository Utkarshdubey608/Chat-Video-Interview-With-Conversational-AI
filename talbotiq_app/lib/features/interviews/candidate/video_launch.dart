// lib/features/interviews/candidate/video_launch.dart
//
// Shared Tavus video launch used by both the assigned-interview flow
// (candidate_home) and the self-serve practice flow (practice_page). Mirrors
// setup_page's pre-launch reset + store seeding, then pushes the
// currentRoute-driven CandidateVideoShell. Callers own key selection,
// validation, loading UI and error handling; this throws on failure.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_models.dart';
import '../../../providers/app_store.dart';
import '../../../core/services/tavus_service.dart';
import '../../../views/setup/launch_payload.dart';
import '../models/interview.dart';
import 'candidate_video_shell.dart';

/// Creates the Tavus conversation from [config] + [questions], seeds the
/// AppStore and opens the video shell. Assumes `tavusService` is already keyed.
Future<void> launchVideoConversation({
  required BuildContext context,
  required DraftForm config,
  required List<String> questions,
  required String candidateName,
  Interview? interview,
  String? resumeText,
  FacialSessionSummary? facialSummary,
}) async {
  final store = context.read<AppStore>();

  // Ground the avatar in the candidate's résumé when one was provided.
  final effectiveConfig = (resumeText != null && resumeText.trim().isNotEmpty)
      ? config.copyWith(
          conversationalContext:
              '${config.conversationalContext}\n\n'
              'Candidate résumé (use it to tailor and follow up on your questions):\n'
              '${resumeText.trim()}',
        )
      : config;

  final payload = buildConversationPayload(
    config: effectiveConfig,
    questions: questions,
    candidateName: candidateName,
  );
  final conv = await tavusService.createConversation(payload);

  _resetHumeState(store);
  // Set the pre-call facefit result AFTER the reset so the results pipeline
  // can fuse it into the scorecard.
  store.setFacialSummary(facialSummary);
  // Carry the real role + duration so scoring isn't judged against a hardcoded
  // default (falls back to the config for self-serve practice).
  store.setActiveInterviewMeta(
    role: interview?.title ?? config.conversationName,
    durationSeconds: (interview?.durationMinutes ?? 0) > 0
        ? interview!.durationMinutes * 60
        : config.maxCallDuration,
  );
  store.setQuestions(questions);
  store.setCurrentConversation(conv);
  store.setInterviewActive(true);
  store.setCurrentQuestionIdx(0);
  store.navigateTo('/interview');

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CandidateVideoShell(interview: interview),
    ),
  );
}

/// Mirror of setup_page's pre-launch reset so a prior session doesn't leak.
void _resetHumeState(AppStore store) {
  store.setHumeJobId(null);
  store.setHumeJobStatus(null);
  store.setHumeResult(null);
  store.resetQuestionTimestamps();
  store.setLiveEmotions([]);
  store.setHumeStreamActive(false);
  store.clearSessionTranscript();
  store.updateMetrics(conf: 0, anx: 0, w: 0, f: 0, eng: 0);
  store.resetIntegrity();
}
