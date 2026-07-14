// lib/core/services/recording_service_io.dart
//
// Native (Android/iOS) microphone recorder. Records the candidate's audio to a
// local .wav file for the duration of the interview, then returns the raw bytes
// so they can be POSTed to Deepgram's pre-recorded transcription endpoint.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/app_models.dart';

class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  // Bytes of the most recent recording, retained so persistLastRecording can
  // write the permanent copy after stopAndReadBytes has deleted the temp file.
  List<int>? _lastBytes;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Begins recording to a fresh .wav file in the temp directory.
  /// Returns false if the mic permission is denied or recording fails to start.
  Future<bool> start() async {
    if (_isRecording) return true;
    try {
      final hasPerm = await _recorder.hasPermission();
      if (kDebugMode) print('debug[rec]: hasPermission = $hasPerm');
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
      if (kDebugMode) print('debug[rec]: recording started -> $path');
      return true;
    } catch (e) {
      _isRecording = false;
      if (kDebugMode) print('debug[rec]: start FAILED: $e');
      return false;
    }
  }

  /// Stops recording and returns the recorded .wav file's bytes (or null if
  /// nothing was recorded). The temp file is deleted once its bytes are in
  /// memory so cached recordings don't accumulate; persistLastRecording writes
  /// its permanent copy from the retained bytes rather than from this file.
  Future<List<int>?> stopAndReadBytes() async {
    if (kDebugMode) print('debug[rec]: stopAndReadBytes (isRecording=$_isRecording)');
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      final finalPath = path ?? _path;
      if (kDebugMode) print('debug[rec]: stopped -> $finalPath');
      if (finalPath == null) return null;
      _path = finalPath;

      final file = File(finalPath);
      try {
        if (!await file.exists()) {
          if (kDebugMode) print('debug[rec]: file does NOT exist at $finalPath');
          return null;
        }
        final bytes = await file.readAsBytes();
        _lastBytes = bytes;
        if (kDebugMode) print('debug[rec]: read ${bytes.length} bytes from $finalPath');
        return bytes;
      } finally {
        // Bytes are captured above, so the temp .wav is no longer needed.
        try {
          if (await file.exists()) await file.delete();
        } catch (e) {
          if (kDebugMode) print('debug[rec]: temp cleanup failed: $e');
        }
      }
    } catch (e) {
      _isRecording = false;
      if (kDebugMode) print('debug[rec]: stop FAILED: $e');
      return null;
    }
  }

  /// Copies the most recent recording from the temp cache into permanent
  /// device storage so it can be played back / deleted later from Settings.
  Future<SavedRecording?> persistLastRecording(String name) async {
    final bytes = _lastBytes;
    if (_path == null || bytes == null) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final recDir = Directory('${docs.path}/recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);

      final filename = _path!.split('/').last;
      final destPath = '${recDir.path}/$filename';
      final dest = File(destPath);
      await dest.writeAsBytes(bytes, flush: true);
      final size = await dest.length();

      return SavedRecording(
        id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        path: destPath,
        savedAt: DateTime.now().toIso8601String(),
        sizeBytes: size,
      );
    } catch (e) {
      if (kDebugMode) print('debug[rec]: persist failed: $e');
      return null;
    }
  }

  /// Deletes a persisted recording file from device storage.
  Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
