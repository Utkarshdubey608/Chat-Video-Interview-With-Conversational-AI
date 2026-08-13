// lib/core/services/recording_service.dart
//
// Records the candidate's microphone to a local .wav file during the interview.
// On end, the file's bytes are sent to Deepgram's pre-recorded endpoint for
// transcription (see results_page).
//
// Native (Android/iOS) uses the `record` package; web is a no-op stub — the
// browser mic is owned by Tavus's page inside the call iframe, so there's no
// separate local recording to make. Results page falls back to Tavus's own
// server-side transcript in that case (see results_page.dart _ensureTranscript).
export 'package:talbotiq/core/services/recording_service_stub.dart'
    if (dart.library.io) 'recording_service_io.dart';
