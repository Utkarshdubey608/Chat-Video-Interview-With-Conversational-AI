// lib/features/interviews/models/interview.dart
//
// The focused, Firestore-backed model for a recruiter-created interview assigned
// to a candidate. Deliberately simpler than the recruiter template module: it
// carries exactly what's needed to launch a Tavus video call or a chat runner
// (prompt + questions + avatar) plus the assignment (candidate email) and
// lifecycle status. See features/interviews/services/interview_repository.dart.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Video (Tavus avatar) vs text Chat interview.
enum InterviewType { video, chat }

extension InterviewTypeX on InterviewType {
  String get wire => this == InterviewType.video ? 'video' : 'chat';
  String get label =>
      this == InterviewType.video ? 'Video Interview' : 'Chat Interview';
  static InterviewType fromWire(String? v) =>
      v == 'video' ? InterviewType.video : InterviewType.chat;
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

  /// Only meaningful for [InterviewType.video].
  final AvatarConfig avatar;
  final int durationMinutes;
  final InterviewStatus status;

  /// Per-test API key overrides. When a candidate launches this interview, any
  /// key present here is used INSTEAD of the recruiter's Settings key; blank/
  /// absent keys fall back to the recruiter's own keys (recruiter_keys doc).
  /// Only non-empty entries are stored. Recognized keys: tavusKey, geminiKey,
  /// humeKey, deepgramKey. See AppConfigService.applyForRecruiter.
  final Map<String, String> keyOverrides;

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

  const Interview({
    required this.id,
    this.testId = '',
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
    required this.avatar,
    required this.durationMinutes,
    required this.status,
    this.keyOverrides = const {},
    this.availableFrom,
    this.expiresAt,
    this.maxAttempts,
    this.attemptsUsed = 0,
    this.createdAt,
    this.updatedAt,
    this.result,
    this.resultPublished = false,
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

  /// Coerces a stored `keyOverrides` map to `Map<String, String>`, dropping
  /// null/blank values so callers can treat "present" as "use this key".
  static Map<String, String> _readKeyOverrides(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v is String && v.trim().isNotEmpty) out[k.toString()] = v.trim();
    });
    return out;
  }

  factory Interview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Interview(
      id: doc.id,
      testId: (d['testId'] as String?) ?? '',
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
      avatar: AvatarConfig.fromMap(d['avatar'] as Map<String, dynamic>?),
      durationMinutes: (d['durationMinutes'] as num?)?.toInt() ?? 15,
      status: InterviewStatusX.fromWire(d['status'] as String?),
      keyOverrides: _readKeyOverrides(d['keyOverrides']),
      availableFrom: (d['availableFrom'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      maxAttempts: (d['maxAttempts'] as num?)?.toInt(),
      attemptsUsed: (d['attemptsUsed'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      result: d['result'] as Map<String, dynamic>?,
      resultPublished: (d['resultPublished'] as bool?) ?? false,
    );
  }

  /// Payload for a new document. `createdAt`/`updatedAt` use server timestamps.
  Map<String, dynamic> toCreateMap() => {
        'testId': testId,
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
        'avatar': avatar.toMap(),
        'durationMinutes': durationMinutes,
        'status': status.wire,
        'keyOverrides': keyOverrides,
        'availableFrom':
            availableFrom == null ? null : Timestamp.fromDate(availableFrom!),
        'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
        'maxAttempts': maxAttempts,
        'attemptsUsed': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Editable fields written on an update (identity + createdAt are preserved).
  Map<String, dynamic> toUpdateMap() => {
        'candidateEmail': candidateEmail,
        'candidateEmailLower': candidateEmailLower,
        'candidateName': candidateName,
        'type': type.wire,
        'title': title,
        'prompt': prompt,
        'questions': questions,
        'avatar': avatar.toMap(),
        'durationMinutes': durationMinutes,
        'keyOverrides': keyOverrides,
        'availableFrom':
            availableFrom == null ? null : Timestamp.fromDate(availableFrom!),
        'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
        // attemptsUsed is intentionally omitted so an edit never resets it.
        'maxAttempts': maxAttempts,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
