// lib/features/interviews/recruiter/create_interview_page.dart
//
// Where a recruiter configures an interview (prompt + questions + avatar) and
// assigns it to a candidate email. This is the new home for the prompt/avatar
// config that previously lived in Settings. Saving writes an `Interview` doc
// to Firestore (see InterviewRepository), scoped to the current recruiter.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_models.dart';
import '../../../views/setup/avatar_picker.dart';
import '../../../core/services/tavus_service.dart';
import '../../../widgets/custom_buttons.dart';
import '../../../widgets/custom_inputs.dart';
import '../../auth/auth_service.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';

class CreateInterviewPage extends StatefulWidget {
  /// When provided, the page edits this interview instead of creating a new one.
  final Interview? existing;
  const CreateInterviewPage({super.key, this.existing});

  @override
  State<CreateInterviewPage> createState() => _CreateInterviewPageState();
}

class _CreateInterviewPageState extends State<CreateInterviewPage> {
  InterviewType _type = InterviewType.video;

  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _replicaIdController = TextEditingController();
  final _personaIdController = TextEditingController();
  final List<TextEditingController> _candidateEmailControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _questionControllers = [
    TextEditingController(),
  ];
  int _durationMinutes = 15;
  DateTime? _availableFrom;
  DateTime? _expiresAt;
  int? _maxAttempts; // null = unlimited

  // Per-test key overrides. When off, candidates run this test on the
  // recruiter's Settings keys; when on, any field filled here is used instead.
  bool _useCustomKeys = false;
  final _tavusKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  final _humeKeyController = TextEditingController();
  final _deepgramKeyController = TextEditingController();

  List<TavusReplica> _replicas = const [];
  bool _loadingReplicas = false;
  bool _saving = false;
  String? _error;
  String? _recruiterName;

  bool get _isEdit => widget.existing != null;

