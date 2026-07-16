// lib/core/services/gemini_live_service.dart
//
// Real-time VOICE INTERVIEW engine (Gemini Live native-audio), ON-DEVICE.
//
// Unlike the WebView-based chat/video tracks, this track owns the microphone
// directly and speaks to the Gemini Live API over a raw WebSocket, streaming
// the candidate's mic audio up and playing the interviewer's audio back. The
// Live model runs the interview naturally (greeting -> "are you ready?" ->
// questions in order -> wrap-up) from the strict, caller-authored system
// instruction; we surface both sides as live captions via Live's built-in
// input/output transcription.
//
// This mirrors the WEBSITE reference (server/services/voice.ts +
// src/features/interview/useVoiceSession.ts) but collapses the server relay
// into the device: the browser build streamed mic PCM to OUR backend, which
// held the Gemini key and relayed to Live. Here the app talks to Gemini Live
// directly.
//
// !!! SECURITY / QA ---------------------------------------------------------
// This connects DIRECTLY to Gemini with the API key on the device (in the WS
// URL query string, as the Live endpoint requires `?key=`). That key is
// therefore shippable-with-the-app and extractable from the device / traffic.
// This is the INSECURE INTERIM used to unblock the on-device voice track. The
// PRODUCTION posture is the website's: a server-side WebSocket relay that holds
// the key and proxies frames, so the key never leaves the backend.
// TODO(security): move to a server relay (wss to our backend, key server-only)
//   before this ships to real candidates; keep this direct path for dev only.
// ---------------------------------------------------------------------------
//
// !!! QA: cannot be runtime-tested in this environment. It needs (1) a real
// Gemini API key with Live access and (2) a physical device microphone +
// speaker. Everything below implements the real BidiGenerateContent protocol;
// it must be validated on-device against a live key.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// High-level call phase surfaced to the UI. Mirrors the website's VoicePhase
/// (minus the browser-only "thinking" affordance, which we fold into greeting).
///
/// Terminal states: [ended] is a GENUINE graceful finish (user End, hard
/// max-duration cap, or idle watchdog) and is the ONLY state the host should
/// score. [interrupted] is an unexpected transport drop mid-interview
/// (connection lost) and must NOT be scored. [error] is an engine/transport
/// failure and must NOT be scored either.
enum GeminiLiveState {
  connecting,
  greeting,
  listening,
  speaking,
  ended,
  interrupted,
  error,
}

/// Who a caption line belongs to.
enum CaptionRole { interviewer, candidate }

/// Events emitted on [GeminiLiveService.events]. Sealed so the UI can switch
/// exhaustively.
sealed class GeminiLiveEvent {
  const GeminiLiveEvent();
}

/// The call phase changed.
class GeminiLiveStateChanged extends GeminiLiveEvent {
  final GeminiLiveState state;
  const GeminiLiveStateChanged(this.state);
}

/// A live caption line (streaming partial -> final flush) for one speaker.
/// While [isFinal] is false this replaces the speaker's most recent non-final
/// line in place; when true it commits that line.
class GeminiLiveCaption extends GeminiLiveEvent {
  final CaptionRole role;
  final String text;
  final bool isFinal;
  const GeminiLiveCaption(this.role, this.text, this.isFinal);
}

/// The candidate barged in over the interviewer (VAD interrupt). The UI should
/// treat any in-flight interviewer caption as discarded; playback is stopped
/// internally.
class GeminiLiveInterrupted extends GeminiLiveEvent {
  const GeminiLiveInterrupted();
}

/// A non-fatal-or-fatal error message for display. Usually followed by a
/// [GeminiLiveStateChanged] to [GeminiLiveState.error]/[ended].
class GeminiLiveErrorEvent extends GeminiLiveEvent {
  final String message;
  const GeminiLiveErrorEvent(this.message);
}

