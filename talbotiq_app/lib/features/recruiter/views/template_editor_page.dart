// lib/features/recruiter/views/template_editor_page.dart
//
// Native port of the recruiter TemplateEditorPage — the multi-section template
// configuration form (Basics / Questions / Timing / Scoring rubric / Branding /
// Integrity) plus a live preview summary. Edits a local copy; Save persists via
// RecruiterStore. Reuses the app's CustomInputField/Select/Slider/Toggle.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_buttons.dart';
import '../../../widgets/custom_inputs.dart';
import '../engine/defaults.dart';
import '../models/recruiter_models.dart';
import '../store/recruiter_store.dart';

class TemplateEditorPage extends StatefulWidget {
  final String templateId;
  const TemplateEditorPage({super.key, required this.templateId});

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  bool _initialized = false;

  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _seniorityController = TextEditingController();
  final _companyController = TextEditingController();
  final _accentController = TextEditingController();
  final _welcomeController = TextEditingController();

  String _track = TrackType.chat;
  String _questionSource = QuestionSource.fixed;
  String? _fixedQuestionSetId;

  int _numberOfQuestions = 5;
  String _difficulty = DifficultyChoice.mixed;
  String _style = QuestionStyle.mix;

  int _prepSeconds = 30;
  int _answerSeconds = 120;
  int _warningSeconds = 15;
  bool _allowSkipPrep = true;
  bool _allowEarlySubmit = true;

  // Conversational-track config (track != chat).
  String _convMode = InterviewMode.conversational;
  int _thinkingSeconds = 30;
  int _perQuestionSeconds = 120;
  bool _allowSkipThinking = true;
  bool _allowFollowUps = false;
  int _maxFollowUps = 1;

  late List<_KpiDraft> _kpis;

  bool _enforceFullscreen = false;
  bool _detectTabSwitch = true;
  bool _disablePaste = true;
  bool _disableCopy = false;
  int _maxTabSwitchWarnings = 3;

