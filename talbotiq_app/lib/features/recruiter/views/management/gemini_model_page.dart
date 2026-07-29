// lib/features/recruiter/views/management/gemini_model_page.dart
//
// Recruiter-side: choose which Gemini model (Flash / Pro) the recruiter module
// uses for question generation and scoring. UI over the additive
// `recruiterGeminiService.model` / `setModel` accessor — it only swaps the
// model-id string; no prompt, scoring, or request logic is changed.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';

class GeminiModelPage extends StatefulWidget {
  const GeminiModelPage({super.key});

  @override
  State<GeminiModelPage> createState() => _GeminiModelPageState();
}

class _GeminiModelPageState extends State<GeminiModelPage> {
  late String _selected = recruiterGeminiService.model;

  static const _labels = <String, String>{
    'gemini-2.5-flash': 'Flash',
    'gemini-2.5-pro': 'Pro',
  };
  static const _subtitles = <String, String>{
    'gemini-2.5-flash': 'Faster and cheaper — great for most interviews.',
    'gemini-2.5-pro': 'Highest quality reasoning — slower and pricier.',
  };

  Future<void> _select(String m) async {
    await recruiterGeminiService.setModel(m);
    if (!mounted) return;
    setState(() => _selected = recruiterGeminiService.model);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Using ${_labels[m] ?? m}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI model')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const RecruiterPageHeader(
              kicker: 'AI',
              title: 'Gemini model',
              subtitle:
                  'Model used for question generation and interview scoring.',
            ),
            const SizedBox(height: 20),
            for (final m in RecruiterGeminiService.availableModels)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecruiterPanel(
                  onTap: () => _select(m),
                  child: Row(
                    children: [
                      Icon(
                        _selected == m
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _selected == m
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_labels[m] ?? m,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(_subtitles[m] ?? m,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
