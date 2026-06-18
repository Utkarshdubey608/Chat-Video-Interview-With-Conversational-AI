// lib/views/setup_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/colors.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/custom_inputs.dart';
import '../widgets/response_widgets.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  // Form controllers
  final _replicaIdController = TextEditingController();
  final _personaIdController = TextEditingController();
  final _convNameController = TextEditingController();
  final _contextController = TextEditingController();
  final _greetingController = TextEditingController();
  final _callbackUrlController = TextEditingController();

  // S3 storage
  final _bucketController = TextEditingController();
  final _regionController = TextEditingController();
  final _roleArnController = TextEditingController();

  // Session Properties
  String _selectedLanguage = 'English';
  String _selectedPipelineMode = 'full';
  double _maxCallDuration = 900.0;
  int _participantLeftTimeout = 60;
  int _participantAbsentTimeout = 300;
  bool _enableRecording = false;
  bool _enableTranscription = true;
  bool _applyConversationOverride = false;
  bool _applyGreenscreen = false;
  final _backgroundUrlController = TextEditingController();

  // Replicas & Personas dropdown options
  List<TavusReplica> _replicas = [];
  List<TavusPersona> _personas = [];
  bool _isLaunching = false;

  // Loading state for replicas/personas fetch
  bool _isLoadingTavus = false;
  String? _tavusLoadError;

  @override
  void initState() {
    super.initState();
    final store = Provider.of<AppStore>(context, listen: false);
    _replicaIdController.text = store.defaultReplicaId;
    _personaIdController.text = store.defaultPersonaId;
    _convNameController.text = 'TalbotIQ Interview';
    _contextController.text =
        'You are Alex, a Senior Talent Specialist at TalbotIQ conducting a screening interview. Maintain a warm, professional tone.';
    _greetingController.text = 'Hello, welcome to your TalbotIQ interview.';
    _loadApis();
  }

  @override
  void dispose() {
    _replicaIdController.dispose();
    _personaIdController.dispose();
    _convNameController.dispose();
    _contextController.dispose();
    _greetingController.dispose();
    _callbackUrlController.dispose();
    _bucketController.dispose();
    _regionController.dispose();
    _roleArnController.dispose();
    _backgroundUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadApis() async {
    final key = Provider.of<AppStore>(context, listen: false).tavusKey;
    if (key.isEmpty) {
      setState(() {
        _tavusLoadError = 'No Tavus API key set. Add it in Settings to load replicas & personas.';
      });
      return;
    }

    setState(() {
      _isLoadingTavus = true;
      _tavusLoadError = null;
    });

    try {
      tavusService.setKey(key);
      final results = await Future.wait([
        tavusService.listReplicas(),
        tavusService.listPersonas(),
      ]);
      if (!mounted) return;
      setState(() {
        _replicas = results[0] as List<TavusReplica>;
        _personas = results[1] as List<TavusPersona>;
        _isLoadingTavus = false;
      });
    } catch (e) {
      debugPrint('Failed to load Tavus replicas/personas: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingTavus = false;
        _tavusLoadError = 'Failed to load replicas/personas: $e';
      });
    }
  }

  // Helper to build the same JSON request preview payload sent to Tavus
  Map<String, dynamic> _buildPayload(String candidateName) {
    final store = Provider.of<AppStore>(context, listen: false);
    final validQs = store.questions.where((q) => q.trim().isNotEmpty).toList();
    
    // Numbered questions list
    String numbered = '';
    for (int i = 0; i < validQs.length; i++) {
      numbered += '${i + 1}. ${validQs[i]}\n';
    }

    final systemPrompt = _contextController.text.trim().isNotEmpty
        ? _contextController.text.trim()
        : 'You are Alex, a Senior Talent Specialist at TalbotIQ conducting a screening interview with $candidateName. Maintain a warm, professional tone.';

    final finalContext = '''
$systemPrompt

INTERVIEW SCRIPT — STRICT RULES:
- Ask ONLY the questions listed below, exactly as written, in this exact order.
- Ask one question at a time and wait for $candidateName to fully finish answering before moving to the next.
- Do NOT invent, add, skip, reorder, or rephrase any questions.
- Do NOT ask any follow-up questions that are not in this list.
- After the final question, briefly thank $candidateName and end the interview.

QUESTIONS:
$numbered''';

    final greeting = _greetingController.text.trim().isNotEmpty
        ? _greetingController.text.trim()
        : "Hello $candidateName, welcome to your TalbotIQ interview. I'm excited to learn more about you today. Are you ready to begin?";

    final Map<String, dynamic> body = {
      'replica_id': _replicaIdController.text.trim(),
      'conversation_name': 'TalbotIQ — $candidateName',
      'conversational_context': finalContext,
      'custom_greeting': greeting,
    };

    if (_personaIdController.text.trim().isNotEmpty) {
      body['persona_id'] = _personaIdController.text.trim();
    }
    if (_callbackUrlController.text.trim().isNotEmpty) {
      body['callback_url'] = _callbackUrlController.text.trim();
    }

    // Properties
    final Map<String, dynamic> props = {
      'max_call_duration': _maxCallDuration.round(),
      'participant_left_timeout': _participantLeftTimeout,
      'enable_recording': _enableRecording,
      'enable_transcription': _enableTranscription,
    };

    if (_selectedLanguage != 'English') {
      props['language'] = _selectedLanguage;
    }
    if (_participantAbsentTimeout != 300) {
      props['participant_absent_timeout'] = _participantAbsentTimeout;
    }
    if (_applyConversationOverride) {
      props['apply_conversation_override'] = true;
    }
    if (_applyGreenscreen) {
      props['apply_greenscreen'] = true;
      if (_backgroundUrlController.text.trim().isNotEmpty) {
        props['background_url'] = _backgroundUrlController.text.trim();
      }
    }
    if (_enableRecording) {
      if (_bucketController.text.trim().isNotEmpty) {
        props['recording_s3_bucket_name'] = _bucketController.text.trim();
      }
      if (_regionController.text.trim().isNotEmpty) {
        props['recording_s3_bucket_region'] = _regionController.text.trim();
      }
      if (_roleArnController.text.trim().isNotEmpty) {
        props['aws_assume_role_arn'] = _roleArnController.text.trim();
      }
    }

    body['properties'] = props;
    return body;
  }

  void _resetHumeState(AppStore store) {
    store.setHumeJobId(null);
    store.setHumeJobStatus(null);
    store.setHumeResult(null);
    store.resetQuestionTimestamps();
    store.setLiveEmotions([]);
    store.setHumeStreamActive(false);
    store.clearSessionTranscript();
    store.updateMetrics(conf: 0, anx: 0, w: 0, f: 0, eng: 0);
  }

  Future<void> _confirmLaunch(String candidateName) async {
    if (candidateName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a display name'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_replicaIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or enter a Replica ID to start a session'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLaunching = true);
    try {
      final store = Provider.of<AppStore>(context, listen: false);
      final payload = _buildPayload(candidateName);
      
      final conv = await tavusService.createConversation(payload);
      
      _resetHumeState(store);
      store.setCurrentConversation(conv);
      store.setInterviewActive(true);
      store.setCurrentQuestionIdx(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Session created!'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
        store.navigateTo('/interview');
      }
    } catch (e) {
      if (mounted) {
        _showTavusErrorDialog(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showLaunchDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Confirm Session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the candidate\'s name to personalise this interview session.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Candidate Name *',
                placeholder: 'e.g. Arjun Kumar',
                controller: textController,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            CustomButton(
              text: 'Launch Interview',
              onPressed: () {
                final name = textController.text;
                Navigator.pop(context);
                _confirmLaunch(name);
              },
            ),
          ],
        );
      },
    );
  }

  void _showSaveDraftDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Save Draft'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Give this draft a name so you can find it later.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Draft Name *',
                placeholder: 'e.g. Senior Engineer Screen',
                controller: textController,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            CustomButton(
              text: 'Save',
              onPressed: () {
                final name = textController.text;
                if (name.trim().isEmpty) return;
                
                final store = Provider.of<AppStore>(context, listen: false);
                final form = DraftForm(
                  replicaId: _replicaIdController.text,
                  personaId: _personaIdController.text,
                  conversationName: _convNameController.text,
                  conversationalContext: _contextController.text,
                  customGreeting: _greetingController.text,
                  callbackUrl: _callbackUrlController.text,
                  maxCallDuration: _maxCallDuration.round(),
                  participantLeftTimeout: _participantLeftTimeout,
                  participantAbsentTimeout: _participantAbsentTimeout,
                  enableRecording: _enableRecording,
                  enableTranscription: _enableTranscription,
                  applyConversationOverride: _applyConversationOverride,
                  applyGreenscreen: _applyGreenscreen,
                  backgroundUrl: _backgroundUrlController.text,
                  language: _selectedLanguage,
                  pipelineMode: _selectedPipelineMode,
                  recordingS3BucketName: _bucketController.text,
                  recordingS3BucketRegion: _regionController.text,
                  awsAssumeRoleArn: _roleArnController.text,
                );

                store.saveDraft(name.trim(), form, store.questions);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Draft "$name" saved successfully'),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showTavusErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withOpacity(0.12), 
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.error, color: theme.colorScheme.error, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tavus API Error',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.04),
                  border: Border.all(color: theme.colorScheme.error.withOpacity(0.12)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'To launch standard conversational sessions, make sure you configure a valid API key in settings.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Try Again',
                      variant: ButtonVariant.secondary,
                      onPressed: () {
                        Navigator.pop(context);
                        _showLaunchDialog();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CustomButton(
                      text: 'Dismiss',
                      variant: ButtonVariant.ghost,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _loadDraft(Draft draft) {
    final form = draft.form;
    setState(() {
      _replicaIdController.text = form.replicaId;
      _personaIdController.text = form.personaId;
      _convNameController.text = form.conversationName;
      _contextController.text = form.conversationalContext;
      _greetingController.text = form.customGreeting;
      _callbackUrlController.text = form.callbackUrl;
      _bucketController.text = form.recordingS3BucketName;
      _regionController.text = form.recordingS3BucketRegion;
      _roleArnController.text = form.awsAssumeRoleArn;
      _selectedLanguage = form.language;
      _selectedPipelineMode = form.pipelineMode;
      _maxCallDuration = form.maxCallDuration.toDouble();
      _participantLeftTimeout = form.participantLeftTimeout;
      _participantAbsentTimeout = form.participantAbsentTimeout;
      _enableRecording = form.enableRecording;
      _enableTranscription = form.enableTranscription;
      _applyConversationOverride = form.applyConversationOverride;
      _applyGreenscreen = form.applyGreenscreen;
      _backgroundUrlController.text = form.backgroundUrl;
    });

    final store = Provider.of<AppStore>(context, listen: false);
    store.setQuestions(draft.questions);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded draft "${draft.name}"'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildSavedDrafts(AppStore store) {
    if (store.drafts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Drafts',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${store.drafts.length} draft(s) — click to load',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: store.drafts.length,
                itemBuilder: (context, index) {
                  final draft = store.drafts[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () => _loadDraft(draft),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        width: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    draft.name,
                                    style: TextStyle(
                                      fontSize: 13, 
                                      fontWeight: FontWeight.bold, 
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${draft.questions.length} questions',
                                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              onPressed: () {
                                store.deleteDraft(draft.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Draft deleted')),
                                );
                              },
                              hoverColor: theme.colorScheme.error.withOpacity(0.08),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTavusConfigCard() {
    final theme = Theme.of(context);
    final replicaOptions = [
      const DropdownMenuItem<String>(value: '', child: Text('Select a Replica')),
      ..._replicas.map((r) => DropdownMenuItem<String>(
            value: r.replicaId,
            child: Text(
              '${r.replicaName} (${r.replicaType == 'stock' ? '[Stock] ' : ''}${r.status})',
              overflow: TextOverflow.ellipsis,
            ),
          )),
    ];

    final personaOptions = [
      const DropdownMenuItem<String>(value: '', child: Text('None')),
      ..._personas.map((p) => DropdownMenuItem<String>(
            value: p.personaId,
            child: Text(p.personaName, overflow: TextOverflow.ellipsis),
          )),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tavus Configuration',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLoadingTavus)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    color: theme.colorScheme.onSurfaceVariant,
                    tooltip: 'Reload replicas & personas',
                    onPressed: _loadApis,
                  ),
              ],
            ),
            Text(
              _isLoadingTavus
                  ? 'Loading replicas & personas from Tavus…'
                  : 'Avatar and persona selection for this session',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            if (_tavusLoadError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tavusLoadError!,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            _buildResponsiveInputRow(
              context,
              [
                Expanded(
                  child: CustomSelectDropdown<String>(
                    label: 'Replica (optional)',
                    value: _replicas.any((r) => r.replicaId == _replicaIdController.text)
                        ? _replicaIdController.text
                        : '',
                    items: replicaOptions,
                    onChanged: (val) => setState(() => _replicaIdController.text = val ?? ''),
                  ),
                ),
                Expanded(
                  child: CustomSelectDropdown<String>(
                    label: 'Persona',
                    value: _personas.any((p) => p.personaId == _personaIdController.text)
                        ? _personaIdController.text
                        : '',
                    items: personaOptions,
                    onChanged: (val) => setState(() => _personaIdController.text = val ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'Replica ID (Manual Override)',
              placeholder: 'e.g. r5f0577fc829',
              controller: _replicaIdController,
              hint: _replicaIdController.text.isNotEmpty
                  ? '✓ Replica ID: ${_replicaIdController.text}'
                  : '${_replicas.length} replicas found',
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'Conversation Name',
              placeholder: 'e.g. Senior Front-End Engineer Screening',
              controller: _convNameController,
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'Conversational Context (System Prompt)',
              placeholder: 'Type prompt settings…',
              controller: _contextController,
              maxLines: 4,
              hint: 'This prompt drives the Tavus avatar Conversational AI Agent.',
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'Custom Greeting',
              placeholder: 'Hello! I\'m Alex…',
              controller: _greetingController,
              hint: 'The very first thing the avatar says when the session starts',
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'Callback Webhook URL',
              placeholder: 'https://api.yourcompany.com/tavus-events',
              controller: _callbackUrlController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionsCard(AppStore store) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interview Questions',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${store.questions.length} questions configured',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 16),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: store.questions.length,
              itemBuilder: (context, idx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12), 
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: store.questions[idx])
                            ..selection = TextSelection.collapsed(offset: store.questions[idx].length),
                          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Question ${idx + 1}',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onChanged: (val) {
                            final qs = List<String>.from(store.questions);
                            qs[idx] = val;
                            store.setQuestions(qs);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () {
                          final qs = List<String>.from(store.questions);
                          qs.removeAt(idx);
                          store.setQuestions(qs);
                        },
                        hoverColor: theme.colorScheme.error.withOpacity(0.08),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                final qs = List<String>.from(store.questions)..add('');
                store.setQuestions(qs);
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3)),
                minimumSize: const Size(double.infinity, 48), // MD3 touch target size
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              ),
              child: Text(
                '+ Add Question',
                style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionPropertiesCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Properties',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'All values map to the Tavus conversation properties object',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 20),

            _buildResponsiveInputRow(
              context,
              [
                Expanded(
                  child: CustomSelectDropdown<String>(
                    label: 'Language',
                    value: _selectedLanguage,
                    items: [
                      'English', 'Spanish', 'French', 'German', 'Italian',
                      'Portuguese', 'Japanese', 'Korean', 'Chinese', 'Hindi', 'Arabic'
                    ].map((l) => DropdownMenuItem<String>(value: l, child: Text(l))).toList(),
                    onChanged: (val) => setState(() => _selectedLanguage = val ?? 'English'),
                  ),
                ),
                Expanded(
                  child: CustomSelectDropdown<String>(
                    label: 'Pipeline Mode',
                    value: _selectedPipelineMode,
                    items: const [
                      DropdownMenuItem(value: 'full', child: Text('Full (audio+video)')),
                      DropdownMenuItem(value: 'echo', child: Text('Echo (test mode)')),
                      DropdownMenuItem(value: 'no_audio', child: Text('No Audio')),
                      DropdownMenuItem(value: 'video_only', child: Text('Video Only')),
                    ],
                    onChanged: (val) => setState(() => _selectedPipelineMode = val ?? 'full'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            CustomSlider(
              label: 'Max Call Duration',
              min: 60.0,
              max: 7200.0,
              divisions: 119,
              value: _maxCallDuration,
              onChanged: (val) => setState(() => _maxCallDuration = val),
              formatValue: (val) => '${(val / 60).round()} mins',
            ),
            const SizedBox(height: 16),

            _buildResponsiveInputRow(
              context,
              [
                Expanded(
                  child: CustomInputField(
                    label: 'Participant Left Timeout (s)',
                    placeholder: '60',
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _participantLeftTimeout = int.tryParse(val) ?? 60,
                    controller: TextEditingController(text: '$_participantLeftTimeout')
                      ..selection = TextSelection.collapsed(offset: '$_participantLeftTimeout'.length),
                  ),
                ),
                Expanded(
                  child: CustomInputField(
                    label: 'Absent Timeout (s)',
                    placeholder: '300',
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _participantAbsentTimeout = int.tryParse(val) ?? 300,
                    controller: TextEditingController(text: '$_participantAbsentTimeout')
                      ..selection = TextSelection.collapsed(offset: '$_participantAbsentTimeout'.length),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
            const SizedBox(height: 8),

            CustomToggle(
              label: 'Enable Transcription',
              description: 'Real-time transcription of candidate speech',
              checked: _enableTranscription,
              onChanged: (val) => setState(() => _enableTranscription = val),
            ),
            CustomToggle(
              label: 'Enable Recording',
              description: 'Save the full session video to storage',
              checked: _enableRecording,
              onChanged: (val) => setState(() => _enableRecording = val),
            ),
            CustomToggle(
              label: 'Conversation Override',
              description: 'Allow text injection prompt updates during call',
              checked: _applyConversationOverride,
              onChanged: (val) => setState(() => _applyConversationOverride = val),
            ),
            CustomToggle(
              label: 'Virtual Background',
              description: 'Replace avatar background image',
              checked: _applyGreenscreen,
              onChanged: (val) => setState(() => _applyGreenscreen = val),
            ),
            if (_applyGreenscreen) ...[
              const SizedBox(height: 8),
              CustomInputField(
                label: 'Background Image URL',
                placeholder: 'https://cdn.example.com/office.jpg',
                controller: _backgroundUrlController,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildS3StorageCard() {
    if (!_enableRecording) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'S3 Recording Storage',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Configure AWS S3 bucket details to preserve session recording',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 20),

            _buildResponsiveInputRow(
              context,
              [
                Expanded(
                  child: CustomInputField(
                    label: 'Bucket Name',
                    placeholder: 'my-talbotiq-bucket',
                    controller: _bucketController,
                  ),
                ),
                Expanded(
                  child: CustomInputField(
                    label: 'Region',
                    placeholder: 'us-east-1',
                    controller: _regionController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            CustomInputField(
              label: 'AWS Assume Role ARN',
              placeholder: 'arn:aws:iam::xxxxxxxxxxxx:role/TavusRole',
              controller: _roleArnController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveInputRow(BuildContext context, List<Widget> children) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.map((child) {
          Widget unwrapped = child;
          if (child is Expanded) {
            unwrapped = child.child;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: unwrapped,
          );
        }).toList(),
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((child) {
          if (child is Expanded) return child;
          return Expanded(child: child);
        }).toList().expand((child) => [child, const SizedBox(width: 16)]).toList()..removeLast(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);
    final payload = _buildPayload('Candidate');

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1050;

          final mainForm = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Hero
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.24)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'AI Avatar Screening',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Configure Your',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w300, 
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 0.95,
                    ),
                  ),
                  Text(
                    'Interview Session',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: 40,
                      fontWeight: FontWeight.w700, 
                      color: theme.colorScheme.onSurface, 
                      height: 1.0, 
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Set up your AI avatar, questions, and analysis preferences. Everything is customisable.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      CustomButton(
                        text: 'Launch Session',
                        onPressed: _showLaunchDialog,
                        isLoading: _isLaunching,
                      ),
                      const SizedBox(width: 12),
                      CustomButton(
                        text: 'Save Draft',
                        variant: ButtonVariant.secondary,
                        onPressed: _showSaveDraftDialog,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Saved Drafts
              _buildSavedDrafts(store),
              const SizedBox(height: 16),

              // Form fields
              _buildTavusConfigCard(),
              const SizedBox(height: 16),
              _buildQuestionsCard(store),
              const SizedBox(height: 16),
              _buildSessionPropertiesCard(),
              const SizedBox(height: 16),
              _buildS3StorageCard(),
            ],
          );

          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: mainForm,
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: StickyColumn(
                      payload: payload,
                    ),
                  ),
                ],
              ),
            );
          } else {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  mainForm,
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 400,
                    child: JsonPreviewPane(
                      data: payload,
                      title: 'Request Preview',
                      method: 'POST',
                      endpoint: '/v2/conversations',
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

// Side widget helper for Wide Screens
class StickyColumn extends StatelessWidget {
  final Map<String, dynamic> payload;

  const StickyColumn({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 380,
          child: JsonPreviewPane(
            data: payload,
            title: 'Request Preview',
            method: 'POST',
            endpoint: '/v2/conversations',
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Reference',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildRefRow(context, 'conversational_context', 'system prompt overrides LLM persona'),
                _buildRefRow(context, 'custom_greeting', 'the first words spoken by avatar'),
                _buildRefRow(context, 'greenscreen', 'needs transparent background replica'),
                _buildRefRow(context, 'callback_url', 'receives conversation event payloads'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRefRow(BuildContext context, String term, String desc) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term,
            style: TextStyle(fontSize: 11, fontFamily: 'Courier', color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
          ),
          Text(
            desc,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