/// Direct-to-Gemini Live voice interview engine. One instance per interview.
///
/// Lifecycle: [connect] -> (listen to [events]) -> [mute]/[end] -> [dispose].
/// Owns and tears down ALL resources: the WebSocket, the mic stream + recorder,
/// the audio player, and its internal subscriptions.
class GeminiLiveService {
  /// [maxDuration] is a HARD wall-clock cap: when it elapses the interview is
  /// ended like a normal graceful finish (mirrors voice.ts's maxDurationMs,
  /// default ~18 min). [idleTimeout] is the listening-phase idle watchdog: if
  /// the candidate produces no speech for this long while it is their turn, the
  /// interview is finalized gracefully (mirrors voice.ts's idle watchdog).
  GeminiLiveService({
    this.maxDuration = const Duration(minutes: 18),
    this.idleTimeout = const Duration(seconds: 45),
  });

  /// Hard wall-clock cap on the whole interview (see [GeminiLiveService]).
  final Duration maxDuration;

  /// Listening-phase idle watchdog window (see [GeminiLiveService]).
  final Duration idleTimeout;

  // ---- protocol constants -------------------------------------------------

  static const String _wsBase =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// Native-audio Live model. Callers may override via [connect].
  static const String defaultModel =
      'models/gemini-2.5-flash-native-audio-preview-09-2025';

  /// A reasonable default prebuilt voice. Callers may override via [connect].
  static const String defaultVoiceName = 'Aoede';

  // Mic capture format: PCM16 mono 16 kHz (what Gemini Live expects on input).
  static const int _inputSampleRate = 16000;
  // Interviewer audio comes back as PCM16 mono 24 kHz.
  static const int _outputSampleRate = 24000;

  // ---- resources (all disposed) -------------------------------------------

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _playerCompleteSub;

  final StreamController<GeminiLiveEvent> _events =
      StreamController<GeminiLiveEvent>.broadcast();

  // Hard max-duration cap (armed on connect) and listening-phase idle watchdog
  // (armed while it is the candidate's turn). BOTH are cancelled in dispose /
  // end / any terminal path so no timer outlives the session.
  Timer? _maxDurationTimer;
  Timer? _idleTimer;

  /// Broadcast stream of call events. Subscribe BEFORE calling [connect] to
  /// avoid missing the initial [GeminiLiveState.connecting] event.
  Stream<GeminiLiveEvent> get events => _events.stream;

  // ---- state --------------------------------------------------------------

  bool _muted = false;
  bool _setupComplete = false; // Gemini acked setup; safe to stream audio
  bool _greeted = false; // first interviewer utterance has played (greeting)
  bool _disposed = false;
  bool _endedByUser = false; // graceful End tapped; suppress close-as-error
  bool _finished = false; // a terminal event has been emitted

  GeminiLiveState _state = GeminiLiveState.connecting;
  GeminiLiveState get state => _state;

  bool get isMuted => _muted;

  // Per-turn transcription buffers (accumulate across streamed fragments, flush
  // as `final` on turnComplete) — mirrors voice.ts pendingInterviewer/Candidate.
  final StringBuffer _pendingInterviewer = StringBuffer();
  final StringBuffer _pendingCandidate = StringBuffer();

  // Per-turn PCM24k output accumulator. We buffer one interviewer utterance and
  // play it as a single WAV on turnComplete.
  // TODO(audio-latency): buffering the whole turn adds ~utterance-length latency
  //   before the candidate hears anything. For true low-latency playback, feed
  //   the PCM chunks into a gapless streaming sink (e.g. a native ring-buffer
  //   player, or just_audio with a custom StreamAudioSource) and schedule them
  //   as they arrive instead of accumulating. Kept simple here for correctness.
  final BytesBuilder _outBuffer = BytesBuilder(copy: false);

  // =========================================================================
  // Public API
  // =========================================================================

