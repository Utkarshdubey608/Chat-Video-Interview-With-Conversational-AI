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
  // runs only once at app startup. We instead (re)run the analysis pipeline
  // each time the user enters the /results route — see _onRouteChanged.
  AppStore? _store;
  bool _didInit = false;

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

  /// Runs the analysis pipeline once when the results route becomes active, and
  /// re-arms it when the user navigates away so a fresh interview re-analyses.
  void _onRouteChanged() {
    final store = _store;
    if (store == null) return;
    if (store.currentRoute == '/results') {
      if (_didInit) return;
      _didInit = true;
      _initResults();
    } else {
      _didInit = false;
    }
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
        final entries = await deepgramService.transcribeFromFile(bytes);
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
    final hasConvId =
        store.currentConversation != null &&
        store.currentConversation!.conversationId.isNotEmpty;

    if (!hasHumeKey || !hasConvId) {
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
        final convId = store.currentConversation!.conversationId;
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
      final summary = FacialSessionSummary(
        totalFrames: 0,
        usableFrames: 0,
        usableFramePercent: 0.0,
        perQuestion: [],
        sessionDominantEmotions: [],
        sessionAvgAttention: 0.0,
        sessionAvgSmile: 0.0,
        overallLookingAwayPercent: 0.0,
        dataQuality: 'insufficient',
        dataQualityNote: 'Camera proxy was not active',
        integrityFlags: [],
        engagementFlags: [],
        concernFlags: [],
      );

      final scorecard = await geminiService.analyze(
        candidateName:
            (store.currentConversation?.conversationName ?? 'Candidate')
                .replaceAll('TalbotIQ — ', ''),
        jobRole: 'Senior Software Engineer',
        interviewDurationSeconds: 120,
        transcript: store.sessionTranscript,
        questions: store.questions,
        humeResult: store.humeResult,
        wpm: store.wpm,
        totalFillers: store.fillers,
        facialSummary: summary,
      );

      setState(() {
        _atsScorecard = scorecard;
      });
    } catch (e) {
      setState(() {
        _geminiError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() => _geminiLoading = false);
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

    if (store.sessionTranscript.isEmpty &&
        store.humeResult == null &&
        !_humeProcessing) {
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
    final int overallScore = humeResult != null
        ? humeResult.compositeScore
        : 72;
    final String verdict = _getScoreVerdict(overallScore);

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
      backgroundColor: theme.colorScheme.surface,
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
                          value: '$overallScore/100',
                          valueColor: theme.colorScheme.primary,
                          subTitle: verdict,
                        ),
                        StatCard(
                          label: 'Hiring Confidence',
                          value: '$overallScore%',
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

                    const FacialAnalysisPanel(),
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
