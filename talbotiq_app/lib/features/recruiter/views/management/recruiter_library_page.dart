// lib/features/recruiter/views/management/recruiter_library_page.dart
//
// Recruiter management hub. A single additive entry point (opened from the
// recruiter dashboard app bar) that links to the reusable-config management
// screens. Purely navigational — no interview-execution code is touched.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'gemini_model_page.dart';
import 'generate_from_resume_page.dart';
import 'personas_page.dart';
import 'question_sets_page.dart';
import 'replicas_page.dart';
import 'templates_page.dart';

class RecruiterLibraryPage extends StatelessWidget {
  const RecruiterLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const RecruiterPageHeader(
              kicker: 'Recruiter',
              title: 'Management',
              subtitle:
                  'Reusable configuration for how roles are interviewed and '
                  'scored.',
            ),
            const SizedBox(height: 20),
            _HubTile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Templates',
              subtitle: 'Reusable interview configurations and scoring rubrics.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TemplatesPage()),
              ),
            ),
            _HubTile(
              icon: Icons.list_alt_outlined,
              title: 'Question sets',
              subtitle:
                  'Reusable fixed questions with categories and ideal-answer '
                  'notes.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuestionSetsPage()),
              ),
            ),
            _HubTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Generate from résumé',
              subtitle:
                  'Upload a candidate PDF and generate a tailored question set.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const GenerateFromResumePage()),
              ),
            ),
            _HubTile(
              icon: Icons.tune_outlined,
              title: 'AI model',
              subtitle: 'Choose the Gemini model (Flash / Pro).',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GeminiModelPage()),
              ),
            ),
            _HubTile(
              icon: Icons.face_retouching_natural_outlined,
              title: 'Personas',
              subtitle: 'Interviewer personalities on your Tavus account.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonasPage()),
              ),
            ),
            _HubTile(
              icon: Icons.smart_display_outlined,
              title: 'Replicas',
              subtitle: 'Avatars available on your Tavus account.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReplicasPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RecruiterPanel(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
