// lib/views/interview_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../core/services/deepgram_service.dart';
import '../core/services/deepgram_live.dart';
import '../core/services/recording_service.dart';
import '../widgets/custom_buttons.dart';
import 'interview/widgets/video_panel.dart';
import 'interview/widgets/question_bar.dart';
import 'interview/widgets/interview_sidebar.dart';


/// The main interview view screen that orchestrates the video feed,
/// bottom control navigation bar, and sidebar analytics/transcript tab panels.
class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key});

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage>
    with TickerProviderStateMixin {
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
  Timer? _tavusPollTimer;

  // Live transcription session for streaming the candidate's mic (web only).
  DeepgramLiveSession? _dgSession;
  bool _transcriptionStarted = false;

  // Local .wav recorder for the candidate's mic (native only). The recording is
  // transcribed by Deepgram on the results page once the call ends.
  final RecordingService _recorder = RecordingService();
  bool _recordingStarted = false;
  String _interimText = '';
  String? _transcriptError;
  bool _dgConnected = false;
  int _totalFillers = 0;

  // Cached store reference so we can add/remove a route listener safely.
  AppStore? _store;

  /// Initializes the interview state, default variables, simulated metrics, and timers.
  @override
  void initState() {
    super.initState();
    _revealedIdx = 0;
    _startSimulations();
    _resetQuestionTimers();
  }

  /// Manages routing/lifecycle dependencies and synchronizes live transcription when active.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = Provider.of<AppStore>(context, listen: false);
    if (!identical(store, _store)) {
      _store?.removeListener(_syncTranscriptionWithRoute);
      _store = store;
      _store!.addListener(_syncTranscriptionWithRoute);
    }
    _syncTranscriptionWithRoute();
  }

  /// Starts or stops live transcription and Tavus polling based on current route activity.
  void _syncTranscriptionWithRoute() {
    final store = _store;
    if (store == null) return;
    final shouldRun = store.currentRoute == '/interview' && store.interviewActive;
    if (shouldRun) {
      _startLiveTranscription();
      _startRecording();
      _startTavusPolling();
    } else {
      _stopLiveTranscription();
      _stopTavusPolling();
    }
  }

  /// Starts recording the candidate's microphone to a local .wav file.
  ///
  /// Native only. The recording is transcribed by Deepgram on the results page
  /// once the call ends. On web this is a no-op (the transcript is captured live
  /// via [_startLiveTranscription]).
  void _startRecording() async {
    if (kIsWeb || _recordingStarted) return;
    _recordingStarted = true;
    debugPrint('debug[rec]: _startRecording invoked');
    final ok = await _recorder.start();
    debugPrint('debug[rec]: _recorder.start() returned $ok');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not start audio recording — the transcript may be unavailable.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Cleans up active sessions, timers, controllers, and listeners.
  @override
  void dispose() {
    _store?.removeListener(_syncTranscriptionWithRoute);
    _jitterTimer?.cancel();
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();
    _avatarSpeakTimer?.cancel();
    _tavusPollTimer?.cancel();
    _dgSession?.stop();
    _recorder.dispose();
    _overrideController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  /// Configures and starts Deepgram Nova-3 live speech-to-text session on Web.
  ///
  /// Web only. On native the Tavus WebView owns the microphone, so a local
  /// recognizer would contend for it and fail. Native instead relies entirely
  /// on Tavus's server-side transcript: polled live by [_startTavusPolling]
  /// during the call and finalised in results_page once the call ends.
  void _startLiveTranscription() {
    if (_transcriptionStarted) return;
    if (!kIsWeb) return;

    final store = Provider.of<AppStore>(context, listen: false);
    _transcriptionStarted = true;

    if (store.deepgramKey.isEmpty) {
      _dgConnected = false;
      if (mounted) setState(() => _transcriptError = 'No Deepgram API key configured.');
      return;
    }

    deepgramService.setKey(store.deepgramKey);

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
  

  /// Stops the active Deepgram live transcription session and resets UI status.
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

  /// Helper to map entry timestamps to the corresponding question indexes.
  int _getQuestionIdxForTimestamp(int entryTimestamp, List<int> timestamps) {
    if (timestamps.isEmpty) return 0;
    for (int i = timestamps.length - 1; i >= 0; i--) {
      if (entryTimestamp >= timestamps[i]) {
        return i;
      }
    }
    return 0;
  }

  /// Initiates periodic polling of Tavus live transcripts.
  void _startTavusPolling() {
    _tavusPollTimer?.cancel();
    final store = Provider.of<AppStore>(context, listen: false);
    final conv = store.currentConversation;
    if (conv == null || conv.conversationId.isEmpty || store.tavusKey.isEmpty) {
      return;
    }

    tavusService.setKey(store.tavusKey);
    _pollTavusTranscript(store, conv.conversationId);

    _tavusPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!store.interviewActive || !mounted) {
        timer.cancel();
        return;
      }
      await _pollTavusTranscript(store, conv.conversationId);
    });
  }

  /// Polls the Tavus live transcript API and synchronizes the local transcript log.
  Future<void> _pollTavusTranscript(AppStore store, String conversationId) async {
    try {
      final entries = await tavusService.getLiveTranscript(conversationId);
      if (entries.isNotEmpty && mounted) {
        final List<TranscriptEntry> mappedEntries = [];
        for (final entry in entries) {
          final qIdx = _getQuestionIdxForTimestamp(entry.timestamp, store.questionTimestamps);
          mappedEntries.add(TranscriptEntry(
            role: entry.role,
            text: entry.text,
            timestamp: entry.timestamp,
            questionIdx: qIdx,
          ));
        }

        store.updateTranscriptEntries(mappedEntries);

        final candidateTurns = mappedEntries.where((e) => e.role == 'candidate').toList();
        final int fillers = candidateTurns.fold(0, (acc, e) => acc + deepgramService.countFillers(e.text));
        final int wpm = deepgramService.calcWpm(mappedEntries);

        _totalFillers = fillers;
        store.updateMetrics(w: wpm > 0 ? wpm : store.wpm, f: fillers);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Tavus live transcript poll error: $e');
    }
  }

  /// Stops periodic Tavus transcript polling.
  void _stopTavusPolling() {
    _tavusPollTimer?.cancel();
    _tavusPollTimer = null;
  }

  /// Simulates candidate emotional levels (confidence, anxiety, engagement) during interview.
  void _startSimulations() {
    final store = Provider.of<AppStore>(context, listen: false);

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

  /// Automatically scrolls the transcript view to show latest messages.
  void _scrollToBottom() {
    if (_transcriptScrollController.hasClients) {
      _transcriptScrollController.animateTo(
        _transcriptScrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Cancels and schedules the timeout advance and fallback reveal timers for the current question.
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

  /// Ends the interview session, triggers scorecard generation, and redirects to results.
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

    _dgSession?.stop();
    _dgSession = null;

    // Stop the local recording and hand its bytes to the store so the results
    // page can transcribe it via Deepgram's pre-recorded endpoint (native only).
    if (!kIsWeb) {
      final bytes = await _recorder.stopAndReadBytes();
      debugPrint('debug[rec]: endInterview got ${bytes?.length ?? 0} bytes');
      store.setRecordingBytes(bytes);
    }

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

  /// Navigates to the previous question in the interview list.
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

  /// Navigates to the next question, or triggers interview wrap-up if finished.
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

  /// Dispatches the custom conversational context override text to the live Tavus session.
  Future<void> _sendOverride() async {
    final store = Provider.of<AppStore>(context, listen: false);
    final overrideText = _overrideController.text.trim();
    if (overrideText.isEmpty || store.currentConversation == null) return;

    try {
      await tavusService.createConversation({
        'conversational_context': overrideText,
      });
      if (!mounted) return;

      _overrideController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Context override sent'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to override context: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      endDrawer: isMobile
          ? Drawer(
              width: 320,
              backgroundColor: theme.colorScheme.surface,
              child: SafeArea(
                child: InterviewSidebar(
                  store: store,
                  validQs: validQs,
                  revealedIdx: _revealedIdx,
                  onQuestionTap: (idx) {
                    store.setCurrentQuestionIdx(idx);
                    setState(() {
                      _revealedIdx = idx;
                    });
                    _resetQuestionTimers();
                  },
                  isMobile: isMobile,
                  onEndInterview: _endInterview,
                  overrideController: _overrideController,
                  onSendOverride: _sendOverride,
                  dgConnected: _dgConnected,
                  transcriptError: _transcriptError,
                  interimText: _interimText,
                  transcriptScrollController: _transcriptScrollController,
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: VideoPanel(
                    store: store,
                    validQs: validQs,
                    isFullscreen: _isFullscreen,
                    onToggleFullscreen: () {
                      setState(() {
                        _isFullscreen = !_isFullscreen;
                      });
                    },
                  ),
                ),
                QuestionBar(
                  store: store,
                  validQs: validQs,
                  avatarSpeaking: _avatarSpeaking,
                  autoAdvance: _autoAdvance,
                  revealedIdx: _revealedIdx,
                  onToggleAutoAdvance: () {
                    setState(() {
                      _autoAdvance = !_autoAdvance;
                      _resetQuestionTimers();
                    });
                  },
                  onShowNow: () {
                    setState(() {
                      _revealedIdx = store.currentQuestionIdx;
                    });
                  },
                  onPrevQuestion: _prevQuestion,
                  onNextQuestion: _nextQuestion,
                  onEndInterview: _endInterview,
                ),
              ],
            ),
          ),
          if (!isMobile && !_isFullscreen)
            InterviewSidebar(
              store: store,
              validQs: validQs,
              revealedIdx: _revealedIdx,
              onQuestionTap: (idx) {
                store.setCurrentQuestionIdx(idx);
                setState(() {
                  _revealedIdx = idx;
                });
                _resetQuestionTimers();
              },
              isMobile: isMobile,
              onEndInterview: _endInterview,
              overrideController: _overrideController,
              onSendOverride: _sendOverride,
              dgConnected: _dgConnected,
              transcriptError: _transcriptError,
              interimText: _interimText,
              transcriptScrollController: _transcriptScrollController,
            ),
        ],
      ),
    );
  }
}