  // Sensible default questions pre-filled on a new interview.
  static const _defaultQuestions = [
    'Tell me about yourself and your background.',
    'Describe a challenging problem you solved recently.',
    'How do you handle pressure and tight deadlines?',
    'Where do you see yourself in 3 years?',
    'Do you have any questions for us?',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _hydrateFrom(existing);
      _recruiterName = existing.recruiterName;
    } else {
      // Pre-fill the prompt with the app's default interviewer prompt and the
      // five default questions.
      _promptController.text = DraftForm.defaults().conversationalContext;
      _questionControllers
        ..clear()
        ..addAll(_defaultQuestions.map((q) => TextEditingController(text: q)));
    }
    // Resolve the recruiter's display name for the candidate screen.
    final user = FirebaseAuth.instance.currentUser;
    _recruiterName ??= user?.displayName;
    if (_recruiterName == null && user != null) {
      context.read<AuthService>().nameFor(user.uid).then((n) {
        if (n != null && mounted) setState(() => _recruiterName = n);
      });
    }
    _loadReplicas();
  }

  void _hydrateFrom(Interview i) {
    _type = i.type;
    _titleController.text = i.title;
    _promptController.text = i.prompt;
    _replicaIdController.text = i.avatar.replicaId;
    _personaIdController.text = i.avatar.personaId ?? '';
    _candidateEmailControllers.first.text = i.candidateEmail;
    _questionControllers.clear();
    for (final q in (i.questions.isEmpty ? [''] : i.questions)) {
      _questionControllers.add(TextEditingController(text: q));
    }
    _durationMinutes = i.durationMinutes;
    _availableFrom = i.availableFrom;
    _expiresAt = i.expiresAt;
    _maxAttempts = i.maxAttempts;
    final ov = i.keyOverrides;
    _useCustomKeys = ov.isNotEmpty;
    _tavusKeyController.text = ov['tavusKey'] ?? '';
    _geminiKeyController.text = ov['geminiKey'] ?? '';
    _humeKeyController.text = ov['humeKey'] ?? '';
    _deepgramKeyController.text = ov['deepgramKey'] ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _replicaIdController.dispose();
    _personaIdController.dispose();
    _tavusKeyController.dispose();
    _geminiKeyController.dispose();
    _humeKeyController.dispose();
    _deepgramKeyController.dispose();
    for (final c in _candidateEmailControllers) {
      c.dispose();
    }
    for (final c in _questionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCandidate() =>
      setState(() => _candidateEmailControllers.add(TextEditingController()));

  void _removeCandidate(int i) {
    if (_candidateEmailControllers.length == 1) return;
    setState(() {
      _candidateEmailControllers.removeAt(i).dispose();
    });
  }

  List<String> get _candidateEmails => _candidateEmailControllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _loadReplicas() async {
    if (tavusService.getKey().isEmpty) return;
    setState(() => _loadingReplicas = true);
    try {
      final replicas = await tavusService.listReplicas();
      if (!mounted) return;
      setState(() => _replicas = replicas);
    } catch (_) {
      // Manual replica-id entry remains available; no hard failure.
    } finally {
      if (mounted) setState(() => _loadingReplicas = false);
    }
  }

  void _addQuestion() =>
      setState(() => _questionControllers.add(TextEditingController()));

  void _removeQuestion(int i) {
    if (_questionControllers.length == 1) return;
    setState(() {
      _questionControllers.removeAt(i).dispose();
    });
  }

  List<String> get _questions => _questionControllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  /// Non-empty per-test key overrides, or an empty map when custom keys are
  /// off. Blank fields are omitted so they fall back to the recruiter's keys.
  Map<String, String> get _keyOverrides {
    if (!_useCustomKeys) return const {};
    final entries = {
      'tavusKey': _tavusKeyController.text.trim(),
      'geminiKey': _geminiKeyController.text.trim(),
      'humeKey': _humeKeyController.text.trim(),
      'deepgramKey': _deepgramKeyController.text.trim(),
    };
    entries.removeWhere((_, v) => v.isEmpty);
    return entries;
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final emails = _candidateEmails;
    final questions = _questions;

    if (title.isEmpty) {
      setState(() => _error = 'Give the interview a title.');
      return;
    }
    if (emails.isEmpty) {
      setState(() => _error = 'Add at least one candidate email.');
      return;
    }
    if (questions.isEmpty) {
      setState(() => _error = 'Add at least one question.');
      return;
    }
    if (_type == InterviewType.video &&
        _replicaIdController.text.trim().isEmpty) {
      setState(() => _error = 'Pick or enter an avatar (replica) for video.');
      return;
    }

    if (_expiresAt != null &&
        _availableFrom != null &&
        !_expiresAt!.isAfter(_availableFrom!)) {
      setState(() => _error = 'Expiry must be after the available-from time.');
      return;
    }

    // Make the recruiter aware, before anything is written, that candidates run
    // this test on the recruiter's keys (or the per-test overrides, if set).
    final confirmed = await _confirmKeyUsage();
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final avatar = AvatarConfig(
      replicaId: _replicaIdController.text.trim(),
      personaId: _personaIdController.text.trim().isEmpty
          ? null
          : _personaIdController.text.trim(),
    );
    // Prompt is only meaningful for the video (Tavus) track.
    final prompt =
        _type == InterviewType.video ? _promptController.text.trim() : '';

    // De-duplicate by normalized email so a candidate isn't assigned twice.
    final unique = <String, String>{}; // lower → original
    for (final e in emails) {
      unique.putIfAbsent(InterviewRepository.normalizeEmail(e), () => e);
    }

    try {
      final repo = context.read<InterviewRepository>();
      final user = FirebaseAuth.instance.currentUser!;
      // All candidates created/added together share one testId.
      final testId = _isEdit
          ? (widget.existing!.testId.isNotEmpty
              ? widget.existing!.testId
              : widget.existing!.id)
          : 'test_${DateTime.now().microsecondsSinceEpoch}';

      Interview build({
        required String id,
        required String email,
        required String emailLower,
        String? candidateName,
        required String recruiterId,
        required String recruiterEmail,
        required InterviewStatus status,
      }) =>
          Interview(
            id: id,
            testId: testId,
            recruiterId: recruiterId,
            recruiterEmail: recruiterEmail,
            recruiterName: _recruiterName,
            candidateEmail: email,
            candidateEmailLower: emailLower,
            candidateName: candidateName,
            type: _type,
            title: title,
            prompt: prompt,
            questions: questions,
            avatar: avatar,
            durationMinutes: _durationMinutes,
            status: status,
            keyOverrides: _keyOverrides,
            availableFrom: _availableFrom,
            expiresAt: _expiresAt,
            maxAttempts: _maxAttempts,
          );

      if (_isEdit) {
        final existing = widget.existing!;
        final entries = unique.entries.toList();
        // First email updates this interview; extras become new interviews.
        final first = entries.first;
        await repo.update(build(
          id: existing.id,
          email: first.value,
          emailLower: first.key,
          candidateName: existing.candidateName,
          recruiterId: existing.recruiterId,
          recruiterEmail: existing.recruiterEmail,
          status: existing.status,
        ));
        for (final e in entries.skip(1)) {
          await repo.create(build(
            id: '',
            email: e.value,
            emailLower: e.key,
            recruiterId: existing.recruiterId,
            recruiterEmail: existing.recruiterEmail,
            status: InterviewStatus.assigned,
          ));
        }
        if (!mounted) return;
        Navigator.of(context).pop();
        final added = entries.length - 1;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added > 0
              ? 'Interview updated; $added more candidate${added == 1 ? '' : 's'} assigned.'
              : 'Interview updated.'),
        ));
        return;
      }

      for (final entry in unique.entries) {
        await repo.create(build(
          id: '',
          email: entry.value,
          emailLower: entry.key,
          recruiterId: user.uid,
          recruiterEmail: user.email ?? '',
          status: InterviewStatus.assigned,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      final n = unique.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Interview assigned to $n candidate${n == 1 ? '' : 's'}.')),
      );
    } catch (e) {
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  /// Confirms, before writing anything, whose API keys this test will consume
  /// when candidates take it. Returns true to proceed.
  Future<bool?> _confirmKeyUsage() {
    final overrides = _keyOverrides;
    final custom = overrides.keys
        .map((k) => const {
              'tavusKey': 'Tavus',
              'geminiKey': 'Gemini',
              'humeKey': 'Hume',
              'deepgramKey': 'Deepgram',
            }[k])
        .whereType<String>()
        .toList();
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Whose keys will this test use?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When a candidate takes or shares this test, it runs on your '
                'API keys — usage is billed to your accounts.',
                style: theme.textTheme.bodyMedium,
              ),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'For this test, the custom key(s) you entered will be used '
                  'instead of your Settings keys: ${custom.join(', ')}.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'The keys from your Settings will be used. To use different '
                  'keys for just this test, turn on "Use custom keys for this '
                  'test" before saving.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_isEdit ? 'Save changes' : 'Save & assign'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDateTime({required bool isExpiry}) async {
    final now = DateTime.now();
    final initial = (isExpiry ? _expiresAt : _availableFrom) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (isExpiry) {
        _expiresAt = picked;
      } else {
        _availableFrom = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEdit ? 'Edit interview' : 'Create interview')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TypeToggle(
                    value: _type,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const SizedBox(height: 20),
                  CustomInputField(
                    label: 'Title',
                    placeholder: 'e.g. Senior Flutter Engineer — Screen 1',
                    controller: _titleController,
                  ),
                  const SizedBox(height: 20),
                  _buildCandidates(theme),
                  // Prompt drives the Tavus avatar; not used by the chat track.
                  if (_type == InterviewType.video) ...[
                    const SizedBox(height: 16),
                    CustomInputField(
                      label: 'Prompt / interviewer instructions',
                      placeholder:
                          'How the AI interviewer should behave, tone, focus…',
                      controller: _promptController,
                      maxLines: 5,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildQuestions(theme),
                  const SizedBox(height: 20),
                  _buildDuration(theme),
                  const SizedBox(height: 20),
                  _buildAccessWindow(theme),
                  const SizedBox(height: 20),
                  _buildAttempts(theme),
                  const SizedBox(height: 20),
                  _buildKeyOverrides(theme),
                  if (_type == InterviewType.video) ...[
                    const SizedBox(height: 20),
                    _buildAvatar(theme),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 28),
                  CustomButton(
                    text: _isEdit ? 'Save changes' : 'Save & assign',
                    isLoading: _saving,
                    onPressed: _saving ? () {} : _save,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidates(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Candidate emails',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
            _isEdit
                ? 'The first email stays assigned to this interview; any extra '
                    'emails are assigned as new interviews.'
                : 'Assign this interview to one or more candidates.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (int i = 0; i < _candidateEmailControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: CustomInputField(
                    label: '',
                    placeholder: 'candidate${i + 1}@example.com',
                    controller: _candidateEmailControllers[i],
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _candidateEmailControllers.length == 1
                      ? null
                      : () => _removeCandidate(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addCandidate,
            icon: const Icon(Icons.add),
            label: const Text('Add candidate'),
          ),
        ),
      ],
    );
  }

  Widget _buildAttempts(ThemeData theme) {
    final limited = _maxAttempts != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Limit attempts',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                      limited
                          ? 'Candidate can take it $_maxAttempts time(s).'
                          : 'Unlimited attempts.',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Switch(
              value: limited,
              onChanged: (v) => setState(() => _maxAttempts = v ? 1 : null),
            ),
          ],
        ),
        if (limited)
          Row(
            children: [
              const Text('Max attempts:'),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: (_maxAttempts ?? 1) <= 1
                    ? null
                    : () => setState(() => _maxAttempts = _maxAttempts! - 1),
              ),
              Text('$_maxAttempts',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: (_maxAttempts ?? 1) >= 10
                    ? null
                    : () => setState(() => _maxAttempts = (_maxAttempts ?? 1) + 1),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildKeyOverrides(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API keys',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.key_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'When candidates take or share this test, it runs on your API '
                  'keys — usage is billed to your accounts. Leave custom keys '
                  'off to use the keys from your Settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Use custom keys for this test',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                      'Override your Settings keys just for this test. Blank '
                      'fields fall back to your Settings keys.',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Switch(
              value: _useCustomKeys,
              onChanged: (v) => setState(() => _useCustomKeys = v),
            ),
          ],
        ),
        if (_useCustomKeys) ...[
          const SizedBox(height: 8),
          CustomInputField(
            label: 'Tavus API key',
            placeholder: 'Used for video interviews',
            controller: _tavusKeyController,
          ),
          const SizedBox(height: 12),
          CustomInputField(
            label: 'Gemini API key',
            placeholder: 'Used for chat scoring & ATS analysis',
            controller: _geminiKeyController,
          ),
          const SizedBox(height: 12),
          CustomInputField(
            label: 'Hume API key',
            placeholder: 'Optional — voice sentiment scoring',
            controller: _humeKeyController,
          ),
          const SizedBox(height: 12),
          CustomInputField(
            label: 'Deepgram API key',
            placeholder: 'Optional — transcription & pace',
            controller: _deepgramKeyController,
          ),
        ],
      ],
    );
  }

  Widget _buildAccessWindow(ThemeData theme) {
    String fmt(DateTime? d) => d == null
        ? 'Not set'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    Widget row(String label, DateTime? value, bool isExpiry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(fmt(value),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _pickDateTime(isExpiry: isExpiry),
              child: Text(value == null ? 'Set' : 'Change'),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() {
                  if (isExpiry) {
                    _expiresAt = null;
                  } else {
                    _availableFrom = null;
                  }
                }),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Access window (optional)',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Candidates can only launch between these times.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        row('Accessible from', _availableFrom, false),
        row('Expires at', _expiresAt, true),
      ],
    );
  }

  Widget _buildQuestions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Questions',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
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
        Text('Avatar',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_loadingReplicas)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_replicas.isNotEmpty)
          AvatarStrip(
            replicas: _replicas,
            selectedId: _replicaIdController.text.trim(),
            onSelect: (id) =>
                setState(() => _replicaIdController.text = id),
          )
        else
          Text(
            tavusService.getKey().isEmpty
                ? 'Add a Tavus API key in Settings to browse avatars, or enter a replica ID below.'
                : 'No avatars loaded. Enter a replica ID below.',
            style: theme.textTheme.bodySmall,
          ),
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

class _TypeToggle extends StatelessWidget {
  final InterviewType value;
  final ValueChanged<InterviewType> onChanged;
  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget seg(InterviewType t, IconData icon) {
      final selected = value == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(t),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(t.label,
                    style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          seg(InterviewType.video, Icons.videocam_outlined),
          seg(InterviewType.chat, Icons.chat_bubble_outline),
        ],
      ),
    );
  }
}
