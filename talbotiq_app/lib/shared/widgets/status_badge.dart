// lib/shared/widgets/status_badge.dart
//
// Small pill status indicator for interview/candidate status across the
// desktop redesign (Recent Interviews table, candidate rows, etc.). Colors
// follow the app's existing semantic intent — green for
// completed/published/positive, amber for in-progress, muted gray for
// assigned/neutral — never an arbitrary new color.

import 'package:flutter/material.dart';
import 'package:talbotiq/core/constants/colors.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  /// Derives the badge for an interview the same way the analytics funnel
  /// already classifies it (status, then resultPublished) — not a new
  /// status concept.
  factory StatusBadge.forInterview(Interview interview) {
    if (interview.resultPublished) {
      return const StatusBadge(label: 'Published', color: AppColors.accent);
    }
    switch (interview.status) {
      case InterviewStatus.completed:
        return const StatusBadge(label: 'Completed', color: AppColors.success);
      case InterviewStatus.inProgress:
        return const StatusBadge(label: 'In Progress', color: AppColors.warning);
      case InterviewStatus.assigned:
        return StatusBadge(label: 'Assigned', color: AppColors.textMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
