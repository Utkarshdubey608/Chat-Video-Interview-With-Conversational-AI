// lib/core/utils/date_format.dart
//
// Small shared date/time formatting helper used across candidate + recruiter
// screens, so the same `yyyy-MM-dd HH:mm` rendering isn't re-implemented per
// file.

/// Formats [d] as `yyyy-MM-dd HH:mm` in local time, zero-padded.
String formatDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
