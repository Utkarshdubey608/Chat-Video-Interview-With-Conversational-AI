// lib/views/setup_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/custom_inputs.dart';
import '../widgets/apple_ui.dart';
import 'setup/launch_payload.dart';
import 'setup/avatar_picker.dart';
import 'setup/welcome_marquee.dart';

/// Meeting kickoff page. Kept intentionally minimal and Apple-clean: pick the
/// avatar (replica/persona) and launch. Everything else (prompt, greeting,
/// session properties, questions, storage) is configured on the Settings page
/// and read from [AppStore.sessionConfig] at launch time.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  // Working state for the avatar selection on this page.
  String _replicaId = '';
  String _personaId = '';

  // Replicas & Personas dropdown options.
  List<TavusReplica> _replicas = [];
  List<TavusPersona> _personas = [];
  bool _isLaunching = false;

  // Loading state for replicas/personas fetch.
  bool _isLoadingTavus = false;
  String? _tavusLoadError;

  @override
  void initState() {
    super.initState();
    final store = Provider.of<AppStore>(context, listen: false);
    _replicaId = store.sessionConfig.replicaId;
    _personaId = store.sessionConfig.personaId;
    _loadApis();
  }

  // Fetches the available replicas & personas from Tavus (cached in the store).
  Future<void> _loadApis({bool forceRefresh = false}) async {
    final store = Provider.of<AppStore>(context, listen: false);
    final key = store.tavusKey;
    if (key.isEmpty) {
      setState(() {
        _tavusLoadError =
            'No Tavus API key set. Add it in Settings to load replicas & personas.';
      });
      return;
    }

    if (!forceRefresh && store.cachedReplicas.isNotEmpty) {
      setState(() {
        _replicas = store.cachedReplicas;
        _personas = store.cachedPersonas;
        _isLoadingTavus = false;
        _tavusLoadError = null;
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

      final replicasResult = results[0] as List<TavusReplica>;
      final personasResult = results[1] as List<TavusPersona>;

      setState(() {
        _replicas = replicasResult;
        _personas = personasResult;
        _isLoadingTavus = false;
      });

      store.setCachedTavusData(replicasResult, personasResult);
    } catch (e) {
      debugPrint('Failed to load Tavus replicas/personas: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingTavus = false;
        _tavusLoadError = 'Failed to load replicas/personas: $e';
      });
    }
  }

  // Merges the current avatar selection into the persisted session config.
  DraftForm _currentConfig(AppStore store) {
    return store.sessionConfig.copyWith(
      replicaId: _replicaId.trim(),
      personaId: _personaId.trim(),
    );
  }

  // Human-readable label for the currently selected persona.
  String get _personaLabel {
    if (_personaId.isEmpty) return 'None';
    final match = _personas.where((p) => p.personaId == _personaId);
    return match.isNotEmpty ? match.first.personaName : _personaId;
  }

  // Clears the previous session's Hume/transcript/metric state before a launch.
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

  // Validates input, creates the Tavus conversation and navigates to interview.
  Future<void> _confirmLaunch(String candidateName) async {
    if (candidateName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a display name'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_replicaId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or enter a Replica ID to start a session'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLaunching = true);
    try {
      final store = Provider.of<AppStore>(context, listen: false);
      final config = _currentConfig(store);
      // Persist the chosen avatar so Settings & drafts stay in sync.
      store.setSessionConfig(config);

      final payload = buildConversationPayload(
        config: config,
        questions: store.questions,
        candidateName: candidateName,
      );

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

  // Prompts for the candidate name, then launches the interview.
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

  // Saves the current session config + questions as a named, reloadable draft.
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
                store.saveDraft(name.trim(), _currentConfig(store), store.questions);
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

  // Error dialog shown when Tavus rejects the conversation-create request.
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

  // Loads a saved draft into the session config and refreshes the avatar fields.
  void _loadDraft(Draft draft) {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setSessionConfig(draft.form);
    store.setQuestions(draft.questions);
    setState(() {
      _replicaId = draft.form.replicaId;
      _personaId = draft.form.personaId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded draft "${draft.name}"'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Opens the persona picker sheet.
  Future<void> _pickPersona() async {
    final options = <AppleOption<String>>[
      const AppleOption('', 'None'),
      ..._personas.map((p) => AppleOption(p.personaId, p.personaName)),
    ];
    final picked = await showAppleOptions<String>(
      context,
      title: 'Choose Persona',
      options: options,
      selected: _personaId,
    );
    if (picked != null) setState(() => _personaId = picked);
  }

  // Text dialog to manually type/override a replica ID.
  Future<void> _editReplicaId() async {
    final controller = TextEditingController(text: _replicaId);
    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Replica ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paste a Replica ID to use one that isn\'t in the list above.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Replica ID',
                placeholder: 'e.g. r5f0577fc829',
                controller: controller,
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
              text: 'Set',
              onPressed: () {
                setState(() => _replicaId = controller.text.trim());
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // Avatar group: header row with refresh, the avatar strip, persona picker and
  // manual replica-ID override.
  Widget _buildAvatarGroup(ThemeData theme) {
    final replicaValue = _replicaId.isEmpty ? 'Not set' : _replicaId;
    return AppleGroup(
      header: 'Avatar',
      dividerIndent: 16,
      footer: _tavusLoadError ??
          (_isLoadingTavus
              ? 'Loading replicas & personas from Tavus…'
              : '${_replicas.length} replica(s) available · tap a face to select'),
      children: [
        // Strip header with refresh control.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Choose who runs the interview',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (_isLoadingTavus)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: theme.colorScheme.onSurfaceVariant,
                  tooltip: 'Reload replicas & personas',
                  onPressed: () => _loadApis(forceRefresh: true),
                ),
            ],
          ),
        ),
        AvatarStrip(
          replicas: _replicas,
          selectedId: _replicaId,
          onSelect: (id) => setState(() => _replicaId = id),
        ),
        AppleDisclosureRow(
          leading: const AppleIconBadge(
              icon: Icons.psychology_outlined, color: Color(0xFF6366F1)),
          title: 'Persona',
          value: _personaLabel,
          onTap: _pickPersona,
        ),
        AppleDisclosureRow(
          leading: const AppleIconBadge(
              icon: Icons.tag, color: Color(0xFF64748B)),
          title: 'Replica ID',
          value: replicaValue,
          onTap: _editReplicaId,
        ),
      ],
    );
  }

  // Saved drafts group; each row loads its draft, trailing button deletes it.
  Widget _buildDraftsGroup(AppStore store) {
    return AppleGroup(
      header: 'Saved Drafts',
      footer: 'Tap a draft to load its avatar, questions and settings.',
      dividerIndent: 58,
      children: [
        for (final draft in store.drafts)
          AppleRow(
            leading: const AppleIconBadge(
                icon: Icons.description_outlined, color: Color(0xFF0EA5E9)),
            title: draft.name,
            subtitle: '${draft.questions.length} questions',
            onTap: () => _loadDraft(draft),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () {
                store.deleteDraft(draft.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Draft deleted')),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Full-bleed welcoming marquee of moving cards across the top.
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: SetupWelcomeMarquee(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                // Primary actions
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Launch Session',
                        onPressed: _showLaunchDialog,
                        isLoading: _isLaunching,
                        icon: const Icon(Icons.videocam_rounded,
                            size: 18, color: Color(0xFF060709)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    CustomButton(
                      text: 'Save Draft',
                      variant: ButtonVariant.secondary,
                      onPressed: _showSaveDraftDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                        _buildAvatarGroup(theme),

                        if (store.drafts.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _buildDraftsGroup(store),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