  /// Opens the Live session: connects the WebSocket, sends the setup message,
  /// starts the mic stream, and kicks off the interviewer's greeting turn.
  ///
  /// [systemInstruction] is the caller-authored interviewer plan + guardrails
  /// (persona, ordered questions, flow, strict rules) — see voice.ts
  /// buildSystemInstruction for the reference shape.
  ///
  /// Throws only for programmer errors (e.g. empty key); transport/engine
  /// failures are surfaced on [events] as [GeminiLiveErrorEvent] + error state.
  Future<void> connect({
    required String apiKey,
    required String systemInstruction,
    String model = defaultModel,
    String voiceName = defaultVoiceName,
    List<String> languageHints = const ['en-IN', 'en-US', 'en-GB', 'en-AU'],
    String kickoffPrompt =
        'Begin the interview now: greet me and ask if I am ready to begin.',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('Gemini API key is required for the voice interview.');
    }
    if (_channel != null) return; // already connected/connecting

    _emitState(GeminiLiveState.connecting);

    // Key travels in the query string because the BidiGenerateContent endpoint
    // requires `?key=` (there is no header handshake for the WS upgrade here).
    // See the security note at the top of this file.
    final uri = Uri.parse('$_wsBase?key=${Uri.encodeQueryComponent(apiKey)}');

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      // `ready` completes on a successful upgrade; it throws on failure so we
      // don't start streaming into a dead socket.
      await channel.ready;
      if (_disposed) {
        await _teardownSocket();
        return;
      }

      _socketSub = channel.stream.listen(
        _onSocketData,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: false,
      );

      // Hard wall-clock cap: once connected, guarantee the interview ends
      // gracefully after [maxDuration] no matter what the model does.
      _armMaxDurationTimer();

      // languageHints is accepted for API stability / future use but is not
      // injected into the raw setup — see the QA note in _sendSetup.
      _sendSetup(
        model: model,
        voiceName: voiceName,
        systemInstruction: systemInstruction,
      );
      // Remember the kickoff so we can send it exactly once, after setupComplete.
      _kickoffPrompt = kickoffPrompt;
    } catch (e) {
      _fail('Could not connect to the voice service: $e');
    }
  }

  String _kickoffPrompt = '';

  /// Forwards one PCM16 mono 16 kHz mic chunk to Gemini as realtimeInput.
  /// No-op while muted, before setup completes, or after teardown. Normally
  /// driven internally by the mic stream, but exposed for testing / custom
  /// capture pipelines.
  void sendAudioChunk(Uint8List pcm16) {
    if (_disposed || _muted || !_setupComplete) return;
    final channel = _channel;
    if (channel == null) return;
    final b64 = base64Encode(pcm16);
    _sendJson({
      'realtimeInput': {
        'audio': {
          'data': b64,
          'mimeType': 'audio/pcm;rate=$_inputSampleRate',
        },
      },
    });
  }

  /// Mutes/unmutes the microphone. While muted, captured chunks are dropped so
  /// the interviewer hears silence (the mic stream itself stays open so unmute
  /// is instant).
  void mute(bool muted) {
    _muted = muted;
  }

  /// Candidate-initiated graceful end: signal end-of-audio, then close. Emits
  /// [GeminiLiveState.ended]. Safe to call multiple times.
  Future<void> end() => _finishGracefully();

  /// Shared graceful-finish path for EVERY genuine completion: the candidate's
  /// End button, the hard max-duration cap, and the idle watchdog. Flushes the
  /// mic/playback, emits the terminal [GeminiLiveState.ended] (which the host
  /// scores), and closes the socket. Setting [_endedByUser] here also ensures
  /// the subsequent socket onDone is treated as a graceful close, never an
  /// interruption. Idempotent.
  Future<void> _finishGracefully() async {
    if (_endedByUser || _finished) return;
    _endedByUser = true;
    _cancelTimers();
    // Tell Live the audio input is finished (best effort).
    if (_setupComplete) {
      _sendJson({
        'realtimeInput': {'audioStreamEnd': true},
      });
    }
    await _stopMic();
    await _stopPlayback();
    _emitState(GeminiLiveState.ended, terminal: true);
    await _teardownSocket();
  }

  /// Releases every resource. Idempotent. Does NOT emit `ended` (that is the
  /// job of [end] or a server-side finish) — this is the unmount teardown.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelTimers();
    await _stopMic();
    try {
      await _recorder.dispose();
    } catch (_) {}
    await _stopPlayback();
    await _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    try {
      await _player.dispose();
    } catch (_) {}
    await _teardownSocket();
    if (!_events.isClosed) await _events.close();
  }

  // =========================================================================
  // WebSocket protocol
  // =========================================================================

  /// The setup message MUST be the first frame after the socket opens.
  /// Configures the model, AUDIO response modality + voice, the interviewer
  /// system instruction, input/output transcription (for captions + the final
  /// scored transcript), and server-side VAD (so the candidate can barge in and
  /// turns auto-complete on silence).
  void _sendSetup({
    required String model,
    required String voiceName,
    required String systemInstruction,
  }) {
    _sendJson({
      'setup': {
        'model': model.startsWith('models/') ? model : 'models/$model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceName},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
        // Enabling both transcriptions gives us the live captions AND the raw
        // material to rebuild a canonical transcript for scoring later. In the
        // RAW BidiGenerateContent protocol, AudioTranscriptionConfig is an
        // empty message — an empty object turns transcription ON.
        //
        // QA/TODO(asr-language): the website relay biased ASR to English
        //   variants ($languageHints) via the @google/genai SDK
        //   (inputAudioTranscription.languageHints.languageCodes). That field
        //   is an SDK convenience and is NOT part of the raw wire proto, so we
        //   do NOT send it here (an unknown field can make Live reject setup).
        //   English-locking is instead enforced through the caller's
        //   systemInstruction. Verify accented-English ASR on-device; if a raw
        //   language-hint field becomes available, wire it in here.
        'inputAudioTranscription': <String, dynamic>{},
        'outputAudioTranscription': <String, dynamic>{},
        // Server-side automatic VAD: detect start/end of the candidate's speech
        // and allow barge-in over the interviewer. Values mirror voice.ts.
        'realtimeInputConfig': {
          'automaticActivityDetection': {
            'startOfSpeechSensitivity': 'START_SENSITIVITY_HIGH',
            'endOfSpeechSensitivity': 'END_SENSITIVITY_HIGH',
            'prefixPaddingMs': 20,
            'silenceDurationMs': 500,
          },
        },
      },
    });
  }

  void _onSocketData(dynamic data) {
    if (_disposed) return;
    // Live frames arrive as UTF-8 JSON, delivered as either a String or binary
    // (List<int>) frame depending on the platform WS implementation.
    final Map<String, dynamic>? msg = _decodeFrame(data);
    if (msg == null) return;

    if (msg.containsKey('setupComplete')) {
      _onSetupComplete();
      return;
    }

    final sc = msg['serverContent'];
    if (sc is Map) {
      _onServerContent(sc.cast<String, dynamic>());
    }

    // `goAway` warns the connection is about to be closed by the server; the
    // subsequent onDone handles the actual teardown. Nothing to do here beyond
    // logging in debug.
    if (kDebugMode && msg.containsKey('goAway')) {
      debugPrint('debug[live]: goAway received — server closing soon');
    }
  }

  Map<String, dynamic>? _decodeFrame(dynamic data) {
    try {
      final String text;
      if (data is String) {
        text = data;
      } else if (data is List<int>) {
        text = utf8.decode(data);
      } else if (data is Uint8List) {
        text = utf8.decode(data);
      } else {
        return null;
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      if (kDebugMode) debugPrint('debug[live]: frame decode failed: $e');
      return null;
    }
  }

  Future<void> _onSetupComplete() async {
    if (_setupComplete) return;
    _setupComplete = true;
    _emitState(GeminiLiveState.greeting);
    // Native audio only speaks when prompted — send the opening turn now.
    if (_kickoffPrompt.isNotEmpty) {
      _sendClientText(_kickoffPrompt);
    }
    // Start capturing the mic only once Gemini is ready to receive audio.
    await _startMic();
  }

  void _onServerContent(Map<String, dynamic> sc) {
    // 1) Interviewer audio out (PCM24k) — accumulate for this turn.
    final modelTurn = sc['modelTurn'];
    if (modelTurn is Map) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is Map) {
            final inline = part['inlineData'];
            if (inline is Map && inline['data'] is String) {
              _outBuffer.add(base64Decode(inline['data'] as String));
            }
          }
        }
      }
    }

    // 2) Streaming transcripts -> partial captions.
    final outT = sc['outputTranscription'];
    if (outT is Map && outT['text'] is String) {
      _pendingInterviewer.write(outT['text']);
      _emit(GeminiLiveCaption(
        CaptionRole.interviewer,
        _pendingInterviewer.toString(),
        false,
      ));
    }
    final inT = sc['inputTranscription'];
    if (inT is Map && inT['text'] is String) {
      _pendingCandidate.write(inT['text']);
      // The candidate is speaking -> it's their turn.
      _emitState(GeminiLiveState.listening);
      // Candidate produced speech -> the call is NOT idle. Reset the watchdog
      // so a long/thoughtful answer is never cut off mid-sentence. (We key the
      // watchdog off VAD-detected speech captions, not raw mic chunks, since the
      // mic streams continuously and would otherwise never let it expire.)
      _armIdleWatchdog();
      _emit(GeminiLiveCaption(
        CaptionRole.candidate,
        _pendingCandidate.toString(),
        false,
      ));
    }

    // 3) Barge-in: candidate interrupted the interviewer. Drop buffered/playing
    //    interviewer audio and its partial caption.
    if (sc['interrupted'] == true) {
      _pendingInterviewer.clear();
      _outBuffer.clear();
      // Stop current playback (fire-and-forget; ordering with the state event
      // below is not important — the UI just needs to know it was interrupted).
      unawaited(_stopPlayback());
      _emit(const GeminiLiveInterrupted());
      _emitState(GeminiLiveState.listening);
    }

    // 4) Turn boundary: finalize captions and play the interviewer's audio.
    if (sc['turnComplete'] == true) {
      final cand = _pendingCandidate.toString().trim();
      if (cand.isNotEmpty) {
        _pendingCandidate.clear();
        _emit(GeminiLiveCaption(CaptionRole.candidate, cand, true));
      }
      final interviewer = _pendingInterviewer.toString().trim();
      if (interviewer.isNotEmpty) {
        _pendingInterviewer.clear();
        _emit(GeminiLiveCaption(CaptionRole.interviewer, interviewer, true));
      }
      // Flush the accumulated interviewer audio for this turn.
      unawaited(_flushOutputAudio());
    }
  }

  void _sendClientText(String text) {
    _sendJson({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  void _sendJson(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || _disposed) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) debugPrint('debug[live]: send failed: $e');
    }
  }

  void _onSocketError(Object error, StackTrace _) {
    if (_disposed || _finished) return;
    _fail('Voice connection error: $error');
  }

  void _onSocketDone() {
    // A graceful terminal (user End, max-duration cap, or idle watchdog) has
    // already set `_finished`/`_endedByUser` and emitted `ended`; ignore the
    // follow-on close. Any OTHER close is an unexpected mid-interview drop.
    if (_disposed || _finished) return;
    if (_endedByUser) return;
    // Not user-initiated and not after a genuine finish -> the connection was
    // lost mid-interview. Emit a DISTINCT terminal state so the UI can show an
    // "interrupted — connection lost" screen and the host does NOT score a
    // partial/aborted interview (only [GeminiLiveState.ended] is scored).
    //
    // TODO(resilience): port voice.ts's reconnect grace window (keep the
    //   interview alive across a transient drop and resume) — out of scope for
    //   this on-device MVP, which surfaces any drop as interrupted.
    _interrupt('Interview interrupted — connection lost.');
  }

  // =========================================================================
  // Microphone (PCM16 @ 16 kHz) -> realtimeInput
  // =========================================================================

  Future<void> _startMic() async {
    if (_disposed || _micSub != null) return;
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        _fail('Microphone permission is required for the voice interview.');
        return;
      }
      // Raw PCM16 mono 16 kHz — exactly what Gemini Live expects on input.
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _inputSampleRate,
          numChannels: 1,
          // Echo cancellation helps when playing the interviewer through a
          // loudspeaker so it isn't re-captured as candidate speech.
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      if (_disposed) {
        await _recorder.stop();
        return;
      }
      _micSub = stream.listen(
        sendAudioChunk,
        onError: (Object e, StackTrace _) {
          if (kDebugMode) debugPrint('debug[live]: mic stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      _fail('Could not start the microphone: $e');
    }
  }

  Future<void> _stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  // =========================================================================
  // Interviewer audio playback (PCM24k -> WAV -> BytesSource)
  // =========================================================================

  Future<void> _flushOutputAudio() async {
    if (_disposed) return;
    if (_outBuffer.isEmpty) return;
    final pcm = _outBuffer.takeBytes(); // clears the builder
    final wav = _pcmToWav(pcm, sampleRate: _outputSampleRate);

    // The first interviewer utterance is the greeting; subsequent ones are
    // regular speaking turns.
    _emitState(_greeted ? GeminiLiveState.speaking : GeminiLiveState.greeting);
    _greeted = true;

    _playerCompleteSub ??= _player.onPlayerComplete.listen((_) {
      // When the interviewer finishes speaking it's the candidate's turn.
      if (!_disposed && !_finished) _emitState(GeminiLiveState.listening);
    });

    try {
      // Replace any in-flight playback with this turn's audio.
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      if (kDebugMode) debugPrint('debug[live]: playback failed: $e');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Wraps raw little-endian PCM16 mono samples in a 44-byte WAV header so
  /// audioplayers' [BytesSource] can decode it.
  Uint8List _pcmToWav(Uint8List pcm, {required int sampleRate}) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int blockAlign = channels * (bitsPerSample ~/ 8);
    final int dataLen = pcm.length;
    final int fileLen = 44 + dataLen;

    final header = BytesBuilder();
    void writeString(String s) => header.add(ascii.encode(s));
    void writeUint32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      header.add(b.buffer.asUint8List());
    }

    void writeUint16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      header.add(b.buffer.asUint8List());
    }

    writeString('RIFF');
    writeUint32(fileLen - 8); // chunk size
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // subchunk1 size (PCM)
    writeUint16(1); // audio format = PCM
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataLen);

    final out = BytesBuilder(copy: false);
    out.add(header.takeBytes());
    out.add(pcm);
    return out.takeBytes();
  }

  // =========================================================================
  // Event emission helpers
  // =========================================================================

  void _emitState(GeminiLiveState state, {bool terminal = false}) {
    if (_finished) return;
    if (state == _state && !terminal) return;
    _state = state;
    if (terminal) _finished = true;
    // The idle watchdog only governs the candidate's turn: arm it when we enter
    // listening, cancel it in every other (incl. terminal) phase. It is also
    // re-armed on each candidate speech caption (see _onServerContent).
    if (!terminal && state == GeminiLiveState.listening) {
      _armIdleWatchdog();
    } else {
      _cancelIdleWatchdog();
    }
    _emit(GeminiLiveStateChanged(state));
  }

  // =========================================================================
  // Watchdog timers: hard max-duration cap + listening-phase idle watchdog
  // =========================================================================

  void _armMaxDurationTimer() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(maxDuration, () {
      if (_disposed || _finished) return;
      // Hard cap reached -> end like any normal graceful finish.
      unawaited(_finishGracefully());
    });
  }

  void _armIdleWatchdog() {
    if (_disposed || _finished) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (_disposed || _finished) return;
      // The candidate went silent for the whole window during their turn ->
      // finalize gracefully (a completed-but-quiet interview, not an error).
      unawaited(_finishGracefully());
    });
  }

  void _cancelIdleWatchdog() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Cancels ALL watchdog timers. Called from dispose and every terminal path
  /// so no timer outlives the session (and the mic is never left open).
  void _cancelTimers() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _cancelIdleWatchdog();
  }

  /// Terminal signal for an unexpected mid-interview drop (connection lost).
  /// Distinct from [_finishGracefully]: emits [GeminiLiveState.interrupted] so
  /// the host does NOT score the aborted interview. Best-effort local cleanup.
  void _interrupt(String message) {
    if (_finished) return;
    _cancelTimers();
    _emit(GeminiLiveErrorEvent(message));
    _emitState(GeminiLiveState.interrupted, terminal: true);
    unawaited(_stopMic());
    unawaited(_stopPlayback());
    unawaited(_teardownSocket());
  }

  void _emit(GeminiLiveEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _fail(String message) {
    if (_finished) return;
    _cancelTimers();
    _emit(GeminiLiveErrorEvent(message));
    _emitState(GeminiLiveState.error, terminal: true);
    // Best-effort local cleanup so a failed session doesn't leave the mic open.
    unawaited(_stopMic());
    unawaited(_stopPlayback());
    unawaited(_teardownSocket());
  }

  Future<void> _teardownSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
