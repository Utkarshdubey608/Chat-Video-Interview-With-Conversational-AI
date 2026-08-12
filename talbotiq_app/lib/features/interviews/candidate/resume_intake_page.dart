// lib/features/interviews/candidate/resume_intake_page.dart
//
// Reusable candidate résumé intake. Lets a candidate attach a résumé (PDF →
// text on the backend, or pasted text) and hands the text to its caller.
//
// Two callers, one screen, because the picking and reviewing is identical and
// only the final action differs:
//
//   * the VIDEO launch flow, when the recruiter enabled "collect résumé" — the
//     text grounds the AI interviewer and is never stored;
//   * a RÉSUMÉ ROUND, where the text is the submission and [onSubmit] posts it
//     for scoring.
//
// (The adaptive chat track has its own equivalent step inside the conversation
// runner, so it does not use this screen.)
//
// [onSubmit] is async and this page STAYS MOUNTED until it completes: a résumé
// round's submit is a network call that can fail, and a candidate who has just
// pasted 4 KB of text must not lose it to a dismissed screen.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/features/interviews/services/resume_service.dart';

/// Minimum résumé length. Matches the backend's own floor on `resumeText`, so a
/// too-short paste is caught here instead of coming back as a 422.
const int kMinResumeChars = 30;

class ResumeIntakePage extends StatefulWidget {
  /// Called with the résumé text when the candidate continues. Awaited, with the
  /// button showing a spinner; throwing shows the message and keeps the text.
  final Future<void> Function(String text) onSubmit;

  /// Optional skip action; when null the résumé is mandatory (no Skip button).
  final VoidCallback? onSkip;

  final String title;
  final String subtitle;

  /// The action's label. "Continue" reads right before an interview; a résumé
  /// round wants "Submit résumé", because that press is the whole round.
  final String submitLabel;

  const ResumeIntakePage({
    super.key,
    required this.onSubmit,
    this.onSkip,
    this.title = 'Your résumé',
    this.subtitle =
        'The interviewer tailors its questions to your background. Upload a PDF résumé or paste the text below.',
    this.submitLabel = 'Continue',
  });

  @override
  State<ResumeIntakePage> createState() => _ResumeIntakePageState();
}

class _ResumeIntakePageState extends State<ResumeIntakePage> {
  final _textCtrl = TextEditingController();
  String? _fileName;
  bool _extracting = false;
  bool _submitting = false;
  bool _truncated = false;
  String? _error;

  /// Either network call in flight. Both buttons are disabled together — picking
  /// a new PDF mid-submit would score one résumé and display another.
  bool get _busy => _extracting || _submitting;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    if (!resumeService.enabled) {
      setState(() => _error =
          'PDF reading is unavailable right now. You can paste your résumé text below instead.');
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
    // Checked again on the server; this one just saves the candidate a slow
    // upload that was always going to be refused.
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() => _error = 'PDF is larger than 10 MB.');
      return;
    }
    setState(() {
      _extracting = true;
      _error = null;
      _truncated = false;
      _fileName = f.name;
    });
    try {
      final extraction = await resumeService.extractText(
        pdfBase64: base64Encode(bytes),
        fileName: f.name,
      );
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _textCtrl.text = extraction.text;
        _truncated = extraction.truncated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _continue() async {
    if (_submitting) return;
    final text = _textCtrl.text.trim();
    if (text.length < kMinResumeChars) {
      setState(() =>
          _error = 'Add at least a few lines of résumé text to continue.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(text);
      // Deliberately no setState on success: the callback usually navigates away,
      // and clearing the spinner on a screen that is being popped is both
      // pointless and a "setState after dispose" waiting to happen.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Hidden mid-submit: skipping after the résumé has already been sent
          // would leave the candidate thinking they had backed out of something
          // that in fact went through.
          if (widget.onSkip != null && !_submitting)
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
                onPressed: _busy ? () {} : _pickPdf,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Résumé text',
                placeholder: 'Paste your résumé text here…',
                controller: _textCtrl,
                maxLines: 10,
              ),
              if (_truncated) ...[
                const SizedBox(height: 12),
                // The server stores and scores a bounded amount of text. Saying
                // so beats letting the candidate believe a 40-page CV was read
                // in full.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your résumé was long, so only the first part was read. '
                        'Trim it above if the most relevant experience is missing.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              CustomButton(
                text: widget.submitLabel,
                isLoading: _submitting,
                onPressed: _busy ? () {} : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
