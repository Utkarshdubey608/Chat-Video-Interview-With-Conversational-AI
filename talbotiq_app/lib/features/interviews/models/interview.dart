// lib/features/interviews/models/interview.dart
//
// The focused, Firestore-backed model for a recruiter-created interview assigned
// to a candidate. Deliberately simpler than the recruiter template module: it
// carries exactly what's needed to launch a Tavus video call or a chat runner
// (prompt + questions + avatar) plus the assignment (candidate email) and
// lifecycle status. See features/interviews/services/interview_repository.dart.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Video (Tavus avatar) vs text Chat vs real-time Voice interview.
enum InterviewType { video, chat, voice }

extension InterviewTypeX on InterviewType {
  String get wire {
    switch (this) {
      case InterviewType.video:
        return 'video';
      case InterviewType.chat:
        return 'chat';
      case InterviewType.voice:
        return 'voice';
    }
  }

  String get label {
    switch (this) {
      case InterviewType.video:
        return 'Video Interview';
      case InterviewType.chat:
        return 'Chat Interview';
      case InterviewType.voice:
        return 'Voice Interview';
    }
  }

  static InterviewType fromWire(String? v) {
    switch (v) {
      case 'video':
        return InterviewType.video;
      case 'voice':
        return InterviewType.voice;
      default:
        return InterviewType.chat;
    }
  }
}

/// What a candidate does in one round of a test's timeline.
///
/// A superset of [InterviewType]: `resume` is a submission step with no
/// interview session, the other three map 1:1 onto the interview tracks. It is
/// declared here rather than beside [InterviewRound] because the `interviews`
/// document itself carries it — putting it in the round file would make these
/// two models import each other.
enum RoundKind { resume, chat, video, voice }

extension RoundKindX on RoundKind {
  String get wire {
    switch (this) {
      case RoundKind.resume:
        return 'resume';
      case RoundKind.chat:
        return 'chat';
      case RoundKind.video:
        return 'video';
      case RoundKind.voice:
        return 'voice';
    }
  }

  String get label {
    switch (this) {
      case RoundKind.resume:
        return 'Résumé screen';
      case RoundKind.chat:
        return 'Chat Interview';
      case RoundKind.video:
        return 'Video Interview';
      case RoundKind.voice:
        return 'Voice Interview';
    }
  }

  /// True when the round runs a live interview session (so it has a transcript,
  /// attempts and a runner). A résumé round has none of those.
  bool get isInterview => this != RoundKind.resume;

  /// The interview track to launch, or null for a résumé round.
  InterviewType? get interviewType {
    switch (this) {
      case RoundKind.resume:
        return null;
      case RoundKind.chat:
        return InterviewType.chat;
      case RoundKind.video:
        return InterviewType.video;
      case RoundKind.voice:
        return InterviewType.voice;
    }
  }

  static RoundKind fromWire(String? v) {
    switch (v) {
      case 'resume':
        return RoundKind.resume;
      case 'video':
        return RoundKind.video;
      case 'voice':
        return RoundKind.voice;
      default:
        return RoundKind.chat;
    }
  }

  static RoundKind fromInterviewType(InterviewType t) {
    switch (t) {
      case InterviewType.video:
        return RoundKind.video;
      case InterviewType.voice:
        return RoundKind.voice;
      case InterviewType.chat:
        return RoundKind.chat;
    }
  }
}

/// Lifecycle of an assigned interview.
enum InterviewStatus { assigned, inProgress, completed }

extension InterviewStatusX on InterviewStatus {
  String get wire {
    switch (this) {
      case InterviewStatus.assigned:
        return 'assigned';
      case InterviewStatus.inProgress:
        return 'in_progress';
      case InterviewStatus.completed:
        return 'completed';
    }
  }

  String get label {
    switch (this) {
      case InterviewStatus.assigned:
        return 'Assigned';
      case InterviewStatus.inProgress:
        return 'In progress';
      case InterviewStatus.completed:
        return 'Completed';
    }
  }

