// lib/features/recruiter/views/question_sets_page.dart
//
// Native port of the recruiter QuestionSetsPage — manage reusable fixed
// question sets. List + create/duplicate/delete; a pushed editor provides
// rename, add/remove, and drag-to-reorder (ReorderableListView).
// (Résumé → question-set generation arrives in Phase 2.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_buttons.dart';
import '../models/recruiter_models.dart';
import '../store/recruiter_store.dart';
import 'generate_from_resume_modal.dart';
import 'widgets/recruiter_ui.dart';

class QuestionSetsPage extends StatelessWidget {
  const QuestionSetsPage({super.key});

  void _openEditor(BuildContext context, String setId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuestionSetEditorPage(setId: setId)),
    );
  }

  QuestionSet _newSet() {
    final now = DateTime.now().toIso8601String();
    return QuestionSet(
      id: recruiterId('set'),
      name: 'New question set',
      questions: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RecruiterStore>();
    final sets = store.questionSets;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecruiterPageHeader(
            kicker: 'AI Interview',
            title: 'Question Sets',
            subtitle: 'Reusable fixed question lists.',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Generate from résumé',
                  icon: const Icon(Icons.auto_awesome),
                  color: Theme.of(context).colorScheme.secondary,
                  onPressed: () async {
                    final set = await openGenerateFromResume(context);
                    if (set != null && context.mounted) {
                      _openEditor(context, set.id);
                    }
                  },
                ),
                const SizedBox(width: 4),
                CustomButton(
                  text: 'New',
                  height: 40,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () {
                    final s = _newSet();
                    store.upsertQuestionSet(s);
                    _openEditor(context, s.id);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (sets.isEmpty)
            const RecruiterEmptyState(
              icon: Icons.library_books_outlined,
              title: 'No question sets yet',
              description: 'Create a set of fixed questions to reuse across templates.',
            )
          else
            ...sets.map((s) => _SetCard(
                  set: s,
                  onOpen: () => _openEditor(context, s.id),
                  onDuplicate: () => store.duplicateQuestionSet(s.id),
                  onDelete: () => store.deleteQuestionSet(s.id),
                )),
        ],
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  final QuestionSet set;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _SetCard({
    required this.set,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.description_outlined,
            color: theme.colorScheme.primary),
        title: Text(set.name,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('${set.questions.length} question(s)',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Duplicate',
              icon: Icon(Icons.copy, size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
              onPressed: onDuplicate,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline,
                  size: 18, color: theme.colorScheme.error),
              onPressed: onDelete,
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

// ── Editor ──────────────────────────────────────────────────────────────────

class QuestionSetEditorPage extends StatefulWidget {
  final String setId;
  const QuestionSetEditorPage({super.key, required this.setId});

  @override
  State<QuestionSetEditorPage> createState() => _QuestionSetEditorPageState();
}

class _QuestionSetEditorPageState extends State<QuestionSetEditorPage> {
  late TextEditingController _nameController;
  late List<_QuestionDraft> _questions;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final store = Provider.of<RecruiterStore>(context, listen: false);
    final set = store.questionSetById(widget.setId);
    _nameController.text = set?.name ?? 'Question set';
    _questions =
        (set?.questions ?? []).map((q) => _QuestionDraft.from(q)).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    setState(() => _questions.add(_QuestionDraft.blank()));
  }

  void _removeQuestion(int i) {
    setState(() {
      _questions[i].dispose();
      _questions.removeAt(i);
    });
  }

  void _save() {
    final store = Provider.of<RecruiterStore>(context, listen: false);
    final existing = store.questionSetById(widget.setId);
    final now = DateTime.now().toIso8601String();
    final updated = QuestionSet(
      id: widget.setId,
      name: _nameController.text.trim().isEmpty
          ? 'Untitled set'
          : _nameController.text.trim(),
      questions: _questions
          .where((q) => q.text.text.trim().isNotEmpty)
          .map((q) => q.toModel())
          .toList(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    store.upsertQuestionSet(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Question set saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Question Set'),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CustomButton(text: 'Save', height: 38, onPressed: _save),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Set name',
                hintText: 'e.g. Backend Engineer — Screening',
              ),
            ),
          ),
          Expanded(
            child: _questions.isEmpty
                ? RecruiterEmptyState(
                    icon: Icons.edit_note,
                    title: 'No questions',
                    description: 'Add your first question to this set.',
                    action: CustomButton(
                      text: 'Add question',
                      height: 40,
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _addQuestion,
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: _questions.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _questions.removeAt(oldIndex);
                        _questions.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, i) => _QuestionRow(
                      key: ValueKey(_questions[i].id),
                      index: i,
                      draft: _questions[i],
                      onRemove: () => _removeQuestion(i),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _questions.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addQuestion,
              icon: const Icon(Icons.add),
              label: const Text('Add question'),
            ),
    );
  }
}

class _QuestionDraft {
  final String id;
  final TextEditingController text;
  final TextEditingController category;
  final TextEditingController notes;

  _QuestionDraft({
    required this.id,
    required this.text,
    required this.category,
    required this.notes,
  });

  factory _QuestionDraft.from(FixedQuestion q) => _QuestionDraft(
        id: q.id,
        text: TextEditingController(text: q.text),
        category: TextEditingController(text: q.category ?? ''),
        notes: TextEditingController(text: q.idealAnswerNotes ?? ''),
      );

  factory _QuestionDraft.blank() => _QuestionDraft(
        id: recruiterId('q'),
        text: TextEditingController(),
        category: TextEditingController(),
        notes: TextEditingController(),
      );

  FixedQuestion toModel() => FixedQuestion(
        id: id,
        text: text.text.trim(),
        category: category.text.trim().isEmpty ? null : category.text.trim(),
        idealAnswerNotes:
            notes.text.trim().isEmpty ? null : notes.text.trim(),
      );

  void dispose() {
    text.dispose();
    category.dispose();
    notes.dispose();
  }
}

class _QuestionRow extends StatelessWidget {
  final int index;
  final _QuestionDraft draft;
  final VoidCallback onRemove;

  const _QuestionRow({
    super.key,
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_handle,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.14),
                  child: Text('${index + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.close,
                      size: 18, color: theme.colorScheme.error),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextField(
              controller: draft.text,
              maxLines: null,
              decoration: const InputDecoration(hintText: 'Question text'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.category,
                    decoration: const InputDecoration(hintText: 'Category'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.notes,
                    decoration:
                        const InputDecoration(hintText: 'Ideal-answer notes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
