// lib/core/services/recording_service_io.dart
//
// Native (Android/iOS) microphone recorder. Records the candidate's audio to a
// local .wav file for the duration of the interview, then returns the raw bytes
// so they can be POSTed to Deepgram's pre-recorded transcription endpoint.
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Begins recording to a fresh .wav file in the temp directory.
  /// Returns false if the mic permission is denied or recording fails to start.
  Future<bool> start() async {
    if (_isRecording) return true;
    try {
      final hasPerm = await _recorder.hasPermission();
      print('debug[rec]: hasPermission = $hasPerm');
      if (!hasPerm) return false;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/interview_${DateTime.now().millisecondsSinceEpoch}.wav';

      // 16 kHz mono PCM wav — small files, ideal for speech transcription.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      _path = path;
      _isRecording = true;
      print('debug[rec]: recording started -> $path');
      return true;
    } catch (e) {
      _isRecording = false;
      print('debug[rec]: start FAILED: $e');
      return false;
    }
  }

  /// Stops recording and returns the recorded .wav file's bytes (or null if
  /// nothing was recorded).
  Future<List<int>?> stopAndReadBytes() async {
    print('debug[rec]: stopAndReadBytes (isRecording=$_isRecording)');
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      final finalPath = path ?? _path;
      print('debug[rec]: stopped -> $finalPath');
      if (finalPath == null) return null;

      final file = File(finalPath);
      if (!await file.exists()) {
        print('debug[rec]: file does NOT exist at $finalPath');
        return null;
      }
      final bytes = await file.readAsBytes();
      print('debug[rec]: read ${bytes.length} bytes from $finalPath');
      return bytes;
    } catch (e) {
      _isRecording = false;
      print('debug[rec]: stop FAILED: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
