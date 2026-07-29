// lib/features/recruiter/views/management/adaptive_params_editor.dart
//
// Reusable editor for an [AdaptiveConfig] (difficulty, style, technical /
// non-technical counts, tone, focus topics, follow-ups). Stateless with an
// onChanged callback so parents own the value. Pure UI over the existing model
// — nothing here touches interview execution or Gemini logic.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';

class AdaptiveParamsEditor extends StatelessWidget {
  final AdaptiveConfig value;
  final ValueChanged<AdaptiveConfig> onChanged;

  const AdaptiveParamsEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return RecruiterPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RecruiterSectionTitle('Adaptive question parameters'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: v.style ?? QuestionStyle.mix,
                  decoration: const InputDecoration(labelText: 'Style'),
                  items: const [
                    DropdownMenuItem(
                        value: QuestionStyle.mix, child: Text('Mix')),
                    DropdownMenuItem(
                        value: QuestionStyle.technical,
                        child: Text('Technical')),
                    DropdownMenuItem(
                        value: QuestionStyle.nonTechnical,
                        child: Text('Non-technical')),
                  ],
                  onChanged: (s) =>
                      onChanged(v.copyWith(style: s ?? v.style)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: v.difficulty,
                  decoration: const InputDecoration(labelText: 'Difficulty'),
                  items: const [
                    DropdownMenuItem(
                        value: DifficultyChoice.mixed, child: Text('Mixed')),
                    DropdownMenuItem(
                        value: DifficultyChoice.easy, child: Text('Easy')),
                    DropdownMenuItem(
                        value: DifficultyChoice.medium, child: Text('Medium')),
                    DropdownMenuItem(
                        value: DifficultyChoice.hard, child: Text('Hard')),
                  ],
                  onChanged: (d) =>
                      onChanged(v.copyWith(difficulty: d ?? v.difficulty)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Stepper(
            label: 'Total questions',
            value: v.numberOfQuestions,
            min: 1,
            max: 30,
            onChanged: (n) => onChanged(v.copyWith(numberOfQuestions: n)),
          ),
          if (v.style != QuestionStyle.nonTechnical)
            _Stepper(
              label: 'Technical count',
              value: v.technicalCount ?? 0,
              min: 0,
              max: 30,
              onChanged: (n) => onChanged(v.copyWith(technicalCount: n)),
            ),
          if (v.style != QuestionStyle.technical)
            _Stepper(
              label: 'Non-technical count',
              value: v.nonTechnicalCount ?? 0,
              min: 0,
              max: 30,
              onChanged: (n) => onChanged(v.copyWith(nonTechnicalCount: n)),
            ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: v.interviewerTone,
            decoration: const InputDecoration(
              labelText: 'Interviewer tone',
              hintText: 'e.g. friendly and professional',
            ),
            onChanged: (t) => onChanged(v.copyWith(interviewerTone: t)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: v.focusTopics.join(', '),
            decoration: const InputDecoration(
              labelText: 'Focus topics (comma-separated)',
              hintText: 'e.g. distributed systems, APIs',
            ),
            onChanged: (t) => onChanged(v.copyWith(
              focusTopics: t
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            )),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow follow-up questions'),
            value: v.allowFollowUps,
            onChanged: (b) => onChanged(v.copyWith(allowFollowUps: b)),
          ),
          if (v.allowFollowUps)
            _Stepper(
              label: 'Max follow-ups per question',
              value: v.maxFollowUpsPerQuestion,
              min: 1,
              max: 5,
              onChanged: (n) =>
                  onChanged(v.copyWith(maxFollowUpsPerQuestion: n)),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
