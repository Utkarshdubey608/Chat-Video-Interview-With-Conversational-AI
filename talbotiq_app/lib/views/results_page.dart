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

  @override
  void initState() {
    super.initState();
    _startHumeProcess();
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
    final hasConvId = store.currentConversation != null && store.currentConversation!.conversationId.isNotEmpty;

    if (!hasHumeKey || !hasConvId) {
      // Hume not active or no conversation - proceed immediately to Gemini analysis
      _runAtsAnalysis();
      return;
    }

    setState(() => _humeProcessing = true);

    // If we already have a hume result, no need to poll
    if (store.humeResult != null) {
      setState(() => _humeProcessing = false);
      _runAtsAnalysis();
      return;
    }

    // If we already have a job ID, skip submission and poll directly
    if (store.humeJobId != null) {
      _pollHumeJob(store.humeJobId!);
      return;
    }

    // Otherwise, poll Tavus for the compiled recording URL first
    _pollAttempts = 0;
    _humePollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      _pollAttempts++;
      if (_pollAttempts > 15) { // Stop polling after 1 minute
        timer.cancel();
        if (mounted) {
          setState(() => _humeProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hume analysis skipped: S3 recording ready event timeout'), backgroundColor: AppColors.warning),
          );
          _runAtsAnalysis();
        }
        return;
      }

      try {
        final convId = store.currentConversation!.conversationId;
        final recordingUri = await tavusService.getConversationRecordingUri(convId);
        
        if (recordingUri != null) {
          timer.cancel();
          // Fallback to us-east-1 if draft is missing bucket region
          final region = store.drafts.isNotEmpty ? store.drafts.first.form.recordingS3BucketRegion : 'us-east-1';
          final httpUrl = _convertS3UriToHttp(recordingUri, region.isNotEmpty ? region : 'us-east-1');
          
          // Submit the URL directly to Hume Batch Jobs API
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
      if (_pollAttempts > 45) { // Stop polling after 3 minutes
        timer.cancel();
        if (mounted) {
          setState(() => _humeProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hume analysis job polling timeout'), backgroundColor: AppColors.danger),
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
          final result = humeService.buildSessionResult(jobId, preds, store.questionTimestamps, questions);
          
          store.setHumeResult(result);
          if (mounted) {
            setState(() => _humeProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hume voice analysis completed!'), backgroundColor: AppColors.success),
            );
            _runAtsAnalysis();
          }
        } else if (job['status'] == 'FAILED') {
          timer.cancel();
          if (mounted) {
            setState(() => _humeProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hume analysis job failed'), backgroundColor: AppColors.danger),
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
    if (store.geminiKey.isEmpty) return; // Need Gemini key
    if (store.sessionTranscript.isEmpty) return; // Need candidate inputs

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
        candidateName: (store.currentConversation?.conversationName ?? 'Candidate').replaceAll('TalbotIQ — ', ''),
        jobRole: 'Senior Software Engineer',
        interviewDurationSeconds: 120, // dummy duration
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

  Color _getScoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 70) return Colors.white;
    return AppColors.warning;
  }

  String _getScoreVerdict(int score) {
    if (score >= 85) return 'Excellent Candidate';
    if (score >= 70) return 'Good Candidate';
    if (score >= 60) return 'Potential Candidate';
    return 'Needs Further Review';
  }

  void _shareProfile(int score, String verdict, String? jobId) {
    final text = 'TalbotIQ Report — Score: $score/100 — $verdict — Session: ${jobId ?? 'TIQ-demo'}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report details copied to clipboard'), backgroundColor: AppColors.success),
    );
  }

  Widget _buildStatRow(String label, String value, Color color, String sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildDimensionProgress(String label, int score) {
    final color = _getScoreColor(score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textLight, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: score / 100.0,
                child: Container(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$score',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionDetails(QuestionEmotionSummary q, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.questionText,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textLight),
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
              Text('Dominant: ${q.dominant}', style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.bold)),
              Text(
                'Confidence: ${(q.avgCategoryScores['positive_high']! * 100).round()}%',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecruiterActions(int overallScore, String verdict, String? jobId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recruiter Actions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
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
                  onPressed: () => _shareProfile(overallScore, verdict, jobId),
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
                    Provider.of<AppStore>(context, listen: false).reset();
                    Navigator.pushReplacementNamed(context, '/setup');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAtsAssessmentCard(AppStore store) {
    if (store.geminiKey.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 36),
              const SizedBox(height: 12),
              const Text('Add Google Gemini API Key to enable ATS scorecards.', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                child: const Text('Go to Settings →', style: TextStyle(color: AppColors.accent, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (_geminiLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.accent)),
                SizedBox(height: 16),
                Text('Gemini is synthesizing transcript analytics…', style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    if (_geminiError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.danger, size: 20),
                  SizedBox(width: 8),
                  Text('ATS Assessment Synthesis Failed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(_geminiError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Retry Synthesis',
                variant: ButtonVariant.outline,
                height: 32,
                onPressed: _runAtsAnalysis,
              ),
            ],
          ),
        ),
      );
    }

    if (_atsScorecard == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No transcripts captured for synthesis.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
      );
    }

    final card = _atsScorecard!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI-Powered ATS Assessment (Gemini)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ATS Recommendation: ${card.hiringRecommendation}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Overall Fit: ${card.overallFitLabel} (${card.overallFitScore}/100)', style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                      ],
                    ),
                    _buildFitBadge(card.hiringRecommendation),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                const SizedBox(height: 12),

                const Text('Hiring Recommendation Rationale', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                Text(card.hiringRecommendationRationale, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
                const SizedBox(height: 16),

                const Text('Key Strengths', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                const SizedBox(height: 6),
                ...card.topStrengths.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.check, color: AppColors.success, size: 12),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),

                const Text('Watch Points & Concerns', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.danger)),
                const SizedBox(height: 6),
                ...card.topConcerns.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: AppColors.danger, size: 12),
                          const SizedBox(width: 8),
                          Expanded(child: Text(c, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFitBadge(String rec) {
    Color bg;
    Color fg;
    if (rec == 'Advance') {
      bg = AppColors.success.withOpacity(0.1);
      fg = AppColors.success;
    } else if (rec == 'Hold') {
      bg = AppColors.accent.withOpacity(0.1);
      fg = AppColors.accent;
    } else {
      bg = AppColors.danger.withOpacity(0.1);
      fg = AppColors.danger;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rec.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildFacialPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Facial Analysis (AWS Rekognition)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), shape: BoxShape.circle),
                  child: const Icon(Icons.videocam_off, color: AppColors.textMuted, size: 18),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No Facial signals captured for this session.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 2),
                      Text('Webcam face-tracking requires proxy registration set up in Settings.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
    final store = Provider.of<AppStore>(context);
    
    // Fallbacks if no active state
    if (store.sessionTranscript.isEmpty && store.humeResult == null && !_humeProcessing) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No interview assessment logs found.', style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 12),
              CustomButton(
                text: 'Go to Setup',
                onPressed: () => Navigator.pushReplacementNamed(context, '/setup'),
              ),
            ],
          ),
        ),
      );
    }

    // Dynamic scoring logic based on Hume Composite score
    final humeResult = store.humeResult;
    final int overallScore = humeResult != null ? humeResult.compositeScore : 72;
    final String verdict = _getScoreVerdict(overallScore);

    // Strengths & Watch points bullet list
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
      backgroundColor: AppColors.background,
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
                    // Header kicker
                    isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Interview Complete',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success, letterSpacing: 1.2),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                store.currentConversation?.conversationName ?? 'Interview Assessment',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Comprehensive candidate intelligence powered by conversational AI.',
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Session ID: ', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  Text(
                                    store.currentConversation?.conversationId ?? 'TIQ-demo',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold),
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
                                    const Text(
                                      'Interview Complete',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success, letterSpacing: 1.2),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      store.currentConversation?.conversationName ?? 'Interview Assessment',
                                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Comprehensive candidate intelligence powered by conversational AI.',
                                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Session ID', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  Text(
                                    store.currentConversation?.conversationId ?? 'TIQ-demo',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    const SizedBox(height: 20),

                    // Hume job active processing banner
                    if (_humeProcessing) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.humeCard,
                          border: Border.all(color: AppColors.humeBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.humeTeal)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'HUME AI · Analysing prosody — emotion results will appear shortly. Job: ${store.humeJobId}',
                                style: const TextStyle(color: AppColors.humeTeal, fontSize: 11, fontFamily: 'Courier'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // KPI row
                    GridPaperStub(
                      children: [
                        _buildStatRow('Overall Score', '$overallScore/100', AppColors.success, verdict),
                        _buildStatRow('Hiring Confidence', '$overallScore%', AppColors.success, 'Based on speech keys'),
                        _buildStatRow('Words / Min', '${store.wpm}', store.wpm > 100 ? AppColors.success : AppColors.warning, 'Nova-3 speech pace'),
                        _buildStatRow('Total Fillers', '${store.fillers}', store.fillers <= 4 ? AppColors.success : AppColors.warning, 'Vocal filler rate'),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Score ring + Dimension bars split
                    LayoutBuilder(
                      builder: (context, box) {
                        final isDesktop = box.maxWidth > 700;
                        final scoreRingCard = Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularScoreRing(score: overallScore, verdict: verdict),
                                const SizedBox(height: 16),
                                const Text('Overall Score', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                  child: Text(verdict, style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
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
                                const Text('Dimension Scores', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 16),
                                _buildDimensionProgress('Communication', overallScore),
                                _buildDimensionProgress('Confidence', overallScore + 4),
                                _buildDimensionProgress('Engagement', overallScore - 2),
                                _buildDimensionProgress('Vocabulary', 75),
                                _buildDimensionProgress('Stress Mgmt', overallScore + 2),
                                _buildDimensionProgress('Articulation', (100 - store.fillers * 5).clamp(40, 100)),
                              ],
                            ),
                          ),
                        );

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 220, child: scoreRingCard),
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
                    const SizedBox(height: 20),

                    // Hume AI Emotional Intelligence Report Dashboard
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.humeBase,
                        border: Border.all(color: AppColors.humeBorder),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HUME AI · PROSODY ANALYSIS',
                                    style: TextStyle(color: AppColors.humeMuted, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Emotional Intelligence Report',
                                    style: TextStyle(color: AppColors.humeText, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              if (humeResult != null)
                                SentimentArc(score: humeResult.compositeScore, label: 'Emotion Score'),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          if (humeResult != null) ...[
                            LayoutBuilder(
                              builder: (context, radarBox) {
                                final isWide = radarBox.maxWidth > 600;
                                final radarWidget = Container(
                                  width: 260,
                                  height: 260,
                                  child: EmotionRadarChart(categoryScores: humeResult.overallCategoryScores),
                                );
                                
                                final breakdownWidget = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Category Breakdown', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 12),
                                    _buildHumeCategoryRow('High Positive', humeResult.overallCategoryScores['positive_high'] ?? 0.0, AppColors.humeTeal),
                                    _buildHumeCategoryRow('Calm Positive', humeResult.overallCategoryScores['positive_calm'] ?? 0.0, AppColors.humeTeal),
                                    _buildHumeCategoryRow('Cognitive', humeResult.overallCategoryScores['cognitive'] ?? 0.0, AppColors.accent),
                                    _buildHumeCategoryRow('Social', humeResult.overallCategoryScores['social'] ?? 0.0, Colors.purpleAccent),
                                    _buildHumeCategoryRow('Negative', humeResult.overallCategoryScores['negative'] ?? 0.0, AppColors.danger),
                                    _buildHumeCategoryRow('Disengaged', humeResult.overallCategoryScores['disengagement'] ?? 0.0, AppColors.textMuted),
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
                            const Text('Question-by-Question Voice Analysis', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: !isMobile ? 2 : 1,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 92,
                              ),
                              itemCount: humeResult.perQuestion.length,
                              itemBuilder: (context, idx) {
                                return _buildQuestionDetails(humeResult.perQuestion[idx], idx);
                              },
                            ),
                          ] else ...[
                            // Hume key absent / no data
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40.0),
                                child: Column(
                                  children: [
                                    const Icon(Icons.mic_off, color: AppColors.humeMuted, size: 36),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Prosody voice analysis was not captured.',
                                      style: TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      store.humeKey.isEmpty
                                          ? 'Add a Hume API key in Settings to analyze emotional tone.'
                                          : 'Make sure candidate speaks clearly during session.',
                                      style: const TextStyle(color: AppColors.humeMuted, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

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
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('✓', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Strengths', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: strengths.map((s) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), border: Border.all(color: AppColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                                      child: Text(s, style: const TextStyle(color: AppColors.success, fontSize: 11)),
                                    )).toList(),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('⚠', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Watch Points', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: watchPoints.map((w) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), border: Border.all(color: AppColors.warning.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                                      child: Text(w, style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                                    )).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Gemini Scorecard
                    _buildAtsAssessmentCard(store),
                    const SizedBox(height: 20),

                    // Facial Analysis
                    _buildFacialPanel(),
                    const SizedBox(height: 20),

                    // Full Recruiter actions
                    _buildRecruiterActions(overallScore, verdict, store.humeJobId),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          // Schedule Technical Round Modal overlay
          if (_scheduleOpen) ...[
            _buildScheduleModal(),
          ],

          // AI Offer Recommendation Modal overlay
          if (_offerOpen) ...[
            _buildOfferModal(overallScore, verdict, strengths, watchPoints),
          ],
        ],
      ),
    );
  }

  Widget _buildHumeCategoryRow(String label, double val, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppColors.humeText, fontSize: 11)),
          ),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: val.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(val * 100).round()}%',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleModal() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Schedule Technical Interview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Book the next round for this candidate.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: 'Confirm Schedule',
                    onPressed: () {
                      setState(() => _scheduleOpen = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Technical round scheduled!'), backgroundColor: AppColors.success),
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

  Widget _buildOfferModal(int score, String verdict, List<String> str, List<String> watch) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI Offer Recommendation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDarker,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '''OFFER RECOMMENDATION — TalbotIQ AI
Score: $score/100 | Verdict: $verdict

RECOMMENDATION: ${score >= 75 ? 'Proceed with Offer' : 'Further Technical Assessment'}

Top Strengths: ${str.join(', ')}
Watch Points: ${watch.join(', ')}

Generated: ${DateTime.now().toString().split(' ').first}''',
                  style: const TextStyle(fontSize: 11, fontFamily: 'Courier', color: AppColors.success, height: 1.4),
                ),
              ),
              const SizedBox(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _offerOpen = false),
                    child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: 'Copy to Clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: 'OFFER RECOMMENDATION — Score: $score/100 — Verdict: $verdict — Strengths: ${str.join(', ')}',
                      ));
                      setState(() => _offerOpen = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Offer copied to clipboard!'), backgroundColor: AppColors.success),
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

// Responsive grid support for cards
class GridPaperStub extends StatelessWidget {
  final List<Widget> children;

  const GridPaperStub({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final crossCount = box.maxWidth > 750 ? 4 : (box.maxWidth > 480 ? 2 : 1);
        final double aspectRatio = box.maxWidth > 750 ? 1.5 : (box.maxWidth > 480 ? 1.8 : 3.0);
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

// Random mock stub helper
class MathRandomStub {
  double nextDouble() => 0.5;
  int nextInt(int max) => 5;
}