  static InterviewStatus fromWire(String? v) {
    switch (v) {
      case 'in_progress':
        return InterviewStatus.inProgress;
      case 'completed':
        return InterviewStatus.completed;
      default:
        return InterviewStatus.assigned;
    }
  }
}

/// Avatar selection for a video interview (maps to Tavus replica/persona).
class AvatarConfig {
  final String replicaId;
  final String? personaId;

  const AvatarConfig({required this.replicaId, this.personaId});

  factory AvatarConfig.fromMap(Map<String, dynamic>? m) => AvatarConfig(
        replicaId: (m?['replicaId'] as String?) ?? '',
        personaId: m?['personaId'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'replicaId': replicaId,
        if (personaId != null && personaId!.isNotEmpty) 'personaId': personaId,
      };
}

class Interview {
  final String id;

  /// Shared by all candidates created together in one action, so a recruiter
  /// can review + publish a whole "test" at once.
  final String testId;

  /// Which round of the test's timeline this assignment belongs to — the id of a
  /// `tests/{testId}/rounds/{roundId}` document (see [InterviewRound]).
  ///
  /// EMPTY on every interview created before timelines existed. Such a document
  /// is treated as the single implicit round of a one-round test, which is why no
  /// migration is needed: see [hasRound] and [effectiveRoundOrder].
  final String roundId;

  /// The round's position in the timeline, copied here so the recruiter list can
  /// group and sort by round without reading the round documents. Null on
  /// pre-timeline interviews.
  final int? roundOrder;

  /// What the candidate does in this round, copied from the round at assignment.
  ///
  /// Exists because [type] cannot express a résumé round — it only names the
  /// three live interview tracks — and because the candidate's device can then
  /// route the round without reading `tests/{testId}/rounds`, which it has no
  /// permission to read. Null on pre-timeline interviews → derived from [type].
  final RoundKind? roundKind;

  final String recruiterId;
  final String recruiterEmail;

  /// Display name of the recruiter/org that created this interview, shown to
  /// the candidate.
  final String? recruiterName;
  final String candidateEmail;

  /// Normalized (lowercased/trimmed) candidate email — the field candidate
  /// queries + security rules match against.
  final String candidateEmailLower;
  final String? candidateName;

  final InterviewType type;
  final String title;
  final String prompt;
  final List<String> questions;

  /// Chat interviews only: when true, the AI generates questions adaptively
  /// (résumé-grounded, with optional follow-ups) instead of using the fixed
  /// [questions] list. Absent/false on every existing doc → fixed behaviour is
  /// preserved unchanged.
  final bool adaptive;

  /// Adaptive settings (an `AdaptiveConfig` JSON map) applied when [adaptive] is
  /// true — role, difficulty, style, numberOfQuestions, allowFollowUps, etc.
  /// Kept as a raw map so this focused model stays free of the recruiter-module
  /// types; the chat launch adapter converts it to an `AdaptiveConfig`.
  final Map<String, dynamic>? adaptiveConfig;

  /// When true, the candidate is asked to provide a résumé (PDF or pasted text)
  /// before a VIDEO interview starts; the text grounds the AI interviewer.
  /// Adaptive chat always collects a résumé via the runner regardless of this
  /// flag. Absent/false on existing docs → no résumé step (unchanged).
  final bool collectResume;

  /// Interview language (full name, e.g. 'English', 'Spanish'). Drives the Tavus
  /// avatar's spoken language and the adaptive chat interviewer. Absent → English
  /// (unchanged behaviour).
  final String language;

  /// Voice track only: the Gemini Live prebuilt voice name (e.g. 'Aoede') and an
  /// optional persona id. Absent → the voice engine's default voice.
  final String? voiceName;
  final String? voicePersonaId;

  /// Optional proctoring/integrity settings (an `IntegrityConfig` JSON map:
  /// detectTabSwitch, disablePasteInAnswers, disableCopy, maxTabSwitchWarnings,
  /// logEvents). Enforced by the chat runner. Absent → sensible defaults.
  final Map<String, dynamic>? integrity;

