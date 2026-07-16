// lib/features/interviews/recruiter/create_interview_page.dart
//
// Where a recruiter configures an interview (prompt + questions + avatar) and
// assigns it to a candidate email. This is the new home for the prompt/avatar
// config that previously lived in Settings. Saving writes an `Interview` doc
// to Firestore (see InterviewRepository), scoped to the current recruiter.

import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/core/constants/colors.dart';
import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/core/utils/validators.dart';
import 'package:talbotiq/features/interviews/shared/avatar_picker.dart';
import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/features/auth/auth_service.dart';
import 'package:talbotiq/features/recruiter/views/widgets/question_templates_bar.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/recruiter/voice/voice_catalog.dart';
import 'package:talbotiq/features/recruiter/voice/voice_models.dart';
import 'package:talbotiq/features/recruiter/voice/voice_picker.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

class CreateInterviewPage extends StatefulWidget {
  /// When provided, the page edits this interview instead of creating a new one.
  final Interview? existing;
  const CreateInterviewPage({super.key, this.existing});

  @override
  State<CreateInterviewPage> createState() => _CreateInterviewPageState();
}

class _CreateInterviewPageState extends State<CreateInterviewPage> {
  InterviewType _type = InterviewType.video;

  // Chat track only: adaptive (AI generates résumé-grounded questions) vs the
  // fixed question list. Video always uses the fixed list.
  bool _adaptive = false;
  int _adaptiveNumQuestions = 5;
  bool _adaptiveFollowUps = true;

  // Video track: ask the candidate for a résumé before the call to ground the
  // avatar's questions.
  bool _collectResume = false;

  // Voice track: selected Gemini Live voice + persona.
  String? _voiceName;
  String? _voicePersonaId;

  // Chat proctoring/integrity (enforced by the conversation runner) + branding.
  bool _detectTabSwitch = true;
  bool _disablePaste = true;
  bool _disableCopy = false;
  final _welcomeController = TextEditingController();

  // Chat track: optional per-question countdown timer. When enabled the chat
  // runner runs in timed mode and auto-submits the current answer at zero.
  bool _chatTimerEnabled = false;
  int _chatTimerPerQuestion = 120; // seconds; 30–600
  int _chatTimerThinking = 0; // seconds; 0 = no separate thinking phase
  bool _chatTimerAutoSubmit = true;

  // Interview language (avatar speech + adaptive interviewer).
  String _language = 'English';
  static const List<String> _languages = [
    'English', 'Spanish', 'French', 'German', 'Hindi', 'Portuguese',
    'Italian', 'Japanese', 'Mandarin', 'Arabic', 'Dutch', 'Korean',
  ];

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
  bool _timingAccessExpanded = false;
  bool _keyOverridesExpanded = false;
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
    _adaptive = i.adaptive;
    _collectResume = i.collectResume;
    _language = _languages.contains(i.language) ? i.language : 'English';
    _voiceName = i.voiceName;
    _voicePersonaId = i.voicePersonaId;
    final integ = i.integrity;
    if (integ != null) {
      _detectTabSwitch = integ['detectTabSwitch'] as bool? ?? true;
      _disablePaste = integ['disablePasteInAnswers'] as bool? ?? true;
      _disableCopy = integ['disableCopy'] as bool? ?? false;
    }
    final brand = i.branding;
    if (brand != null) {
      _welcomeController.text = (brand['welcomeMessage'] as String?) ?? '';
    }
    final timer = i.chatTimer;
    if (timer != null) {
      _chatTimerEnabled = timer['enabled'] as bool? ?? false;
      _chatTimerPerQuestion =
          (timer['perQuestionSeconds'] as num?)?.toInt() ?? 120;
      _chatTimerThinking = (timer['thinkingSeconds'] as num?)?.toInt() ?? 0;
      _chatTimerAutoSubmit = timer['autoSubmitOnExpiry'] as bool? ?? true;
    }
    final ac = i.adaptiveConfig;
    if (ac != null) {
      _adaptiveNumQuestions = (ac['numberOfQuestions'] as num?)?.toInt() ?? 5;
      _adaptiveFollowUps = ac['allowFollowUps'] as bool? ?? true;
    }
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
    _welcomeController.dispose();
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