  String _createdAt = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final store = Provider.of<RecruiterStore>(context, listen: false);
    final t = store.templateById(widget.templateId);
    if (t != null) _hydrate(t);
  }

  void _hydrate(InterviewTemplate t) {
    _nameController.text = t.name;
    _roleController.text = t.role;
    _seniorityController.text = t.seniority ?? '';
    _companyController.text = t.branding.companyName;
    _accentController.text = t.branding.accentColor;
    _welcomeController.text = t.branding.welcomeMessage ?? '';
    _track = t.track;
    _questionSource = t.questionSource;
    _fixedQuestionSetId = t.fixedQuestionSetId;
    final adaptive = t.adaptive ?? defaultAdaptive(t.role);
    _numberOfQuestions = adaptive.numberOfQuestions;
    _difficulty = adaptive.difficulty;
    _style = adaptive.style ?? QuestionStyle.mix;
    _prepSeconds = t.timing.prepSeconds;
    _answerSeconds = t.timing.answerSeconds;
    _warningSeconds = t.timing.warningThresholdSeconds;
    _allowSkipPrep = t.timing.allowSkipPrep;
    _allowEarlySubmit = t.timing.allowEarlySubmit;
    _convMode = t.mode ?? InterviewMode.conversational;
    final ct = t.conversationTiming ?? defaultConversationTiming();
    _thinkingSeconds = ct.thinkingSeconds;
    _perQuestionSeconds = ct.perQuestionSeconds;
    _allowSkipThinking = ct.allowSkipThinking;
    _allowFollowUps = adaptive.allowFollowUps;
    _maxFollowUps = adaptive.maxFollowUpsPerQuestion;
    _kpis = t.rubric.kpis.map((k) => _KpiDraft.from(k)).toList();
    _enforceFullscreen = t.integrity.enforceFullscreen;
    _detectTabSwitch = t.integrity.detectTabSwitch;
    _disablePaste = t.integrity.disablePasteInAnswers;
    _disableCopy = t.integrity.disableCopy;
    _maxTabSwitchWarnings = t.integrity.maxTabSwitchWarnings;
    _createdAt = t.createdAt;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _seniorityController.dispose();
    _companyController.dispose();
    _accentController.dispose();
    _welcomeController.dispose();
    for (final k in _kpis) {
      k.dispose();
    }
    super.dispose();
  }

  void _save() {
    final store = Provider.of<RecruiterStore>(context, listen: false);
    final now = DateTime.now().toIso8601String();
    final template = InterviewTemplate(
      id: widget.templateId,
      name: _nameController.text.trim().isEmpty
          ? 'Untitled template'
          : _nameController.text.trim(),
      role: _roleController.text.trim().isEmpty
          ? 'Software Engineer'
          : _roleController.text.trim(),
      seniority: _seniorityController.text.trim().isEmpty
          ? null
          : _seniorityController.text.trim(),
      track: _track,
      questionSource: _questionSource,
      fixedQuestionSetId:
          _questionSource == QuestionSource.fixed ? _fixedQuestionSetId : null,
      timing: TimingConfig(
        prepSeconds: _prepSeconds,
        answerSeconds: _answerSeconds,
        allowSkipPrep: _allowSkipPrep,
        allowEarlySubmit: _allowEarlySubmit,
        warningThresholdSeconds: _warningSeconds,
        numberOfQuestions: _questionSource == QuestionSource.adaptive
            ? _numberOfQuestions
            : null,
      ),
      rubric: KpiRubric(kpis: _kpis.map((k) => k.toModel()).toList()),
      integrity: IntegrityConfig(
        enforceFullscreen: _enforceFullscreen,
        detectTabSwitch: _detectTabSwitch,
        disablePasteInAnswers: _disablePaste,
        disableCopy: _disableCopy,
        maxTabSwitchWarnings: _maxTabSwitchWarnings,
        logEvents: true,
      ),
      branding: BrandingConfig(
        companyName: _companyController.text.trim().isEmpty
            ? 'TalbotIQ'
            : _companyController.text.trim(),
        accentColor: _accentController.text.trim().isEmpty
            ? '#0d5c3a'
            : _accentController.text.trim(),
        welcomeMessage: _welcomeController.text.trim().isEmpty
            ? null
            : _welcomeController.text.trim(),
      ),
      mode: _track != TrackType.chat ? _convMode : null,
      conversationTiming: _track != TrackType.chat
          ? ConversationTimingConfig(
              thinkingSeconds: _thinkingSeconds,
              perQuestionSeconds: _perQuestionSeconds,
              allowSkipThinking: _allowSkipThinking,
              allowEarlySubmit: _allowEarlySubmit,
              warningThresholdSeconds: _warningSeconds,
            )
          : null,
      adaptive: _questionSource == QuestionSource.adaptive
          ? defaultAdaptive(_roleController.text.trim()).copyWith(
              difficulty: _difficulty,
              style: _style,
              numberOfQuestions: _numberOfQuestions,
              allowFollowUps: _allowFollowUps,
              maxFollowUpsPerQuestion: _maxFollowUps,
            )
          : null,
      createdAt: _createdAt.isEmpty ? now : _createdAt,
      updatedAt: now,
    );
    store.upsertTemplate(template);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Template saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<RecruiterStore>();
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Template'),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CustomButton(text: 'Save', height: 38, onPressed: _save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard('Basics', [
                  CustomInputField(
                    label: 'Template name',
                    placeholder: 'e.g. Backend Engineer — Screen',
                    controller: _nameController,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Role',
                    placeholder: 'Software Engineer',
                    controller: _roleController,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Seniority',
                    placeholder: 'e.g. Mid, Senior',
                    controller: _seniorityController,
                  ),
                  const SizedBox(height: 16),
                  CustomSelectDropdown<String>(
                    label: 'Track',
                    value: _track,
                    items: TrackType.all
                        .map((t) => DropdownMenuItem(
                            value: t, child: Text(TrackType.label(t))))
                        .toList(),
                    onChanged: (v) => setState(() => _track = v ?? _track),
                  ),
                ]),
                _sectionCard('Questions', [
                  CustomSelectDropdown<String>(
                    label: 'Question source',
                    value: _questionSource,
                    items: const [
                      DropdownMenuItem(
                          value: QuestionSource.fixed,
                          child: Text('Fixed question set')),
                      DropdownMenuItem(
                          value: QuestionSource.adaptive,
                          child: Text('Adaptive (AI-generated)')),
                    ],
                    onChanged: (v) =>
                        setState(() => _questionSource = v ?? _questionSource),
                  ),
                  if (_questionSource == QuestionSource.fixed) ...[
                    const SizedBox(height: 16),
                    CustomSelectDropdown<String>(
                      label: 'Question set',
                      value: _fixedQuestionSetId ??
                          (store.questionSets.isNotEmpty
                              ? store.questionSets.first.id
                              : ''),
                      items: [
                        if (store.questionSets.isEmpty)
                          const DropdownMenuItem(
                              value: '', child: Text('No sets — create one')),
                        ...store.questionSets.map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} (${s.questions.length})',
                                overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) =>
                          setState(() => _fixedQuestionSetId = v),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    CustomSlider(
                      label: 'Number of questions',
                      min: 1,
                      max: 15,
                      divisions: 14,
                      value: _numberOfQuestions.toDouble(),
                      onChanged: (v) =>
                          setState(() => _numberOfQuestions = v.round()),
                    ),
                    const SizedBox(height: 8),
                    CustomSelectDropdown<String>(
                      label: 'Difficulty',
                      value: _difficulty,
                      items: DifficultyChoice.all
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text(_cap(d))))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _difficulty = v ?? _difficulty),
                    ),
                    const SizedBox(height: 16),
                    CustomSelectDropdown<String>(
                      label: 'Question style',
                      value: _style,
                      items: const [
                        DropdownMenuItem(
                            value: QuestionStyle.technical,
                            child: Text('Technical')),
                        DropdownMenuItem(
                            value: QuestionStyle.nonTechnical,
                            child: Text('Non-technical')),
                        DropdownMenuItem(
                            value: QuestionStyle.mix, child: Text('Mix')),
                      ],
                      onChanged: (v) => setState(() => _style = v ?? _style),
                    ),
                  ],
                ]),
                if (_track != TrackType.chat) _convSection(),
                if (_track == TrackType.chat)
                _sectionCard('Timing', [
                  CustomSlider(
                    label: 'Preparation seconds',
                    min: 0,
                    max: 120,
                    divisions: 24,
                    value: _prepSeconds.toDouble(),
                    formatValue: (v) => '${v.round()}s',
                    onChanged: (v) => setState(() => _prepSeconds = v.round()),
                  ),
                  const SizedBox(height: 8),
                  CustomSlider(
                    label: 'Answer seconds',
                    min: 30,
                    max: 300,
                    divisions: 27,
                    value: _answerSeconds.toDouble(),
                    formatValue: (v) => '${v.round()}s',
                    onChanged: (v) =>
                        setState(() => _answerSeconds = v.round()),
                  ),
                  const SizedBox(height: 8),
                  CustomSlider(
                    label: 'Warning threshold',
                    min: 5,
                    max: 30,
                    divisions: 25,
                    value: _warningSeconds.toDouble(),
                    formatValue: (v) => '${v.round()}s',
                    onChanged: (v) =>
                        setState(() => _warningSeconds = v.round()),
                  ),
                  CustomToggle(
                    label: 'Allow skipping prep',
                    description: 'Candidate can start answering early.',
                    checked: _allowSkipPrep,
                    onChanged: (v) => setState(() => _allowSkipPrep = v),
                  ),
                  CustomToggle(
                    label: 'Allow early submit',
                    description: 'Candidate can submit before time runs out.',
                    checked: _allowEarlySubmit,
                    onChanged: (v) => setState(() => _allowEarlySubmit = v),
                  ),
                ]),
                _sectionCard('Scoring rubric', [
                  for (int i = 0; i < _kpis.length; i++)
                    _KpiRow(
                      draft: _kpis[i],
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() {
                        _kpis[i].dispose();
                        _kpis.removeAt(i);
                      }),
                    ),
                  const SizedBox(height: 8),
                  CustomButton(
                    text: 'Add custom KPI',
                    variant: ButtonVariant.outline,
                    height: 40,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => setState(() => _kpis.add(_KpiDraft.blank())),
                  ),
                ]),
                _sectionCard('Branding', [
                  CustomInputField(
                    label: 'Company name',
                    placeholder: 'TalbotIQ',
                    controller: _companyController,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Accent color (hex)',
                    placeholder: '#0d5c3a',
                    controller: _accentController,
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Welcome message',
                    placeholder: 'Shown to the candidate before starting.',
                    controller: _welcomeController,
                    maxLines: 3,
                  ),
                ]),
                _sectionCard('Integrity', [
                  CustomToggle(
                    label: 'Enforce fullscreen',
                    description: 'Immersive mode during the interview.',
                    checked: _enforceFullscreen,
                    onChanged: (v) => setState(() => _enforceFullscreen = v),
                  ),
                  CustomToggle(
                    label: 'Detect app switching',
                    description: 'Log when the app is backgrounded.',
                    checked: _detectTabSwitch,
                    onChanged: (v) => setState(() => _detectTabSwitch = v),
                  ),
                  CustomToggle(
                    label: 'Disable paste in answers',
                    description: 'Prevent pasting into answer fields.',
                    checked: _disablePaste,
                    onChanged: (v) => setState(() => _disablePaste = v),
                  ),
                  CustomToggle(
                    label: 'Disable copy',
                    description: 'Prevent copying question text.',
                    checked: _disableCopy,
                    onChanged: (v) => setState(() => _disableCopy = v),
                  ),
                  const SizedBox(height: 8),
                  CustomSlider(
                    label: 'Max app-switch warnings',
                    min: 0,
                    max: 10,
                    divisions: 10,
                    value: _maxTabSwitchWarnings.toDouble(),
                    onChanged: (v) =>
                        setState(() => _maxTabSwitchWarnings = v.round()),
                  ),
                ]),
                _buildPreview(context, store),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _convSection() {
    final timed = _convMode == InterviewMode.timed;
    return _sectionCard('Conversation', [
      CustomSelectDropdown<String>(
        label: 'Conversation mode',
        value: _convMode,
        items: const [
          DropdownMenuItem(
              value: InterviewMode.conversational,
              child: Text('Conversational (untimed)')),
          DropdownMenuItem(
              value: InterviewMode.timed,
              child: Text('Timed (per-question clock)')),
        ],
        onChanged: (v) => setState(() => _convMode = v ?? _convMode),
      ),
      if (timed) ...[
        const SizedBox(height: 8),
        CustomSlider(
          label: 'Thinking seconds',
          min: 0,
          max: 120,
          divisions: 24,
          value: _thinkingSeconds.toDouble(),
          formatValue: (v) => '${v.round()}s',
          onChanged: (v) => setState(() => _thinkingSeconds = v.round()),
        ),
        const SizedBox(height: 8),
        CustomSlider(
          label: 'Answer seconds (per question)',
          min: 30,
          max: 300,
          divisions: 27,
          value: _perQuestionSeconds.toDouble(),
          formatValue: (v) => '${v.round()}s',
          onChanged: (v) => setState(() => _perQuestionSeconds = v.round()),
        ),
        CustomToggle(
          label: 'Allow skipping thinking time',
          description: 'Candidate can start answering early.',
          checked: _allowSkipThinking,
          onChanged: (v) => setState(() => _allowSkipThinking = v),
        ),
      ],
      if (_questionSource == QuestionSource.adaptive) ...[
        CustomToggle(
          label: 'Allow follow-up questions',
          description: 'The interviewer may drill into an answer before moving on.',
          checked: _allowFollowUps,
          onChanged: (v) => setState(() => _allowFollowUps = v),
        ),
        if (_allowFollowUps)
          CustomSlider(
            label: 'Max follow-ups per question',
            min: 1,
            max: 3,
            divisions: 2,
            value: _maxFollowUps.toDouble(),
            onChanged: (v) => setState(() => _maxFollowUps = v.round()),
          ),
      ],
    ]);
  }

  Widget _buildPreview(BuildContext context, RecruiterStore store) {
    final theme = Theme.of(context);
    final enabledKpis = _kpis.where((k) => k.enabled).toList();
    int questionCount;
    if (_questionSource == QuestionSource.fixed) {
      final set = _fixedQuestionSetId != null
          ? store.questionSetById(_fixedQuestionSetId!)
          : null;
      questionCount = set?.questions.length ?? 0;
    } else {
      questionCount = _numberOfQuestions;
    }
    final totalMin =
        ((questionCount * (_prepSeconds + _answerSeconds)) / 60).ceil();

    return Card(
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Live preview',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _previewRow('Track', TrackType.label(_track)),
            _previewRow('Source',
                _questionSource == QuestionSource.fixed ? 'Fixed set' : 'Adaptive'),
            _previewRow('Questions', '$questionCount'),
            _previewRow('Estimated length', '~$totalMin min'),
            _previewRow('Enabled KPIs', '${enabledKpis.length}'),
            if (_questionSource == QuestionSource.fixed &&
                (_fixedQuestionSetId == null || questionCount == 0))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠ Select a question set with questions.',
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _KpiDraft {
  final String id;
  final TextEditingController label;
  double weight;
  bool enabled;
  final String description;

  _KpiDraft({
    required this.id,
    required this.label,
    required this.weight,
    required this.enabled,
    required this.description,
  });

  factory _KpiDraft.from(KpiDefinition k) => _KpiDraft(
        id: k.id,
        label: TextEditingController(text: k.label),
        weight: k.weight,
        enabled: k.enabled,
        description: k.description,
      );

  factory _KpiDraft.blank() => _KpiDraft(
        id: recruiterId('kpi'),
        label: TextEditingController(text: 'New KPI'),
        weight: 1,
        enabled: true,
        description: '',
      );

  KpiDefinition toModel() => KpiDefinition(
        id: id,
        label: label.text.trim().isEmpty ? 'KPI' : label.text.trim(),
        description: description,
        weight: weight,
        enabled: enabled,
      );

  void dispose() => label.dispose();
}

class _KpiRow extends StatelessWidget {
  final _KpiDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _KpiRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Switch(
            value: draft.enabled,
            onChanged: (v) {
              draft.enabled = v;
              onChanged();
            },
          ),
          Expanded(
            child: TextField(
              controller: draft.label,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.remove, size: 18,
                color: theme.colorScheme.onSurfaceVariant),
            onPressed: () {
              if (draft.weight > 1) {
                draft.weight -= 1;
                onChanged();
              }
            },
          ),
          Text('${draft.weight.round()}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: Icon(Icons.add, size: 18,
                color: theme.colorScheme.onSurfaceVariant),
            onPressed: () {
              draft.weight += 1;
              onChanged();
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: theme.colorScheme.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
