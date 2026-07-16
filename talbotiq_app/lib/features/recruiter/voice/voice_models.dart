// lib/features/recruiter/voice/voice_models.dart
//
// Dart models for the Voice & Persona catalog. These MIRROR the website's
// single source of truth in `shared/types.ts` (VoiceOption, InterviewPersona,
// VoiceConfig) so the Flutter app and the web platform interoperate over the
// exact same JSON shapes returned by `GET /api/voices`.
//
// Field names are kept identical to the TypeScript contract (camelCase) so a
// payload can round-trip through fromJson/toJson without a mapping layer.

/// Real-time engine backing the voice track.
///
/// `gemini_live` = native-audio bidirectional stream (built).
/// `pipeline`    = Cloud STT -> Gemini -> TTS (typed flag; not yet implemented).
enum VoiceEngine {
  geminiLive,
  pipeline;

  /// The wire value used by the website contract (`VoiceEngine` in types.ts).
  String get wire => switch (this) {
        VoiceEngine.geminiLive => 'gemini_live',
        VoiceEngine.pipeline => 'pipeline',
      };

  static VoiceEngine fromWire(String? value) => switch (value) {
        'pipeline' => VoiceEngine.pipeline,
        _ => VoiceEngine.geminiLive, // default/back-compat
      };
}

/// Speaker gender tag used only for grouping/labelling in the picker UI.
enum VoiceGender {
  male,
  female,
  neutral;

  String get wire => name; // 'male' | 'female' | 'neutral'

  /// Human-facing label for section headers / chips.
  String get label => switch (this) {
        VoiceGender.male => 'Male',
        VoiceGender.female => 'Female',
        VoiceGender.neutral => 'Neutral',
      };

  static VoiceGender? fromWire(String? value) => switch (value) {
        'male' => VoiceGender.male,
        'female' => VoiceGender.female,
        'neutral' => VoiceGender.neutral,
        _ => null,
      };
}

/// A selectable voice for the catalog/preview UI.
///
/// Mirrors `VoiceOption` in shared/types.ts. `id` is the
/// `prebuiltVoiceConfig.voiceName` for the gemini_live engine.
class VoiceOption {
  /// prebuiltVoiceConfig.voiceName for gemini_live.
  final String id;
  final String label;
  final VoiceGender? gender;
  final String language;
  final String? accent;
  final VoiceEngine engine;
  final String? description;

  /// Optional pre-rendered sample; else previewed live.
  final String? sampleUrl;

  const VoiceOption({
    required this.id,
    required this.label,
    this.gender,
    required this.language,
    this.accent,
    this.engine = VoiceEngine.geminiLive,
    this.description,
    this.sampleUrl,
  });

  factory VoiceOption.fromJson(Map<String, dynamic> json) => VoiceOption(
        id: json['id'] as String,
        label: (json['label'] ?? json['id']) as String,
        gender: VoiceGender.fromWire(json['gender'] as String?),
        language: (json['language'] ?? '') as String,
        accent: json['accent'] as String?,
        engine: VoiceEngine.fromWire(json['engine'] as String?),
        description: json['description'] as String?,
        sampleUrl: json['sampleUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (gender != null) 'gender': gender!.wire,
        'language': language,
        if (accent != null) 'accent': accent,
        'engine': engine.wire,
        if (description != null) 'description': description,
        if (sampleUrl != null) 'sampleUrl': sampleUrl,
      };

  VoiceOption copyWith({
    String? id,
    String? label,
    VoiceGender? gender,
    String? language,
    String? accent,
    VoiceEngine? engine,
    String? description,
    String? sampleUrl,
  }) =>
      VoiceOption(
        id: id ?? this.id,
        label: label ?? this.label,
        gender: gender ?? this.gender,
        language: language ?? this.language,
        accent: accent ?? this.accent,
        engine: engine ?? this.engine,
        description: description ?? this.description,
        sampleUrl: sampleUrl ?? this.sampleUrl,
      );

  @override
  bool operator ==(Object other) => other is VoiceOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A selectable interviewer character = style prompt + default voice + delivery.
///
/// Mirrors `InterviewPersona` in shared/types.ts.
class InterviewPersona {
  final String id;
  final String name;
  final String description;

  /// Interviewer character injected into the system instruction.
  final String stylePrompt;
  final String defaultVoiceId;

  /// pipeline TTS only.
  final double? speakingRate;

  /// pipeline TTS only.
  final double? pitch;

  const InterviewPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.stylePrompt,
    required this.defaultVoiceId,
    this.speakingRate,
    this.pitch,
  });

