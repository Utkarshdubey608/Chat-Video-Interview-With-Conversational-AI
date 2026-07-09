// lib/views/setup_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/custom_inputs.dart';
import 'setup/launch_payload.dart';

/// Meeting kickoff page. Kept intentionally minimal: pick the avatar
/// (replica/persona) and launch. Everything else (prompt, greeting, session
/// properties, questions, storage) is configured on the Settings page and read
/// from [AppStore.sessionConfig] at launch time.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  // Working state for the avatar selection on this page.
  final _replicaIdController = TextEditingController();
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
    _replicaIdController.text = store.sessionConfig.replicaId;
    _personaId = store.sessionConfig.personaId;
    _loadApis();
  }

  @override
  void dispose() {
    _replicaIdController.dispose();
    super.dispose();
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
      replicaId: _replicaIdController.text.trim(),
      personaId: _personaId.trim(),
    );
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

    if (_replicaIdController.text.trim().isEmpty) {
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
      _replicaIdController.text = draft.form.replicaId;
      _personaId = draft.form.personaId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded draft "${draft.name}"'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Horizontal strip of saved drafts; tapping one loads it.
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

  // Avatar picker: replica & persona dropdowns plus a manual replica ID override.
  Widget _buildAvatarCard() {
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
                    'Avatar Selection',
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
                    onPressed: () => _loadApis(forceRefresh: true),
                  ),
              ],
            ),
            Text(
              _isLoadingTavus
                  ? 'Loading replicas & personas from Tavus…'
                  : 'Pick the AI avatar and persona for this session',
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
                    value: _personas.any((p) => p.personaId == _personaId) ? _personaId : '',
                    items: personaOptions,
                    onChanged: (val) => setState(() => _personaId = val ?? ''),
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
          ],
        ),
      ),
    );
  }

  // Lays children in a row on wide screens, stacked column on mobile.
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

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Hero
                const SizedBox(height: 16),
                Text(
                  'Kick off your',
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
                  'Pick your AI avatar and launch. Prompt, questions and session '
                  'properties live in Settings.',
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
                const SizedBox(height: 24),

                // Saved Drafts
                _buildSavedDrafts(store),
                const SizedBox(height: 16),

                // Avatar picker
                _buildAvatarCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
