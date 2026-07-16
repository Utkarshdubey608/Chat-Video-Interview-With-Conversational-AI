// lib/core/services/voice_preview_service.dart
//
// One-shot VOICE SAMPLE PREVIEW engine (Gemini Live native-audio), ON-DEVICE.
//
// This is the on-device analogue of the website's `POST /api/voices/:id/sample`
// (talbotiq-platform/server/routes/voices.ts): it opens a SHORT, OUTPUT-ONLY
// Gemini Live session for a single prebuilt voice, asks the model to read one
// short line once, accumulates the returned PCM24k audio for that single turn,
// wraps it as WAV, and plays it through the device speaker — then tears the
// whole thing down.
//
// It deliberately reuses the Live BidiGenerateContent protocol shapes and the
// PCM24k -> WAV playback approach proven in gemini_live_service.dart, but it is
// a much smaller surface:
//   * OUTPUT ONLY — it NEVER opens the microphone, never sends realtimeInput,
//     never enables VAD or input transcription. A stray mic open here would be
//     a privacy bug; there is intentionally no AudioRecorder in this file.
//   * ONE turn — it sends a single client text turn, buffers the model's audio
//     until turnComplete (or a hard timeout), plays it once, and stops.
//
// Where the website ran this server-side (so the key never left the backend),
// the app talks to Gemini Live directly with the key in the WS query string.
//
// !!! SECURITY / QA ---------------------------------------------------------
// Like gemini_live_service.dart, this connects DIRECTLY to Gemini with the API
// key on the device (in the WS URL `?key=`). That key is therefore extractable
// from the device / traffic. This is the INSECURE INTERIM used to unblock the
// on-device preview. The PRODUCTION posture is the website's: a server-side
// relay/endpoint that holds the key. Keep this direct path for dev only.
// TODO(security): route previews through a server relay/endpoint (key
//   server-only) before shipping to real users; keep this direct path for dev.
// ---------------------------------------------------------------------------
//
// !!! QA: this file CANNOT be runtime-tested in CI / this environment. It needs
// (1) a real Gemini API key with Live access and (2) a physical device speaker.
// Everything below implements the real BidiGenerateContent protocol and must be
// validated on-device against a live key. Search this file for `QA:` markers.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Coarse lifecycle of a single preview. Surfaced to the UI via
/// [VoicePreviewService.state] so it can show a spinner / stop toggle / error.
enum VoicePreviewStatus {
  /// Nothing playing; ready to start.
  idle,

  /// Connecting + waiting for the model's audio for the requested voice.
  loading,

  /// The sample is playing through the speaker.
  playing,

  /// The last attempt failed; [VoicePreviewState.error] describes it.
  error,
}

/// Immutable snapshot of what the preview engine is doing right now.
///
/// [voiceName] is the voice the CURRENT non-idle activity belongs to, so the UI
/// can scope its spinner / stop button to exactly the row the user tapped and
/// leave every other voice untouched. It is null while [status] is [idle].
@immutable
class VoicePreviewState {
  final VoicePreviewStatus status;

  /// The voice id the current loading/playing/error activity is about; null
  /// when idle.
  final String? voiceName;

  /// Human-facing error message when [status] is [error]; else null.
  final String? error;

  const VoicePreviewState._(this.status, this.voiceName, this.error);

  const VoicePreviewState.idle() : this._(VoicePreviewStatus.idle, null, null);

  const VoicePreviewState.loading(String voiceName)
      : this._(VoicePreviewStatus.loading, voiceName, null);

  const VoicePreviewState.playing(String voiceName)
      : this._(VoicePreviewStatus.playing, voiceName, null);

  const VoicePreviewState.error(String voiceName, String message)
      : this._(VoicePreviewStatus.error, voiceName, message);

  bool get isBusy =>
      status == VoicePreviewStatus.loading ||
      status == VoicePreviewStatus.playing;

  /// True when [voiceName] is the voice the given [id] activity is about.
  bool isFor(String id) => voiceName == id;