  /// Flattens every cell of an .xlsx workbook to a single text blob so the email
  /// regex can extract addresses regardless of which column they're in.
  String _extractXlsxText(List<int> bytes) {
    try {
      final book = xl.Excel.decodeBytes(bytes);
      final sb = StringBuffer();
      for (final table in book.tables.values) {
        for (final row in table.rows) {
          for (final cell in row) {
            final v = cell?.value;
            if (v != null) sb.write(' ${v.toString()}');
          }
        }
      }
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  /// Bulk-import candidate emails from a CSV or plain-text file. Extracts every
  /// email-shaped token, de-duplicates (case-insensitive) against what's already
  /// entered, fills blank rows first, then appends new ones. (Excel/PDF parsing
  /// is a server-side follow-up; CSV/TXT covers the common export case on-device.)
  Future<void> _importEmails() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx'],
      withData: true,
    );
    if (!mounted) return;
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.first.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')));
      return;
    }

    // .xlsx → flatten every cell to text; csv/txt → decode as UTF-8. The email
    // regex below then pulls addresses out of whatever text we produced.
    String content;
    if (res.files.first.name.toLowerCase().endsWith('.xlsx')) {
      content = _extractXlsxText(bytes);
    } else {
      try {
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        content = String.fromCharCodes(bytes);
      }
    }

    final emailRe = RegExp(
        r"[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+");
    final found = emailRe
        .allMatches(content)
        .map((m) => m.group(0)!.trim())
        .where(Validators.isValidEmail)
        .toList();

    if (found.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No valid email addresses found in that file.')));
      return;
    }

