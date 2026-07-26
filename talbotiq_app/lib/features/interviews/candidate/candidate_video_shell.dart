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
// For an ASSIGNED interview, the moment the candidate ends the call (reaches
// '/results') the interview is marked completed with a placeholder (unscored)
// result — independent of the AI pipeline that then runs behind an opaque
// "submitted" overlay, which the candidate can leave at any time (leaving
// disposes this whole subtree, abandoning any in-flight AI analysis). If that
// analysis lands before the candidate leaves, _maybeStoreResult upgrades the
// placeholder into the real AI-scored result. Either way the recruiter
// reviews, edits and publishes it. Decoupling "completed" from "AI scoring
// succeeded" is deliberate: previously the interview only flipped to completed
// once AI analysis landed, so a failed/abandoned analysis left it stuck at
// in-progress forever — indistinguishable from never having been attempted —
// and the candidate could be offered (and burn attempts on) a "fresh" launch
// of an interview they'd already completed.
//
// For self-serve Practice (interview == null) results are shown normally and
// nothing is stored.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/core/services/gemini_service.dart';
import 'package:talbotiq/features/interviews/candidate/interview/interview_page.dart';
import 'package:talbotiq/features/interviews/candidate/results/results_page.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

class CandidateVideoShell extends StatefulWidget {
  /// The assigned interview being run, or null for self-serve practice.
  final Interview? interview;
  const CandidateVideoShell({super.key, this.interview});

  @override
  State<CandidateVideoShell> createState() => _CandidateVideoShellState();
}

