// lib/views/settings/session_setup_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_store.dart';
import '../../widgets/custom_buttons.dart';
import '../../widgets/custom_inputs.dart';
import '../../widgets/apple_ui.dart';

/// Settings category: the conversation prompt/greeting/callback, session
/// properties (language, pipeline, timeouts, toggles) and the interview
/// questions. Edits are held locally until "Save Session Setup" writes them
/// back into [AppStore.sessionConfig] (via copyWith, preserving other fields).
class SessionSetupSection extends StatefulWidget {
  const SessionSetupSection({super.key});

  @override
  State<SessionSetupSection> createState() => _SessionSetupSectionState();
}

class _SessionSetupSectionState extends State<SessionSetupSection> {
  final _convNameController = TextEditingController();
  final _contextController = TextEditingController();
  final _greetingController = TextEditingController();
  final _callbackUrlController = TextEditingController();
  final _backgroundUrlController = TextEditingController();

  String _selectedLanguage = 'English';
  String _selectedPipelineMode = 'full';
  double _maxCallDuration = 900.0;
  int _participantLeftTimeout = 60;
  int _participantAbsentTimeout = 300;
  bool _enableTranscription = true;
  bool _applyConversationOverride = false;
  bool _applyGreenscreen = false;

  @override
  void initState() {
    super.initState();
    // Seed the controls from the persisted session config.
    final cfg = Provider.of<AppStore>(context, listen: false).sessionConfig;
    _convNameController.text = cfg.conversationName;
    _contextController.text = cfg.conversationalContext;
    _greetingController.text = cfg.customGreeting;
    _callbackUrlController.text = cfg.callbackUrl;
    _backgroundUrlController.text = cfg.backgroundUrl;
    _selectedLanguage = cfg.language;
    _selectedPipelineMode = cfg.pipelineMode;
    _maxCallDuration = cfg.maxCallDuration.toDouble();
    _participantLeftTimeout = cfg.participantLeftTimeout;
    _participantAbsentTimeout = cfg.participantAbsentTimeout;
    _enableTranscription = cfg.enableTranscription;
    _applyConversationOverride = cfg.applyConversationOverride;
    _applyGreenscreen = cfg.applyGreenscreen;
  }

  @override
  void dispose() {
    _convNameController.dispose();
    _contextController.dispose();
    _greetingController.dispose();
    _callbackUrlController.dispose();
    _backgroundUrlController.dispose();
    super.dispose();
  }

  // Merges this section's fields into the stored session config and persists it.
  void _save() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setSessionConfig(store.sessionConfig.copyWith(
      conversationName: _convNameController.text,
      conversationalContext: _contextController.text,
      customGreeting: _greetingController.text,
      callbackUrl: _callbackUrlController.text,
      backgroundUrl: _backgroundUrlController.text,
      language: _selectedLanguage,
      pipelineMode: _selectedPipelineMode,
      maxCallDuration: _maxCallDuration.round(),
      participantLeftTimeout: _participantLeftTimeout,
      participantAbsentTimeout: _participantAbsentTimeout,
      enableTranscription: _enableTranscription,
      applyConversationOverride: _applyConversationOverride,
      applyGreenscreen: _applyGreenscreen,
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Session setup saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Conversation-level config: name, system prompt, greeting, callback URL.
  Widget _buildConversationCard() {
    return AppleSectionCard(
      title: 'Avatar & Conversation',
      subtitle: 'Prompt and greeting that drive the Tavus conversational agent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  // Session properties: language, pipeline, duration, timeouts and toggles.
  Widget _buildPropertiesCard() {
    final theme = Theme.of(context);
    return AppleSectionCard(
      title: 'Session Properties',
      subtitle: 'All values map to the Tavus conversation properties object',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  // Editable list of interview questions, backed directly by the store.
  Widget _buildQuestionsCard(AppStore store) {
    final theme = Theme.of(context);
    return AppleSectionCard(
      title: 'Interview Questions',
      subtitle: '${store.questions.length} questions configured',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              ),
              child: Text(
                '+ Add Question',
                style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
        ],
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
    final store = Provider.of<AppStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConversationCard(),
        const SizedBox(height: 16),
        _buildPropertiesCard(),
        const SizedBox(height: 16),
        _buildQuestionsCard(store),
        const SizedBox(height: 24),
        CustomButton(text: 'Save Session Setup', onPressed: _save),
      ],
    );
  }
}