    // De-duplicate against existing entries (case-insensitive), preserving order.
    final existing = _candidateEmails.map((e) => e.toLowerCase()).toSet();
    final seen = <String>{};
    final toAdd = <String>[];
    for (final e in found) {
      final lower = e.toLowerCase();
      if (existing.contains(lower) || !seen.add(lower)) continue;
      toAdd.add(e);
    }
    if (toAdd.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('All emails in that file are already added.')));
      return;
    }

    setState(() {
      for (final email in toAdd) {
        // Reuse the first blank row if there is one, else append.
        final blank = _candidateEmailControllers
            .indexWhere((c) => c.text.trim().isEmpty);
        if (blank >= 0) {
          _candidateEmailControllers[blank].text = email;
        } else {
          _candidateEmailControllers.add(TextEditingController(text: email));
        }
      }
    });
    messenger.showSnackBar(SnackBar(
        content: Text('Added ${toAdd.length} candidate'
            '${toAdd.length == 1 ? '' : 's'} from file.')));
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

  /// True when this is a chat interview set to generate questions adaptively —
  /// the fixed-questions list is then hidden and not required.
  bool get _isAdaptiveChat => _type == InterviewType.chat && _adaptive;

  /// Replaces the question list with a saved template's questions. When the
  /// title is still empty and the template supplied one, it seeds the title too.
  void _applyTemplate(List<String> questions, {String? title}) {
    setState(() {
      for (final c in _questionControllers) {
        c.dispose();
      }
      _questionControllers
        ..clear()
        ..addAll((questions.isEmpty ? [''] : questions)
            .map((q) => TextEditingController(text: q)));
      if (title != null &&
          title.trim().isNotEmpty &&
          _titleController.text.trim().isEmpty) {
        _titleController.text = title.trim();
      }
    });
  }

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
    // Re-entrancy guard set BEFORE any await so a fast double-tap can't run the
    // save (and create duplicate interviews) twice.
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final title = _titleController.text.trim();
    final emails = _candidateEmails;
    final questions = _questions;

    void fail(String message) => setState(() {
          _error = message;
          _saving = false;
        });

    if (title.isEmpty) {
      fail('Give the interview a title.');
      return;
    }
    if (emails.isEmpty) {
      fail('Add at least one candidate email.');
      return;
    }
    final invalidEmails =
        emails.where((e) => !Validators.isValidEmail(e)).toList();
    if (invalidEmails.isNotEmpty) {
      fail('Enter valid candidate email(s): ${invalidEmails.join(', ')}');
      return;
    }
    if (!_isAdaptiveChat && questions.isEmpty) {
      fail('Add at least one question.');
      return;
    }
    if (_type == InterviewType.video &&
        _replicaIdController.text.trim().isEmpty) {
      fail('Pick or enter an avatar (replica) for video.');
      return;
    }

    // The access window stays OPTIONAL (unchanged behaviour). We only reject the
    // actual defect — an interview born already expired — and an inverted
    // window. An `availableFrom` in the past is legitimate ("available since").
    final now = DateTime.now();
    if (_expiresAt != null && !_expiresAt!.isAfter(now)) {
      fail('Expiry must be in the future.');
      return;
    }
    if (_availableFrom != null &&
        _expiresAt != null &&
        !_expiresAt!.isAfter(_availableFrom!)) {
      fail('Expiry must be after the available-from time.');
      return;
    }

    // Make the recruiter aware, before anything is written, that candidates run
    // this test on the recruiter's keys (or the per-test overrides, if set).
    final confirmed = await _confirmKeyUsage();
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _saving = false);
      return;
    }

    final avatar = AvatarConfig(
      replicaId: _replicaIdController.text.trim(),
      personaId: _personaIdController.text.trim().isEmpty
          ? null
          : _personaIdController.text.trim(),
    );
    // Prompt is meaningful for the video (Tavus) and voice tracks.
    final prompt = (_type == InterviewType.video ||
            _type == InterviewType.voice)
        ? _promptController.text.trim()
        : '';

    // De-duplicate by normalized email so a candidate isn't assigned twice.
    final unique = <String, String>{}; // lower → original
    for (final e in emails) {
      unique.putIfAbsent(InterviewRepository.normalizeEmail(e), () => e);
    }

    try {
      final repo = context.read<InterviewRepository>();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _error = 'Your session has expired. Please sign in again.';
            _saving = false;
          });
        }
        return;
      }
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
            questions: _isAdaptiveChat ? const [] : questions,
            adaptive: _isAdaptiveChat,
            adaptiveConfig: _isAdaptiveChat
                ? {
                    'role': title,
                    'numberOfQuestions': _adaptiveNumQuestions,
                    'allowFollowUps': _adaptiveFollowUps,
                    'difficulty': 'mixed',
                    'style': 'mix',
                  }
                : null,
            collectResume: _type == InterviewType.video && _collectResume,
            language: _language,
            voiceName: _type == InterviewType.voice ? _voiceName : null,
            voicePersonaId:
                _type == InterviewType.voice ? _voicePersonaId : null,
            // Integrity + branding are enforced/shown by the chat runner.
            integrity: _type == InterviewType.chat
                ? {
                    'enforceFullscreen': false,
                    'detectTabSwitch': _detectTabSwitch,
                    'disablePasteInAnswers': _disablePaste,
                    'disableCopy': _disableCopy,
                    'maxTabSwitchWarnings': 3,
                    'logEvents': true,
                  }
                : null,
            branding: (_type == InterviewType.chat &&
                    _welcomeController.text.trim().isNotEmpty)
                ? {
                    'companyName': _recruiterName ?? 'TalbotIQ',
                    'accentColor': '#0d5c3a',
                    'welcomeMessage': _welcomeController.text.trim(),
                  }
                : null,
            // Per-question countdown (chat only). Persisted whenever enabled so
            // the chat launch adapter can run the interview in timed mode.
            chatTimer: (_type == InterviewType.chat && _chatTimerEnabled)
                ? {
                    'enabled': true,
                    'perQuestionSeconds':
                        _chatTimerPerQuestion.clamp(30, 600),
                    'thinkingSeconds': _chatTimerThinking.clamp(0, 300),
                    'allowEarlySubmit': true,
                    'warningThresholdSeconds': 15,
                    'autoSubmitOnExpiry': _chatTimerAutoSubmit,
                  }
                : null,
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
      if (mounted) {
        setState(() {
          _error = 'Could not save: $e';
          _saving = false;
        });
      }
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
        title: Text(_isEdit ? 'Edit Interview' : 'Create Interview'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildJobDetailsCard(theme),
                  _buildCandidatesCard(theme),
                  _buildInterviewDesignCard(theme),
                  if (_type == InterviewType.chat) _buildIntegrityBrandingCard(theme),
                  _buildTimingAccessCard(theme),
                  _buildKeyOverridesCard(theme),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  CustomButton(
                    text: _isEdit ? 'Save Changes' : 'Save & Assign Interview',
                    isLoading: _saving,
                    width: double.infinity,
                    onPressed: _saving ? () {} : _save,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(24.0),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 20),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobDetailsCard(ThemeData theme) {
    return _buildFormSection(
      context: context,
      title: 'Interview Basics',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTypeToggle(theme),
          const SizedBox(height: 20),
          CustomInputField(
            label: 'Job Title / Interview Role',
            placeholder: 'e.g. Senior Flutter Engineer — Screen 1',
            controller: _titleController,
          ),
          const SizedBox(height: 16),
          CustomSelectDropdown<String>(
            label: 'Interview Language',
            value: _language,
            items: [
              for (final l in _languages)
                DropdownMenuItem(value: l, child: Text(l)),
            ],
            onChanged: (v) => setState(() => _language = v ?? 'English'),
          ),
          const SizedBox(height: 16),
          CustomSlider(
            label: 'Interview Duration',
            min: 5,
            max: 60,
            divisions: 11,
            value: _durationMinutes.toDouble(),
            formatValue: (v) => '${v.round()} mins',
            onChanged: (v) => setState(() => _durationMinutes = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle(ThemeData theme) {
    final cs = theme.colorScheme;
    Widget seg(InterviewType t, IconData icon, String label, String desc) {
      final selected = _type == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _type = t),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? cs.primary.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? cs.primary : cs.outline.withOpacity(0.12),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: selected ? cs.primary.withOpacity(0.8) : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          seg(InterviewType.video, Icons.videocam_outlined, 'Video', 'AI Video Avatar'),
          const SizedBox(width: 4),
          seg(InterviewType.chat, Icons.chat_bubble_outline, 'Chat', 'AI Chat Screen'),
          const SizedBox(width: 4),
          seg(InterviewType.voice, Icons.record_voice_over_outlined, 'Voice', 'AI Voice Call'),
        ],
      ),
    );
  }

  Widget _buildCandidatesCard(ThemeData theme) {
    return _buildFormSection(
      context: context,
      title: 'Candidates',
      icon: Icons.people_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit
                ? 'The first email remains assigned to this interview; any extra emails are assigned as new interviews.'
                : 'Assign this interview to one or more candidate email addresses.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _buildCandidates(theme),
        ],
      ),
    );
  }

  Widget _buildCandidates(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _candidateEmailControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomInputField(
                    label: 'Candidate ${i + 1}',
                    placeholder: 'candidate${i + 1}@example.com',
                    controller: _candidateEmailControllers[i],
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                if (_candidateEmailControllers.length > 1) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 28), // Align with input field
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => _removeCandidate(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CustomButton(
                text: 'Add Candidate',
                variant: ButtonVariant.outline,
                height: 44,
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addCandidate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomButton(
                text: 'Import File',
                variant: ButtonVariant.outline,
                height: 44,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                onPressed: _importEmails,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInterviewDesignCard(ThemeData theme) {
    final title = _type == InterviewType.video
        ? 'Video Setup'
        : _type == InterviewType.chat
            ? 'Chat Questions'
            : 'Voice & Persona';

    final icon = _type == InterviewType.video
        ? Icons.video_settings_outlined
        : _type == InterviewType.chat
            ? Icons.question_answer_outlined
            : Icons.record_voice_over_outlined;

    return _buildFormSection(
      context: context,
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_type == InterviewType.video) ...[
            CustomInputField(
              label: 'AI Interviewer Instructions / Prompt',
              placeholder: 'e.g. You are a professional tech recruiter. Be encouraging, ask deep technical questions...',
              controller: _promptController,
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            CustomToggle(
              label: 'Collect Resume',
              description: 'Require candidates to upload a resume to ground the avatar\'s questions.',
              checked: _collectResume,
              onChanged: (v) => setState(() => _collectResume = v),
            ),
            const SizedBox(height: 16),
            _buildAvatarSection(theme),
          ] else if (_type == InterviewType.chat) ...[
            _buildQuestionSourceToggle(theme),
            const SizedBox(height: 16),
            if (_isAdaptiveChat) ...[
              Text(
                'The AI interviewer dynamically creates resume-grounded questions. The candidate will upload their resume before starting.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Number of Questions',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildModernStepper(
                    value: _adaptiveNumQuestions,
                    min: 1,
                    max: 15,
                    onChanged: (v) => setState(() => _adaptiveNumQuestions = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CustomToggle(
                label: 'Allow Follow-ups',
                description: 'Let the AI ask conversational follow-up questions based on the candidate\'s responses.',
                checked: _adaptiveFollowUps,
                onChanged: (v) => setState(() => _adaptiveFollowUps = v),
              ),
            ] else ...[
              _buildQuestions(theme),
            ],
          ] else if (_type == InterviewType.voice) ...[
            _buildVoiceConfigSection(theme),
            const SizedBox(height: 16),
            CustomInputField(
              label: 'AI Voice Instructions / Prompt',
              placeholder: 'Describe how the AI voice agent should behave, context of the interview, tone...',
              controller: _promptController,
              maxLines: 5,
            ),
            const SizedBox(height: 20),
            _buildQuestions(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionSourceToggle(ThemeData theme) {
    final cs = theme.colorScheme;
    Widget seg(bool adaptive, String label, String desc, IconData icon) {
      final selected = _adaptive == adaptive;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _adaptive = adaptive),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? cs.primary.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? cs.primary : cs.outline.withOpacity(0.12),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                          color: selected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 9,
                          color: selected ? cs.primary.withOpacity(0.8) : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(false, 'Fixed List', 'Predefined set', Icons.list_alt_outlined),
        const SizedBox(width: 12),
        seg(true, 'Adaptive AI', 'Dynamic resume-based', Icons.auto_awesome_outlined),
      ],
    );
  }

  Widget _buildQuestions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Questions List',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            QuestionTemplatesBar(
              currentQuestions: () => _questions,
              onApply: _applyTemplate,
              includeInterviewTemplates: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < _questionControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomInputField(
                    label: 'Question ${i + 1}',
                    placeholder: 'e.g. Describe a time you resolved a technical challenge.',
                    controller: _questionControllers[i],
                  ),
                ),
                if (_questionControllers.length > 1) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 28), // Align with input field
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => _removeQuestion(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        CustomButton(
          text: 'Add Question',
          variant: ButtonVariant.outline,
          width: double.infinity,
          height: 44,
          icon: const Icon(Icons.add, size: 18),
          onPressed: _addQuestion,
        ),
      ],
    );
  }

  Widget _buildAvatarSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Avatar Video',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingReplicas)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_replicas.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: AvatarStrip(
              replicas: _replicas,
              selectedId: _replicaIdController.text.trim(),
              onSelect: (id) => setState(() => _replicaIdController.text = id),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: Text(
              tavusService.getKey().isEmpty
                  ? 'Add a Tavus API key in Settings to browse avatars, or enter a replica ID manually below.'
                  : 'No avatars loaded. Enter a replica ID manually below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 16),
        CustomInputField(
          label: 'Replica ID',
          placeholder: 'e.g. r1234abc...',
          controller: _replicaIdController,
        ),
        const SizedBox(height: 12),
        CustomInputField(
          label: 'Persona ID (Optional)',
          placeholder: 'e.g. p1234abc...',
          controller: _personaIdController,
        ),
      ],
    );
  }

  Widget _buildVoiceConfigSection(ThemeData theme) {
    final base = VoiceCatalog.defaultVoiceConfig;
    final current = VoiceConfig(
      engine: base.engine,
      personaId: VoiceCatalog.personaById(_voicePersonaId) != null
          ? _voicePersonaId!
          : base.personaId,
      voiceId: VoiceCatalog.voiceById(_voiceName) != null
          ? _voiceName!
          : base.voiceId,
      allowBargeIn: base.allowBargeIn,
      language: base.language,
    );
    final previewKey =
        (_useCustomKeys && _geminiKeyController.text.trim().isNotEmpty)
            ? _geminiKeyController.text.trim()
            : context.read<AppStore>().geminiKey.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Voice & Persona',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.12),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: VoicePicker(
            value: current,
            onChanged: (c) => setState(() {
              _voicePersonaId = c.personaId;
              _voiceName = c.voiceId;
            }),
            previewApiKey: previewKey.isEmpty ? null : previewKey,
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrityBrandingCard(ThemeData theme) {
    return _buildFormSection(
      context: context,
      title: 'Proctoring & Experience',
      icon: Icons.security_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomToggle(
            label: 'Detect Tab Switch',
            description: 'Flag candidate if they leave or switch tabs during the interview.',
            checked: _detectTabSwitch,
            onChanged: (v) => setState(() => _detectTabSwitch = v),
          ),
          const Divider(height: 1),
          CustomToggle(
            label: 'Block Paste',
            description: 'Prevent candidates from pasting text answers.',
            checked: _disablePaste,
            onChanged: (v) => setState(() => _disablePaste = v),
          ),
          const Divider(height: 1),
          CustomToggle(
            label: 'Block Copy',
            description: 'Prevent candidates from copying questions.',
            checked: _disableCopy,
            onChanged: (v) => setState(() => _disableCopy = v),
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: 'Welcome Message (Optional)',
            placeholder: 'Displayed to the candidate before starting the interview...',
            controller: _welcomeController,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildTimingAccessCard(ThemeData theme) {
    final hasChatTimer = _type == InterviewType.chat;

    final List<String> summaryParts = [];
    if (_availableFrom != null || _expiresAt != null) {
      summaryParts.add('Schedule set');
    }
    if (_maxAttempts != null) {
      summaryParts.add('Max $_maxAttempts attempts');
    } else {
      summaryParts.add('Unlimited attempts');
    }
    if (hasChatTimer && _chatTimerEnabled) {
      summaryParts.add('Timed questions');
    }
    final summary = summaryParts.join(' · ');

    return _buildCollapsibleSection(
      context: context,
      title: 'Scheduling & Retries',
      subtitle: summary,
      icon: Icons.schedule_outlined,
      isExpanded: _timingAccessExpanded,
      onToggle: () => setState(() => _timingAccessExpanded = !_timingAccessExpanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Access Window (Optional)',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _buildDateTimeTile(label: 'Accessible From', value: _availableFrom, isExpiry: false),
          const SizedBox(height: 12),
          _buildDateTimeTile(label: 'Expires At', value: _expiresAt, isExpiry: true),
          const SizedBox(height: 20),
          CustomToggle(
            label: 'Limit Candidate Attempts',
            description: 'Control how many attempts a candidate is allowed to complete the interview.',
            checked: _maxAttempts != null,
            onChanged: (v) => setState(() => _maxAttempts = v ? 1 : null),
          ),
          if (_maxAttempts != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.08),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attempts Allowed',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildModernStepper(
                    value: _maxAttempts!,
                    min: 1,
                    max: 10,
                    onChanged: (v) => setState(() => _maxAttempts = v),
                  ),
                ],
              ),
            ),
          ],
          if (hasChatTimer) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Per-Question Countdown Timer',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            CustomToggle(
              label: 'Enable Question Timer',
              description: 'Give candidate a fixed amount of time to think and write their response.',
              checked: _chatTimerEnabled,
              onChanged: (v) => setState(() => _chatTimerEnabled = v),
            ),
            if (_chatTimerEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Answer time per question', style: theme.textTheme.bodyMedium),
                        _buildModernStepper(
                          value: _chatTimerPerQuestion,
                          min: 30,
                          max: 600,
                          step: 30,
                          suffix: 's',
                          onChanged: (v) => setState(() => _chatTimerPerQuestion = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Thinking time before typing', style: theme.textTheme.bodyMedium),
                        _buildModernStepper(
                          value: _chatTimerThinking,
                          min: 0,
                          max: 300,
                          step: 15,
                          suffix: 's',
                          onChanged: (v) => setState(() => _chatTimerThinking = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CustomToggle(
                      label: 'Auto-submit at 0',
                      description: 'Submit candidate\'s current text when time runs out.',
                      checked: _chatTimerAutoSubmit,
                      onChanged: (v) => setState(() => _chatTimerAutoSubmit = v),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDateTimeTile({
    required String label,
    required DateTime? value,
    required bool isExpiry,
  }) {
    final theme = Theme.of(context);
    final isSet = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.15),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isExpiry ? Icons.event_busy_outlined : Icons.event_available_outlined,
            color: isSet ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSet ? formatDateTime(value) : (isExpiry ? 'No expiration date' : 'Available immediately'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSet ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _pickDateTime(isExpiry: isExpiry),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text(isSet ? 'Change' : 'Set'),
          ),
          if (isSet) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() {
                if (isExpiry) {
                  _expiresAt = null;
                } else {
                  _availableFrom = null;
                }
              }),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModernStepper({
    required int value,
    required int min,
    required int max,
    int step = 1,
    String suffix = '',
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget btn(IconData icon, bool enabled, VoidCallback onTap) {
      return Material(
        color: enabled
            ? cs.surfaceContainerHighest.withOpacity(0.3)
            : cs.surfaceContainerHighest.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? cs.primary : cs.onSurfaceVariant.withOpacity(0.3),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(
          Icons.remove,
          value > min,
          () => onChanged((value - step).clamp(min, max)),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '$value$suffix',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ),
        btn(
          Icons.add,
          value < max,
          () => onChanged((value + step).clamp(min, max)),
        ),
      ],
    );
  }

  Widget _buildKeyOverridesCard(ThemeData theme) {
    final summary = _useCustomKeys ? 'Custom keys enabled' : 'Using global settings keys';
    return _buildCollapsibleSection(
      context: context,
      title: 'API Keys Override',
      subtitle: summary,
      icon: Icons.key_outlined,
      isExpanded: _keyOverridesExpanded,
      onToggle: () => setState(() => _keyOverridesExpanded = !_keyOverridesExpanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Optional override for this specific interview. Leave custom keys disabled to use the global keys configured in your Settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CustomToggle(
            label: 'Use Custom Keys',
            description: 'Provide unique API keys for this interview only.',
            checked: _useCustomKeys,
            onChanged: (v) => setState(() => _useCustomKeys = v),
          ),
          if (_useCustomKeys) ...[
            const SizedBox(height: 12),
            CustomInputField(
              label: 'Tavus API Key',
              placeholder: 'Enter Tavus key override',
              controller: _tavusKeyController,
            ),
            const SizedBox(height: 12),
            CustomInputField(
              label: 'Gemini API Key',
              placeholder: 'Enter Gemini key override',
              controller: _geminiKeyController,
            ),
            const SizedBox(height: 12),
            CustomInputField(
              label: 'Hume API Key',
              placeholder: 'Enter Hume key override',
              controller: _humeKeyController,
            ),
            const SizedBox(height: 12),
            CustomInputField(
              label: 'Deepgram API Key',
              placeholder: 'Enter Deepgram key override',
              controller: _deepgramKeyController,
            ),
          ],
        ],
      ),
    );
  }
}