  @override
  bool operator ==(Object other) =>
      other is VoicePreviewState &&
      other.status == status &&
      other.voiceName == voiceName &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, voiceName, error);
}

/// Focused, one-shot Gemini Live voice-sample player.
///
/// Lifecycle: create once (e.g. per picker) -> [play] for each preview ->
/// [stop] to cancel -> [dispose] on unmount. A new [play] cancels any in-flight
/// preview first, so only one sample is ever connected/playing at a time.
///
/// Owns and tears down ALL resources it creates: the WebSocket + its
/// subscription, the [AudioPlayer] + its completion subscription, the watchdog
/// timer, and the [state] notifier. There is NO microphone anywhere in here.
class VoicePreviewService {
  VoicePreviewService({
    this.timeout = const Duration(seconds: 15),
    this.model = defaultModel,
  });

  /// Hard cap on a single preview reaching playback. If the model produces no
  /// playable audio within this window the attempt fails with [error] instead
  /// of hanging. Mirrors the website's server-side ~12s sample cap, with a
  /// little extra headroom for the on-device connect handshake.
  final Duration timeout;

  /// Live model to use for the sample turn. Defaults to the native-audio model
  /// that gemini_live_service.dart uses on-device (proven to emit PCM24k here).
  ///
  /// QA: the website's `/sample` used DEFAULT_LIVE_MODEL. If the deployed
  ///   catalog model differs, pass it in; the protocol below is model-agnostic.
  final String model;

  // ---- protocol constants (mirror gemini_live_service.dart) ---------------

  static const String _wsBase =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// Native-audio Live model (same default as GeminiLiveService.defaultModel).
  static const String defaultModel =
      'models/gemini-2.5-flash-native-audio-preview-09-2025';

  /// Default sample line, copied verbatim from the website's `/sample` route so
  /// the on-device preview says exactly what the web recruiter UI does.
  static const String defaultSampleText =
      "Hi, I'm your interviewer today. Whenever you're ready, we'll get started.";

  /// Sample audio comes back as PCM16 mono 24 kHz (same as the interview track).
  static const int _outputSampleRate = 24000;

  // ---- resources (all disposed) -------------------------------------------

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _playerCompleteSub;

  Timer? _watchdog;

  /// Observable engine state. The UI listens to this to drive per-voice
  /// loading spinners, the playing/stop toggle, and inline error + retry.
  final ValueNotifier<VoicePreviewState> state =
      ValueNotifier<VoicePreviewState>(const VoicePreviewState.idle());

  bool _disposed = false;

  // Monotonic session id. Every [play] bumps this; async callbacks from an
  // older session compare against it and no-op if they are stale. This is what
  // makes "tap voice A, then quickly tap voice B" safe — A's late frames or
  // timeout can never clobber B's state or audio.
  int _session = 0;

  // Per-turn PCM24k accumulator for the CURRENT session (see gemini_live's
  // _outBuffer). Buffer the one utterance, play it as a single WAV.
  final BytesBuilder _outBuffer = BytesBuilder(copy: false);

  // Setup handshake / kickoff bookkeeping for the current session.
  bool _kickedOff = false;
  String _voiceName = '';
  String _sampleLine = '';

  // =========================================================================
  // Public API
  // =========================================================================

  /// Plays a short spoken sample of [voiceName] once.
  ///
  /// Opens an output-only Gemini Live session, asks the model to read
  /// [sampleText] (or [defaultSampleText]) once in [voiceName], buffers the
  /// returned PCM24k, plays it as WAV, then tears the session down. Any
  /// in-flight preview is cancelled first.
  ///
  /// Never throws for transport/engine failures — those surface on [state] as
  /// [VoicePreviewStatus.error]. Throws only for the programmer error of an
  /// empty [apiKey] (the UI should gate the button on a non-empty key).
  Future<void> play({
    required String apiKey,
    required String voiceName,
    String? sampleText,
  }) async {
    if (_disposed) return;
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('A Gemini API key is required to preview voices.');
    }

