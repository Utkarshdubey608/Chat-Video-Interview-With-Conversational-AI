// lib/features/interviews/candidate/candidate_home.dart
//
// Candidate landing surface: lists interviews assigned to the signed-in user's
// email (video and chat shown separately) and launches them. Video launches
// reuse the Tavus machinery via a CandidateVideoShell; chat launches reuse the
// recruiter conversation runner via chat_launch_adapter. Shared API keys are
// pulled from Firestore on entry so this device can reach Tavus/Gemini even
// though the candidate never opens Settings.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/deep_link/deep_link_service.dart';
import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/settings/settings_page.dart';
import 'package:talbotiq/features/app_config/app_config_service.dart';
import 'package:talbotiq/features/auth/auth_service.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/candidate/candidate_result_page.dart';
import 'package:talbotiq/features/interviews/candidate/chat_launch_adapter.dart';
import 'package:talbotiq/features/interviews/candidate/facefit_page.dart';
import 'package:talbotiq/features/interviews/candidate/practice_page.dart';
import 'package:talbotiq/features/interviews/candidate/resume_intake_page.dart';
import 'package:talbotiq/features/interviews/candidate/system_check_page.dart';
import 'package:talbotiq/features/interviews/candidate/video_launch.dart';
import 'package:talbotiq/features/interviews/candidate/voice_launch.dart';

class CandidateHome extends StatefulWidget {
  const CandidateHome({super.key});

  @override
  State<CandidateHome> createState() => _CandidateHomeState();
}

