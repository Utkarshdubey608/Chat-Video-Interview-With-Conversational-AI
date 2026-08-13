// lib/features/interviews/candidate/practice/practice_formatters.dart
//
// Formatting shared by the practice history list and the practice report.
// Extracted so the two screens cannot drift on how a date or a duration reads.

import 'package:intl/intl.dart';

import 'package:talbotiq/shared/models/app_models.dart';

/// "12 Mar 2026, 14:05" from an ISO-8601 string; falls back to the raw value.
String formatAttemptDate(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return DateFormat('d MMM yyyy, HH:mm').format(dt.toLocal());
}

/// Attempt length derived from the transcript's first→last timestamps.
///
/// InterviewResult stores no duration and the entries carry epoch-ms stamps, so
/// this is the only signal available for a completed attempt.
String formatAttemptDuration(List<TranscriptEntry> transcript) {
  if (transcript.length < 2) return '—';
  var min = transcript.first.timestamp;
  var max = transcript.first.timestamp;
  for (final e in transcript) {
    if (e.timestamp < min) min = e.timestamp;
    if (e.timestamp > max) max = e.timestamp;
  }
  final secs = ((max - min) / 1000).round();
  if (secs <= 0) return '—';
  if (secs >= 3600) return '${secs ~/ 3600}h ${(secs % 3600) ~/ 60}m';
  if (secs >= 60) return '${secs ~/ 60}m ${secs % 60}s';
  return '${secs}s';
}

/// A practice-appropriate verdict for a 0-100 score.
///
/// Deliberately NOT the scorecard's `hiringRecommendation`: that is written for a
/// recruiter deciding whether to advance someone. A candidate reviewing their own
/// practice run should read progress, not a hiring verdict.
String practiceVerdict(int score) {
  if (score >= 85) return 'Excellent';
  if (score >= 70) return 'Strong';
  if (score >= 55) return 'Developing';
  if (score > 0) return 'Needs work';
  return 'Not scored';
}

/// 1-10 dimension score → the 0-100 scale the rest of the UI colours by.
int dimensionPercent(int scoreOutOfTen) => (scoreOutOfTen.clamp(0, 10)) * 10;
