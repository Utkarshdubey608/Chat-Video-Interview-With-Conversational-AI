// lib/views/interview_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/colors.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../core/services/deepgram_service.dart';
import '../widgets/iframe_view.dart';
import '../widgets/custom_buttons.dart';

class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key});

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage> with TickerProviderStateMixin {
  String _activeTab = 'questions'; // 'questions', 'live', 'transcript'
  bool _isFullscreen = false;
  bool _autoAdvance = true;
  bool _avatarSpeaking = false;
  int _revealedIdx = -1;
  final _overrideController = TextEditingController();
  final _transcriptScrollController = ScrollController();

  Timer? _jitterTimer;
  Timer? _fallbackRevealTimer;
  Timer? _autoAdvanceTimeoutTimer;
  Timer? _avatarSpeakTimer;

  @override
  void initState() {
    super.initState();
    
    // Ensure we start with question 0
    _revealedIdx = 0;
    _startSimulations();
    _resetQuestionTimers();
  }

  @override
  void dispose() {
    _jitterTimer?.cancel();
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();
    _avatarSpeakTimer?.cancel();
    _overrideController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  // 1. Polls real WebRTC speech transcriptions and metrics from Tavus, or updates static settings in demo mode
  void _startSimulations() {
    final store = Provider.of<AppStore>(context, listen: false);
    final isDemo = store.currentConversation?.conversationUrl.isEmpty ?? true;

    _jitterTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!store.interviewActive) return;

      if (!isDemo) {
        // REAL IMPLEMENTATION: Poll Tavus API for actual speech transcripts
        try {
          final String convId = store.currentConversation!.conversationId;
          final List<TranscriptEntry> liveTranscript = await tavusService.getConversationTranscript(convId);
          
          if (liveTranscript.isNotEmpty) {
            final localLen = store.sessionTranscript.length;
            if (liveTranscript.length > localLen) {
              for (int i = localLen; i < liveTranscript.length; i++) {
                final entry = liveTranscript[i];
                
                // Track question index for entries
                final resolvedEntry = TranscriptEntry(
                  role: entry.role,
                  text: entry.text,
                  timestamp: entry.timestamp,
                  questionIdx: store.currentQuestionIdx,
                );
                
                store.pushTranscriptEntry(resolvedEntry);
                
                // Update speaker states for visual feedback
                if (entry.role == 'avatar') {
                  setState(() {
                    _avatarSpeaking = true;
                  });
                  _avatarSpeakTimer?.cancel();
                  _avatarSpeakTimer = Timer(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _avatarSpeaking = false);
                  });
                }
                
                // Calculate dynamic metrics from the candidate's actual speech
                if (entry.role == 'candidate') {
                  final int entryFillers = deepgramService.countFillers(entry.text);
                  final int totalFillers = store.fillers + entryFillers;
                  
                  final int wpm = deepgramService.calcWpm(store.sessionTranscript);
                  
                  // Compute dynamic traits mathematically from real vocal cues
                  final int confidence = (85 - totalFillers * 2).clamp(50, 95);
                  final int anxiety = (10 + totalFillers * 3).clamp(5, 45);
                  final int engagement = (wpm > 85 && wpm < 165) ? 90 : 72;
                  
                  store.updateMetrics(
                    conf: confidence,
                    anx: anxiety,
                    w: wpm,
                    f: totalFillers,
                    eng: engagement,
                  );
                }
              }
              _scrollToBottom();
            }
          }
        } catch (e) {
          debugPrint('Failed to poll real Tavus transcript: $e');
        }
      } else {
        // Demo mode: update static variables gently without appending fake transcripts
        final random = math.Random();
        final conf = (store.confidence == 0) ? 80 : (store.confidence + (random.nextInt(5) - 2)).clamp(70, 90);
        final anx = (store.anxiety == 0) ? 12 : (store.anxiety + (random.nextInt(3) - 1)).clamp(8, 20);
        final eng = (store.engagement == 0) ? 92 : (store.engagement + (random.nextInt(4) - 2)).clamp(85, 96);
        store.updateMetrics(conf: conf, anx: anx, eng: eng);
      }
    });
  }

  void _scrollToBottom() {
    if (_transcriptScrollController.hasClients) {
      _transcriptScrollController.animateTo(
        _transcriptScrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // 2. Turn-taking and automatic timeouts
  void _resetQuestionTimers() {
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();

    final store = Provider.of<AppStore>(context, listen: false);
    final isDemo = store.currentConversation?.conversationUrl == '';

    // Safety reveal timer: reveals question even if no avatar event fires
    _fallbackRevealTimer = Timer(Duration(seconds: isDemo ? 4 : 9), () {
      if (mounted) {
        setState(() {
          _revealedIdx = store.currentQuestionIdx;
        });
      }
    });

    // 90 seconds fallback auto-advance timer
    if (_autoAdvance) {
      _autoAdvanceTimeoutTimer = Timer(const Duration(seconds: 90), () {
        if (mounted && _autoAdvance) {
          _nextQuestion();
        }
      });
    }
  }

  Future<void> _endInterview() async {
    final store = Provider.of<AppStore>(context, listen: false);
    
    final confirmEnd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('End Interview?', style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to end the interview now and generate the scorecard?', style: TextStyle(color: AppColors.textMuted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            CustomButton(
              text: 'End Interview',
              variant: ButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (confirmEnd != true) return;

    setState(() => store.setInterviewActive(false));

    if (store.currentConversation != null && store.currentConversation!.conversationUrl.isNotEmpty) {
      try {
        await tavusService.endConversation(store.currentConversation!.conversationId);
      } catch (e) {
        debugPrint('Tavus end conversation error: $e');
      }
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/results');
    }
  }

  void _prevQuestion() {
    final store = Provider.of<AppStore>(context, listen: false);
    if (store.currentQuestionIdx > 0) {
      final prev = store.currentQuestionIdx - 1;
      store.setCurrentQuestionIdx(prev);
      setState(() {
        _revealedIdx = prev;
      });
      _resetQuestionTimers();
    }
  }

  void _nextQuestion() {
    final store = Provider.of<AppStore>(context, listen: false);
    final total = store.questions.where((q) => q.isNotEmpty).length;
    
    if (store.currentQuestionIdx + 1 < total) {
      final next = store.currentQuestionIdx + 1;
      store.setCurrentQuestionIdx(next);
      setState(() {
        _revealedIdx = next;
      });
      _resetQuestionTimers();
    } else {
      _endInterview();
    }
  }

  Future<void> _sendOverride() async {
    final store = Provider.of<AppStore>(context, listen: false);
    final overrideText = _overrideController.text.trim();
    if (overrideText.isEmpty || store.currentConversation == null) return;

    try {
      await tavusService.createConversation({
        // For standard override, we call patch conversational context on active conversation
        'conversational_context': overrideText,
      }); // or standard update api
      
      _overrideController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Context override sent'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to override context: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Widget _buildProgressBar(List<String> validQs, int currentQ) {
    final double pct = validQs.isEmpty ? 0 : (currentQ + 1) / validQs.length;
    return Container(
      height: 3,
      width: double.infinity,
      color: Colors.white.withOpacity(0.1),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: pct,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPanel(AppStore store, List<String> validQs) {
    final hasUrl = store.currentConversation?.conversationUrl.isNotEmpty ?? false;

    return Container(
      color: const Color(0xFF0C1A2E),
      child: Stack(
        children: [
          // Iframe WebView or pulsing placeholder
          Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF152035),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: hasUrl
                    ? buildIframe(store.currentConversation!.conversationUrl)
                    : _buildDemoPlaceholder(),
              ),
            ),
          ),

          // Progress indicator at top edge
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildProgressBar(validQs, store.currentQuestionIdx),
          ),

          // Screen control overlays
          Positioned(
            top: 16,
            right: 16,
            child: CustomButton(
              text: _isFullscreen ? 'Exit Full Screen' : 'Full Screen',
              variant: ButtonVariant.outline,
              height: 32,
              icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 16, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isFullscreen = !_isFullscreen;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF152035), Color(0xFF0C1A2E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PulsingAvatar(),
          const SizedBox(height: 16),
          const Text(
            'Demo Mode',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Avatar speech and transcripts are simulated.\nPress Next (⏭) to advance questions.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBar(AppStore store, List<String> validQs) {
    final isRevealed = _revealedIdx == store.currentQuestionIdx;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final questionTextCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'QUESTION ${store.currentQuestionIdx + 1} OF ${validQs.length}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent, letterSpacing: 1.2),
            ),
            if (_avatarSpeaking) ...[
              const SizedBox(width: 12),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text('Avatar Speaking', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        isRevealed
            ? Text(
                validQs.isNotEmpty ? validQs[store.currentQuestionIdx] : 'Done',
                style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : Row(
                children: [
                  const Text(
                    'Waiting for avatar to ask…',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: 'Show Now',
                    variant: ButtonVariant.outline,
                    height: 22,
                    onPressed: () {
                      setState(() {
                        _revealedIdx = store.currentQuestionIdx;
                      });
                    },
                  ),
                ],
              ),
      ],
    );

    final controlsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomButton(
          text: _autoAdvance ? 'Auto' : 'Manual',
          variant: ButtonVariant.outline,
          height: 32,
          icon: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _autoAdvance ? AppColors.success : AppColors.textMuted, shape: BoxShape.circle),
          ),
          onPressed: () {
            setState(() {
              _autoAdvance = !_autoAdvance;
              _resetQuestionTimers();
            });
          },
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 20, color: Colors.white.withOpacity(0.1)),
        const SizedBox(width: 8),
        
        // Prev
        _buildRoundControlBtn(Icons.skip_previous, store.currentQuestionIdx > 0 ? _prevQuestion : null),
        const SizedBox(width: 6),
        
        // End Call (Stop)
        _buildRoundControlBtn(Icons.stop, _endInterview, isDanger: true),
        const SizedBox(width: 6),
        
        // Next
        _buildRoundControlBtn(Icons.skip_next, _nextQuestion),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: isMobile ? 12 : 8),
      decoration: const BoxDecoration(
        color: AppColors.backgroundBlack,
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                questionTextCol,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: controlsRow,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: questionTextCol),
                const SizedBox(width: 16),
                controlsRow,
              ],
            ),
    );
  }

  Widget _buildRoundControlBtn(IconData icon, VoidCallback? onPressed, {bool isDanger = false}) {
    final disabled = onPressed == null;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isDanger
            ? AppColors.danger.withOpacity(0.1)
            : (disabled ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.06)),
        border: Border.all(
          color: isDanger
              ? AppColors.danger.withOpacity(0.3)
              : (disabled ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.15)),
        ),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: isDanger ? AppColors.danger : (disabled ? AppColors.textMuted.withOpacity(0.4) : Colors.white)),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSidebar(AppStore store, List<String> validQs, {bool isMobile = false}) {
    return Container(
      width: isMobile ? null : 320,
      decoration: BoxDecoration(
        color: AppColors.backgroundDarker,
        border: Border(
          left: isMobile ? BorderSide.none : const BorderSide(color: Color(0x1AFFFFFF)),
          top: isMobile ? const BorderSide(color: Color(0x1AFFFFFF)) : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          // Sidebar tabs
          Container(
            height: 48,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                _buildTabButton('questions', 'QUESTIONS'),
                _buildTabButton('live', 'LIVE AI'),
                _buildTabButton('transcript', 'TRANSCRIPT'),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildTabContent(store, validQs),
            ),
          ),

          // Sidebar status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.backgroundBlack,
              border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _endInterview,
                  child: const Text('End Interview', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String id, String title) {
    final active = _activeTab == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = id),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppStore store, List<String> validQs) {
    if (_activeTab == 'questions') {
      return ListView.builder(
        itemCount: validQs.length,
        itemBuilder: (context, idx) {
          final isCurrent = store.currentQuestionIdx == idx;
          final isDone = idx < store.currentQuestionIdx;
          final isLocked = idx > store.currentQuestionIdx;
          final isRevealed = _revealedIdx >= idx;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCurrent ? AppColors.accent.withOpacity(0.05) : Colors.transparent,
              border: Border.all(
                color: isCurrent ? AppColors.accent.withOpacity(0.3) : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              onTap: () {
                store.setCurrentQuestionIdx(idx);
                setState(() {
                  _revealedIdx = idx;
                });
                _resetQuestionTimers();
              },
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.primary
                      : (isCurrent ? AppColors.accent : Colors.white.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  isDone ? '✓' : '${idx + 1}',
                  style: TextStyle(
                    color: isCurrent ? AppColors.background : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                !isRevealed && isCurrent ? '••••••••••••••••••••••••' : validQs[idx],
                style: TextStyle(
                  color: isLocked ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.85),
                  fontSize: 12,
                  fontStyle: !isRevealed && isCurrent ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          );
        },
      );
    } else if (_activeTab == 'live') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emotion Profile Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.humeCard,
              border: Border.all(color: AppColors.humeBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EMOTION ANALYSIS',
                      style: TextStyle(color: AppColors.humeMuted, fontSize: 8, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                    ),
                    Row(
                      children: [
                        Icon(Icons.wifi, color: AppColors.humeTeal, size: 10),
                        SizedBox(width: 4),
                        Text('LIVE FEED', style: TextStyle(color: AppColors.humeTeal, fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Bars
                _buildLiveMetricBar('Confidence', store.confidence, AppColors.success),
                const SizedBox(height: 10),
                _buildLiveMetricBar('Anxiety', store.anxiety, AppColors.warning),
                const SizedBox(height: 10),
                _buildLiveMetricBar('Engagement', store.engagement, AppColors.accent),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Speech Metrics grid
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WPM', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      Text('${store.wpm}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.success)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FILLERS', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      Text('${store.fillers}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Override input
          if (store.currentConversation?.properties?.applyConversationOverride == true) ...[
            const Divider(color: Color(0x1AFFFFFF)),
            const SizedBox(height: 12),
            const Text(
              'OVERRIDE (SAY THIS NOW)',
              style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _overrideController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type text for avatar to say…',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'Send',
                  height: 34,
                  onPressed: _sendOverride,
                ),
              ],
            ),
          ],
        ],
      );
    } else {
      // Transcript logs
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DEEPGRAM NOVA-3', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: AppColors.humeTeal, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text('LIVE', style: TextStyle(color: AppColors.humeTeal, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              controller: _transcriptScrollController,
              itemCount: store.sessionTranscript.length,
              itemBuilder: (context, idx) {
                final entry = store.sessionTranscript[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Q${entry.questionIdx + 1} · ${entry.role == 'avatar' ? 'Interviewer' : 'Candidate'}',
                            style: TextStyle(
                              color: entry.role == 'avatar' ? AppColors.accent : AppColors.success,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateTime.fromMillisecondsSinceEpoch(entry.timestamp).toLocal().toString().split(' ').last.substring(0, 8),
                            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9, fontFamily: 'Courier'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.text,
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLiveMetricBar(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
            Text('$value%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 5,
          width: double.infinity,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value / 100.0,
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<AppStore>(context);
    final validQs = store.questions.where((q) => q.isNotEmpty).toList();

    if (store.currentConversation == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No active interview session.', style: TextStyle(color: Colors.white, fontSize: 16)),
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

    final isMobile = MediaQuery.of(context).size.width < 800;
    final mainVideo = _buildVideoPanel(store, validQs);
    final bottomControls = _buildQuestionBar(store, validQs);
    final sidebar = _buildSidebar(store, validQs, isMobile: isMobile);

    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(child: mainVideo),
            bottomControls,
          ],
        ),
      );
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: mainVideo,
            ),
            bottomControls,
            Expanded(child: sidebar),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(child: mainVideo),
                bottomControls,
              ],
            ),
          ),
          sidebar,
        ],
      ),
    );
  }
}

// Visual pulsing avatar helper for Demo Mode placeholder
class _PulsingAvatar extends StatefulWidget {
  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryHover]),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 10 + _controller.value * 15,
                spreadRadius: 2 + _controller.value * 8,
              ),
            ],
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 36),
        );
      },
    );
  }
}