  /// Optional branding (a `BrandingConfig` JSON map: companyName, accentColor,
  /// welcomeMessage) shown on the candidate welcome screen. Absent → defaults.
  final Map<String, dynamic>? branding;

  /// Chat interviews only: optional per-question countdown timer. A
  /// `ConversationTimingConfig`-shaped JSON map:
  /// { enabled:bool, perQuestionSeconds:int, thinkingSeconds:int,
  ///   allowEarlySubmit:bool, warningThresholdSeconds:int,
  ///   autoSubmitOnExpiry:bool }.
  /// When `enabled` is true the chat launch adapter runs the interview in
  /// `InterviewMode.timed`; the answer clock auto-submits at zero. Absent or
  /// `enabled:false` → the untimed conversational behaviour is preserved
  /// unchanged.
  final Map<String, dynamic>? chatTimer;

  /// Only meaningful for [InterviewType.video].
  final AvatarConfig avatar;
  final int durationMinutes;
  final InterviewStatus status;

  /// Optional access window. The candidate can only launch between
  /// [availableFrom] (if set) and [expiresAt] (if set).
  final DateTime? availableFrom;
  final DateTime? expiresAt;

  /// Max times a candidate may take this interview. null = unlimited.
  final int? maxAttempts;

  /// How many times the candidate has launched it so far.
  final int attemptsUsed;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Canonical result map (both video + chat). Written unpublished on
  /// completion; the recruiter reviews/edits it and publishes. Shape:
  /// { overallScore:int, summary:String, recommendation:String,
  ///   strengths:[String], improvements:[String], evaluatedBy:'ai'|'manual',
  ///   detail:{...raw} }.
  final Map<String, dynamic>? result;

  /// Whether the result is visible to the candidate. Recruiter-controlled.
  final bool resultPublished;

  /// A résumé submission and its AI score (a `ResumeSubmission` JSON map:
  /// text, charCount, fileName, extractedAt, score).
  ///
  /// READ-ONLY here, and absent from both write maps below on purpose: this field
  /// is written only by the backend with the Admin SDK, and `firestore.rules`
  /// blocks the candidate from touching it. See `resume_submission.dart`.
  final Map<String, dynamic>? resume;

  // ── Evaluation state ──────────────────────────────────────────────────────
  //
  // Who — if anyone — produced the stored score. `evaluatedBy` is the single
  // source of truth: 'ai', 'manual', or EMPTY meaning nothing has scored this.
  //
  // Empty is deliberately never a score. A heuristic fallback used to be written
  // here as `'ai'`, which put a number derived from answer LENGTH in front of a
  // recruiter looking like a judgement of content, and let it be published to the
  // candidate. Failed scoring now stores no score at all, which is why
  // `overallScore` is absent rather than 0 — a 0 would rank on the leaderboard as
  // if the candidate had earned it.

  String get evaluatedBy => (result?['evaluatedBy'] as String?)?.trim() ?? '';

  /// Why AI scoring failed, when it did and recorded a reason.
  String get evaluationError =>
      (result?['evaluationError'] as String?)?.trim() ?? '';

  bool get isAiScored => evaluatedBy == 'ai';
  bool get isManuallyScored => evaluatedBy == 'manual';

  /// A real score exists — produced by the AI or entered by a recruiter.
  bool get hasScore => evaluatedBy.isNotEmpty && result?['overallScore'] != null;

  /// The candidate finished, but nothing has produced a score.
  ///
  /// Covers both "AI scoring failed" and "the AI never got there" — from the
  /// recruiter's point of view both need the same thing done about them, which is
  /// why [canRetryEvaluation] rather than this decides what the retry button acts
  /// on.
  bool get awaitingEvaluation =>
      status == InterviewStatus.completed &&
      result != null &&
      evaluatedBy.isEmpty;

  /// Scoring failed and said why — the case worth reporting as a FAILURE rather
  /// than as "not scored yet".
  bool get evaluationFailed =>
      awaitingEvaluation && evaluationError.isNotEmpty;

