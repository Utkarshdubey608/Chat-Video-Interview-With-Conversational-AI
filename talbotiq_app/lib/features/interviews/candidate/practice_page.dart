// lib/features/interviews/candidate/practice_page.dart
//
// Candidate self-serve "Practice with AI" add-on. The candidate enters their own
// Tavus API key and configures their own prompt / questions / avatar, then runs
// the AI avatar for practice. It reuses the same Tavus launch machinery as
// assigned interviews (video_launch.dart) but with no Firestore Interview doc —
// nothing is assigned, tracked, or scored on the recruiter side.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_models.dart';
import '../../../providers/app_store.dart';
import '../../../core/services/tavus_service.dart';
import '../../../views/setup/avatar_picker.dart';
import '../../../widgets/custom_buttons.dart';
import '../../../widgets/custom_inputs.dart';
import '../../recruiter/views/widgets/question_templates_bar.dart';
import 'video_launch.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final _keyController = TextEditingController();
  final _promptController = TextEditingController();
  final _replicaIdController = TextEditingController();
  final _personaIdController = TextEditingController();
  final List<TextEditingController> _questionControllers = [
    TextEditingController(),
  ];
  int _durationMinutes = 10;

  List<TavusReplica> _replicas = const [];
  bool _loadingReplicas = false;
  bool _launching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _promptController.text = DraftForm.defaults().conversationalContext;
    // Prefill with any key already on the device (e.g. pulled org key); the
    // candidate can replace it with their own.
    final existing = context.read<AppStore>().tavusKey;
    if (existing.isNotEmpty) _keyController.text = existing;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _promptController.dispose();
    _replicaIdController.dispose();
    _personaIdController.dispose();
    for (final c in _questionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadReplicas() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter your Tavus API key first.');
      return;
    }
    tavusService.setKey(key);
    setState(() {
      _loadingReplicas = true;
      _error = null;
    });
    try {
      final replicas = await tavusService.listReplicas();
      if (!mounted) return;
      setState(() => _replicas = replicas);
    } catch (e) {
      setState(() => _error = 'Could not load avatars: '
          '${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loadingReplicas = false);
    }
  }

  void _addQuestion() =>
      setState(() => _questionControllers.add(TextEditingController()));

  void _removeQuestion(int i) {
    if (_questionControllers.length == 1) return;
    setState(() => _questionControllers.removeAt(i).dispose());
  }

  /// Replaces the practice questions with a saved template's questions.
  void _applyTemplate(List<String> questions, {String? title}) {
    setState(() {
      for (final c in _questionControllers) {
        c.dispose();
      }
      _questionControllers
        ..clear()
        ..addAll((questions.isEmpty ? [''] : questions)
            .map((q) => TextEditingController(text: q)));
    });
  }

  List<String> get _questions => _questionControllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  String _candidateName() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : 'Candidate';
  }

  Future<void> _launch() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter your Tavus API key.');
      return;
    }
    if (_replicaIdController.text.trim().isEmpty) {
      setState(() => _error = 'Pick or enter an avatar (replica).');
      return;
    }

    setState(() {
      _launching = true;
      _error = null;
    });
    tavusService.setKey(key);

    final config = DraftForm.defaults().copyWith(
      conversationalContext: _promptController.text.trim(),
      replicaId: _replicaIdController.text.trim(),
      personaId: _personaIdController.text.trim(),
      conversationName: 'AI Practice',
      maxCallDuration: _durationMinutes * 60,
    );

    try {
      await launchVideoConversation(
        context: context,
        config: config,
        questions: _questions,
        candidateName: _candidateName(),
        interview: null,
      );
    } catch (e) {
      setState(() => _error = 'Could not start practice: '
          '${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Practice with AI')),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Practice mode uses your own Tavus account and settings. '
                          'Nothing here is assigned by a recruiter or scored.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 20),
                      CustomInputField(
                        label: 'Your Tavus API key',
                        placeholder: 'tavus_...',
                        controller: _keyController,
                        isPassword: true,
                      ),
                      const SizedBox(height: 16),
                      CustomInputField(
                        label: 'Prompt / interviewer instructions',
                        placeholder: 'How the AI should behave…',
                        controller: _promptController,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 20),
                      _buildQuestions(theme),
                      const SizedBox(height: 20),
                      _buildDuration(theme),
                      const SizedBox(height: 20),
                      _buildAvatar(theme),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 28),
                      CustomButton(
                        text: 'Start practice',
                        isLoading: _launching,
                        onPressed: _launching ? () {} : _launch,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_launching)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Questions (optional)',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: QuestionTemplatesBar(
                  currentQuestions: () => _questions,
                  onApply: _applyTemplate,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _questionControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: CustomInputField(
                    label: '',
                    placeholder: 'Question ${i + 1}',
                    controller: _questionControllers[i],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _questionControllers.length == 1
                      ? null
                      : () => _removeQuestion(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addQuestion,
            icon: const Icon(Icons.add),
            label: const Text('Add question'),
          ),
        ),
      ],
    );
  }

  Widget _buildDuration(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Duration: $_durationMinutes min',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        Slider(
          value: _durationMinutes.toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          label: '$_durationMinutes min',
          onChanged: (v) => setState(() => _durationMinutes = v.round()),
        ),
      ],
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Avatar',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            TextButton.icon(
              onPressed: _loadingReplicas ? null : _loadReplicas,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Load avatars'),
            ),
          ],
        ),
        if (_loadingReplicas)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_replicas.isNotEmpty)
          AvatarStrip(
            replicas: _replicas,
            selectedId: _replicaIdController.text.trim(),
            onSelect: (id) => setState(() => _replicaIdController.text = id),
          )
        else
          Text('Enter your key and tap “Load avatars”, or type a replica ID.',
              style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        CustomInputField(
          label: 'Replica ID',
          placeholder: 'r1234...',
          controller: _replicaIdController,
        ),
        const SizedBox(height: 12),
        CustomInputField(
          label: 'Persona ID (optional)',
          placeholder: 'p1234...',
          controller: _personaIdController,
        ),
      ],
    );
  }
}
