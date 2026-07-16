// lib/features/interviews/candidate/resume_intake_page.dart
//
// Reusable candidate résumé intake. Lets a candidate attach a résumé (PDF →
// text via Gemini, or pasted text) before an interview so the AI interviewer is
// grounded in their background. Used by the video launch flow when the recruiter
// enabled "collect résumé". (The adaptive chat track has its own equivalent step
// inside the conversation runner, so it does not use this screen.)

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';

class ResumeIntakePage extends StatefulWidget {
  /// Called with the résumé text (min a few lines) when the candidate continues.
  final ValueChanged<String> onReady;

  /// Optional skip action; when null the résumé is mandatory (no Skip button).
  final VoidCallback? onSkip;

  final String title;
  final String subtitle;

  const ResumeIntakePage({
    super.key,
    required this.onReady,
    this.onSkip,
    this.title = 'Your résumé',
    this.subtitle =
        'The interviewer tailors its questions to your background. Upload a PDF résumé or paste the text below.',
  });

  @override
  State<ResumeIntakePage> createState() => _ResumeIntakePageState();
}

class _ResumeIntakePageState extends State<ResumeIntakePage> {
  final _textCtrl = TextEditingController();
  String? _fileName;
  bool _extracting = false;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    if (!recruiterGeminiService.enabled) {
      setState(() => _error =
          'PDF extraction needs the recruiter\'s Gemini key. You can paste your résumé text below instead.');
      return;
    }
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (!mounted) return;
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() => _error = 'PDF is larger than 10 MB.');
      return;
    }
    setState(() {
      _extracting = true;
      _error = null;
      _fileName = f.name;
    });
    try {
      final text = await recruiterGeminiService.extractResumeText(
          pdfBase64: base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _textCtrl.text = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _continue() {
    final text = _textCtrl.text.trim();
    if (text.length < 30) {
      setState(() =>
          _error = 'Add at least a few lines of résumé text to continue.');
      return;
    }
    widget.onReady(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onSkip != null)
            TextButton(onPressed: widget.onSkip, child: const Text('Skip')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.subtitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: _fileName ?? 'Choose PDF résumé',
                variant: ButtonVariant.outline,
                isLoading: _extracting,
                icon: const Icon(Icons.upload_file, size: 18),
                onPressed: _extracting ? () {} : _pickPdf,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Résumé text',
                placeholder: 'Paste your résumé text here…',
                controller: _textCtrl,
                maxLines: 10,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              CustomButton(
                text: 'Continue',
                isLoading: false,
                onPressed: _extracting ? () {} : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
