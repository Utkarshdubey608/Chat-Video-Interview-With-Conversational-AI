// lib/core/services/deepgram_live_stub.dart
//
// Native fallback for non-web targets. It uses the platform speech recognizer
// so mobile interview results can be generated from the same sessionTranscript
// store used by the web Deepgram implementation.
import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class DeepgramLiveSession {
  final void Function(String finalText) onFinal;
  final void Function(String interimText) onInterim;
  final void Function(bool connected) onConnected;
  final void Function(String message)? onError;

  final SpeechToText _speech = SpeechToText();
  bool _active = false;
  bool _initialized = false;
  bool _restartQueued = false;
  String _lastCommittedText = '';
  Timer? _restartTimer;

  DeepgramLiveSession({
    required this.onFinal,
    required this.onInterim,
    required this.onConnected,
    this.onError,
  });

  Future<void> start() async {
    _active = true;

    final hasPermission = await _requestSpeechPermissions();
    if (!_active) return;
    if (!hasPermission) {
      onConnected(false);
      onError?.call(
        'Microphone/speech recognition permission was not granted.',
      );
      return;
    }

    if (!_initialized) {
      try {
        _initialized = await _speech
            .initialize(
              onStatus: _handleStatus,
              onError: _handleError,
              debugLogging: true,
            )
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        _initialized = false;
        onConnected(false);
        onError?.call(
          'Native speech recognition did not start. The device may not expose a speech recognizer, or the microphone is busy.',
        );
        return;
      } catch (e) {
        _initialized = false;
        onConnected(false);
        onError?.call('Native speech recognition initialization failed: $e');
        return;
      }
    }

    if (!_initialized) {
      onConnected(false);
      onError?.call('Native speech recognition is unavailable on this device.');
      return;
    }

    await _startListening();
  }

  void stop() {
    _active = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    onInterim('');
    onConnected(false);
    _speech.stop();
  }

  Future<void> _startListening() async {
    if (!_active || _speech.isListening) return;

    try {
      await _speech
          .listen(
            onResult: _handleResult,
            listenOptions: SpeechListenOptions(
              listenFor: const Duration(minutes: 30),
              pauseFor: const Duration(seconds: 4),
              partialResults: true,
              cancelOnError: false,
              listenMode: ListenMode.dictation,
            ),
          )
          .timeout(const Duration(seconds: 6));
      onConnected(true);
    } on TimeoutException {
      onConnected(false);
      onError?.call(
        'Native speech recognition timed out while starting. The microphone may already be in use by the video call.',
      );
    } catch (e) {
      onConnected(false);
      onError?.call('Native speech recognition failed to start: $e');
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    if (result.finalResult) {
      onInterim('');
      if (text != _lastCommittedText) {
        _lastCommittedText = text;
        onFinal(text);
      }
    } else {
      onInterim(text);
    }
  }

  void _handleStatus(String status) {
    final listening = status == 'listening';
    onConnected(listening);

    if (!_active || listening) return;
    if (status == 'notListening' || status == 'done') {
      _queueRestart();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    onConnected(false);
    if (!_active) return;

    if (error.permanent) {
      onError?.call(error.errorMsg);
      return;
    }

    _queueRestart();
  }

  void _queueRestart() {
    if (_restartQueued) return;
    _restartQueued = true;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 650), () {
      _restartQueued = false;
      _startListening();
    });
  }

  Future<bool> _requestSpeechPermissions() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    if (Platform.isIOS || Platform.isMacOS) {
      final speech = await Permission.speech.request();
      return speech.isGranted;
    }

    return true;
  }
}
