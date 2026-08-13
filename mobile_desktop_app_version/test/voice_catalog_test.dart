// test/voice_catalog_test.dart
//
// A Voice interview's voice/persona picker lives inside "Advanced settings"
// in create_interview_page.dart, collapsed by default — a recruiter who
// never opens it must still end up with a valid, resolved voice/persona
// persisted, not `voiceName: null`. resolveVoiceId/resolvePersonaId are what
// guarantee that (see create_interview_page.dart's _resolvedVoiceName /
// _resolvedVoicePersonaId), so they're pinned here independently of the page.

import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/recruiter/voice/voice_catalog.dart';

void main() {
  group('resolveVoiceId', () {
    test('an unset (null) voice falls back to the product default', () {
      expect(VoiceCatalog.resolveVoiceId(null),
          VoiceCatalog.defaultVoiceConfig.voiceId);
    });

    test('an unrecognized voice id falls back to the product default', () {
      expect(VoiceCatalog.resolveVoiceId('not-a-real-voice'),
          VoiceCatalog.defaultVoiceConfig.voiceId);
    });

    test('a recognized voice id is used as-is', () {
      expect(VoiceCatalog.resolveVoiceId('Charon'), 'Charon');
    });

    test('never returns null', () {
      expect(VoiceCatalog.resolveVoiceId(null), isNotNull);
    });
  });

  group('resolvePersonaId', () {
    test('an unset (null) persona falls back to the product default', () {
      expect(VoiceCatalog.resolvePersonaId(null),
          VoiceCatalog.defaultVoiceConfig.personaId);
    });

    test('an unrecognized persona id falls back to the product default', () {
      expect(VoiceCatalog.resolvePersonaId('not-a-real-persona'),
          VoiceCatalog.defaultVoiceConfig.personaId);
    });

    test('a recognized persona id is used as-is', () {
      expect(VoiceCatalog.resolvePersonaId('rigorous_tech'), 'rigorous_tech');
    });

    test('never returns null', () {
      expect(VoiceCatalog.resolvePersonaId(null), isNotNull);
    });
  });
}