    // Cancel whatever is running and start a fresh session.
    await _resetSession();
    final session = ++_session;

    _voiceName = voiceName;
    final line = (sampleText != null && sampleText.trim().isNotEmpty)
        ? sampleText.trim()
        : defaultSampleText;
    // Match the website's 200-char guard so a runaway custom line can't turn a
    // "sample" into a long read.
    _sampleLine = line.length > 200 ? line.substring(0, 200) : line;

    _set(VoicePreviewState.loading(voiceName));

    // Key travels in the query string because the BidiGenerateContent endpoint
    // requires `?key=` — see the security note at the top of this file.
    final uri = Uri.parse('$_wsBase?key=${Uri.encodeQueryComponent(apiKey)}');

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      // Bail if we were disposed or superseded while the socket was opening.
      if (_disposed || session != _session) {
        await _teardownSocket();
        return;
      }

      _socketSub = channel.stream.listen(
        (data) => _onSocketData(session, data),
        onError: (Object e, StackTrace _) => _onSocketError(session, e),
        onDone: () => _onSocketDone(session),
        cancelOnError: false,
      );

      // Watchdog: guarantee the attempt resolves (played or errored) so a
      // stalled sample never hangs the UI spinner.
      _watchdog = Timer(timeout, () => _onTimeout(session));

