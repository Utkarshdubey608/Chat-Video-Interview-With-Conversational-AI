// lib/views/settings/session_setup_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_store.dart';
import '../../widgets/custom_buttons.dart';
import '../../widgets/custom_inputs.dart';
import '../../widgets/apple_ui.dart';

/// Settings category: global session properties (language, pipeline, duration,
/// timeouts, toggles) used as launch defaults for every interview.
///
/// The per-interview prompt, greeting, questions and avatar are NOT edited here
/// anymore — a recruiter configures those when creating an interview
/// (see features/interviews/recruiter/create_interview_page.dart). Edits are
/// held locally until "Save" writes them back into [AppStore.sessionConfig]
/// (via copyWith, preserving other fields).
class SessionSetupSection extends StatefulWidget {
  const SessionSetupSection({super.key});

  @override
  State<SessionSetupSection> createState() => _SessionSetupSectionState();
}

class _SessionSetupSectionState extends State<SessionSetupSection> {
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
    _backgroundUrlController.dispose();
    super.dispose();
  }

  // Merges this section's fields into the stored session config and persists it.
  void _save() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setSessionConfig(store.sessionConfig.copyWith(
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

  // Session properties: language, pipeline, duration, timeouts and toggles.
  Widget _buildPropertiesCard() {
    final theme = Theme.of(context);
    return AppleSectionCard(
      title: 'Session Properties',
      subtitle: 'Global launch defaults — map to the Tavus properties object',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPropertiesCard(),
        const SizedBox(height: 24),
        CustomButton(text: 'Save Session Setup', onPressed: _save),
      ],
    );
  }
}
