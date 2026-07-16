// lib/features/recruiter/voice/voice_catalog.dart
//
// On-device static Voice & Persona catalog for the recruiter picker.
//
// SOURCE OF TRUTH: these values are copied verbatim from the website platform's
// server defaults —
//   talbotiq-platform/server/store/defaults.ts
//     -> VOICE_CATALOG, PERSONA_PRESETS, DEFAULT_LIVE_MODEL, DEFAULT_VOICE_CONFIG
// which is what `GET /api/voices` (routes/voices.ts) serves. Keeping this file
// in sync with that export ensures the Flutter picker offers exactly the same
// Gemini Live prebuilt voices and interviewer personas as the web recruiter UI.
//
// If/when the app fetches the live catalog from the server, the models in
// voice_models.dart deserialize the same JSON; this static list is the offline
// fallback and the default for new templates.

import 'voice_models.dart';

/// Static, on-device Voice & Persona catalog.
///
/// All voices are Gemini Live native-audio prebuilt timbres (multilingual);
/// `id` equals the `prebuiltVoiceConfig.voiceName` sent to the Live API.
abstract final class VoiceCatalog {
  const VoiceCatalog._();

  /// Default Gemini Live model (mirrors DEFAULT_LIVE_MODEL in defaults.ts).
  static const String defaultLiveModel = 'gemini-3.1-flash-live-preview';

  /// Browsable catalog of Gemini Live native-audio prebuilt voices.
  /// Gender/description tags follow Google's published voice characteristics.
  static const List<VoiceOption> voices = <VoiceOption>[
    VoiceOption(
        id: 'Aoede',
        label: 'Aoede',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Breezy, natural'),
    VoiceOption(
        id: 'Kore',
        label: 'Kore',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Firm, composed'),
    VoiceOption(
        id: 'Leda',
        label: 'Leda',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Youthful, warm'),
    VoiceOption(
        id: 'Zephyr',
        label: 'Zephyr',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Bright, upbeat'),
    VoiceOption(
        id: 'Callirrhoe',
        label: 'Callirrhoe',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Easy-going'),
    VoiceOption(
        id: 'Erinome',
        label: 'Erinome',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Clear, measured'),
    VoiceOption(
        id: 'Despina',
        label: 'Despina',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Smooth, calm'),
    VoiceOption(
        id: 'Laomedeia',
        label: 'Laomedeia',
        gender: VoiceGender.female,
        language: 'English (multilingual)',
        description: 'Upbeat, lively'),
    VoiceOption(
        id: 'Charon',
        label: 'Charon',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Informative, steady'),
    VoiceOption(
        id: 'Orus',
        label: 'Orus',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Firm, authoritative'),
    VoiceOption(
        id: 'Puck',
        label: 'Puck',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Upbeat, friendly'),
    VoiceOption(
        id: 'Fenrir',
        label: 'Fenrir',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Excitable, energetic'),
    VoiceOption(
        id: 'Iapetus',
        label: 'Iapetus',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Clear, articulate'),
    VoiceOption(
        id: 'Umbriel',
        label: 'Umbriel',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Easy-going'),
    VoiceOption(
        id: 'Enceladus',
        label: 'Enceladus',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Breathy, soft'),
    VoiceOption(
        id: 'Algieba',
        label: 'Algieba',
        gender: VoiceGender.male,
        language: 'English (multilingual)',
        description: 'Smooth, warm'),
  ];

  /// Selectable interviewer personas: character + default voice.
  static const List<InterviewPersona> personas = <InterviewPersona>[
    InterviewPersona(
      id: 'friendly_hr',
      name: 'Friendly HR Screener',
      description:
          'Warm, encouraging first-round screener who puts candidates at ease.',
      stylePrompt:
          'You are a warm, personable HR screener. You sound friendly and encouraging, keep the candidate at ease, and speak in a relaxed conversational tone.',
      defaultVoiceId: 'Aoede',
    ),
    InterviewPersona(
      id: 'rigorous_tech',
      name: 'Rigorous Technical Interviewer',
      description: 'Sharp, focused engineer probing depth and problem-solving.',
      stylePrompt:
          'You are a sharp, focused senior engineer running a technical interview. You are professional and respectful, but you probe for depth and precision. Stay crisp and direct.',
      defaultVoiceId: 'Charon',
    ),
    InterviewPersona(
      id: 'warm_behavioral',
      name: 'Warm Behavioral Interviewer',
      description:
          'Empathetic interviewer exploring experience and collaboration.',
      stylePrompt:
          'You are an empathetic behavioral interviewer. You listen closely, sound genuinely interested, and gently draw out stories about the candidate’s experience and how they work with others.',
      defaultVoiceId: 'Leda',
    ),
    InterviewPersona(
      id: 'exec_panel',
      name: 'Executive Panel Lead',
      description:
          'Composed, senior leader assessing strategic thinking and presence.',
      stylePrompt:
          'You are a composed, senior executive leading a final-round conversation. You are gracious but discerning, assessing judgment, strategic thinking, and presence. Speak with calm authority.',
      defaultVoiceId: 'Orus',
    ),
  ];

  /// Default voice configuration for a new voice-track template
  /// (mirrors DEFAULT_VOICE_CONFIG in defaults.ts).
  static const VoiceConfig defaultVoiceConfig = VoiceConfig(
    engine: VoiceEngine.geminiLive,
    personaId: 'friendly_hr',
    voiceId: 'Aoede',
    allowBargeIn: true,
    language: 'en-US',
    model: defaultLiveModel,
  );

  // ── Lookup helpers ─────────────────────────────────────────────────────

  /// The voice with [id], or null when unknown.
  static VoiceOption? voiceById(String? id) {
    if (id == null) return null;
    for (final v in voices) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// The persona with [id], or null when unknown.
  static InterviewPersona? personaById(String? id) {
    if (id == null) return null;
    for (final p in personas) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Resolve the effective voice for a config: the explicit override when it
  /// names a known voice, else the selected persona's default, else the first
  /// catalog voice. Never returns null when the catalog is non-empty.
  static VoiceOption resolveVoice(VoiceConfig config) {
    return voiceById(config.voiceId) ??
        voiceById(personaById(config.personaId)?.defaultVoiceId) ??
        voices.first;
  }
}
