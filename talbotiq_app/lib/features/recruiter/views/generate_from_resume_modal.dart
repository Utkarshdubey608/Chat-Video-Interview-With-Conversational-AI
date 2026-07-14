// lib/features/recruiter/views/generate_from_resume_modal.dart
//
// Native port of the recruiter GenerateFromResumeModal — pick a PDF résumé,
// choose style/counts/difficulty, have Gemini generate tailored questions,
// review/edit them, and save as a QuestionSet. The PDF is sent inline to
// Gemini (no local parsing). Requires a Gemini key (from Settings).

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_buttons.dart';
import '../../../widgets/custom_inputs.dart';
import '../models/recruiter_models.dart';
import '../services/recruiter_gemini_service.dart';
import '../store/recruiter_store.dart';

/// Opens the generator; returns the created QuestionSet (or null if cancelled).
Future<QuestionSet?> openGenerateFromResume(BuildContext context) {
  return Navigator.of(context).push<QuestionSet>(
    MaterialPageRoute(builder: (_) => const GenerateFromResumePage()),
  );
}

class GenerateFromResumePage extends StatefulWidget {
  const GenerateFromResumePage({super.key});

  @override
  State<GenerateFromResumePage> createState() => _GenerateFromResumePageState();
}

class _GenerateFromResumePageState extends State<GenerateFromResumePage> {
  Uint8List? _pdfBytes;
  String? _fileName;

