// lib/core/services/recording_service.dart
//
// Records the candidate's microphone to a local .wav file during the interview.
// On end, the file's bytes are sent to Deepgram's pre-recorded endpoint for
// transcription (see results_page).
//
// Native (Android/iOS) uses the `record` package; web is a no-op stub because
// the web build already captures the transcript via Deepgram live streaming.
export 'package:talbotiq/core/services/recording_service_stub.dart'
    if (dart.library.io) 'recording_service_io.dart';