  /// The candidate's raw answers, kept so a failed evaluation can be retried
  /// without making them sit the interview again.
  List<Map<String, dynamic>> get storedResponses => [
        for (final e in (result?['responses'] as List?) ?? const [])
          if (e is Map)
            e.map((k, v) => MapEntry(k.toString(), v)),
      ];

  /// Retryable: nothing scored it, and the answers needed to score it survive.
  /// Without responses there is nothing to feed the scorer, so the only route is
  /// a manual evaluation.
  bool get canRetryEvaluation =>
      awaitingEvaluation && storedResponses.isNotEmpty;

  /// Whether this interview belongs to an explicit round. False for every
  /// pre-timeline document, which is treated as a single implicit round.
  bool get hasRound => roundId.isNotEmpty;

  /// Timeline position, defaulting a pre-timeline interview to the first round so
  /// grouping and sorting never has to special-case null.
  int get effectiveRoundOrder => roundOrder ?? 0;

  /// What the candidate does here. Falls back to [type] for pre-timeline
  /// documents, which were always live interviews.
  RoundKind get effectiveRoundKind =>
      roundKind ?? RoundKindX.fromInterviewType(type);

  const Interview({
    required this.id,
    this.testId = '',
    this.roundId = '',
    this.roundOrder,
    this.roundKind,
    required this.recruiterId,
    required this.recruiterEmail,
    this.recruiterName,
    required this.candidateEmail,
    required this.candidateEmailLower,
    this.candidateName,
    required this.type,
    required this.title,
    required this.prompt,
    required this.questions,
    this.adaptive = false,
    this.adaptiveConfig,
    this.collectResume = false,
    this.language = 'English',
    this.voiceName,
    this.voicePersonaId,
    this.integrity,
    this.branding,
    this.chatTimer,
    required this.avatar,
    required this.durationMinutes,
    required this.status,
    this.availableFrom,
    this.expiresAt,
    this.maxAttempts,
    this.attemptsUsed = 0,
    this.createdAt,
    this.updatedAt,
    this.result,
    this.resultPublished = false,
    this.resume,
  });

  /// Time-window checks.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isNotYetAvailable =>
      availableFrom != null && DateTime.now().isBefore(availableFrom!);
  bool get isWithinWindow => !isExpired && !isNotYetAvailable;

  /// Attempt checks.
  bool get hasAttemptsLeft => maxAttempts == null || attemptsUsed < maxAttempts!;
  int? get attemptsRemaining =>
      maxAttempts == null ? null : (maxAttempts! - attemptsUsed).clamp(0, maxAttempts!);

  /// The candidate may launch only within the window AND with attempts left.
  bool get isAccessible => isWithinWindow && hasAttemptsLeft;

