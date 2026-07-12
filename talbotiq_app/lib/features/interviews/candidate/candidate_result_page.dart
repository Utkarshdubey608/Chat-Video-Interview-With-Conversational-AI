// lib/features/interviews/candidate/candidate_result_page.dart
//
// Read-only view of a candidate's PUBLISHED result for one interview.

import 'package:flutter/material.dart';

import '../models/interview.dart';

class CandidateResultPage extends StatelessWidget {
  final Interview interview;
  const CandidateResultPage({super.key, required this.interview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = interview.result ?? const {};
    final score = (r['overallScore'] as num?)?.round();
    final summary = (r['summary'] as String?) ?? '';
    final recommendation = (r['recommendation'] as String?) ?? '';
    final strengths = _list(r['strengths']);
    final improvements = _list(r['improvements']);

    return Scaffold(
      appBar: AppBar(title: Text(interview.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (score != null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.secondaryContainer,
                        ]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Text('Overall score',
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 6),
                          Text('$score',
                              style: theme.textTheme.displaySmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          Text('out of 100',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  if (recommendation.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _section(theme, 'Recommendation',
                        [_pretty(recommendation)]),
                  ],
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Summary', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(summary, style: theme.textTheme.bodyMedium),
                  ],
                  if (strengths.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _section(theme, 'Strengths', strengths),
                  ],
                  if (improvements.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _section(theme, 'Areas to improve', improvements),
                  ],
                  if (score == null && summary.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text('No result details available.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _list(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  String _pretty(String rec) {
    switch (rec) {
      case 'strong_yes':
        return 'Strong yes';
      case 'yes':
        return 'Yes';
      case 'maybe':
        return 'Maybe';
      case 'no':
        return 'No';
      default:
        return rec;
    }
  }

  Widget _section(ThemeData theme, String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        ...items.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                      child: Text(s, style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
      ],
    );
  }
}
