// lib/views/interview_page.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/core/services/recording_service.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/features/interviews/candidate/interview/widgets/video_panel.dart';
import 'package:talbotiq/features/interviews/candidate/interview/widgets/question_bar.dart';
import 'package:talbotiq/features/interviews/candidate/interview/widgets/interview_sidebar.dart';


/// The main interview view screen that orchestrates the video feed,
/// bottom control navigation bar, and sidebar analytics/transcript tab panels.
///
/// The candidate's microphone is recorded to a local .wav for the duration of
/// the call; on end the recording is transcribed by Deepgram on the results
/// page. There is no live transcription during the call.
class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key});

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isFullscreen = false;

  bool _autoAdvance = true;
  final bool _avatarSpeaking = false;
  int _revealedIdx = -1;
  final _overrideController = TextEditingController();

  // Guards against re-entrant _endInterview calls (e.g. the auto-advance timer
  // firing while the end dialog is open). A second run would call
  // stopAndReadBytes() again and overwrite the recording bytes with null.
  bool _ending = false;

  Timer? _fallbackRevealTimer;
  Timer? _autoAdvanceTimeoutTimer;

  // Local .wav recorder for the candidate's mic (native only). The recording is
  // transcribed by Deepgram on the results page once the call ends.
  final RecordingService _recorder = RecordingService();
  bool _recordingStarted = false;

  // Cached store reference so we can add/remove a route listener safely.
  AppStore? _store;

  /// Initializes the interview state, default variables, and question timers.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revealedIdx = 0;
    _resetQuestionTimers();
  }

  /// Integrity: flag when the candidate leaves the app mid-interview.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = _store;
    if (store == null) return;
    final active =
        store.currentRoute == '/interview' && store.interviewActive;
    if (!active) return;
    if (state == AppLifecycleState.paused) {
      store.incrementIntegrityLeftApp();
    } else if (state == AppLifecycleState.resumed &&
        store.integrityLeftAppCount > 0 &&
        mounted) {
      final n = store.integrityLeftAppCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please stay in the interview. Leaving the app was noted '
            '($n time${n == 1 ? '' : 's'}).',
          ),
        ),
      );
    }
  }

  /// Manages routing/lifecycle dependencies and starts recording when active.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = Provider.of<AppStore>(context, listen: false);
    if (!identical(store, _store)) {
      _store?.removeListener(_syncRecordingWithRoute);
      _store = store;
      _store!.addListener(_syncRecordingWithRoute);
    }
    _syncRecordingWithRoute();
  }

  /// Starts microphone recording when the interview becomes active.
  void _syncRecordingWithRoute() {
    final store = _store;
    if (store == null) return;
    final shouldRun = store.currentRoute == '/interview' && store.interviewActive;
    if (shouldRun) {
      _startRecording();
    }
  }

  /// Cleans up active timers, controllers, listeners, and the recorder.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store?.removeListener(_syncRecordingWithRoute);
    _fallbackRevealTimer?.cancel();
    _autoAdvanceTimeoutTimer?.cancel();
    _recorder.dispose();
    _overrideController.dispose();
    super.dispose();
  }

  /// Starts recording the candidate's microphone to a local .wav file.
  ///
  /// Native only. On web this is a no-op (the web build does not record).
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

  /// Ends the interview session, finalises the recording, and redirects to results.
  Future<void> _endInterview() async {
    // Re-entrancy guard: a second invocation (e.g. an auto-advance timer firing
    // while this is running) must not reach stopAndReadBytes() a second time
    // and overwrite the captured recording bytes with null.
    if (_ending) return;
    _ending = true;

    // Cancel the question timers up-front so they cannot re-enter this method
    // (via _nextQuestion) while the confirm dialog / finalisation is in flight.
    _autoAdvanceTimeoutTimer?.cancel();
    _fallbackRevealTimer?.cancel();

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

    if (confirmEnd != true) {
      // User backed out — allow ending again later and re-arm the timers we
      // cancelled above.
      _ending = false;
      if (mounted) _resetQuestionTimers();
      return;
    }
    if (!mounted) return;

    // NB: keep this out of setState — firing provider notifyListeners from
    // inside a setState callback is not allowed.
    store.setInterviewActive(false);

    // Stop the local recording and hand its bytes to the store so the results
    // page can transcribe it via Deepgram's pre-recorded endpoint (native only).
    if (!kIsWeb) {
      final bytes = await _recorder.stopAndReadBytes();
      debugPrint('debug[rec]: endInterview got ${bytes?.length ?? 0} bytes');
      store.setRecordingBytes(bytes);

      // If the user opted to keep recordings, persist this one to device
      // storage so it can be played back / deleted later from Settings.
      if (store.storeLocalRecordings && bytes != null && bytes.isNotEmpty) {
        final name = (store.currentConversation?.conversationName ?? 'Interview')
            .replaceAll('TalbotIQ — ', '');
        final saved = await _recorder.persistLastRecording(name);
        if (saved != null) store.addRecording(saved);
      }
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
    if (overrideText.isEmpty) return;

    // Send the override to the EXISTING live conversation. (Previously this
    // called createConversation, which span up a brand-new billed Tavus
    // session instead of updating the running one.)
    final conversationId = store.currentConversation?.conversationId;
    if (conversationId == null || conversationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No active conversation to override.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      await tavusService.sendInteraction(conversationId, overrideText);
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
                  // InterviewPage is only ever reached via the candidate video
                  // flow (CandidateVideoShell), so hide upcoming questions and
                  // disable jumping ahead.
                  candidateMode: true,
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
              // Candidate-only flow: hide upcoming questions, no jumping ahead.
              candidateMode: true,
            ),
        ],
      ),
    );
  }
}
