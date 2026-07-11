// lib/features/recruiter/views/templates_page.dart
//
// Native port of the recruiter TemplatesPage — a grid of reusable interview
// templates with create / edit / duplicate / delete.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_buttons.dart';
import '../engine/defaults.dart';
import '../models/recruiter_models.dart';
import '../store/recruiter_store.dart';
import 'template_editor_page.dart';
import 'widgets/recruiter_ui.dart';

class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  InterviewTemplate _newTemplate() {
    final now = DateTime.now().toIso8601String();
    return InterviewTemplate(
      id: recruiterId('tpl'),
      name: 'New template',
      role: 'Software Engineer',
      track: TrackType.chat,
      questionSource: QuestionSource.fixed,
      timing: defaultTiming(),
      rubric: defaultRubric(),
      integrity: defaultIntegrity(),
      branding: defaultBranding(),
      createdAt: now,
      updatedAt: now,
    );
  }

  void _openEditor(BuildContext context, InterviewTemplate template) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateEditorPage(templateId: template.id),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, RecruiterStore store, InterviewTemplate t) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('Permanently delete "${t.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          CustomButton(
            text: 'Delete',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) store.deleteTemplate(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RecruiterStore>();
    final templates = store.templates;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecruiterPageHeader(
            kicker: 'AI Interview',
            title: 'Templates',
            subtitle: 'Reusable interview definitions.',
            action: CustomButton(
              text: 'New',
              height: 40,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                final t = _newTemplate();
                store.upsertTemplate(t);
                _openEditor(context, t);
              },
            ),
          ),
          const SizedBox(height: 20),
          if (templates.isEmpty)
            const RecruiterEmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: 'No templates yet',
              description: 'Create a template to define questions, timing, and scoring.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth > 900
                    ? 3
                    : constraints.maxWidth > 560
                        ? 2
                        : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    mainAxisExtent: 200,
                  ),
                  itemCount: templates.length,
                  itemBuilder: (context, i) => _TemplateCard(
                    template: templates[i],
                    onEdit: () => _openEditor(context, templates[i]),
                    onDelete: () => _confirmDelete(context, store, templates[i]),
                    store: store,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final InterviewTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final RecruiterStore store;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = template.track == TrackType.videoAvatar;
    final kpiCount = template.rubric.kpis.where((k) => k.enabled).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isVideo ? Icons.videocam : Icons.description_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const Spacer(),
                RecruiterBadge(
                  text: template.questionSource == QuestionSource.adaptive
                      ? 'Adaptive'
                      : 'Fixed',
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              template.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${template.role}${template.seniority != null ? ' · ${template.seniority}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Prep ${template.timing.prepSeconds}s · Answer ${template.timing.answerSeconds}s · $kpiCount KPIs',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                CustomButton(
                  text: 'Edit',
                  variant: ButtonVariant.secondary,
                  height: 38,
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: onEdit,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Duplicate',
                  icon: Icon(Icons.copy, size: 18,
                      color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () {
                    // Genuine duplicate: new id + timestamps.
                    final now = DateTime.now().toIso8601String();
                    store.upsertTemplate(InterviewTemplate.fromJson({
                      ...template.toJson(),
                      'id': recruiterId('tpl'),
                      'name': '${template.name} (copy)',
                      'createdAt': now,
                      'updatedAt': now,
                    }));
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: theme.colorScheme.error),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
