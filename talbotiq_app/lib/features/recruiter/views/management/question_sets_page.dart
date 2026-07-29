// lib/features/recruiter/views/management/question_sets_page.dart
//
// Recruiter-side management: reusable fixed question sets. Lists the sets held
// by [RecruiterStore] and lets the recruiter create, edit, duplicate, and
// delete them. Additive management surface over the already-ported store CRUD
// (upsertQuestionSet / deleteQuestionSet / duplicateQuestionSet); it does not
// touch interview execution.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'generate_from_resume_page.dart';
import 'question_set_editor_page.dart';

class QuestionSetsPage extends StatelessWidget {
  const QuestionSetsPage({super.key});

  Future<void> _openEditor(BuildContext context, {QuestionSet? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionSetEditorPage(existing: existing),
      ),
    );
  }

  Future<void> _delete(BuildContext context, QuestionSet s) async {
    final store = context.read<RecruiterStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete question set?'),
        content: Text('“${s.name}” will be removed. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    store.deleteQuestionSet(s.id);
    messenger.showSnackBar(SnackBar(content: Text('Deleted “${s.name}”.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<RecruiterStore>();
    final sets = [...store.questionSets]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Question sets'),
        actions: [
          IconButton(
            tooltip: 'Generate from résumé',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const GenerateFromResumePage()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New set'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const RecruiterPageHeader(
              kicker: 'Library',
              title: 'Question sets',
              subtitle:
                  'Reusable lists of fixed questions with categories and '
                  'ideal-answer notes.',
            ),
            const SizedBox(height: 20),
            if (sets.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: RecruiterEmptyState(
                  icon: Icons.list_alt_outlined,
                  title: 'No question sets yet',
                  description:
                      'Create a set of fixed questions you can reuse across '
                      'interviews.',
                ),
              )
            else
              for (final s in sets) ...[
                RecruiterPanel(
                  onTap: () => _openEditor(context, existing: s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name.isEmpty ? 'Untitled set' : s.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${s.questions.length} question'
                              '${s.questions.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              _openEditor(context, existing: s);
                              break;
                            case 'duplicate':
                              store.duplicateQuestionSet(s.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Duplicated “${s.name}”.')),
                              );
                              break;
                            case 'delete':
                              _delete(context, s);
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'duplicate', child: Text('Duplicate')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}
