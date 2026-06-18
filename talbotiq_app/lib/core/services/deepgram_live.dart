// lib/core/services/deepgram_live.dart
//
// Real-time Deepgram transcription session. The web implementation streams the
// candidate's microphone to Deepgram over a WebSocket; the stub is a no-op so
// non-web targets still compile.
export 'deepgram_live_stub.dart'
    if (dart.library.html) 'deepgram_live_web.dart';
