// lib/core/utils/date_format.dart
//
// Small shared date/time formatting helper used across candidate + recruiter
// screens, so the same `yyyy-MM-dd HH:mm` rendering isn't re-implemented per
// file.

/// Formats [d] as `yyyy-MM-dd HH:mm` in local time, zero-padded.
String formatDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A coarse, human duration: `3d`, `5h`, `20m`, `<1m`.
///
/// One unit only, deliberately. This reads inside a status chip ("closes in 3d"),
/// where a recruiter wants to know roughly how long is left, not `3d 4h 12m`.
/// Rounds DOWN, so a chip never claims more time than actually remains.
String formatDurationShort(Duration d) {
  if (d.isNegative || d.inMinutes < 1) return '<1m';
  if (d.inDays >= 1) return '${d.inDays}d';
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${d.inMinutes}m';
}
