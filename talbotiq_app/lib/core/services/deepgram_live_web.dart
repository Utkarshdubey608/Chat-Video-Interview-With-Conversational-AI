// lib/core/services/deepgram_live_web.dart
//
// Web implementation of live transcription. Opens the candidate's microphone,
// streams WebM/Opus chunks to Deepgram Nova-3 over a WebSocket, and reports
// finalized + interim transcript text back through callbacks.
//
// This mirrors the working React `useAudioAnalysis` Deepgram path:
//  - Auth uses the `['token', key]` WebSocket subprotocol (browsers can't set
//    an Authorization header, and ?token= query params get stripped).
//  - The FIRST MediaRecorder chunk carries the WebM/Opus header; chunks emitted
//    before the socket opens are buffered and flushed in order so the header is
//    never lost (without it Deepgram can't decode the stream).
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'deepgram_service.dart';

void _log(String msg) {
  // Visible in the browser devtools console.
  print('[Deepgram] $msg');
}

class DeepgramLiveSession {
  final void Function(String finalText) onFinal;
  final void Function(String interimText) onInterim;
  final void Function(bool connected) onConnected;
  final void Function(String message)? onError;

  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  html.WebSocket? _ws;
  final List<html.Blob> _queue = [];
  bool _open = false;
  bool _cancelled = false;
  bool _errorReported = false;
  final List<StreamSubscription> _subs = [];

  DeepgramLiveSession({
    required this.onFinal,
    required this.onInterim,
    required this.onConnected,
    this.onError,
  });

  void _reportError(String message) {
    if (_errorReported || _cancelled) return;
    _errorReported = true;
    _log('ERROR: $message');
    onError?.call(message);
  }

  Future<void> start() async {
    final key = deepgramService.getTrimmedKey();
    if (key.isEmpty) {
      _log('No Deepgram key set — transcription disabled.');
      return;
    }

    // 1) Microphone — disable processing so Deepgram sees raw speech.
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        _reportError('This browser does not expose mediaDevices (need HTTPS).');
        onConnected(false);
        return;
      }
      _log('Requesting microphone…');
      _stream = await mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': false,
          'noiseSuppression': false,
          'autoGainControl': false,
        },
      });
      _log('Microphone granted.');
    } catch (e) {
      _reportError('Microphone unavailable: $e');
      onConnected(false);
      return;
    }
    if (_cancelled) {
      _cleanup();
      return;
    }

    // 2) MediaRecorder FIRST so we buffer audio (incl. the header chunk) while
    //    the socket is still connecting. Build it before opening the socket.
    try {
      const preferred = 'audio/webm;codecs=opus';
      final supported = html.MediaRecorder.isTypeSupported(preferred);
      _recorder = html.MediaRecorder(
        _stream!,
        {'mimeType': supported ? preferred : 'audio/webm'},
      );
      _log('MediaRecorder created (mimeType=${supported ? preferred : 'audio/webm'}).');

      _recorder!.addEventListener('dataavailable', (event) {
        final blob = js_util.getProperty(event, 'data');
        if (blob is! html.Blob || blob.size == 0) return;
        final ws = _ws;
        if (_open && ws != null && ws.readyState == html.WebSocket.OPEN) {
          ws.sendBlob(blob);
        } else {
          // Socket still connecting — buffer (preserves the header chunk).
          _queue.add(blob);
        }
      });
    } catch (e) {
      _reportError('Audio recorder failed: $e');
      onConnected(false);
      _cleanup();
      return;
    }

    // 3) Deepgram WebSocket (auth via subprotocol token).
    try {
      final url = deepgramService.buildWsUrl();
      _log('Opening WebSocket: $url');
      _ws = html.WebSocket(url, ['token', key]);
      _ws!.binaryType = 'arraybuffer';
    } catch (e) {
      _reportError('Could not open Deepgram connection: $e');
      onConnected(false);
      _cleanup();
      return;
    }

    _subs.add(_ws!.onOpen.listen((_) {
      if (_cancelled) {
        _ws?.close();
        return;
      }
      _open = true;
      onConnected(true);
      _log('WebSocket OPEN — flushing ${_queue.length} buffered chunk(s).');
      // Flush buffered chunks IN ORDER — the first carries the WebM header.
      for (final b in _queue) {
        if (_ws?.readyState == html.WebSocket.OPEN) _ws!.sendBlob(b);
      }
      _queue.clear();
    }));

    _subs.add(_ws!.onMessage.listen((event) {
      final data = event.data;
      if (data is! String) return;
      try {
        final msg = jsonDecode(data);
        final type = msg['type'];
        if (type == 'Results') {
          final alts = msg['channel']?['alternatives'];
          final text = (alts is List && alts.isNotEmpty
                  ? (alts[0]['transcript'] ?? '')
                  : '')
              .toString()
              .trim();
          if (text.isEmpty) return;
          // Commit on ANY finalized segment (is_final), not only clean speech
          // endpoints (speech_final) — with noise suppression off, speech_final
          // rarely fires. Interim results just drive the "typing" indicator.
          if (msg['is_final'] == true) {
            onFinal(text);
          } else {
            onInterim(text);
          }
        } else if (type == 'UtteranceEnd') {
          onInterim('');
        }
      } catch (_) {
        // ignore malformed frames
      }
    }));

    _subs.add(_ws!.onError.listen((_) {
      onConnected(false);
      _log('WebSocket error event.');
    }));

    _subs.add(_ws!.onClose.listen((html.CloseEvent event) {
      onConnected(false);
      final code = event.code;
      final reason = event.reason;
      _log('WebSocket CLOSED code=$code reason=$reason');
      if (!_cancelled && !_open) {
        // Never opened → handshake/auth failure.
        if (code == 1008 || code == 4001 || code == 4008) {
          _reportError('Deepgram rejected the API key (code $code). Check the key in Settings.');
        } else if (code == 1006) {
          _reportError(
              'Deepgram connection failed (1006) — usually an invalid key or a key without streaming access.');
        } else {
          _reportError('Deepgram closed before connecting (code $code${reason != null && reason.isNotEmpty ? ': $reason' : ''}).');
        }
      }
    }));

    // 4) Start streaming — 250ms chunks for low-latency transcription.
    try {
      _recorder!.start(250);
      _log('Recording started (250ms chunks).');
    } catch (e) {
      _reportError('Failed to start recording: $e');
      onConnected(false);
      _cleanup();
    }
  }

  void stop() {
    _cancelled = true;
    onConnected(false);
    _cleanup();
  }

  void _cleanup() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _queue.clear();
    try {
      _recorder?.stop();
    } catch (_) {}
    _recorder = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    try {
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _stream = null;
    _open = false;
  }
}