      _sendSetup(voiceName: voiceName);
    } catch (e) {
      _fail(session, 'Could not start the voice preview: $e');
    }
  }

  /// Stops any in-flight or playing preview and returns to [idle]. Safe to call
  /// at any time (including when already idle).
  Future<void> stop() async {
    await _resetSession();
    if (!_disposed) _set(const VoicePreviewState.idle());
  }

  /// Releases every resource. Idempotent. Call from the host widget's dispose.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _session++; // invalidate any pending async callbacks
    _cancelWatchdog();
    await _stopPlayback();
    await _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    try {
      await _player.dispose();
    } catch (_) {}
    await _teardownSocket();
    _outBuffer.clear();
    state.dispose();
  }

  // =========================================================================
  // Session teardown (between previews) — keeps the player instance alive
  // =========================================================================

  /// Cancels the current session's socket, playback, watchdog and buffers so a
  /// new preview starts clean. Bumps nothing itself (callers own [_session]).
  Future<void> _resetSession() async {
    _cancelWatchdog();
    await _stopPlayback();
    await _teardownSocket();
    _outBuffer.clear();
    _kickedOff = false;
  }

  // =========================================================================
  // WebSocket protocol (output-only subset of BidiGenerateContent)
  // =========================================================================

  /// First frame after the socket opens. Output-only: AUDIO response modality +
  /// the chosen prebuilt voice + a terse "read this once" system instruction.
  ///
  /// Deliberately OMITTED vs. the interview setup: input/output transcription
  /// and realtimeInputConfig/VAD. We are not listening, so none of that applies.
  void _sendSetup({required String voiceName}) {
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
            {
              // Mirrors the website's sample systemInstruction intent.
              'text':
                  'Say exactly this once, warmly and naturally, then stop. '
                      'Say nothing else, do not add commentary: "$_sampleLine"',
            },
          ],
        },
      },
    });
  }

  void _onSocketData(int session, dynamic data) {
    if (_disposed || session != _session) return;
    final Map<String, dynamic>? msg = _decodeFrame(data);
    if (msg == null) return;

    if (msg.containsKey('setupComplete')) {
      _onSetupComplete(session);
      return;
    }

    final sc = msg['serverContent'];
    if (sc is Map) {
      _onServerContent(session, sc.cast<String, dynamic>());
    }
  }

  void _onSetupComplete(int session) {
    if (session != _session || _kickedOff) return;
    _kickedOff = true;
    // Native audio only speaks when prompted — send the single sample turn now.
    _sendClientText(_sampleLine);
  }

  void _onServerContent(int session, Map<String, dynamic> sc) {
    // Accumulate the model's PCM24k audio parts for this single turn.
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

    // Turn boundary: the model finished the line -> play what we buffered.
    if (sc['turnComplete'] == true) {
      unawaited(_playBufferedAudio(session));
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
      if (kDebugMode) debugPrint('debug[preview]: send failed: $e');
    }
  }

  void _onSocketError(int session, Object error) {
    if (_disposed || session != _session) return;
    _fail(session, 'Voice preview connection error: $error');
  }

  void _onSocketDone(int session) {
    if (_disposed || session != _session) return;
    // If the socket closes before we ever got a full turn's audio, treat it as
    // a failed sample (the buffered-audio path already handles the success case
    // and will have superseded this session). If audio is currently playing we
    // ignore the close — the player finishes on its own.
    if (state.value.status == VoicePreviewStatus.loading) {
      _fail(session, 'Voice preview ended before any audio arrived.');
    }
  }

  Map<String, dynamic>? _decodeFrame(dynamic data) {
    try {
      final String text;
      if (data is String) {
        text = data;
      } else if (data is Uint8List) {
        text = utf8.decode(data);
      } else if (data is List<int>) {
        text = utf8.decode(data);
      } else {
        return null;
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      if (kDebugMode) debugPrint('debug[preview]: frame decode failed: $e');
      return null;
    }
  }

  // =========================================================================
  // Playback (PCM24k -> WAV -> BytesSource)
  // =========================================================================

  Future<void> _playBufferedAudio(int session) async {
    if (_disposed || session != _session) return;
    if (_outBuffer.isEmpty) {
      _fail(session, 'Voice preview produced no audio — try again.');
      return;
    }

    final pcm = _outBuffer.takeBytes(); // clears the builder
    final wav = _pcmToWav(pcm, sampleRate: _outputSampleRate);

    // We have the audio — the connect/generate race is over, so the watchdog's
    // job is done. Playback length governs itself via onPlayerComplete.
    _cancelWatchdog();
    // The socket has served its purpose; close it before playback so nothing
    // stays open longer than necessary.
    await _teardownSocket();
    if (_disposed || session != _session) return;

    _playerCompleteSub ??= _player.onPlayerComplete.listen((_) {
      // Only the session that is actually playing should return us to idle.
      if (_disposed) return;
      if (state.value.status == VoicePreviewStatus.playing) {
        _set(const VoicePreviewState.idle());
      }
    });

    _set(VoicePreviewState.playing(_voiceName));
    try {
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      _fail(session, 'Could not play the voice preview: $e');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Wraps raw little-endian PCM16 mono samples in a 44-byte WAV header so
  /// audioplayers' [BytesSource] can decode it. (Same shape as
  /// gemini_live_service._pcmToWav; duplicated minimally to avoid touching that
  /// file, as instructed.)
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
    writeUint32(fileLen - 8);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1); // PCM
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
  // Watchdog + failure + teardown
  // =========================================================================

  void _onTimeout(int session) {
    if (_disposed || session != _session) return;
    // Only a stalled load times out; if we're already playing the audio arrived.
    if (state.value.status == VoicePreviewStatus.loading) {
      _fail(session, 'Voice preview timed out — try again.');
    }
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Fails the CURRENT session: surfaces the error on [state] and tears the
  /// session's socket/playback/timer down. No-op for stale sessions.
  void _fail(int session, String message) {
    if (_disposed || session != _session) return;
    // Invalidate this session so its own follow-on callbacks (socket onDone,
    // etc.) don't recurse back through here.
    final failedVoice = _voiceName;
    _session++;
    _cancelWatchdog();
    unawaited(_stopPlayback());
    unawaited(_teardownSocket());
    _outBuffer.clear();
    _kickedOff = false;
    _set(VoicePreviewState.error(failedVoice, message));
  }

  Future<void> _teardownSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _set(VoicePreviewState next) {
    if (_disposed) return;
    state.value = next;
  }
}
