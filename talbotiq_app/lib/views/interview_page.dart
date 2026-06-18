// lib/views/interview_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/colors.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../core/services/deepgram_service.dart';
import '../core/services/deepgram_live.dart';
import '../widgets/iframe_view.dart';
import '../widgets/custom_buttons.dart';

class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key});

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage>
    with TickerProviderStateMixin {
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

  // Live transcription:
  // - web: Deepgram Nova-3 streaming the candidate's mic
  // - mobile/desktop: platform speech recognizer via speech_to_text
  DeepgramLiveSession? _dgSession;
  bool _transcriptionStarted = false;
  String _interimText = '';
  String? _transcriptError;
  bool _dgConnected = false;
  int _totalFillers = 0;

  // Cached store reference so we can add/remove a route listener safely.
  AppStore? _store;

  @override
  void initState() {
    super.initState();
    _revealedIdx = 0;
    _startSimulations();
    _resetQuestionTimers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InterviewPage lives inside MainLayout's IndexedStack, so it is BUILT (and
    // initState runs) while the user is still on the Setup page. We must NOT
    // grab the mic / speech recognizer until the interview page is actually the
    // active route and a session is live — otherwise transcription fires on
    // Setup. Drive the live transcription lifecycle off the store's route here.
    final store = Provider.of<AppStore>(context, listen: false);
    if (!identical(store, _store)) {
      _store?.removeListener(_syncTranscriptionWithRoute);
      _store = store;
      _store!.addListener(_syncTranscriptionWithRoute);
    }
    _syncTranscriptionWithRoute();
  }

  // Start transcription only while the interview page is visible AND active;
  // stop it as soon as we navigate away.
  void _syncTranscriptionWithRoute() {
    final store = _store;
    if (store == null) return;
    final shouldRun = store.currentRoute == '/interview' && store.interviewActive;
    if (shouldRun) {
      _startLiveTranscription();
    } else {
      _stopLiveTranscription();
    }
  }

  @override
  void dispose() {
    _store?.removeListener(_syncTranscriptionWithRoute);
    _jitterTimer?.cancel();
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();
    _avatarSpeakTimer?.cancel();
    _dgSession?.stop();
    _overrideController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  // Live candidate transcript. Web mirrors the React app's Deepgram path;
  // native builds use platform speech recognition so Results can be generated
  // immediately from store.sessionTranscript.
  void _startLiveTranscription() {
    if (_transcriptionStarted) return;
    final store = Provider.of<AppStore>(context, listen: false);
    if (kIsWeb) {
      if (store.deepgramKey.isEmpty) return;
      deepgramService.setKey(store.deepgramKey);
    }
    // Mark started before creating the session so route-change notifications
    // that fire mid-startup don't spawn a second recognizer.
    _transcriptionStarted = true;

    _dgSession = DeepgramLiveSession(
      onFinal: (text) {
        if (!mounted) return;
        final entry = TranscriptEntry(
          role: 'candidate',
          text: text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          questionIdx: store.currentQuestionIdx,
        );
        store.pushTranscriptEntry(entry);

        _totalFillers += deepgramService.countFillers(text);
        final int wpm = deepgramService.calcWpm(store.sessionTranscript);
        store.updateMetrics(w: wpm > 0 ? wpm : store.wpm, f: _totalFillers);
        setState(() => _interimText = '');
        _scrollToBottom();
      },
      onInterim: (text) {
        if (mounted) setState(() => _interimText = text);
      },
      onConnected: (connected) {
        if (!mounted) return;
        setState(() {
          _dgConnected = connected;
          if (connected) _transcriptError = null;
        });
        store.setDeepgramConnected(connected);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _dgConnected = false;
          _transcriptError = message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcript: $message'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 8),
          ),
        );
      },
    );
    _dgSession!.start();
  }

  void _stopLiveTranscription() {
    if (!_transcriptionStarted) return;
    _transcriptionStarted = false;
    _dgSession?.stop();
    _dgSession = null;
    if (mounted) {
      setState(() {
        _interimText = '';
        _dgConnected = false;
      });
    }
  }

  void _startSimulations() {
    final store = Provider.of<AppStore>(context, listen: false);

    // Confidence / anxiety / engagement are jittered as a live-feed proxy
    // (Hume EVI streaming is not wired up on this client). WPM and fillers come
    // from the real Deepgram transcript in _startLiveTranscription.
    _jitterTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!store.interviewActive) return;
      final random = math.Random();
      final conf = (store.confidence == 0)
          ? 80
          : (store.confidence + (random.nextInt(5) - 2)).clamp(70, 90);
      final anx = (store.anxiety == 0)
          ? 12
          : (store.anxiety + (random.nextInt(3) - 1)).clamp(8, 20);
      final eng = (store.engagement == 0)
          ? 92
          : (store.engagement + (random.nextInt(4) - 2)).clamp(85, 96);
      store.updateMetrics(conf: conf, anx: anx, eng: eng);
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

  void _resetQuestionTimers() {
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();

    final store = Provider.of<AppStore>(context, listen: false);
    final isDemo = store.currentConversation?.conversationUrl == '';

    _fallbackRevealTimer = Timer(Duration(seconds: isDemo ? 4 : 9), () {
      if (mounted) {
        setState(() {
          _revealedIdx = store.currentQuestionIdx;
        });
      }
    });

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
    final theme = Theme.of(context);

    final confirmEnd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Interview?'),
          content: const Text(
            'Are you sure you want to end the interview now and generate the scorecard?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
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

    // Stop the live mic/transcription stream — the transcript is already captured in
    // the store as the candidate spoke, so results can be generated immediately.
    _dgSession?.stop();
    _dgSession = null;

    if (store.currentConversation != null &&
        store.currentConversation!.conversationUrl.isNotEmpty) {
      try {
        await tavusService.endConversation(
          store.currentConversation!.conversationId,
        );
      } catch (e) {
        debugPrint('Tavus end conversation error: $e');
      }
    }

    if (mounted) {
      store.navigateTo('/results');
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
        'conversational_context': overrideText,
      });

      _overrideController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Context override sent'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to override context: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildProgressBar(
    ThemeData theme,
    List<String> validQs,
    int currentQ,
  ) {
    final double pct = validQs.isEmpty ? 0 : (currentQ + 1) / validQs.length;
    return Container(
      height: 4,
      width: double.infinity,
      color: theme.colorScheme.outline.withOpacity(0.12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: pct,
          child: Container(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildVideoPanel(AppStore store, List<String> validQs) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 850;
    final hasUrl =
        store.currentConversation?.conversationUrl.isNotEmpty ?? false;

    return Container(
      color: theme.colorScheme.surface,
      child: Stack(
        children: [
          Center(
            child: Container(
              margin: EdgeInsets.all(isMobile ? 12 : 24),
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.12),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (hasUrl && store.currentRoute == '/interview')
                    ? buildIframe(store.currentConversation!.conversationUrl)
                    : _buildDemoPlaceholder(),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildProgressBar(theme, validQs, store.currentQuestionIdx),
          ),

          Positioned(
            top: 16,
            right: 16,
            child: CustomButton(
              text: _isFullscreen ? 'Exit Full Screen' : 'Full Screen',
              variant: ButtonVariant.outline,
              height: 36,
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
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
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PulsingAvatar(),
          const SizedBox(height: 16),
          Text(
            'Demo Mode',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Avatar speech and transcripts are simulated.\nPress Next (⏭) to advance questions.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBar(AppStore store, List<String> validQs) {
    final theme = Theme.of(context);
    final isRevealed = _revealedIdx == store.currentQuestionIdx;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 650;

        final questionTextCol = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'QUESTION ${store.currentQuestionIdx + 1} OF ${validQs.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (_avatarSpeaking) ...[
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Avatar Speaking',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            isRevealed
                ? Text(
                    validQs.isNotEmpty
                        ? validQs[store.currentQuestionIdx]
                        : 'Done',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Row(
                    children: [
                      Text(
                        'Waiting for avatar to ask…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 12),
                      CustomButton(
                        text: 'Show Now',
                        variant: ButtonVariant.outline,
                        height: 28,
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
              height: 36,
              icon: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _autoAdvance
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              onPressed: () {
                setState(() {
                  _autoAdvance = !_autoAdvance;
                  _resetQuestionTimers();
                });
              },
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
            const SizedBox(width: 8),

            _buildRoundControlBtn(
              Icons.skip_previous,
              store.currentQuestionIdx > 0 ? _prevQuestion : null,
            ),
            const SizedBox(width: 8),

            _buildRoundControlBtn(Icons.stop, _endInterview, isDanger: true),
            const SizedBox(width: 8),

            _buildRoundControlBtn(Icons.skip_next, _nextQuestion),
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.12),
              ),
            ),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    questionTextCol,
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            Icons.assignment_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(
                            'Menu',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                        ),
                        controlsRow,
                      ],
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
      },
    );
  }

  Widget _buildRoundControlBtn(
    IconData icon,
    VoidCallback? onPressed, {
    bool isDanger = false,
  }) {
    final theme = Theme.of(context);
    final disabled = onPressed == null;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDanger
            ? theme.colorScheme.error.withOpacity(0.08)
            : (disabled
                  ? theme.colorScheme.onSurface.withOpacity(0.02)
                  : theme.colorScheme.onSurface.withOpacity(0.06)),
        border: Border.all(
          color: isDanger
              ? theme.colorScheme.error.withOpacity(0.24)
              : (disabled
                    ? theme.colorScheme.outline.withOpacity(0.05)
                    : theme.colorScheme.outline.withOpacity(0.24)),
        ),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: isDanger
              ? theme.colorScheme.error
              : (disabled
                    ? theme.colorScheme.onSurfaceVariant.withOpacity(0.4)
                    : theme.colorScheme.onSurface),
        ),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSidebar(
    AppStore store,
    List<String> validQs, {
    bool isMobile = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: isMobile ? null : 320,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: isMobile
              ? BorderSide.none
              : BorderSide(color: theme.colorScheme.outline.withOpacity(0.12)),
          top: isMobile
              ? BorderSide(color: theme.colorScheme.outline.withOpacity(0.12))
              : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          // Sidebar tabs
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.12),
                ),
              ),
            ),
            child: Row(
              children: [
                if (isMobile)
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
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
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.12),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.24),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _endInterview,
                  child: Text(
                    'End Interview',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String id, String title) {
    final theme = Theme.of(context);
    final active = _activeTab == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = id),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppStore store, List<String> validQs) {
    final theme = Theme.of(context);

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
              color: isCurrent
                  ? theme.colorScheme.primary.withOpacity(0.08)
                  : Colors.transparent,
              border: Border.all(
                color: isCurrent
                    ? theme.colorScheme.primary.withOpacity(0.24)
                    : Colors.transparent,
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
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDone
                      ? theme.colorScheme.primary
                      : (isCurrent
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.outline.withOpacity(0.12)),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  isDone ? '✓' : '${idx + 1}',
                  style: TextStyle(
                    color: isDone || !isCurrent
                        ? Colors.white
                        : theme.colorScheme.onSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                !isRevealed && isCurrent
                    ? '••••••••••••••••••••••••'
                    : validQs[idx],
                style: TextStyle(
                  color: isLocked
                      ? theme.colorScheme.onSurface.withOpacity(0.38)
                      : theme.colorScheme.onSurface,
                  fontSize: 13,
                  fontStyle: !isRevealed && isCurrent
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          );
        },
      );
    } else if (_activeTab == 'live') {
      final Color chartColor = theme.brightness == Brightness.dark
          ? AppColors.humeTeal
          : theme.colorScheme.secondary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EMOTION ANALYSIS',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.wifi, color: chartColor, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE FEED',
                          style: TextStyle(
                            color: chartColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildLiveMetricBar(
                  'Confidence',
                  store.confidence,
                  theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                _buildLiveMetricBar(
                  'Anxiety',
                  store.anxiety,
                  theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                _buildLiveMetricBar(
                  'Engagement',
                  store.engagement,
                  theme.colorScheme.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
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
                        'WPM',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${store.wpm}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
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
                        'FILLERS',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${store.fillers}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (store
                  .currentConversation
                  ?.properties
                  ?.applyConversationOverride ==
              true) ...[
            Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
            const SizedBox(height: 12),
            Text(
              'OVERRIDE (SAY THIS NOW)',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _overrideController,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type text for avatar to say…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'Send',
                  height: 38,
                  onPressed: _sendOverride,
                ),
              ],
            ),
          ],
        ],
      );
    } else {
      final Color chartColor = theme.brightness == Brightness.dark
          ? AppColors.humeTeal
          : theme.colorScheme.secondary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                kIsWeb ? 'DEEPGRAM NOVA-3' : 'DEVICE SPEECH',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _dgConnected
                          ? chartColor
                          : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _dgConnected
                        ? 'LIVE'
                        : (_transcriptError != null
                              ? 'UNAVAILABLE'
                              : (kIsWeb && store.deepgramKey.isEmpty
                                    ? 'NO KEY'
                                    : 'CONNECTING…')),
                    style: TextStyle(
                      color: _dgConnected
                          ? chartColor
                          : theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (store.sessionTranscript.isEmpty && _interimText.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Text(
                !kIsWeb
                    ? (_transcriptError != null
                          ? 'Device speech unavailable. Results will try the Tavus transcript after the call ends.'
                          : (_dgConnected
                                ? 'Listening — transcript will appear as you speak…'
                                : 'Starting device speech recognition…'))
                    : (store.deepgramKey.isEmpty
                          ? 'Transcript requires a Deepgram API key in Settings.'
                          : (_dgConnected
                                ? 'Listening — transcript will appear as you speak…'
                                : 'Connecting to Deepgram…')),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          Expanded(
            child: ListView.builder(
              controller: _transcriptScrollController,
              itemCount:
                  store.sessionTranscript.length +
                  (_interimText.isNotEmpty ? 1 : 0),
              itemBuilder: (context, idx) {
                // Trailing interim "typing" entry
                if (idx >= store.sessionTranscript.length) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.02),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.12),
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Typing…',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _interimText,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 13,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final entry = store.sessionTranscript[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Q${entry.questionIdx + 1} · ${entry.role == 'avatar' ? 'Interviewer' : 'Candidate'}',
                            style: TextStyle(
                              color: entry.role == 'avatar'
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateTime.fromMillisecondsSinceEpoch(entry.timestamp)
                                .toLocal()
                                .toString()
                                .split(' ')
                                .last
                                .substring(0, 8),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.5),
                              fontSize: 9,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.text,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 13,
                          height: 1.4,
                        ),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            Text(
              '$value%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.outline.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
    final validQs = store.questions.where((q) => q.isNotEmpty).toList();

    if (store.currentConversation == null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No active interview session.',
                style: theme.textTheme.titleMedium,
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

    final isMobile = MediaQuery.of(context).size.width < 850;
    final mainVideo = _buildVideoPanel(store, validQs);
    final bottomControls = _buildQuestionBar(store, validQs);
    final sidebar = _buildSidebar(store, validQs, isMobile: isMobile);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      endDrawer: isMobile
          ? Drawer(
              width: 320,
              backgroundColor: theme.colorScheme.surface,
              child: SafeArea(child: sidebar),
            )
          : null,
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
          if (!isMobile && !_isFullscreen) sidebar,
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

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
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
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withOpacity(0.12),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(
                0.3 + _controller.value * 0.5,
              ),
              width: 2 + _controller.value * 2,
            ),
          ),
          child: Icon(Icons.person, color: theme.colorScheme.primary, size: 36),
        );
      },
    );
  }
}
