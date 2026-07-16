// lib/views/results_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // for clipboard

import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/gemini_service.dart';
import '../core/services/tavus_service.dart';
import '../core/services/hume_service.dart';
import '../core/services/deepgram_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/response_widgets.dart';

// Modular components
import 'results/widgets/results_modals.dart';
import 'results/widgets/results_loading_view.dart';
import 'results/widgets/ats_assessment_card.dart';
import 'results/widgets/facial_analysis_panel.dart';
import 'results/widgets/dimension_scores_panel.dart';
import 'results/widgets/hume_emotion_panel.dart';
import 'results/widgets/strengths_watchpoints_panel.dart';
import 'results/widgets/results_stats_widgets.dart';

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  bool _humeProcessing = false;
  bool _geminiLoading = false;
  String? _geminiError;
  ATSScorecard? _atsScorecard;

  bool _scheduleOpen = false;
  bool _offerOpen = false;

  Timer? _humePollTimer;
  int _pollAttempts = 0;

  bool _fetchingTranscript = false;

  // ResultsPage lives inside an IndexedStack (always mounted), so initState
  // runs only once at app startup. We instead react to the /results route
  // becoming active — but only (re)generate for a NEW interview. Results are
  // cached per conversation so navigating away and back does NOT re-run Gemini.
  AppStore? _store;
  String? _loadedConvId;
  bool _onResults = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = Provider.of<AppStore>(context, listen: false);
    if (!identical(store, _store)) {
      _store?.removeListener(_onRouteChanged);
      _store = store;
      _store!.addListener(_onRouteChanged);
    }
    _onRouteChanged();
  }

  /// Loads results when the user enters /results. Generation runs once per
  /// interview; for an already-analysed session it restores the cached result
  /// instead of re-running the pipeline.
  void _onRouteChanged() {
    final store = _store;
    if (store == null) return;

    // Only act on a transition INTO /results. The listener fires on every
    // store change, so ignore notifications while already on the page —
    // otherwise viewing a past result would reload the current session.
    final onResults = store.currentRoute == '/results';
    if (!onResults) {
      _onResults = false;
      return;
    }
    if (_onResults) return;
    _onResults = true;

    final convId = store.currentConversation?.conversationId ?? '';
    if (_loadedConvId == convId && convId.isNotEmpty) {
      return; // already showing this session's result
    }

    // A freshly-recorded interview that just ended is the ONLY trigger for
    // running analysis. `recordingBytes` is set in _endInterview and is never
    // persisted, so on an app relaunch it is null — meaning we never
    // regenerate; we restore the saved result instead.
    final hasFreshRecording = store.recordingBytes?.isNotEmpty ?? false;
    if (hasFreshRecording && convId.isNotEmpty) {
      final cached = store.interviewResults
          .where((r) => r.conversationId == convId)
          .toList();
      if (cached.isNotEmpty) {
        _loadedConvId = convId;
        _applyResult(cached.first);
      } else {
        _loadedConvId = convId;
        _initResults();
      }
      return;
    }

    // No fresh interview (navigated in, or relaunched): show the matching
    // cached result, otherwise the most recently saved one.
    InterviewResult? toShow;
    if (convId.isNotEmpty) {
      final match =
          store.interviewResults.where((r) => r.conversationId == convId);
      if (match.isNotEmpty) toShow = match.first;
    }
    toShow ??=
        store.interviewResults.isNotEmpty ? store.interviewResults.first : null;
    if (toShow != null) {
      _loadedConvId = toShow.conversationId;
      _applyResult(toShow);
    }
  }

  /// Restores a previously-generated result into the view without re-running
  /// any analysis.
  void _applyResult(InterviewResult r) {
    final store = _store;
    if (store == null) return;
    store.updateTranscriptEntries(r.transcript);
    store.setHumeResult(r.humeResult);
    store.updateMetrics(w: r.wpm, f: r.fillers);
    if (!mounted) return;
    setState(() {
      _atsScorecard = r.scorecard;
      _geminiError = null;
      _geminiLoading = false;
      _humeProcessing = false;
      _fetchingTranscript = false;
    });
  }

  @override
  void dispose() {
    _store?.removeListener(_onRouteChanged);
    _humePollTimer?.cancel();
    super.dispose();
  }

  /// Initialises results page by fetching transcripts and starting Hume processing.
  Future<void> _initResults() async {
    // On web the transcript is captured live via Deepgram during the call. On
    // mobile the WebView owns the mic, so we instead pull Tavus's own
    // server-side transcript (enable_transcription) once the call has ended.
    await _ensureTranscript();
    if (!mounted) return;
    _startHumeProcess();
  }

  /// Builds the session transcript. Prefers the candidate's locally-recorded
  /// .wav (transcribed via Deepgram's pre-recorded endpoint). Falls back to
  /// Tavus's server-side transcript only when no local recording is available
  /// (e.g. on web, where the transcript is captured live during the call).
  Future<void> _ensureTranscript() async {
    final store = Provider.of<AppStore>(context, listen: false);

    // Preferred path: transcribe the locally-recorded interview audio.
    final bytes = store.recordingBytes;
    debugPrint(
      'debug[rec]: results recordingBytes=${bytes?.length ?? 0}, deepgramKey=${store.deepgramKey.isNotEmpty}',
    );
    if (bytes != null && bytes.isNotEmpty && store.deepgramKey.isNotEmpty) {
      setState(() => _fetchingTranscript = true);
      try {
        deepgramService.setKey(store.deepgramKey);
        final entries = await deepgramService.transcribeFromFile(
          bytes,
          language: DeepgramService.localeFor(store.activeInterviewLanguage),
        );
        if (entries.isNotEmpty) {
          store.clearSessionTranscript();
          for (final e in entries) {
            store.pushTranscriptEntry(e);
          }
          final int fillers = store.sessionTranscript
              .where((t) => t.role == 'candidate')
              .fold(0, (acc, e) => acc + deepgramService.countFillers(e.text));
          final int wpm = deepgramService.calcWpm(store.sessionTranscript);
          store.updateMetrics(w: wpm > 0 ? wpm : store.wpm, f: fillers);
        }
      } catch (e) {
        debugPrint('Deepgram file transcription failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to transcribe recording: $e'),
              backgroundColor: Colors.amber,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _fetchingTranscript = false);
      }
    }

    // If the local recording already produced a transcript, we're done.
    if (store.sessionTranscript.isNotEmpty) return;

    // Fallback path: pull Tavus's own server-side transcript.
    final conv = store.currentConversation;
    if (conv == null || conv.conversationId.isEmpty || store.tavusKey.isEmpty) {
      return;
    }

    tavusService.setKey(store.tavusKey);

    setState(() => _fetchingTranscript = true);
    try {
      final entries = await tavusService.fetchTranscriptWithRetry(
        conv.conversationId,
        maxAttempts: 18,
        initialDelay: const Duration(seconds: 5),
      );
      debugPrint('DEBUG: Tavus API returned ${entries.length} transcript entries.');

      // Found transcript! Clear local transcript list to prevent duplicates
      store.clearSessionTranscript();
      for (final e in entries) {
        store.pushTranscriptEntry(e);
      }

      // Derive speech metrics from the candidate's turns so the scorecard
      // isn't all zeros (these are computed live from Deepgram on web).
      final int fillers = store.sessionTranscript
          .where((t) => t.role == 'candidate')
          .fold(0, (acc, e) => acc + deepgramService.countFillers(e.text));
      final int wpm = deepgramService.calcWpm(store.sessionTranscript);
      store.updateMetrics(w: wpm, f: fillers);
    } catch (e) {
      debugPrint('Transcript fetch failed after retries: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to fetch transcript: $e'),
            backgroundColor: Colors.amber,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingTranscript = false);
    }
  }

  /// Triggers the background analysis of Hume audio recording.
  void _startHumeProcess() async {
    final store = Provider.of<AppStore>(context, listen: false);
    final hasHumeKey = store.humeKey.isNotEmpty;
    // Capture the conversation id up-front. The polling timer below fires long
    // after this method returns, so relying on a force-unwrapped
    // store.currentConversation! inside the callback risks a null crash if the
    // session is reset meanwhile.
    final convId = store.currentConversation?.conversationId;

    if (!hasHumeKey || convId == null || convId.isEmpty) {
      _runAtsAnalysis();
      return;
    }

    setState(() => _humeProcessing = true);

    if (store.humeResult != null) {
      setState(() => _humeProcessing = false);
      _runAtsAnalysis();
      return;
    }

    if (store.humeJobId != null) {
      _pollHumeJob(store.humeJobId!);
      return;
    }

    _pollAttempts = 0;
    // Cancel any poll still running from a prior interview — this page lives in
    // a persistent IndexedStack, so dispose() won't fire between attempts.
    _humePollTimer?.cancel();
    _humePollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      _pollAttempts++;
      if (_pollAttempts > 15) {
        timer.cancel();
        if (mounted) {
          setState(() => _humeProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hume analysis skipped: S3 recording ready event timeout',
              ),
              backgroundColor: Colors.amber,
            ),
          );
          _runAtsAnalysis();
        }
        return;
      }

      try {
        final recordingUri = await tavusService.getConversationRecordingUri(
          convId,
        );

        if (recordingUri != null) {
          timer.cancel();
          final region = store.drafts.isNotEmpty
              ? store.drafts.first.form.recordingS3BucketRegion
              : 'us-east-1';
          final httpUrl = _convertS3UriToHttp(
            recordingUri,
            region.isNotEmpty ? region : 'us-east-1',
          );

          // Submit the Tavus recording to Hume for facial/voice analysis. The
          // session transcript itself comes from the candidate's locally
          // recorded .wav (see _ensureTranscript).
          final jobId = await humeService.submitBatchJobWithUrls([httpUrl]);
          store.setHumeJobId(jobId);
          store.setHumeJobStatus('QUEUED');

          _pollHumeJob(jobId);
        }
      } catch (e) {
        debugPrint('Tavus recording poll error: $e');
      }
    });
  }

  /// Converts standard S3 URI format to direct HTTP link.
  String _convertS3UriToHttp(String s3Uri, String region) {
    if (!s3Uri.startsWith('s3://')) return s3Uri;
    final clean = s3Uri.replaceFirst('s3://', '');
    final parts = clean.split('/');
    final bucket = parts[0];
    final key = parts.sublist(1).join('/');
    return 'https://$bucket.s3.$region.amazonaws.com/$key';
  }

  /// Periodically checks Hume batch job status until completion or failure.
  void _pollHumeJob(String jobId) {
    final store = Provider.of<AppStore>(context, listen: false);
    _pollAttempts = 0;

    // Cancel any poll still running from a prior interview (see _startHumeProcess).
    _humePollTimer?.cancel();
    _humePollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      _pollAttempts++;
      if (_pollAttempts > 45) {
        timer.cancel();
        if (mounted) {
          setState(() => _humeProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hume analysis job polling timeout'),
              backgroundColor: Colors.red,
            ),
          );
          _runAtsAnalysis();
        }
        return;
      }

      try {
        final job = await humeService.pollBatchJob(jobId);
        store.setHumeJobStatus(job['status']);

        if (job['status'] == 'COMPLETED') {
          timer.cancel();
          final preds = await humeService.fetchBatchPredictions(jobId);
          final questions = store.questions.where((q) => q.isNotEmpty).toList();
          final result = humeService.buildSessionResult(
            jobId,
            preds,
            store.questionTimestamps,
            questions,
          );

          store.setHumeResult(result);
          if (mounted) {
            setState(() => _humeProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Hume voice analysis completed!'),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
            _runAtsAnalysis();
          }
        } else if (job['status'] == 'FAILED') {
          timer.cancel();
          if (mounted) {
            setState(() => _humeProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Hume analysis job failed'),
                backgroundColor: Colors.red,
              ),
            );
            _runAtsAnalysis();
          }
        }
      } catch (e) {
        debugPrint('Hume job poll error: $e');
      }
    });
  }

  /// Runs final ATS assessment synthesis using Gemini service.
  Future<void> _runAtsAnalysis() async {
    final store = Provider.of<AppStore>(context, listen: false);

    if (store.geminiKey.isEmpty) {
      setState(() {
        _geminiError =
            'Failed: Google Gemini API key is missing. Go to Settings and add your key.';
        _geminiLoading = false;
      });
      return;
    }

    if (store.sessionTranscript.isEmpty) {
      setState(() {
        _geminiError =
            'Failed: No transcript entries captured. ATS scorecard requires interview dialogue.';
        _geminiLoading = false;
      });
      return;
    }

    setState(() {
      _geminiLoading = true;
      _geminiError = null;
    });

    try {
      // Use the pre-call facefit capture when present; otherwise a neutral
      // placeholder (facefit skipped / camera unavailable).
      final summary = store.facialSummary ??
          FacialSessionSummary(
            totalFrames: 0,
            usableFrames: 0,
            usableFramePercent: 0.0,
            perQuestion: [],
            sessionDominantEmotions: [],
            sessionAvgAttention: 0.0,
            sessionAvgSmile: 0.0,
            overallLookingAwayPercent: 0.0,
            dataQuality: 'insufficient',
            dataQualityNote: 'Facefit was not captured',
            integrityFlags: [],
            engagementFlags: [],
            concernFlags: [],
          );

      final scorecard = await geminiService.analyze(
        candidateName:
            (store.currentConversation?.conversationName ?? 'Candidate')
                .replaceAll('TalbotIQ — ', ''),
        jobRole: store.activeInterviewRole,
        interviewDurationSeconds: store.activeInterviewDurationSeconds > 0
            ? store.activeInterviewDurationSeconds
            : 120,
        transcript: store.sessionTranscript,
        questions: store.questions,
        humeResult: store.humeResult,
        wpm: store.wpm,
        totalFillers: store.fillers,
        facialSummary: summary,
      );

      if (mounted) {
        setState(() {
          _atsScorecard = scorecard;
        });
      }

      // Persist this finished result to history so it can be revisited /
      // deleted later and is never regenerated on navigation. This must run
      // regardless of mounted — an assigned interview's shell reads the result
      // out of the store, so we cannot skip it if the page was disposed.
      final score = store.humeResult?.compositeScore ??
          scorecard.overallFitScore ??
          0;
      store.addInterviewResult(
        InterviewResult(
          id: 'res-${DateTime.now().millisecondsSinceEpoch}',
          conversationId: store.currentConversation?.conversationId ?? '',
          name: (store.currentConversation?.conversationName ?? 'Interview')
              .replaceAll('TalbotIQ — ', ''),
          createdAt: DateTime.now().toIso8601String(),
          score: score,
          wpm: store.wpm,
          fillers: store.fillers,
          transcript: List<TranscriptEntry>.from(store.sessionTranscript),
          scorecard: scorecard,
          humeResult: store.humeResult,
        ),
      );
      // The recording has now been analysed and saved — clear the "pending"
      // bytes so navigating back or relaunching never re-runs analysis.
      store.setRecordingBytes(null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geminiError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _geminiLoading = false);
    }
  }

  /// Maps composite score to verbal candidate fit verdict.
  String _getScoreVerdict(int score) {
    if (score >= 85) return 'Excellent Candidate';
    if (score >= 70) return 'Good Candidate';
    if (score >= 60) return 'Potential Candidate';
    return 'Needs Further Review';
  }

  /// Copies text report summary to system clipboard.
  void _shareProfile(
    BuildContext context,
    int score,
    String verdict,
    String? jobId,
  ) {
    final theme = Theme.of(context);
    final text =
        'TalbotIQ Report — Score: $score/100 — $verdict — Session: ${jobId ?? 'TIQ-demo'}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Report details copied to clipboard'),
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }

  /// Confirms and deletes a saved interview result from history.
  Future<void> _deleteResult(BuildContext context, InterviewResult r) async {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Result?'),
        content: Text('Permanently delete the result for "${r.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          CustomButton(
            text: 'Delete',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    store.deleteInterviewResult(r.id);
    // If we were viewing the deleted result, drop the cache key so the page
    // falls back to the current session on next entry.
    if (_loadedConvId == r.conversationId) _loadedConvId = null;
  }

  /// Builds the "Previous Interviews" history card (view / delete past results).
  Widget _buildHistoryCard(BuildContext context, AppStore store) {
    final results = store.interviewResults;
    if (results.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final currentConvId = store.currentConversation?.conversationId ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Previous Interviews (${results.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...results.map((r) {
                final viewing = _loadedConvId == r.conversationId;
                final date =
                    r.createdAt.contains('T') ? r.createdAt.split('T').first : r.createdAt;
                final isCurrent = r.conversationId == currentConvId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: viewing
                        ? theme.colorScheme.primary.withOpacity(0.08)
                        : theme.colorScheme.onSurface.withOpacity(0.04),
                    border: Border.all(
                      color: viewing
                          ? theme.colorScheme.primary.withOpacity(0.4)
                          : theme.colorScheme.outline.withOpacity(0.12),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${r.score}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    r.name,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '· current',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$date · ${r.wpm} wpm · ${r.fillers} fillers',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: viewing
                            ? null
                            : () {
                                setState(() => _loadedConvId = r.conversationId);
                                _applyResult(r);
                              },
                        child: Text(viewing ? 'Viewing' : 'View'),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: theme.colorScheme.error, size: 20),
                        onPressed: () => _deleteResult(context, r),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the interview transcript card from the session transcript
  /// (produced by transcribing the candidate's recording via Deepgram).
  Widget _buildTranscriptCard(BuildContext context, AppStore store) {
    final theme = Theme.of(context);
    final entries = store.sessionTranscript;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Interview Transcript',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Transcribed from your recording via Deepgram Nova-3.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text(
                'No transcript available for this session.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic),
              )
            else
              ...entries.map((e) {
                final isCandidate = e.role == 'candidate';
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.12),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCandidate ? 'Candidate' : 'Interviewer',
                        style: TextStyle(
                          color: isCandidate
                              ? theme.colorScheme.primary
                              : theme.colorScheme.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        e.text,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Builds recruiter quick actions card layout.
  Widget _buildRecruiterActions(
    BuildContext context,
    int overallScore,
    String verdict,
    String? jobId,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recruiter Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CustomButton(
                  text: 'Schedule Technical Interview',
                  onPressed: () => setState(() => _scheduleOpen = true),
                ),
                CustomButton(
                  text: 'Share Profile Summary',
                  variant: ButtonVariant.secondary,
                  onPressed: () =>
                      _shareProfile(context, overallScore, verdict, jobId),
                ),
                CustomButton(
                  text: 'Generate AI Offer Rec.',
                  variant: ButtonVariant.secondary,
                  onPressed: () => setState(() => _offerOpen = true),
                ),
                CustomButton(
                  text: 'New Interview Session',
                  variant: ButtonVariant.ghost,
                  onPressed: () {
                    final store = Provider.of<AppStore>(context, listen: false);
                    store.reset();
                    store.navigateTo('/setup');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Checks if Hume voice analysis job is running.
  bool _hProcessingAndPending(AppStore store) {
    return _humeProcessing && store.humeJobId != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);

    // Unified progressive loading screen for background tasks
    final showLoader = _fetchingTranscript || _humeProcessing || _geminiLoading;

    if (showLoader) {
      return ResultsLoadingView(
        fetchingTranscript: _fetchingTranscript,
        humeProcessing: _humeProcessing,
        geminiLoading: _geminiLoading,
        sessionTranscript: store.sessionTranscript,
        atsScorecard: _atsScorecard,
        geminiError: _geminiError,
      );
    }

    final bool noCurrentResult = store.sessionTranscript.isEmpty &&
        store.humeResult == null &&
        !_humeProcessing;

    if (noCurrentResult) {
      // No result for the current session — but if past results exist, let the
      // user pick one to view rather than showing a dead end.
      if (store.interviewResults.isNotEmpty) {
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 950),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interview Results',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select a previous interview below to view its full scorecard.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    _buildHistoryCard(context, store),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No interview assessment logs found.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  store.tavusKey.isEmpty
                      ? 'Add a Tavus API key in Settings so the transcript can be retrieved.'
                      : 'The transcript could not be retrieved. Make sure transcription was enabled for the session.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Go to Setup',
                onPressed: () => store.navigateTo('/setup'),
              ),
            ],
          ),
        ),
      );
    }

    final humeResult = store.humeResult;
    // Unified score resolver: prefer Hume's composite, otherwise the Gemini ATS
    // fit score. When neither is available we surface N/A instead of a
    // fabricated 72, so this headline matches the persisted / candidate-visible
    // score.
    final int? resolvedScore =
        humeResult?.compositeScore ?? _atsScorecard?.overallFitScore;
    final int overallScore = resolvedScore ?? 0;
    final String verdict =
        resolvedScore != null ? _getScoreVerdict(resolvedScore) : 'Awaiting score';

    final List<String> strengths = [];
    final List<String> watchPoints = [];

    if (overallScore >= 75) {
      strengths.add('Composed under pressure');
      strengths.add('High engagement signals');
    } else {
      watchPoints.add('Slight confidence fluctuations');
    }
    if (store.wpm >= 110 && store.wpm <= 160) {
      strengths.add('Clear speaking pace');
    } else if (store.wpm > 165) {
      watchPoints.add('Speaking pace slightly fast');
    }
    if (store.fillers <= 3) {
      strengths.add('Minimal vocal fillers');
    } else {
      watchPoints.add('Vocal filler usage noted');
    }

    if (strengths.isEmpty) strengths.add('Completed all questions');
    if (watchPoints.isEmpty) watchPoints.add('No major warning flags detected');

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 950),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Interview Complete',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                store.currentConversation?.conversationName ??
                                    'Interview Assessment',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Comprehensive candidate intelligence powered by conversational AI.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'Session ID: ',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    store.currentConversation?.conversationId ??
                                        'TIQ-demo',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Interview Complete',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.2,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      store
                                              .currentConversation
                                              ?.conversationName ??
                                          'Interview Assessment',
                                      style: theme.textTheme.headlineLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Comprehensive candidate intelligence powered by conversational AI.',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Session ID',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    store.currentConversation?.conversationId ??
                                        'TIQ-demo',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontFamily: 'Courier',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    const SizedBox(height: 24),

                    _buildHistoryCard(context, store),

                    if (_hProcessingAndPending(store)) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withValues(alpha: 0.08),
                          border: Border.all(
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.24,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  theme.colorScheme.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'HUME AI · Analysing prosody — emotion results will appear shortly. Job: ${store.humeJobId}',
                                style: TextStyle(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 12,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    GridPaperResult(
                      children: [
                        StatCard(
                          label: 'Overall Score',
                          value: resolvedScore != null
                              ? '$overallScore/100'
                              : 'N/A',
                          valueColor: theme.colorScheme.primary,
                          subTitle: verdict,
                        ),
                        StatCard(
                          label: 'Hiring Confidence',
                          value: resolvedScore != null
                              ? '$overallScore%'
                              : 'N/A',
                          valueColor: theme.colorScheme.primary,
                          subTitle: 'Based on speech keys',
                        ),
                        StatCard(
                          label: 'Words / Min',
                          value: '${store.wpm}',
                          valueColor: store.wpm > 100
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          subTitle: 'Nova-3 speech pace',
                        ),
                        StatCard(
                          label: 'Total Fillers',
                          value: '${store.fillers}',
                          valueColor: store.fillers <= 4
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          subTitle: 'Vocal filler rate',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    LayoutBuilder(
                      builder: (context, box) {
                        final isDesktop = box.maxWidth > 700;
                        final scoreRingCard = Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularScoreRing(
                                  score: overallScore,
                                  verdict: verdict,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Overall Score',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    verdict,
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );

                        final dimsCard = DimensionScoresPanel(
                          overallScore: overallScore,
                          fillers: store.fillers,
                        );

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 220, child: scoreRingCard),
                              const SizedBox(width: 20),
                              Expanded(child: dimsCard),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              scoreRingCard,
                              const SizedBox(height: 16),
                              dimsCard,
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Hume AI Emotional Intelligence Report Dashboard
                    HumeEmotionPanel(
                      humeResult: humeResult,
                      humeKey: store.humeKey,
                      humeJobId: store.humeJobId,
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 24),

                    // Strengths / Watch points tags
                    StrengthsWatchpointsPanel(
                      strengths: strengths,
                      watchPoints: watchPoints,
                    ),
                    const SizedBox(height: 24),

                    AtsAssessmentCard(
                      geminiKey: store.geminiKey,
                      geminiError: _geminiError,
                      geminiLoading: _geminiLoading,
                      atsScorecard: _atsScorecard,
                      onRetry: _runAtsAnalysis,
                      onNavigateToSettings: () => store.navigateTo('/settings'),
                    ),
                    const SizedBox(height: 24),

                    _buildTranscriptCard(context, store),
                    const SizedBox(height: 24),

                    FacialAnalysisPanel(summary: store.facialSummary),
                    const SizedBox(height: 24),

                    _buildRecruiterActions(
                      context,
                      overallScore,
                      verdict,
                      store.humeJobId,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          if (_scheduleOpen) ...[
            ScheduleInterviewDialog(
              onClose: () => setState(() => _scheduleOpen = false),
            )
          ],

          if (_offerOpen) ...[
            OfferRecommendationDialog(
              score: overallScore,
              verdict: verdict,
              strengths: strengths,
              watchPoints: watchPoints,
              onClose: () => setState(() => _offerOpen = false),
            ),
          ],
        ],
      ),
    );
  }
}