class _CandidateVideoShellState extends State<CandidateVideoShell> {
  bool _markedInProgress = false;
  bool _placeholderWritten = false;
  bool _resultWritten = false;
  bool _fallbackSubmitted = false;
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
        // Best-effort status update — must not crash the interview (an
        // unawaited Future's rejection is otherwise an UNCAUGHT async error,
        // e.g. if Firestore is unreachable) just because this side note
        // couldn't be written.
        repo.updateStatus(interview.id, InterviewStatus.inProgress).catchError(
              (e) => debugPrint('updateStatus(inProgress) failed: $e'),
            );
      }
    } else if (route == '/results') {
      // The candidate has ended the call — mark it completed right away (see
      // file header) so leaving before AI analysis lands never reopens this
      // interview for a fresh "Launch".
      if (interview != null) _writePlaceholderIfNeeded(interview, repo);
      _maybeStoreResult(interview, repo);
      _maybeSubmitFallbackOnFailure(interview, repo);
    } else if (!_popScheduled) {
      // A page navigated somewhere outside this shell (e.g. "New session").
      _popScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  /// Marks the interview completed with an empty/unscored placeholder result
  /// the instant the call ends — before the AI pipeline (which can be
  /// abandoned if the candidate leaves the pending overlay early) has any
  /// chance to finish. `evaluatedBy: ''` signals "nothing has scored this
  /// yet" to the recruiter's review screen, which shows a blank form ready
  /// for manual evaluation — the correct fallback if AI scoring never lands.
  /// `_maybeStoreResult` below overwrites this with the real AI-scored result
  /// once/if it's ready.
  void _writePlaceholderIfNeeded(Interview interview, InterviewRepository repo) {
    if (_placeholderWritten) return;
    _placeholderWritten = true;
    // Best-effort — must not crash on a network hiccup (see updateStatus's
    // comment above on unawaited Futures and uncaught async errors).
    repo.completeWithResult(interview.id, {
      'overallScore': 0,
      'summary': '',
      'recommendation': '',
      'strengths': const <String>[],
      'improvements': const <String>[],
      'evaluatedBy': '',
    }).catchError((e) => debugPrint('completeWithResult(placeholder) failed: $e'));
  }

  // Once the AI pipeline finishes, its InterviewResult appears in AppStore.
  // Upgrade the placeholder above into the real AI-scored result, then hand
  // the candidate-facing pending screen off to its final stage.
  Future<void> _maybeStoreResult(
      Interview? interview, InterviewRepository repo) async {
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

    store.setProcessingStage(InterviewProcessingStage.sendingToRecruiter);
    try {
      await repo.completeWithResult(interview.id, {
        'overallScore': r.score,
        'summary': sc?.hiringRecommendationRationale ?? '',
        'recommendation': mapHiringRecommendationToCanonical(sc?.hiringRecommendation),
        'strengths': sc?.topStrengths ?? const <String>[],
        'improvements': sc?.topConcerns ?? const <String>[],
        'evaluatedBy': 'ai',
        if (sc != null) 'detail': sc.toJson(),
        // Integrity: how many times the candidate left the app mid-interview.
        if (store.integrityLeftAppCount > 0)
          'integrity': {'leftAppCount': store.integrityLeftAppCount},
        'responses': _buildResponses(r.transcript, interview.questions),
      });
      store.setProcessingStage(InterviewProcessingStage.complete);
    } catch (e) {
      // The unscored placeholder from _writePlaceholderIfNeeded is already
      // saved, so the recruiter isn't blocked — this only affects what the
      // candidate sees. Not re-armed for retry: the AI-scored upgrade above
      // is idempotent-in-spirit but retrying on every unrelated store
      // notification would hammer Firestore.
      store.setProcessingStage(
        InterviewProcessingStage.failed,
        error: 'Could not send your results to the recruiter: $e',
      );
    }
  }

  /// If Gemini scoring fails (AppStore.processingStage reaches `failed`),
  /// don't leave the candidate's raw responses stranded behind a blank
  /// placeholder — submit the transcript-derived Q&A to the recruiter as an
  /// unscored draft (unlocking their "Regenerate Results" button, gated on
  /// `responses` being non-empty), and move the candidate-facing screen to
  /// `submittedWithoutScoring` — a reassuring "we got it, no action needed"
  /// state rather than a scary permanent error.
  Future<void> _maybeSubmitFallbackOnFailure(
      Interview? interview, InterviewRepository repo) async {
    if (interview == null || _resultWritten || _fallbackSubmitted) return;
    if (!mounted) return;
    final store = context.read<AppStore>();
    if (store.processingStage != InterviewProcessingStage.failed) return;

    _fallbackSubmitted = true;
    final geminiError = store.processingError;
    try {
      await repo.completeWithResult(interview.id, {
        'overallScore': 0,
        'summary': '',
        'recommendation': '',
        'strengths': const <String>[],
        'improvements': const <String>[],
        'evaluatedBy': '',
        'responses': _buildResponses(store.sessionTranscript, interview.questions),
        if (geminiError != null && geminiError.isNotEmpty)
          'evaluationError': geminiError,
        if (store.integrityLeftAppCount > 0)
          'integrity': {'leftAppCount': store.integrityLeftAppCount},
      });
      store.setProcessingStage(InterviewProcessingStage.submittedWithoutScoring);
    } catch (e) {
      // A genuine hard failure — even the raw-data fallback couldn't be
      // saved. Not re-armed for retry, same reasoning as _maybeStoreResult's
      // catch above: retrying on every unrelated store notification would
      // hammer Firestore.
      store.setProcessingStage(
        InterviewProcessingStage.failed,
        error: 'Could not submit your responses to the recruiter: $e',
      );
    }
  }


  /// Pairs each question with the candidate's spoken answer(s) for it, so the
  /// recruiter can review the raw response alongside the AI-scored summary.
  List<Map<String, String>> _buildResponses(
      List<TranscriptEntry> transcript, List<String> questions) {
    final candidateEntries =
        transcript.where((e) => e.role == 'candidate').toList();
    return [
      for (var idx = 0; idx < questions.length; idx++)
        {
          'question': questions[idx],
          'answer': candidateEntries
              .where((e) => e.questionIdx == idx)
              .map((e) => e.text)
              .join(' ')
              .trim(),
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Route handling is driven by the store listener (_onStoreChanged); here we
    // only read the route to decide what to render.
    final route = context.select<AppStore, String>((s) => s.currentRoute);

    // Assigned interviews hide the result behind a pending overlay.
    final gated = widget.interview != null && route == '/results';
    return Stack(
      children: [
        const _IndexedStackPages(),
        if (gated) const _VideoPendingScreen(),
      ],
    );
  }
}

/// The two reused pages, mounted together and switched by currentRoute.
class _IndexedStackPages extends StatelessWidget {
  const _IndexedStackPages();

  @override
  Widget build(BuildContext context) {
    final route = context.select<AppStore, String>((s) => s.currentRoute);
    final index = route == '/results' ? 1 : 0;
    return IndexedStack(
      index: index,
      children: const [InterviewPage(), ResultsPage()],
    );
  }
}

/// Opaque overlay shown to the candidate after an assigned video interview,
/// tracking AppStore's `processingStage` live so the candidate sees exactly
/// what's happening (fetching the transcript → AI scoring → sending to the
/// recruiter → done) instead of an indefinite, unexplained spinner.
class _VideoPendingScreen extends StatelessWidget {
  const _VideoPendingScreen();

  static const _steps = <(InterviewProcessingStage, String)>[
    (InterviewProcessingStage.fetchingTranscript, 'Fetching your interview from Tavus'),
    (InterviewProcessingStage.evaluating, 'Evaluating your answers with Gemini'),
    (InterviewProcessingStage.sendingToRecruiter, 'Sending results to the recruiter'),
  ];

  /// Index of the step currently in progress (steps before it are done).
  int _activeStepIndex(InterviewProcessingStage stage) {
    switch (stage) {
      case InterviewProcessingStage.idle:
      case InterviewProcessingStage.fetchingTranscript:
        return 0;
      case InterviewProcessingStage.evaluating:
        return 1;
      case InterviewProcessingStage.sendingToRecruiter:
        return 2;
      case InterviewProcessingStage.complete:
      case InterviewProcessingStage.submittedWithoutScoring:
      case InterviewProcessingStage.failed:
        return _steps.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<AppStore>();
    final stage = store.processingStage;
    final failed = stage == InterviewProcessingStage.failed;
    final complete = stage == InterviewProcessingStage.complete;
    final submittedWithoutScoring =
        stage == InterviewProcessingStage.submittedWithoutScoring;
    final done = complete || submittedWithoutScoring;
    final activeIdx = _activeStepIndex(stage);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : (done ? Icons.check_circle : Icons.hourglass_top),
                  size: 64,
                  color: failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  failed ? 'Something went wrong' : 'Interview submitted',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  failed
                      ? (store.processingError ??
                          'Processing failed, but your responses were saved. '
                              'The recruiter will follow up.')
                      : submittedWithoutScoring
                          ? 'An error occurred while generating your interview '
                              'evaluation. Your interview responses have been '
                              'safely submitted to the recruiter, who can '
                              'regenerate the evaluation and publish your '
                              'results. No further action is required from '
                              'your side.'
                          : complete
                              ? 'Your interview has been processed and sent to '
                                  'the recruiter. You may now close this window.'
                              : 'Please wait while we process your responses…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (!failed && !done) ...[
                  const SizedBox(height: 24),
                  for (var i = 0; i < _steps.length; i++)
                    _StepRow(
                      label: _steps[i].$2,
                      done: i < activeIdx,
                      active: i == activeIdx,
                    ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                ],
                const SizedBox(height: 24),
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

class _StepRow extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;

  const _StepRow({required this.label, required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = done || active;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done
                ? Icons.check_circle
                : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            size: 16,
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: highlighted
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
