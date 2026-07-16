// lib/features/interviews/recruiter/evaluate_interview_page.dart
//
// Recruiter reviews a candidate's (unpublished) result — an AI/heuristic draft
// if one was produced, or a blank form for manual evaluation — edits the score,
// summary, recommendation, strengths and improvements, then publishes it to the
// candidate. Publishing sets resultPublished = true on the interview.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

class EvaluateInterviewPage extends StatefulWidget {
  final Interview interview;
  const EvaluateInterviewPage({super.key, required this.interview});

  @override
  State<EvaluateInterviewPage> createState() => _EvaluateInterviewPageState();
}

class _EvaluateInterviewPageState extends State<EvaluateInterviewPage> {
  static const _recommendations = {
    '': 'Not set',
    'strong_yes': 'Strong yes',
    'yes': 'Yes',
    'maybe': 'Maybe',
    'no': 'No',
  };

  final _summaryCtrl = TextEditingController();
  final _strengthsCtrl = TextEditingController();
  final _improvementsCtrl = TextEditingController();
  int _score = 0;
  String _recommendation = '';
  late bool _published;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.interview.result ?? const {};
    _score = (r['overallScore'] as num?)?.round() ?? 0;
    _summaryCtrl.text = (r['summary'] as String?) ?? '';
    _recommendation = _recommendations.containsKey(r['recommendation'])
        ? r['recommendation'] as String
        : '';
    _strengthsCtrl.text = _joinList(r['strengths']);
    _improvementsCtrl.text = _joinList(r['improvements']);
    _published = widget.interview.resultPublished;
  }

  String _joinList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).join('\n') : '';

  List<String> _splitLines(String s) => s
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _strengthsCtrl.dispose();
    _improvementsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildResult() => {
        'overallScore': _score,
        'summary': _summaryCtrl.text.trim(),
        'recommendation': _recommendation,
        'strengths': _splitLines(_strengthsCtrl.text),
        'improvements': _splitLines(_improvementsCtrl.text),
        // Preserve the original AI detail + note that a recruiter touched it.
        'evaluatedBy': 'manual',
        if (widget.interview.result?['detail'] != null)
          'detail': widget.interview.result!['detail'],
        // Preserve the integrity signal captured during the interview.
        if (widget.interview.result?['integrity'] != null)
          'integrity': widget.interview.result!['integrity'],
      };

  Future<void> _save({required bool publish}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<InterviewRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.saveResult(widget.interview.id, _buildResult());
      if (publish) {
        await repo.setPublished(widget.interview.id, true);
        _published = true;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
          content: Text(publish ? 'Result published.' : 'Result saved.')));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _unpublish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<InterviewRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.setPublished(widget.interview.id, false);
      if (!mounted) return;
      setState(() {
        _published = false;
        _saving = false;
      });
      messenger
          .showSnackBar(const SnackBar(content: Text('Result unpublished.')));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = widget.interview;
    final evaluatedBy = (i.result?['evaluatedBy'] as String?) ?? '';
    final leftAppCount =
        ((i.result?['integrity'] as Map?)?['leftAppCount'] as num?)?.toInt() ??
            0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluate'),
        actions: [
          if (_published)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: TextButton.icon(
                  onPressed: _saving ? null : _unpublish,
                  icon: const Icon(Icons.visibility_off, size: 18),
                  label: const Text('Unpublish'),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(i.candidateName ?? i.candidateEmail,
                      style: theme.textTheme.titleLarge),
                  Text(
                      '${i.type.label} · ${i.candidateEmail}'
                      '${evaluatedBy.isEmpty ? '' : ' · ${evaluatedBy == 'ai' ? 'AI draft' : 'edited'}'}',
                      style: theme.textTheme.bodySmall),
                  if (_published)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Icon(Icons.visibility,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Visible to candidate',
                              style: TextStyle(color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                  if (leftAppCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Integrity: left the app $leftAppCount '
                              'time${leftAppCount == 1 ? '' : 's'} during the interview',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('Overall score: $_score / 100',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Slider(
                    value: _score.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '$_score',
                    onChanged: (v) => setState(() => _score = v.round()),
                  ),
                  const SizedBox(height: 8),
                  CustomSelectDropdown<String>(
                    label: 'Recommendation',
                    value: _recommendation,
                    items: _recommendations.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _recommendation = v ?? ''),
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Summary',
                    placeholder: 'Overall assessment…',
                    controller: _summaryCtrl,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Strengths (one per line)',
                    placeholder: 'Clear communication\nStrong problem solving',
                    controller: _strengthsCtrl,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Areas to improve (one per line)',
                    placeholder: 'Could go deeper on system design',
                    controller: _improvementsCtrl,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 28),
                  CustomButton(
                    text: _published ? 'Save changes' : 'Save & publish',
                    isLoading: _saving,
                    onPressed:
                        _saving ? () {} : () => _save(publish: !_published),
                  ),
                  const SizedBox(height: 10),
                  if (!_published)
                    CustomButton(
                      text: 'Save draft (don\'t publish)',
                      variant: ButtonVariant.outline,
                      onPressed: _saving ? () {} : () => _save(publish: false),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
