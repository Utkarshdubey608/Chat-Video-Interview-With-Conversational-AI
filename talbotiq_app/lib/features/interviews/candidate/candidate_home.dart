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

import '../../../providers/app_store.dart';
import '../../../views/settings_page.dart';
import '../../app_config/app_config_service.dart';
import '../../auth/auth_service.dart';
import '../../recruiter/store/recruiter_store.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';
import 'candidate_result_page.dart';
import 'chat_launch_adapter.dart';
import 'practice_page.dart';
import 'video_launch.dart';

class CandidateHome extends StatefulWidget {
  const CandidateHome({super.key});

  @override
  State<CandidateHome> createState() => _CandidateHomeState();
}

class _CandidateHomeState extends State<CandidateHome> {
  bool _launching = false;

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

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

    setState(() => _launching = true);
    try {
      // Apply THIS interview's recruiter (org) keys to the in-memory services
      // only — never persisted, never shown in the candidate's Settings. Each
      // launch re-establishes the right org's keys, so one org's interview
      // never uses another org's credentials.
      final hasKey =
          await appConfig.applyForRecruiter(interview.recruiterId, store);
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
      );

      await launchVideoConversation(
        context: context,
        config: config,
        questions: interview.questions,
        candidateName: interview.candidateName ?? _localPart(_email),
        interview: interview,
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
    if (!_guardAccess(interview)) return;
    final repo = context.read<InterviewRepository>();
    final recruiterStore = context.read<RecruiterStore>();
    final store = context.read<AppStore>();
    // Apply the org's Gemini key (for scoring) in-memory before running.
    await context.read<AppConfigService>().applyForRecruiter(interview.recruiterId, store);
    if (!mounted) return;
    repo.incrementAttempt(interview.id); // count this attempt
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
                return _Message(
                  icon: Icons.error_outline,
                  title: 'Could not load your interviews',
                  subtitle: '${snap.error}',
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data!;
              if (all.isEmpty) {
                return _Message(
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
      subtitle = 'Expired · ${_fmtDate(interview.expiresAt!)}';
    } else if (interview.isNotYetAvailable) {
      subtitle = 'Available from ${_fmtDate(interview.availableFrom!)}';
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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Message(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
