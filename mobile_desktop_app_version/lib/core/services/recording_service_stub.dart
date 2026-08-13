// lib/core/services/recording_service_stub.dart
//
// No-op recorder used on the web build. Local .wav recording is a native-only
// feature, so every method is an inert default here.
import 'package:talbotiq/shared/models/app_models.dart';

class RecordingService {
  bool get isRecording => false;

  Future<bool> start() async => false;

  Future<List<int>?> stopAndReadBytes() async => null;

  Future<SavedRecording?> persistLastRecording(String name) async => null;

  Future<void> deleteFile(String path) async {}

  Future<void> dispose() async {}
}