  factory InterviewPersona.fromJson(Map<String, dynamic> json) =>
      InterviewPersona(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] ?? '') as String,
        stylePrompt: (json['stylePrompt'] ?? '') as String,
        defaultVoiceId: json['defaultVoiceId'] as String,
        speakingRate: (json['speakingRate'] as num?)?.toDouble(),
        pitch: (json['pitch'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'stylePrompt': stylePrompt,
        'defaultVoiceId': defaultVoiceId,
        if (speakingRate != null) 'speakingRate': speakingRate,
        if (pitch != null) 'pitch': pitch,
      };

  InterviewPersona copyWith({
    String? id,
    String? name,
    String? description,
    String? stylePrompt,
    String? defaultVoiceId,
    double? speakingRate,
    double? pitch,
  }) =>
      InterviewPersona(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        stylePrompt: stylePrompt ?? this.stylePrompt,
        defaultVoiceId: defaultVoiceId ?? this.defaultVoiceId,
        speakingRate: speakingRate ?? this.speakingRate,
        pitch: pitch ?? this.pitch,
      );

  @override
  bool operator ==(Object other) => other is InterviewPersona && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Per-template voice configuration.
///
/// Mirrors `VoiceConfig` in shared/types.ts. This is the value the recruiter
/// builds with the [VoicePicker] and stores on an InterviewTemplate.
class VoiceConfig {
  final VoiceEngine engine;
  final String personaId;

  /// Overrides the persona default when set.
  final String voiceId;

  /// Candidate can interrupt the agent.
  final bool allowBargeIn;
  final String language;

  /// Live model override (default: native-audio preview).
  final String? model;

  const VoiceConfig({
    this.engine = VoiceEngine.geminiLive,
    required this.personaId,
    required this.voiceId,
    this.allowBargeIn = true,
    this.language = 'en-US',
    this.model,
  });

  factory VoiceConfig.fromJson(Map<String, dynamic> json) => VoiceConfig(
        engine: VoiceEngine.fromWire(json['engine'] as String?),
        personaId: json['personaId'] as String,
        voiceId: json['voiceId'] as String,
        allowBargeIn: (json['allowBargeIn'] as bool?) ?? true,
        language: (json['language'] ?? 'en-US') as String,
        model: json['model'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'engine': engine.wire,
        'personaId': personaId,
        'voiceId': voiceId,
        'allowBargeIn': allowBargeIn,
        'language': language,
        if (model != null) 'model': model,
      };

  VoiceConfig copyWith({
    VoiceEngine? engine,
    String? personaId,
    String? voiceId,
    bool? allowBargeIn,
    String? language,
    String? model,
  }) =>
      VoiceConfig(
        engine: engine ?? this.engine,
        personaId: personaId ?? this.personaId,
        voiceId: voiceId ?? this.voiceId,
        allowBargeIn: allowBargeIn ?? this.allowBargeIn,
        language: language ?? this.language,
        model: model ?? this.model,
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceConfig &&
      other.engine == engine &&
      other.personaId == personaId &&
      other.voiceId == voiceId &&
      other.allowBargeIn == allowBargeIn &&
      other.language == language &&
      other.model == model;

  @override
  int get hashCode =>
      Object.hash(engine, personaId, voiceId, allowBargeIn, language, model);
}