  factory Interview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Interview(
      id: doc.id,
      testId: (d['testId'] as String?) ?? '',
      roundId: (d['roundId'] as String?) ?? '',
      roundOrder: (d['roundOrder'] as num?)?.toInt(),
      // Absent (pre-timeline) must stay null rather than defaulting through
      // fromWire, so `effectiveRoundKind` can fall back to the interview type.
      roundKind: d['roundKind'] == null
          ? null
          : RoundKindX.fromWire(d['roundKind'] as String?),
      recruiterId: (d['recruiterId'] as String?) ?? '',
      recruiterEmail: (d['recruiterEmail'] as String?) ?? '',
      recruiterName: d['recruiterName'] as String?,
      candidateEmail: (d['candidateEmail'] as String?) ?? '',
      candidateEmailLower: (d['candidateEmailLower'] as String?) ??
          (d['candidateEmail'] as String?)?.trim().toLowerCase() ??
          '',
      candidateName: d['candidateName'] as String?,
      type: InterviewTypeX.fromWire(d['type'] as String?),
      title: (d['title'] as String?) ?? 'Interview',
      prompt: (d['prompt'] as String?) ?? '',
      questions:
          (d['questions'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      adaptive: (d['adaptive'] as bool?) ?? false,
      adaptiveConfig: (d['adaptiveConfig'] as Map<String, dynamic>?),
      collectResume: (d['collectResume'] as bool?) ?? false,
      language: (d['language'] as String?) ?? 'English',
      voiceName: d['voiceName'] as String?,
      voicePersonaId: d['voicePersonaId'] as String?,
      integrity: d['integrity'] as Map<String, dynamic>?,
      branding: d['branding'] as Map<String, dynamic>?,
      chatTimer: d['chatTimer'] as Map<String, dynamic>?,
      avatar: AvatarConfig.fromMap(d['avatar'] as Map<String, dynamic>?),
      durationMinutes: (d['durationMinutes'] as num?)?.toInt() ?? 15,
      status: InterviewStatusX.fromWire(d['status'] as String?),
      availableFrom: (d['availableFrom'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      maxAttempts: (d['maxAttempts'] as num?)?.toInt(),
      attemptsUsed: (d['attemptsUsed'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      result: d['result'] as Map<String, dynamic>?,
      resultPublished: (d['resultPublished'] as bool?) ?? false,
      resume: d['resume'] as Map<String, dynamic>?,
    );
  }

  /// Payload for a new document. `createdAt`/`updatedAt` use server timestamps.
  Map<String, dynamic> toCreateMap() => {
        'testId': testId,
        // Round fields are written only when this interview belongs to a
        // timeline, so a single-round test's documents stay byte-identical to
        // what the app wrote before rounds existed.
        if (roundId.isNotEmpty) 'roundId': roundId,
        if (roundOrder != null) 'roundOrder': roundOrder,
        if (roundKind != null) 'roundKind': roundKind!.wire,
        'resultPublished': false,
        'recruiterId': recruiterId,
        'recruiterEmail': recruiterEmail,
        if (recruiterName != null && recruiterName!.isNotEmpty)
          'recruiterName': recruiterName,
        'candidateEmail': candidateEmail,
        'candidateEmailLower': candidateEmailLower,
        if (candidateName != null && candidateName!.isNotEmpty)
          'candidateName': candidateName,
        'type': type.wire,
        'title': title,
        'prompt': prompt,
        'questions': questions,
        'adaptive': adaptive,
        if (adaptiveConfig != null) 'adaptiveConfig': adaptiveConfig,
        'collectResume': collectResume,
        'language': language,
        if (voiceName != null) 'voiceName': voiceName,
        if (voicePersonaId != null) 'voicePersonaId': voicePersonaId,
        if (integrity != null) 'integrity': integrity,
        if (branding != null) 'branding': branding,
        if (chatTimer != null) 'chatTimer': chatTimer,
        'avatar': avatar.toMap(),
        'durationMinutes': durationMinutes,
        'status': status.wire,
        'availableFrom':
            availableFrom == null ? null : Timestamp.fromDate(availableFrom!),
        'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
        'maxAttempts': maxAttempts,
        'attemptsUsed': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Editable fields written on an update (identity + createdAt are preserved).
  ///
  /// `testId` and the three round fields are deliberately absent: which round of
  /// which test an assignment belongs to is identity, not content. Reordering a
  /// timeline rewrites `roundOrder` through
  /// `InterviewRepository.reorderRounds`, not through an interview edit.
  Map<String, dynamic> toUpdateMap() => {
        'candidateEmail': candidateEmail,
        'candidateEmailLower': candidateEmailLower,
        'candidateName': candidateName,
        'type': type.wire,
        'title': title,
        'prompt': prompt,
        'questions': questions,
        'adaptive': adaptive,
        'collectResume': collectResume,
        'language': language,
        // Type-specific config written UNCONDITIONALLY (null when absent) so
        // editing an interview to a different type clears stale fields.
        'adaptiveConfig': adaptiveConfig,
        'voiceName': voiceName,
        'voicePersonaId': voicePersonaId,
        'integrity': integrity,
        'branding': branding,
        'chatTimer': chatTimer,
        'avatar': avatar.toMap(),
        'durationMinutes': durationMinutes,
        'availableFrom':
            availableFrom == null ? null : Timestamp.fromDate(availableFrom!),
        'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
        // attemptsUsed is intentionally omitted so an edit never resets it.
        'maxAttempts': maxAttempts,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
