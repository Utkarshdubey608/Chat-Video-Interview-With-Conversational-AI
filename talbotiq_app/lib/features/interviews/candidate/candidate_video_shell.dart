// lib/features/interviews/candidate/candidate_video_shell.dart
//
// A stripped stand-in for the old MainLayout, used only when a candidate runs
// an assigned VIDEO interview. The reused InterviewPage/ResultsPage are driven
// by AppStore.currentRoute (not the Navigator): video only renders at
// '/interview', ResultsPage's analysis only fires on the transition into
// '/results', and InterviewPage._endInterview calls navigateTo('/results')
// rather than popping. So we mirror MainLayout: an IndexedStack of both pages
// keyed by currentRoute.
//
// For an ASSIGNED interview the ResultsPage still runs its AI pipeline (behind
// an opaque "submitted" overlay) so the analysis is computed and stored to
// Firestore UNPUBLISHED — the candidate never sees it; the recruiter reviews,
// edits and publishes it. For self-serve Practice (interview == null) results
// are shown normally and nothing is stored.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/app_store.dart';
import '../../../models/app_models.dart';
import '../../../views/interview_page.dart';
import '../../../views/results_page.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';

class CandidateVideoShell extends StatefulWidget {
  /// The assigned interview being run, or null for self-serve practice.
  final Interview? interview;
  const CandidateVideoShell({super.key, this.interview});

  @override
  State<CandidateVideoShell> createState() => _CandidateVideoShellState();
}

class _CandidateVideoShellState extends State<CandidateVideoShell> {
  bool _markedInProgress = false;
  bool _resultWritten = false;
  bool _popScheduled = false;
  AppStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<AppStore>();
    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      _store!.addListener(_onStoreChanged);
    }
    // Handle the route we're already on (e.g. the initial '/interview'), and
    // pick up a result that may already be in the store.
    _handleRoute(store.currentRoute);
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    // Restore the candidate's own API keys (undo the org's ephemeral keys)
    // when leaving an assigned interview.
    if (widget.interview != null) _store?.reloadApiKeysFromPrefs();
    super.dispose();
  }

  /// Route/result handling is driven off AppStore notifications rather than an
  /// addPostFrameCallback fired on every build. The AI pipeline finishing
  /// (store.addInterviewResult) notifies listeners, which lets us persist the
  /// result to Firestore the moment it lands.
  void _onStoreChanged() {
    final store = _store;
    if (store == null || !mounted) return;
    _handleRoute(store.currentRoute);
  }

  void _handleRoute(String route) {
    if (!mounted) return;
    final interview = widget.interview;
    final repo = context.read<InterviewRepository>();
    if (route == '/interview') {
      if (interview != null && !_markedInProgress) {
        _markedInProgress = true;
        repo.updateStatus(interview.id, InterviewStatus.inProgress);
      }
    } else if (route == '/results') {
      // Deliberately do NOT mark the interview completed here. completeWithResult
      // (in _maybeStoreResult) flips the status to completed atomically WITH the
      // result. Marking completed up-front stranded any candidate whose result
      // never landed (analysis failed, or they left mid-processing) on
      // "Submitted — awaiting results" forever; leaving the status as in-progress
      // until a result exists keeps the interview safely retakeable instead.
      _maybeStoreResult(interview, repo);
    } else if (!_popScheduled) {
      // A page navigated somewhere outside this shell (e.g. "New session").
      _popScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  // Once the AI pipeline finishes, its InterviewResult appears in AppStore.
  // Convert it to the canonical (unpublished) result and store to Firestore.
  // This is what marks the interview completed (via completeWithResult).
  void _maybeStoreResult(Interview? interview, InterviewRepository repo) {
    if (interview == null || _resultWritten) return;
    if (!mounted) return;
    final store = context.read<AppStore>();
    final convId = store.currentConversation?.conversationId ?? '';
    if (convId.isEmpty) return;
    final matches =
        store.interviewResults.where((r) => r.conversationId == convId);
    if (matches.isEmpty) return;
    _resultWritten = true;
    final InterviewResult r = matches.first;
    final sc = r.scorecard;
    repo.completeWithResult(interview.id, {
      'overallScore': r.score,
      'summary': sc?.hiringRecommendationRationale ?? '',
      'recommendation': sc?.hiringRecommendation ?? '',
      'strengths': sc?.topStrengths ?? const <String>[],
      'improvements': sc?.topConcerns ?? const <String>[],
      'evaluatedBy': 'ai',
      if (sc != null) 'detail': sc.toJson(),
    });
  }

  @override
  Widget build(BuildContext context) {
    // Route handling is driven by the store listener (_onStoreChanged); here we
    // only read the route to decide what to render.
    final route = context.watch<AppStore>().currentRoute;

    // Assigned interviews hide the result behind a pending overlay.
    final gated = widget.interview != null && route == '/results';
    return Stack(
      children: [
        const _IndexedStackPages(),
        if (gated) _VideoPendingScreen(resultReady: _resultWritten),
      ],
    );
  }
}

/// The two reused pages, mounted together and switched by currentRoute.
class _IndexedStackPages extends StatelessWidget {
  const _IndexedStackPages();

  @override
  Widget build(BuildContext context) {
    final route = context.watch<AppStore>().currentRoute;
    final index = route == '/results' ? 1 : 0;
    return IndexedStack(
      index: index,
      children: const [InterviewPage(), ResultsPage()],
    );
  }
}

/// Opaque overlay shown to the candidate after an assigned video interview,
/// while the analysis runs behind it and is stored (unpublished).
class _VideoPendingScreen extends StatelessWidget {
  final bool resultReady;
  const _VideoPendingScreen({required this.resultReady});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(resultReady ? Icons.check_circle : Icons.hourglass_top,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Interview submitted',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  resultReady
                      ? 'Your responses are in. Results will be available once '
                          'the recruiter publishes them.'
                      : 'Processing your responses… you can leave this screen; '
                          'results will be available after the recruiter '
                          'publishes them.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                if (!resultReady)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: CircularProgressIndicator(),
                  ),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
