// lib/core/services/recording_service_stub.dart
//
// No-op recorder used on the web build. Web captures the transcript live via
// Deepgram streaming, so there is nothing to record/transcribe at the end.
class RecordingService {
  bool get isRecording => false;

  Future<bool> start() async => false;

  Future<List<int>?> stopAndReadBytes() async => null;

  Future<void> dispose() async {}
}