class _CandidateHomeState extends State<CandidateHome> {
  bool _launching = false;

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    // Consume a deep link (talbotiq://interview/<id>) that arrived before/at
    // launch: fetch the interview and, if it's this candidate's, open it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consumePendingDeepLink();
    });
  }

  Future<void> _consumePendingDeepLink() async {
    final id = PendingDeepLink.instance.take();
    if (id == null) return;
    final repo = context.read<InterviewRepository>();
    try {
      final interview = await repo.getById(id);
      if (!mounted || interview == null) return;
      // Only auto-open an interview actually assigned to this candidate.
      if (interview.candidateEmailLower != _email.trim().toLowerCase()) return;
      switch (interview.type) {
        case InterviewType.video:
          _launchVideo(interview);
          break;
        case InterviewType.chat:
          _launchChat(interview);
          break;
        case InterviewType.voice:
          _launchVoice(interview);
          break;
      }
    } catch (_) {
      // Ignore — the interview still appears in the list for manual launch.
    }
  }

  String _localPart(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  bool _guardAccess(Interview interview) {
    if (interview.isAccessible) return true;
    final msg = interview.isExpired
        ? 'This interview has expired.'
        : interview.isNotYetAvailable
            ? 'This interview is not available yet.'
            : 'You have no attempts left for this interview.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }

  Future<void> _launchVideo(Interview interview) async {
    if (_launching) return;
    if (!_guardAccess(interview)) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<AppStore>();
    final appConfig = context.read<AppConfigService>();
    final repo = context.read<InterviewRepository>();

    if (interview.avatar.replicaId.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('This interview has no avatar configured.')));
      return;
    }

    // Optional résumé intake (recruiter opt-in) — grounds the avatar's
    // questions. Cancelling the intake aborts the launch.
    String? resumeText;
    if (interview.collectResume) {
      resumeText = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (ctx) => ResumeIntakePage(
            onReady: (t) => Navigator.of(ctx).pop(t),
          ),
        ),
      );
      if (!mounted) return;
      if (resumeText == null || resumeText.trim().isEmpty) return;
    }

    // Pre-join camera/mic check so a permission denial is handled here (retry /
    // open settings) instead of a dead video panel once the call starts.
    final ready = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => SystemCheckPage(
          onReady: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (!mounted) return;
    if (ready != true) return;

    // Optional pre-call facefit capture (camera was granted in the system
    // check). Returns an 'insufficient' summary if skipped/unavailable.
    final facial = await Navigator.of(context).push<FacialSessionSummary>(
      MaterialPageRoute(
        builder: (ctx) => FacefitPage(
          onCaptured: (s) => Navigator.of(ctx).pop(s),
        ),
      ),
    );
    if (!mounted) return;

    setState(() => _launching = true);
    try {
      // Apply THIS interview's recruiter (org) keys to the in-memory services
      // only — never persisted, never shown in the candidate's Settings. Each
      // launch re-establishes the right org's keys, so one org's interview
      // never uses another org's credentials.
      final hasKey = await appConfig.applyForRecruiter(
          interview.recruiterId, store,
          overrides: interview.keyOverrides);
      if (!mounted) return;
      if (!hasKey) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Video is not available yet — the recruiter has not configured a Tavus key.'),
        ));
        return;
      }

      final config = store.sessionConfig.copyWith(
        conversationalContext: interview.prompt,
        replicaId: interview.avatar.replicaId,
        personaId: interview.avatar.personaId ?? '',
        conversationName: interview.title,
        maxCallDuration: interview.durationMinutes * 60,
        language: interview.language,
      );

      // Carry the interview language so the results page transcribes in the
      // right Deepgram locale.
      store.setActiveInterviewLanguage(interview.language);

      await launchVideoConversation(
        context: context,
        config: config,
        questions: interview.questions,
        candidateName: interview.candidateName ?? _localPart(_email),
        interview: interview,
        resumeText: resumeText,
        facialSummary: facial,
      );
      // The attempt has started — count it.
      repo.incrementAttempt(interview.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Could not start the interview: ${e.toString().replaceAll('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _launchChat(Interview interview) async {
    if (_launching) return;
    if (!_guardAccess(interview)) return;
    final repo = context.read<InterviewRepository>();
    final recruiterStore = context.read<RecruiterStore>();
    final store = context.read<AppStore>();
    setState(() => _launching = true);
    // Apply the org's Gemini key (for scoring) in-memory before running.
    await context.read<AppConfigService>().applyForRecruiter(
        interview.recruiterId, store,
        overrides: interview.keyOverrides);
    if (!mounted) return;
    repo.incrementAttempt(interview.id); // count this attempt
    if (mounted) setState(() => _launching = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildChatRunnerPage(
          interview: interview,
          repository: repo,
          recruiterStore: recruiterStore,
        ),
      ),
    );
    // Restore the candidate's own keys once the org session ends.
    await store.reloadApiKeysFromPrefs();
  }

  Future<void> _launchVoice(Interview interview) async {
    if (_launching) return;
    if (!_guardAccess(interview)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _launching = true);
    try {
      // launchVoiceInterview applies the org keys, runs the Gemini Live call,
      // scores the transcript on completion, and restores the candidate's keys.
      await launchVoiceInterview(context: context, interview: interview);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Could not start the interview: ${e.toString().replaceAll('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<InterviewRepository>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Interviews'),
        actions: [
          IconButton(
            tooltip: 'Practice with AI',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PracticePage()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SettingsScaffold()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<List<Interview>>(
            stream: repo.watchForCandidate(_email),
            builder: (context, snap) {
              if (snap.hasError) {
                // Never surface the raw error to the candidate — it can leak
                // Firestore internals and composite-index URLs. Log it for
                // developers and show a friendly message instead.
                debugPrint('CandidateHome interviews stream error: ${snap.error}');
                return const AppMessageState(
                  icon: Icons.error_outline,
                  title: 'Could not load your interviews',
                  subtitle: 'Please check your connection and try again.',
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data!;
              if (all.isEmpty) {
                return AppMessageState(
                  icon: Icons.inbox_outlined,
                  title: 'No interviews assigned',
                  subtitle:
                      'Interviews assigned to $_email will appear here.',
                );
              }
              final video =
                  all.where((i) => i.type == InterviewType.video).toList();
              final chat =
                  all.where((i) => i.type == InterviewType.chat).toList();
              final voice =
                  all.where((i) => i.type == InterviewType.voice).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (video.isNotEmpty) ...[
                    _Header(
                        label: 'Video Interviews',
                        icon: Icons.videocam_outlined),
                    ...video.map((i) => _AssignedCard(
                          interview: i,
                          onLaunch: () => _launchVideo(i),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (chat.isNotEmpty) ...[
                    _Header(
                        label: 'Chat Interviews',
                        icon: Icons.chat_bubble_outline),
                    ...chat.map((i) => _AssignedCard(
                          interview: i,
                          onLaunch: () => _launchChat(i),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (voice.isNotEmpty) ...[
                    _Header(
                        label: 'Voice Interviews',
                        icon: Icons.record_voice_over_outlined),
                    ...voice.map((i) => _AssignedCard(
                          interview: i,
                          onLaunch: () => _launchVoice(i),
                        )),
                  ],
                ],
              );
            },
          ),
          if (_launching)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Wraps the reused [SettingsPage] (which has no app bar) in its own Scaffold.
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsPage(),
    );
  }
}

class _AssignedCard extends StatelessWidget {
  final Interview interview;
  final VoidCallback onLaunch;
  const _AssignedCard({required this.interview, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = interview.type == InterviewType.video;
    final completed = interview.status == InterviewStatus.completed;
    final accessible = interview.isAccessible;
    final published =
        interview.resultPublished && interview.result != null;
    final awaiting =
        interview.status == InterviewStatus.completed && !published;
    final attemptsNote = interview.maxAttempts == null
        ? ''
        : ' · ${interview.attemptsRemaining} attempt(s) left';
    String subtitle =
        '${interview.questions.length} question(s) · ${interview.durationMinutes} min$attemptsNote';
    if (published) {
      subtitle = 'Results available';
    } else if (awaiting) {
      subtitle = 'Submitted — awaiting results';
    } else if (interview.isExpired) {
      subtitle = 'Expired · ${formatDateTime(interview.expiresAt!)}';
    } else if (interview.isNotYetAvailable) {
      subtitle = 'Available from ${formatDateTime(interview.availableFrom!)}';
    } else if (!interview.hasAttemptsLeft) {
      subtitle = 'No attempts left';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                isVideo ? Icons.videocam_outlined : Icons.chat_bubble_outline,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(interview.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'from ${interview.recruiterName?.isNotEmpty == true ? interview.recruiterName : interview.recruiterEmail}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accessible
                          ? null
                          : theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (published)
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CandidateResultPage(interview: interview),
                  ),
                ),
                child: const Text('View result'),
              )
            else if (awaiting && !accessible)
              const Text('Pending')
            else
              FilledButton(
                onPressed: accessible ? onLaunch : null,
                child: Text(completed ? 'Re-take' : 'Launch'),
              ),
          ],
        ),
      ),
    );
  }

}

class _Header extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Header({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
