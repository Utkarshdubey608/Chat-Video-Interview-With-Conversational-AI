// lib/features/interviews/models/resume_submission.dart
//
// A candidate's résumé submission and its AI score, as stored on the interview
// document's `resume` field.
//
// Written ONLY by the backend (`app/routers/resume.py`), with the Admin SDK. The
// app reads it and never writes it — a score decides whether someone progresses,
// and `firestore.rules` lets a candidate update their own interview document, so
// a client-writable score would be a score the candidate chose. There is
// deliberately no `toMap` here.
//
// Parsed defensively for the usual reason a wire model is: the score comes from a
// language model, and an older backend, a partial write or a half-finished
// submission must render as "no score yet" rather than throwing inside a list.

import 'package:cloud_firestore/cloud_firestore.dart';

/// How well the résumé matches, as a coarse bucket beside the number.
enum ResumeVerdict { strongMatch, possible, weak }

extension ResumeVerdictX on ResumeVerdict {
  String get wire {
    switch (this) {
      case ResumeVerdict.strongMatch:
        return 'strong_match';
      case ResumeVerdict.possible:
        return 'possible';
      case ResumeVerdict.weak:
        return 'weak';
    }
  }

  String get label {
    switch (this) {
      case ResumeVerdict.strongMatch:
        return 'Strong match';
      case ResumeVerdict.possible:
        return 'Possible';
      case ResumeVerdict.weak:
        return 'Weak match';
    }
  }

  /// Unknown values fall back by SCORE rather than to a fixed default, so the
  /// chip can never contradict the number printed next to it.
  static ResumeVerdict fromWire(String? v, {int score = 0}) {
    switch (v) {
      case 'strong_match':
        return ResumeVerdict.strongMatch;
      case 'possible':
        return ResumeVerdict.possible;
      case 'weak':
        return ResumeVerdict.weak;
      default:
        if (score >= 70) return ResumeVerdict.strongMatch;
        if (score >= 45) return ResumeVerdict.possible;
        return ResumeVerdict.weak;
    }
  }
}

/// One skill the résumé was judged on.
class ResumeSkillScore {
  final String name;

  /// True when the round listed this as a must-have.
  final bool required;

  /// Evidence strength, 0-100.
  final int score;

  /// The phrase in the résumé that supports this, or why nothing does.
  final String evidence;

  const ResumeSkillScore({
    required this.name,
    this.required = false,
    this.score = 0,
    this.evidence = '',
  });

  factory ResumeSkillScore.fromMap(Map<String, dynamic> m) => ResumeSkillScore(
        name: (m['name'] as String?)?.trim() ?? '',
        required: m['required'] == true,
        score: ((m['score'] as num?)?.toInt() ?? 0).clamp(0, 100),
        evidence: (m['evidence'] as String?)?.trim() ?? '',
      );
}

class ResumeScore {
  /// 0-100. Also mirrored to `result.overallScore` by the backend, which is what
  /// the recruiter's score chip and the round leaderboard sort on.
  final int overallScore;
  final ResumeVerdict verdict;
  final String summary;

  /// Null when the résumé did not evidence a total, or the value was absurd.
  final double? experienceYears;

  final List<String> strengths;

  /// What the résumé failed to evidence.
  final List<String> gaps;

  final List<ResumeSkillScore> skills;

  /// The model that produced this, recorded so an old score is identifiable
  /// after the default model changes.
  final String model;

  const ResumeScore({
    required this.overallScore,
    required this.verdict,
    this.summary = '',
    this.experienceYears,
    this.strengths = const [],
    this.gaps = const [],
    this.skills = const [],
    this.model = '',
  });

  /// Must-have skills first, then by weakest evidence — the recruiter's question
  /// is "what is missing", so the gaps sort to the top.
  List<ResumeSkillScore> get skillsByConcern {
    final sorted = [...skills];
    sorted.sort((a, b) {
      if (a.required != b.required) return a.required ? -1 : 1;
      return a.score.compareTo(b.score);
    });
    return sorted;
  }

  static ResumeScore? fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return null;
    final score = ((m['overallScore'] as num?)?.toInt() ?? 0).clamp(0, 100);
    return ResumeScore(
      overallScore: score,
      verdict: ResumeVerdictX.fromWire(m['verdict'] as String?, score: score),
      summary: (m['summary'] as String?)?.trim() ?? '',
      experienceYears: (m['experienceYears'] as num?)?.toDouble(),
      strengths: _strings(m['strengths']),
      gaps: _strings(m['gaps']),
      skills: [
        for (final s in (m['skills'] as List?) ?? const [])
          if (s is Map<String, dynamic>) ResumeSkillScore.fromMap(s),
      ],
      model: (m['model'] as String?)?.trim() ?? '',
    );
  }

  static List<String> _strings(Object? v) => [
        for (final e in (v as List?) ?? const [])
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
      ];
}

class ResumeSubmission {
  /// The raw extracted text, exactly as it was scored. Surfaced behind a
  /// recruiter-side toggle: a score whose basis cannot be read is not reviewable.
  final String text;
  final int charCount;
  final String? fileName;
  final DateTime? extractedAt;

  /// Null when the résumé was stored but scoring failed — the text is still
  /// worth showing.
  final ResumeScore? score;

  const ResumeSubmission({
    required this.text,
    required this.charCount,
    this.fileName,
    this.extractedAt,
    this.score,
  });

  bool get hasScore => score != null;

  static ResumeSubmission? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final text = (m['text'] as String?) ?? '';
    if (text.trim().isEmpty) return null;
    return ResumeSubmission(
      text: text,
      // Prefer the stored count, but fall back to the text's own length so a
      // partial write cannot show "0 characters" next to a full résumé.
      charCount: (m['charCount'] as num?)?.toInt() ?? text.length,
      fileName: (m['fileName'] as String?)?.trim(),
      extractedAt: (m['extractedAt'] as Timestamp?)?.toDate(),
      score: ResumeScore.fromMap(m['score'] as Map<String, dynamic>?),
    );
  }
}
