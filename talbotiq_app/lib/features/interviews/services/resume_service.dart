// lib/features/interviews/services/resume_service.dart
//
// The two résumé calls, wrapped in feature types.
//
// This lives here rather than as typed helpers on BackendClient because that
// class is deliberately transport-only — it knows about auth, JSON and errors and
// nothing about what a résumé is (see its header). Same shape as
// core/services/gemini_service.dart: a module-level singleton, with the backend
// injectable so tests need no Firebase.
//
// Note what is NOT here: no prompt, no criteria, no scoring, and no Firestore
// write. All four are server-side, because a résumé score decides whether someone
// progresses and `firestore.rules` lets a candidate update their own interview
// document — a score this file computed would be a score the candidate could
// choose. See backend `app/resume.py`.

import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/features/interviews/models/resume_submission.dart';

/// What `/api/resume/extract` returns: the text, and whether it was clipped.
class ResumeExtraction {
  final String text;
  final int charCount;

  /// True when the résumé was longer than the server stores. Surfaced so the
  /// candidate is told, rather than silently scored on a partial résumé.
  final bool truncated;

  const ResumeExtraction({
    required this.text,
    required this.charCount,
    this.truncated = false,
  });

  factory ResumeExtraction.fromJson(Map<String, dynamic> json) {
    final text = (json['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw const BackendException(
        'No text could be read from that PDF. You can paste it instead.',
      );
    }
    return ResumeExtraction(
      text: text,
      charCount: (json['charCount'] as num?)?.toInt() ?? text.length,
      truncated: json['truncated'] == true,
    );
  }
}

class ResumeService {
  ResumeService({BackendClient? backend}) : _injectedBackend = backend;

  final BackendClient? _injectedBackend;
  BackendClient get _backend => _injectedBackend ?? backendClient;

  bool get enabled => _backend.isConfigured;

  /// Transcribes a résumé PDF. Stateless — nothing is stored, so the candidate
  /// can read the text and correct it before anything is scored.
  Future<ResumeExtraction> extractText({
    required String pdfBase64,
    String? fileName,
  }) async {
    final json = await _backend.postJson(
      '/api/resume/extract',
      body: {
        'pdfBase64': pdfBase64,
        if (fileName != null && fileName.trim().isNotEmpty)
          'fileName': fileName.trim(),
      },
    );
    return ResumeExtraction.fromJson(json);
  }

  /// Submits a résumé for one interview and returns the stored score.
  ///
  /// The bar it is measured against comes from the round document, server-side —
  /// nothing in this request can change it. The backend also performs the
  /// Firestore write, so a successful return means the recruiter can already see
  /// it.
  Future<ResumeScore> submitForScoring({
    required String interviewId,
    required String resumeText,
    String? fileName,
  }) async {
    final json = await _backend.postJson(
      '/api/resume/score',
      body: {
        'interviewId': interviewId,
        'resumeText': resumeText,
        if (fileName != null && fileName.trim().isNotEmpty)
          'fileName': fileName.trim(),
      },
    );
    final score = ResumeScore.fromMap(json['score'] as Map<String, dynamic>?);
    if (score == null) {
      // The submission may well have been stored; what failed is our ability to
      // show it. Say that rather than implying the résumé was lost.
      throw const BackendException(
        'Your résumé was sent but the score could not be read back. '
        'Check with the recruiter before resubmitting.',
      );
    }
    return score;
  }
}

final resumeService = ResumeService();
