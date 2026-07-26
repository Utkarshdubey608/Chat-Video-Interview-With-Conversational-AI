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
import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/app_config/app_config_service.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/candidate/candidate_result_page.dart';
import 'package:talbotiq/features/interviews/candidate/chat_launch_adapter.dart';
import 'package:talbotiq/features/interviews/candidate/facefit_page.dart';
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

  /// Human-readable name of the launch step currently in flight, shown in the
  /// loading overlay. Whatever it last displayed is the step that failed.
  String _launchStage = '';

  void _setStage(String stage) {
    debugPrint('[launch] $stage');
    if (mounted) setState(() => _launchStage = stage);
  }

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

  /// Shows a launch failure as a blocking dialog rather than a SnackBar.
  /// A failed launch drops the candidate straight back to this list, which on
  /// its own is indistinguishable from "the app just closed the interview" —
  /// a transient SnackBar is far too easy to miss for something that ends the
  /// whole attempt. The full error text is shown (and selectable) so it can
  /// be reported verbatim.
  Future<void> _showLaunchError(String stage, Object error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Could not start the interview'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Failed at: $stage',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SelectableText(
                error.toString().replaceAll('Exception: ', ''),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'If this mentions a network or host error, check this '
                'device’s internet connection and try again.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
    debugPrint('[launch] system check returned: $ready (mounted=$mounted)');
    if (!mounted) return;
    // SystemCheckPage pops `true` only from its "Join interview" button, so
    // anything else means the candidate backed out. That is a cancellation,
    // not an error — abort quietly and leave them on their interview list.
    if (ready != true) return;

    // Optional pre-call facefit capture (camera was granted in the system
    // check). Returns an 'insufficient' summary if skipped/unavailable.
    debugPrint('[launch] opening facefit…');
    final facial = await Navigator.of(context).push<FacialSessionSummary>(
      MaterialPageRoute(
        builder: (ctx) => FacefitPage(
          onCaptured: (s) => Navigator.of(ctx).pop(s),
        ),
      ),
    );
    debugPrint('[launch] facefit returned ${facial == null ? 'null (backed out)' : 'a summary'} (mounted=$mounted)');
    if (!mounted) return;
    // A null result means the candidate pressed BACK out of the attention
    // check — that is a cancellation and must abort the launch. "Skip" is a
    // different thing: it pops an 'insufficient' summary (non-null) and
    // legitimately continues. Without this check a back-press fell through and
    // started the interview anyway, which is the opposite of what Back means.
    if (facial == null) return;

    setState(() => _launching = true);
    // Tracks how far the launch got, so a failure can name the exact step
    // instead of a generic "could not start" (this sequence hits Firestore
    // and then Tavus over HTTP — on a flaky/offline device several distinct
    // failures all LOOK identical to the candidate: spinner, then back to
    // the dashboard).
    var stage = 'fetching recruiter keys (Firestore)';
    try {
      _setStage('Step 1/3 — fetching recruiter keys…');
      // Apply THIS interview's recruiter (org) keys to the in-memory services
      // only — never persisted, never shown in the candidate's Settings. Each
      // launch re-establishes the right org's keys, so one org's interview
      // never uses another org's credentials.
      final hasKey = await appConfig.applyForRecruiter(
          interview.recruiterId, store,
          overrides: interview.keyOverrides);
      if (!mounted) return;
      debugPrint('[launchVideo] 2/4 recruiter keys ok — hasTavusKey=$hasKey');
      if (!hasKey) {
        // Dialog, not a SnackBar: this aborts the launch and drops the
        // candidate back to the list, which is indistinguishable from a
        // crash if the only feedback is a toast that scrolls by. Note this
        // is specifically the TAVUS key — chat/voice interviews only need a
        // Gemini key, so they keep working while video silently fails here.
        if (mounted) setState(() => _launching = false);
        await _showLaunchError(
          'checking the recruiter’s API keys',
          'No Tavus API key is configured for this recruiter, so the video '
              'avatar cannot be started.\n\n'
              'Chat and voice interviews only need a Gemini key, which is why '
              'those still work.\n\n'
              'Fix: the recruiter should open Settings → API Credentials, add '
              'their Tavus key, then tap "Save to Cloud".',
        );
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

      stage = 'creating the Tavus conversation (network)';
      _setStage('Step 2/3 — creating the video session…');
      await launchVideoConversation(
        context: context,
        config: config,
        questions: interview.questions,
        candidateName: interview.candidateName ?? _localPart(_email),
        interview: interview,
        resumeText: resumeText,
        facialSummary: facial,
      );
      _setStage('Step 3/3 — opening the interview…');
      // The attempt has started — count it. Best-effort: not awaited (so a
      // slow/failed write never delays entering the interview), so it must
      // catch its own errors — an unawaited Future's rejection would
      // otherwise be an uncaught async error even though this call is
      // textually inside this try/catch.
      repo
          .incrementAttempt(interview.id)
          .catchError((e) => debugPrint('incrementAttempt failed: $e'));
    } catch (e, st) {
      debugPrint('[launchVideo] FAILED at "$stage": $e\n$st');
      if (mounted) setState(() => _launching = false);
      await _showLaunchError(stage, e);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _launchChat(Interview interview) async {
    if (_launching) return;
    if (!_guardAccess(interview)) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<InterviewRepository>();
    final recruiterStore = context.read<RecruiterStore>();
    final store = context.read<AppStore>();
    setState(() => _launching = true);
    try {
      // Apply the org's Gemini key (for scoring) in-memory before running.
      await context.read<AppConfigService>().applyForRecruiter(
          interview.recruiterId, store,
          overrides: interview.keyOverrides);
      if (!mounted) return;
      // Best-effort — see the video path's comment on why this must catch its
      // own errors despite being unawaited.
      repo
          .incrementAttempt(interview.id)
          .catchError((e) => debugPrint('incrementAttempt failed: $e')); // count this attempt
      if (mounted) setState(() => _launching = false);
      // Build the page HERE, not inside the MaterialPageRoute builder.
      // buildChatRunnerPage() writes an ephemeral template into RecruiterStore
      // (notifyListeners), and a route builder runs during Flutter's build
      // phase — mutating a provider there throws "setState()/markNeedsBuild()
      // called during build" and the route fails to render. Constructing the
      // widget eagerly keeps that write outside the build phase.
      final chatPage = buildChatRunnerPage(
        interview: interview,
        repository: repo,
        recruiterStore: recruiterStore,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => chatPage),
      );
      // Restore the candidate's own keys once the org session ends.
      await store.reloadApiKeysFromPrefs();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Could not start the interview: ${e.toString().replaceAll('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _launching = false);
    }
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
        title: const _Wordmark(subtitle: 'My Interviews'),
        actions: const [
          LogoutButton(),
          SizedBox(width: 4),
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
            ColoredBox(
              color: const Color(0xCC000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    // The launch sequence can abort at several points that all
                    // look identical (spinner, then back to this list). Naming
                    // the current step on screen means the last step shown IS
                    // the one that failed — no log capture required.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _launchStage.isEmpty ? 'Starting…' : _launchStage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignedCard extends StatelessWidget {
  final Interview interview;
  final VoidCallback onLaunch;
  const _AssignedCard({required this.interview, required this.onLaunch});

  Widget _buildStatusBadge(
      BuildContext context, String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100), // Pill-shaped!
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    ThemeData theme,
    bool published,
    bool awaiting,
    bool accessible,
    bool completed,
  ) {
    if (published) {
      return FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CandidateResultPage(interview: interview),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('View Result'),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 14),
          ],
        ),
      );
    } else if (awaiting && !accessible) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          'Pending',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accessible
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.1),
          foregroundColor: accessible
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        onPressed: accessible ? onLaunch : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(completed ? 'Re-take' : 'Launch'),
            const SizedBox(width: 4),
            Icon(completed ? Icons.refresh : Icons.play_arrow, size: 14),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = interview.status == InterviewStatus.completed;
    final accessible = interview.isAccessible;
    final published =
        interview.resultPublished && interview.result != null;
    final awaiting =
        interview.status == InterviewStatus.completed && !published;

    final typeIcon = switch (interview.type) {
      InterviewType.video => Icons.videocam_outlined,
      InterviewType.voice => Icons.record_voice_over_outlined,
      InterviewType.chat => Icons.chat_bubble_outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28.0), // More rounded!
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28.0), // More rounded!
        onTap: accessible
            ? onLaunch
            : (published
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CandidateResultPage(interview: interview),
                      ),
                    )
                : null),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle, // Fully circular shape!
                ),
                child: Icon(
                  typeIcon,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      interview.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'from ${interview.recruiterName?.isNotEmpty == true ? interview.recruiterName : interview.recruiterEmail}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildStatusBadge(
                          context,
                          '${interview.questions.length} Qs · ${interview.durationMinutes} min',
                          theme.colorScheme.surfaceContainerHighest,
                          theme.colorScheme.onSurfaceVariant,
                        ),
                        if (published) ...[
                          _buildStatusBadge(
                            context,
                            'Results Available',
                            Colors.green.withValues(alpha: 0.15),
                            Colors.green,
                          ),
                        ] else if (awaiting) ...[
                          _buildStatusBadge(
                            context,
                            'Awaiting Evaluation',
                            Colors.orange.withValues(alpha: 0.15),
                            Colors.orange,
                          ),
                        ] else if (interview.isExpired) ...[
                          _buildStatusBadge(
                            context,
                            'Expired',
                            theme.colorScheme.error.withValues(alpha: 0.15),
                            theme.colorScheme.error,
                          ),
                        ] else if (interview.isNotYetAvailable) ...[
                          _buildStatusBadge(
                            context,
                            'Scheduled',
                            theme.colorScheme.secondary.withValues(alpha: 0.15),
                            theme.colorScheme.secondary,
                          ),
                        ] else if (!interview.hasAttemptsLeft) ...[
                          _buildStatusBadge(
                            context,
                            'No Attempts Left',
                            theme.colorScheme.error.withValues(alpha: 0.15),
                            theme.colorScheme.error,
                          ),
                        ] else ...[
                          if (interview.maxAttempts != null)
                            _buildStatusBadge(
                              context,
                              '${interview.attemptsRemaining} left',
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                              theme.colorScheme.primary,
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                theme,
                published,
                awaiting,
                accessible,
                completed,
              ),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final String subtitle;
  const _Wordmark({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
            children: [
              const TextSpan(text: 'talbot'),
              TextSpan(
                  text: 'iq',
                  style: TextStyle(color: theme.colorScheme.primary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('· $subtitle',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
