// lib/views/results_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // for clipboard
import '../core/constants/colors.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/gemini_service.dart';
import '../core/services/tavus_service.dart';
import '../core/services/hume_service.dart';
import '../core/services/deepgram_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/custom_inputs.dart';
import '../widgets/response_widgets.dart';

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

  // Dialog controllers
  final _dateController = TextEditingController();
  final _timeController = TextEditingController(text: '10:00');
  final _interviewerController = TextEditingController();
  final _notesController = TextEditingController();

  bool _fetchingTranscript = false;

  @override
  void initState() {
    super.initState();
    _initResults();
  }

  Future<void> _initResults() async {
    // On web the transcript is captured live via Deepgram during the call. On
    // mobile the WebView owns the mic, so we instead pull Tavus's own
    // server-side transcript (enable_transcription) once the call has ended.
    await _ensureTranscript();
    if (!mounted) return;
    _startHumeProcess();
  }

  // Poll Tavus for the conversation transcript. It is only produced after the
  // call ends and takes a little while to become available, so we retry.
  Future<void> _ensureTranscript() async {
    final store = Provider.of<AppStore>(context, listen: false);
    final capturedCandidateText = store.sessionTranscript
        .where((e) => e.role == 'candidate')
        .map((e) => e.text)
        .join(' ')
        .trim();
    if (capturedCandidateText.length >= 30)
      return; // already captured live/native

    final conv = store.currentConversation;
    if (conv == null || conv.conversationId.isEmpty || store.tavusKey.isEmpty)
      return;

    setState(() => _fetchingTranscript = true);
    try {
      for (int attempt = 0; attempt < 18; attempt++) {
        try {
          final entries = await tavusService.getConversationTranscript(
            conv.conversationId,
          );
          if (entries.isNotEmpty) {
            for (final e in entries) {
              store.pushTranscriptEntry(e);
            }
            // Derive speech metrics from the candidate's turns so the scorecard
            // isn't all zeros (these are computed live from Deepgram on web).
            final int fillers = store.sessionTranscript
                .where((e) => e.role == 'candidate')
                .fold(
                  0,
                  (acc, e) => acc + deepgramService.countFillers(e.text),
                );
            final int wpm = deepgramService.calcWpm(store.sessionTranscript);
            store.updateMetrics(w: wpm, f: fillers);
            break;
          }
        } catch (e) {
          debugPrint('Transcript fetch attempt $attempt failed: $e');
        }
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
      }
    } finally {
      if (mounted) setState(() => _fetchingTranscript = false);
    }
  }

  @override
  void dispose() {
    _humePollTimer?.cancel();
    _dateController.dispose();
    _timeController.dispose();
    _interviewerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

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

  String _convertS3UriToHttp(String s3Uri, String region) {
    if (!s3Uri.startsWith('s3://')) return s3Uri;
    final clean = s3Uri.replaceFirst('s3://', '');
    final parts = clean.split('/');
    final bucket = parts[0];
    final key = parts.sublist(1).join('/');
    return 'https://$bucket.s3.$region.amazonaws.com/$key';
  }

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

  Color _getScoreColor(BuildContext context, int score) {
    final theme = Theme.of(context);
    if (score >= 85) return theme.colorScheme.primary;
    if (score >= 70) return theme.colorScheme.secondary;
    return theme.colorScheme.error;
  }

  String _getScoreVerdict(int score) {
    if (score >= 85) return 'Excellent Candidate';
    if (score >= 70) return 'Good Candidate';
    if (score >= 60) return 'Potential Candidate';
    return 'Needs Further Review';
  }

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

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    Color color,
    String sub,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionProgress(
    BuildContext context,
    String label,
    int score,
  ) {
    final theme = Theme.of(context);
    final color = _getScoreColor(context, score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: score / 100.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionDetails(
    BuildContext context,
    QuestionEmotionSummary q,
    int index,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.02),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dominant: ${q.dominant}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Confidence: ${(q.avgCategoryScores['positive_high']! * 100).round()}%',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  Widget _buildAtsAssessmentCard(BuildContext context, AppStore store) {
    final theme = Theme.of(context);

    if (_geminiError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ATS Assessment Synthesis Failed',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _geminiError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Retry Synthesis',
                variant: ButtonVariant.outline,
                height: 36,
                onPressed: _runAtsAnalysis,
              ),
            ],
          ),
        ),
      );
    }

    if (store.geminiKey.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(
                Icons.lock_outline,
                color: theme.colorScheme.onSurfaceVariant,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                'Add Google Gemini API Key to enable ATS scorecards.',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Provider.of<AppStore>(
                  context,
                  listen: false,
                ).navigateTo('/settings'),
                child: Text(
                  'Go to Settings →',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_geminiLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'Gemini is synthesizing transcript analytics…',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_atsScorecard == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No transcripts captured for synthesis.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final card = _atsScorecard!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI-Powered ATS Assessment (Gemini)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ATS Recommendation: ${card.hiringRecommendation}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Overall Fit: ${card.overallFitLabel} (${card.overallFitScore}/100)',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildFitBadge(card.hiringRecommendation),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
                const SizedBox(height: 16),

                Text(
                  'Hiring Recommendation Rationale',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  card.hiringRecommendationRationale,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),

                Text(
                  'Key Strengths',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...card.topStrengths.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          color: theme.colorScheme.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Watch Points & Concerns',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...card.topConcerns.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: theme.colorScheme.error,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFitBadge(String rec) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    if (rec == 'Advance') {
      bg = theme.colorScheme.primary.withOpacity(0.12);
      fg = theme.colorScheme.primary;
    } else if (rec == 'Hold') {
      bg = theme.colorScheme.secondary.withOpacity(0.12);
      fg = theme.colorScheme.secondary;
    } else {
      bg = theme.colorScheme.error.withOpacity(0.12);
      fg = theme.colorScheme.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rec.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFacialPanel() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Facial Analysis (AWS Rekognition)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.videocam_off,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No Facial signals captured for this session.',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Webcam face-tracking requires proxy registration set up in Settings.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);

    // Retrieving Tavus's server-side transcript after the call (mobile path).
    if (_fetchingTranscript && store.sessionTranscript.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colorScheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Retrieving interview transcript…',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Tavus is finalising the conversation transcript. This can take up to a minute.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (store.sessionTranscript.isEmpty &&
        store.humeResult == null &&
        !_humeProcessing) {
      return Scaffold(
        backgroundColor: theme.colorScheme.background,
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
      backgroundColor: theme.colorScheme.background,
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
                          color: theme.colorScheme.secondary.withOpacity(0.08),
                          border: Border.all(
                            color: theme.colorScheme.secondary.withOpacity(
                              0.24,
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
                        _buildStatRow(
                          context,
                          'Overall Score',
                          '$overallScore/100',
                          theme.colorScheme.primary,
                          verdict,
                        ),
                        _buildStatRow(
                          context,
                          'Hiring Confidence',
                          '$overallScore%',
                          theme.colorScheme.primary,
                          'Based on speech keys',
                        ),
                        _buildStatRow(
                          context,
                          'Words / Min',
                          '${store.wpm}',
                          store.wpm > 100
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          'Nova-3 speech pace',
                        ),
                        _buildStatRow(
                          context,
                          'Total Fillers',
                          '${store.fillers}',
                          store.fillers <= 4
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          'Vocal filler rate',
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
                                        .withOpacity(0.12),
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

                        final dimsCard = Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dimension Scores',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildDimensionProgress(
                                  context,
                                  'Communication',
                                  overallScore,
                                ),
                                _buildDimensionProgress(
                                  context,
                                  'Confidence',
                                  overallScore + 4,
                                ),
                                _buildDimensionProgress(
                                  context,
                                  'Engagement',
                                  overallScore - 2,
                                ),
                                _buildDimensionProgress(
                                  context,
                                  'Vocabulary',
                                  75,
                                ),
                                _buildDimensionProgress(
                                  context,
                                  'Stress Mgmt',
                                  overallScore + 2,
                                ),
                                _buildDimensionProgress(
                                  context,
                                  'Articulation',
                                  (100 - store.fillers * 5).clamp(40, 100),
                                ),
                              ],
                            ),
                          ),
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
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        border: Border.all(
                          color: theme.colorScheme.outline.withOpacity(0.12),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HUME AI · PROSODY ANALYSIS',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Emotional Intelligence Report',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              if (humeResult != null)
                                SentimentArc(
                                  score: humeResult.compositeScore,
                                  label: 'Emotion Score',
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          if (humeResult != null) ...[
                            LayoutBuilder(
                              builder: (context, radarBox) {
                                final isWide = radarBox.maxWidth > 600;
                                final radarWidget = SizedBox(
                                  width: 260,
                                  height: 260,
                                  child: EmotionRadarChart(
                                    categoryScores:
                                        humeResult.overallCategoryScores,
                                  ),
                                );

                                final breakdownWidget = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Category Breakdown',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildHumeCategoryRow(
                                      context,
                                      'High Positive',
                                      humeResult
                                              .overallCategoryScores['positive_high'] ??
                                          0.0,
                                      theme.colorScheme.primary,
                                    ),
                                    _buildHumeCategoryRow(
                                      context,
                                      'Calm Positive',
                                      humeResult
                                              .overallCategoryScores['positive_calm'] ??
                                          0.0,
                                      theme.colorScheme.primary,
                                    ),
                                    _buildHumeCategoryRow(
                                      context,
                                      'Cognitive',
                                      humeResult
                                              .overallCategoryScores['cognitive'] ??
                                          0.0,
                                      theme.colorScheme.secondary,
                                    ),
                                    _buildHumeCategoryRow(
                                      context,
                                      'Social',
                                      humeResult
                                              .overallCategoryScores['social'] ??
                                          0.0,
                                      Colors.purpleAccent,
                                    ),
                                    _buildHumeCategoryRow(
                                      context,
                                      'Negative',
                                      humeResult
                                              .overallCategoryScores['negative'] ??
                                          0.0,
                                      theme.colorScheme.error,
                                    ),
                                    _buildHumeCategoryRow(
                                      context,
                                      'Disengaged',
                                      humeResult
                                              .overallCategoryScores['disengagement'] ??
                                          0.0,
                                      theme.colorScheme.onSurfaceVariant
                                          .withOpacity(0.6),
                                    ),
                                  ],
                                );

                                if (isWide) {
                                  return Row(
                                    children: [
                                      radarWidget,
                                      const SizedBox(width: 40),
                                      Expanded(child: breakdownWidget),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      radarWidget,
                                      const SizedBox(height: 20),
                                      breakdownWidget,
                                    ],
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Question-by-Question Voice Analysis',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: !isMobile ? 2 : 1,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    mainAxisExtent: 96,
                                  ),
                              itemCount: humeResult.perQuestion.length,
                              itemBuilder: (context, idx) {
                                return _buildQuestionDetails(
                                  context,
                                  humeResult.perQuestion[idx],
                                  idx,
                                );
                              },
                            ),
                          ] else ...[
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40.0,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.mic_off,
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withOpacity(0.5),
                                      size: 36,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Prosody voice analysis was not captured.',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      store.humeKey.isEmpty
                                          ? 'Add a Hume API key in Settings to analyze emotional tone.'
                                          : 'Make sure candidate speaks clearly during session.',
                                      style: theme.textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Strengths / Watch points tags
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '✓',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Strengths',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: strengths
                                        .map(
                                          (s) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary
                                                  .withOpacity(0.08),
                                              border: Border.all(
                                                color: theme.colorScheme.primary
                                                    .withOpacity(0.24),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              s,
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.primary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.error
                                              .withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '⚠',
                                          style: TextStyle(
                                            color: theme.colorScheme.error,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Watch Points',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: watchPoints
                                        .map(
                                          (w) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.error
                                                  .withOpacity(0.08),
                                              border: Border.all(
                                                color: theme.colorScheme.error
                                                    .withOpacity(0.24),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              w,
                                              style: TextStyle(
                                                color: theme.colorScheme.error,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    _buildAtsAssessmentCard(context, store),
                    const SizedBox(height: 24),

                    _buildFacialPanel(),
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

          if (_scheduleOpen) ...[_buildScheduleModal(theme)],

          if (_offerOpen) ...[
            _buildOfferModal(
              theme,
              overallScore,
              verdict,
              strengths,
              watchPoints,
            ),
          ],
        ],
      ),
    );
  }

  bool _hProcessingAndPending(AppStore store) {
    return _humeProcessing && store.humeJobId != null;
  }

  Widget _buildHumeCategoryRow(
    BuildContext context,
    String label,
    double val,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: val.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(val * 100).round()}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleModal(ThemeData theme) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28), // M3 Dialog corner radius
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schedule Technical Interview',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Book the next round for this candidate.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: CustomInputField(
                      label: 'Date',
                      placeholder: 'YYYY-MM-DD',
                      controller: _dateController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomInputField(
                      label: 'Time',
                      placeholder: '10:00',
                      controller: _timeController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              CustomInputField(
                label: 'Interviewer',
                placeholder: 'Interviewer Name',
                controller: _interviewerController,
              ),
              const SizedBox(height: 12),

              CustomInputField(
                label: 'Notes',
                placeholder: 'Areas to probe further…',
                controller: _notesController,
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _scheduleOpen = false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: 'Confirm Schedule',
                    onPressed: () {
                      setState(() => _scheduleOpen = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Technical round scheduled!'),
                          backgroundColor: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferModal(
    ThemeData theme,
    int score,
    String verdict,
    List<String> str,
    List<String> watch,
  ) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28), // M3 Dialog corner radius
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Offer Recommendation',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.12),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '''OFFER RECOMMENDATION — TalbotIQ AI
Score: $score/100 | Verdict: $verdict

RECOMMENDATION: ${score >= 75 ? 'Proceed with Offer' : 'Further Technical Assessment'}

Top Strengths: ${str.join(', ')}
Watch Points: ${watch.join(', ')}

Generated: ${DateTime.now().toString().split(' ').first}''',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Courier',
                    color: theme.colorScheme.primary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _offerOpen = false),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: 'Copy to Clipboard',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text:
                              'OFFER RECOMMENDATION — Score: $score/100 — Verdict: $verdict — Strengths: ${str.join(', ')}',
                        ),
                      );
                      setState(() => _offerOpen = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Offer copied to clipboard!'),
                          backgroundColor: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GridPaperResult extends StatelessWidget {
  final List<Widget> children;

  const GridPaperResult({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final crossCount = box.maxWidth > 750
            ? 4
            : (box.maxWidth > 480 ? 2 : 1);
        final double aspectRatio = box.maxWidth > 750
            ? 1.5
            : (box.maxWidth > 480 ? 1.8 : 3.0);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}