  String _style = QuestionStyle.mix;
  int _tech = 8;
  int _nonTech = 8;
  String _difficulty = DifficultyChoice.mixed;
  final _roleCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: 'Résumé-based set');

  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<_GenDraft>? _drafts; // non-null → review step

  @override
  void dispose() {
    _roleCtrl.dispose();
    _nameCtrl.dispose();
    for (final d in _drafts ?? []) {
      d.dispose();
    }
    super.dispose();
  }

  int get _total => resumeQuestionTotal(_style, _tech, _nonTech);

  Future<void> _pickPdf() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }
    if (f.bytes!.lengthInBytes > 10 * 1024 * 1024) {
      setState(() => _error = 'PDF is larger than 10 MB.');
      return;
    }
    setState(() {
      _pdfBytes = f.bytes;
      _fileName = f.name;
      _error = null;
    });
  }

  Future<void> _generate() async {
    if (_pdfBytes == null) {
      setState(() => _error = 'Choose a PDF résumé first.');
      return;
    }
    if (_total < 1 || _total > 25) {
      setState(() => _error = 'Total questions must be between 1 and 25.');
      return;
    }
    if (!recruiterGeminiService.enabled) {
      setState(() => _error =
          'No Gemini key configured. Add your Gemini key in Settings, then try again.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final questions = await recruiterGeminiService.generateQuestionsFromPdf(
        pdfBase64: base64Encode(_pdfBytes!),
        style: _style,
        technicalCount: _tech,
        nonTechnicalCount: _nonTech,
        difficulty: _difficulty,
        role: _roleCtrl.text.trim(),
      );
      if (!mounted) return;
      if (questions.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Gemini returned no questions. Try again or adjust options.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _drafts = questions.map(_GenDraft.from).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _save() {
    // Re-entrancy guard: a rapid double-tap must not create two sets or pop
    // the route more than once.
    if (_saving) return;
    _saving = true;
    final store = Provider.of<RecruiterStore>(context, listen: false);
    final now = DateTime.now().toIso8601String();
    final set = QuestionSet(
      id: recruiterId('set'),
      name: _nameCtrl.text.trim().isEmpty
          ? 'Résumé-based set'
          : _nameCtrl.text.trim(),
      questions: _drafts!
          .where((d) => d.text.text.trim().isNotEmpty)
          .map((d) => d.toFixedQuestion())
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    store.upsertQuestionSet(set);
    Navigator.of(context).pop(set);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = _drafts != null;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(review ? 'Review questions' : 'Generate from résumé'),
        backgroundColor: theme.colorScheme.surface,
        leading: review
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _drafts = null),
              )
            : null,
      ),
      body: SafeArea(
        child: review ? _buildReview(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final keyMissing = !recruiterGeminiService.enabled;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dropzone / file chip
          InkWell(
            onTap: _pickPdf,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                      _pdfBytes == null
                          ? Icons.upload_file
                          : Icons.picture_as_pdf,
                      size: 36,
                      color: theme.colorScheme.primary),
                  const SizedBox(height: 10),
                  Text(
                    _fileName ?? 'Tap to choose a PDF résumé',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          CustomSelectDropdown<String>(
            label: 'Question style',
            value: _style,
            items: const [
              DropdownMenuItem(
                  value: QuestionStyle.technical, child: Text('Technical')),
              DropdownMenuItem(
                  value: QuestionStyle.nonTechnical,
                  child: Text('Non-technical')),
              DropdownMenuItem(value: QuestionStyle.mix, child: Text('Mix')),
            ],
            onChanged: (v) => setState(() => _style = v ?? _style),
          ),
          const SizedBox(height: 16),
          if (_style == QuestionStyle.mix) ...[
            _counter(context, 'Technical questions', _tech,
                (v) => setState(() => _tech = v)),
            const SizedBox(height: 8),
            _counter(context, 'Non-technical questions', _nonTech,
                (v) => setState(() => _nonTech = v)),
          ] else
            _counter(
                context,
                'Number of questions',
                _style == QuestionStyle.technical ? _tech : _nonTech,
                (v) => setState(() {
                      if (_style == QuestionStyle.technical) {
                        _tech = v;
                      } else {
                        _nonTech = v;
                      }
                    })),
          const SizedBox(height: 16),
          CustomSelectDropdown<String>(
            label: 'Difficulty',
            value: _difficulty,
            items: DifficultyChoice.all
                .map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d[0].toUpperCase() + d.substring(1))))
                .toList(),
            onChanged: (v) => setState(() => _difficulty = v ?? _difficulty),
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: 'Role (optional)',
            placeholder: 'e.g. Backend Engineer',
            controller: _roleCtrl,
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: 'Set name',
            placeholder: 'Résumé-based set',
            controller: _nameCtrl,
          ),
          const SizedBox(height: 16),
          Text('Total: $_total question(s)',
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: (_total < 1 || _total > 25)
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant)),
          if (keyMissing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'A Gemini key is required. Add it under Settings → Google Gemini Key.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12, color: const Color(0xFFE4C270)),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Generate questions',
            isLoading: _loading,
            icon: const Icon(Icons.auto_awesome, size: 18),
            onPressed: _loading ? () {} : _generate,
          ),
        ],
      ),
    );
  }

  Widget _counter(
      BuildContext context, String label, int value, ValueChanged<int> onSet) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 0 ? () => onSet(value - 1) : null,
        ),
        Text('$value',
            style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < 25 ? () => onSet(value + 1) : null,
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _nameCtrl,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            decoration: const InputDecoration(labelText: 'Set name'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            itemCount: _drafts!.length,
            itemBuilder: (context, i) {
              final d = _drafts![i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Q${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              children: [
                                _tag(context, d.meta.type),
                                _tag(context, d.meta.difficulty),
                                if (d.meta.skillTag.isNotEmpty)
                                  _tag(context, d.meta.skillTag),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                size: 18, color: theme.colorScheme.error),
                            onPressed: () => setState(() {
                              _drafts!.removeAt(i).dispose();
                            }),
                          ),
                        ],
                      ),
                      TextField(
                        controller: d.text,
                        maxLines: null,
                        decoration:
                            const InputDecoration(hintText: 'Question text'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomButton(
              text: 'Save question set (${_drafts!.length})',
              onPressed: _save,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tag(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.secondary)),
    );
  }
}

class _GenDraft {
  final GeneratedInterviewQuestion meta;
  final TextEditingController text;

  _GenDraft(this.meta, this.text);

  factory _GenDraft.from(GeneratedInterviewQuestion q) =>
      _GenDraft(q, TextEditingController(text: q.text));

  FixedQuestion toFixedQuestion() => FixedQuestion(
        id: recruiterId('q'),
        text: text.text.trim(),
        category: meta.category.isEmpty ? null : meta.category,
        idealAnswerNotes: [
          if (meta.skillTag.isNotEmpty) 'Skill: ${meta.skillTag}',
          'Difficulty: ${meta.difficulty}',
          if (meta.rationale.isNotEmpty) 'Why: ${meta.rationale}',
        ].join(' · '),
      );

  void dispose() => text.dispose();
}
