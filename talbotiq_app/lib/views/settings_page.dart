// lib/views/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../models/app_models.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../core/services/deepgram_service.dart';
import '../core/services/recording_service.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/custom_inputs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _tavusController;
  late TextEditingController _deepgramController;
  late TextEditingController _humeController;
  late TextEditingController _awsController;
  late TextEditingController _anthropicController;
  late TextEditingController _geminiController;
  late TextEditingController _awsProxyUrlController;
  late TextEditingController _webhookController;

  bool _showTavus = false;
  bool _showDeepgram = false;
  bool _showHume = false;
  bool _showAws = false;
  bool _showAnthropic = false;
  bool _showGemini = false;

  String _tavusTestState = 'idle'; // 'idle', 'testing', 'ok', 'fail'
  String _dgTestState = 'idle';
  String _humeTestState = 'idle';

  // Recording playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RecordingService _recordingService = RecordingService();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    final store = Provider.of<AppStore>(context, listen: false);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    _tavusController = TextEditingController(text: store.tavusKey);
    _deepgramController = TextEditingController(text: store.deepgramKey);
    _humeController = TextEditingController(text: store.humeKey);
    _awsController = TextEditingController(text: store.awsKey);
    _anthropicController = TextEditingController(text: store.anthropicKey);
    _geminiController = TextEditingController(text: store.geminiKey);
    _awsProxyUrlController = TextEditingController(text: store.awsProxyUrl);
    _webhookController = TextEditingController(text: store.webhookUrl);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tavusController.dispose();
    _deepgramController.dispose();
    _humeController.dispose();
    _awsController.dispose();
    _anthropicController.dispose();
    _geminiController.dispose();
    _awsProxyUrlController.dispose();
    _webhookController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setTavusKey(_tavusController.text.trim());
    store.setDeepgramKey(_deepgramController.text.trim());
    store.setHumeKey(_humeController.text.trim());
    store.setAwsKey(_awsController.text.trim());
    store.setAnthropicKey(_anthropicController.text.trim());
    store.setGeminiKey(_geminiController.text.trim());
    store.setAwsProxyUrl(_awsProxyUrlController.text.trim());
    store.setWebhookUrl(_webhookController.text.trim());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved successfully'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _testTavus() async {
    if (_tavusController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Tavus API Key first')),
      );
      return;
    }
    setState(() => _tavusTestState = 'testing');
    try {
      tavusService.setKey(_tavusController.text.trim());
      final replicas = await tavusService.listReplicas();
      
      setState(() => _tavusTestState = 'ok');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected — ${replicas.length} replica(s) found'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('$e');
      setState(() => _tavusTestState = 'fail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _testDeepgram() async {
    if (_deepgramController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Deepgram API Key first')),
      );
      return;
    }
    setState(() => _dgTestState = 'testing');
    try {
      deepgramService.setKey(_deepgramController.text.trim());
      final res = await deepgramService.testConnection();
      if (res['ok'] == true) {
        setState(() => _dgTestState = 'ok');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Deepgram Nova-3 connected successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } else {
        setState(() => _dgTestState = 'fail');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deepgram connection failed: ${res['message']}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _dgTestState = 'fail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _testHume() async {
    if (_humeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Hume API Key first')),
      );
      return;
    }
    setState(() => _humeTestState = 'testing');
    try {
      final res = await http.get(
        Uri.parse('https://api.hume.ai/v0/batch/jobs?limit=1'),
        headers: {'X-Hume-Api-Key': _humeController.text.trim()},
      );
      if (res.statusCode == 200) {
        setState(() => _humeTestState = 'ok');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Hume AI connected successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } else {
        setState(() => _humeTestState = 'fail');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hume returned HTTP ${res.statusCode}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _humeTestState = 'fail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hume connection failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _resetToDefaults() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reset Settings?'),
          content: const Text(
            'Are you sure you want to reset all settings and clear stored API keys?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            CustomButton(
              text: 'Reset',
              variant: ButtonVariant.danger,
              onPressed: () {
                final store = Provider.of<AppStore>(context, listen: false);
                store.clearAllPrefs();
                _tavusController.clear();
                _deepgramController.clear();
                _humeController.clear();
                _awsController.clear();
                _anthropicController.clear();
                _geminiController.clear();
                _awsProxyUrlController.clear();
                _webhookController.clear();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Reset completed'),
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

  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
      return;
    }
    controller.text = text;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  Widget _buildKeyField({
    required BuildContext context,
    required String label,
    required String hint,
    required String placeholder,
    required TextEditingController controller,
    required bool show,
    required VoidCallback toggleShow,
    Widget? trailingStatus,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (trailingStatus != null) trailingStatus,
          ],
        ),
        const SizedBox(height: 8), // M3 consistent 8dp spacing
        TextField(
          controller: controller,
          obscureText: !show,
          style: TextStyle(
            fontSize: 14, 
            color: theme.colorScheme.onSurface, 
            fontFamily: 'Courier',
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.content_paste,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: 'Paste',
                  onPressed: () => _pasteInto(controller),
                ),
                IconButton(
                  icon: Icon(
                    show ? Icons.visibility : Icons.visibility_off,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: show ? 'Hide' : 'Show',
                  onPressed: toggleShow,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Future<void> _togglePlay(SavedRecording rec) async {
    if (_playingId == rec.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(rec.path));
      if (mounted) setState(() => _playingId = rec.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play recording: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteRecording(SavedRecording rec) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text('Permanently delete the recording "${rec.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          CustomButton(
            text: 'Delete',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (_playingId == rec.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingId = null);
    }
    await _recordingService.deleteFile(rec.path);
    if (!mounted) return;
    Provider.of<AppStore>(context, listen: false).deleteRecording(rec.id);
  }

  Widget _buildRecordingRow(BuildContext context, SavedRecording rec) {
    final theme = Theme.of(context);
    final playing = _playingId == rec.id;
    final sizeMb = (rec.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final date = rec.savedAt.contains('T')
        ? rec.savedAt.split('T').first
        : rec.savedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.04),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              playing ? Icons.stop_circle : Icons.play_circle_fill,
              color: theme.colorScheme.primary,
              size: 32,
            ),
            onPressed: () => _togglePlay(rec),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · $sizeMb MB',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () => _deleteRecording(rec),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsCard(BuildContext context, AppStore store) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interview Recordings',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Audio recordings are stored only on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save interview recordings'),
              subtitle: Text(
                'Keep a local .wav of each interview to play back here.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
              value: store.storeLocalRecordings,
              onChanged: (v) => store.setStoreLocalRecordings(v),
            ),
            Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
            const SizedBox(height: 8),
            if (store.recordings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  store.storeLocalRecordings
                      ? 'No recordings yet — finish an interview to save one.'
                      : 'Enable saving above to keep recordings of your interviews.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              )
            else
              ...store.recordings.map((rec) => _buildRecordingRow(context, rec)),
          ],
        ),
      ),
    );
  }

  Widget _getStatusIndicator(BuildContext context, String state) {
    final theme = Theme.of(context);
    if (state == 'testing') {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2, 
          valueColor: AlwaysStoppedAnimation(theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (state == 'ok') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 16),
          const SizedBox(width: 6),
          Text(
            'Connected', 
            style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }
    if (state == 'fail') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: theme.colorScheme.error, size: 16),
          const SizedBox(width: 6),
          Text(
            'Failed', 
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Provider.of<AppStore>(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Platform Config',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Settings',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Manage API credentials and platform behaviour.',
                              style: theme.textTheme.bodyMedium,
                              softWrap: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      CustomButton(
                        text: 'Save Settings',
                        onPressed: _saveSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // API Key Credentials Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'API Credentials',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Keys are stored locally in your browser and never sent to TalbotIQ servers.',
                            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'Tavus API Key',
                            hint: 'Required — from tavus.io → Settings → API Keys',
                            placeholder: 'ta_xxxxxxxxxxxxxxxxxxxxxxxx',
                            controller: _tavusController,
                            show: _showTavus,
                            toggleShow: () => setState(() => _showTavus = !_showTavus),
                            trailingStatus: _getStatusIndicator(context, _tavusTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'Deepgram API Key',
                            hint: 'Optional — transcription & pace analysis (Nova-3)',
                            placeholder: 'Token xxxxxxxxxxxxxxxx',
                            controller: _deepgramController,
                            show: _showDeepgram,
                            toggleShow: () => setState(() => _showDeepgram = !_showDeepgram),
                            trailingStatus: _getStatusIndicator(context, _dgTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'Hume AI API Key',
                            hint: 'Optional — voice prosody & sentiment scoring',
                            placeholder: 'hume_xxxxxxxx',
                            controller: _humeController,
                            show: _showHume,
                            toggleShow: () => setState(() => _showHume = !_showHume),
                            trailingStatus: _getStatusIndicator(context, _humeTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'Google Gemini Key',
                            hint: 'Optional — Gemini-powered ATS scorecard analysis (2.5 Flash)',
                            placeholder: 'AIza…',
                            controller: _geminiController,
                            show: _showGemini,
                            toggleShow: () => setState(() => _showGemini = !_showGemini),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'AWS Access Key',
                            hint: 'Optional — Rekognition facial analysis',
                            placeholder: 'AKIA…',
                            controller: _awsController,
                            show: _showAws,
                            toggleShow: () => setState(() => _showAws = !_showAws),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            context: context,
                            label: 'Anthropic / Claude Key',
                            hint: 'Optional — AI scorecard synthesis',
                            placeholder: 'sk-ant-api03-…',
                            controller: _anthropicController,
                            show: _showAnthropic,
                            toggleShow: () => setState(() => _showAnthropic = !_showAnthropic),
                          ),
                          const SizedBox(height: 20),

                          // Testing row buttons
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              CustomButton(
                                text: 'Test Tavus Connection',
                                variant: ButtonVariant.outline,
                                height: 40,
                                onPressed: _testTavus,
                                isLoading: _tavusTestState == 'testing',
                              ),
                              CustomButton(
                                text: 'Test Deepgram Connection',
                                variant: ButtonVariant.outline,
                                height: 40,
                                onPressed: _testDeepgram,
                                isLoading: _dgTestState == 'testing',
                              ),
                              CustomButton(
                                text: 'Test Hume Connection',
                                variant: ButtonVariant.outline,
                                height: 40,
                                onPressed: _testHume,
                                isLoading: _humeTestState == 'testing',
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
                          const SizedBox(height: 16),

                          CustomInputField(
                            label: 'AWS Rekognition Proxy URL',
                            placeholder: 'http://localhost:3002/analyze-face',
                            controller: _awsProxyUrlController,
                            hint: 'Optional — Lambda function URL (production) or http://localhost:3002/analyze-face (local dev). Enables facial analysis. The AWS secret stays server-side in the proxy, never in the app.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Webhook Configuration Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Webhook Configuration',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Receives real-time conversation events from Tavus',
                            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          CustomInputField(
                            label: 'Webhook URL',
                            placeholder: 'https://api.yourcompany.com/webhook/tavus',
                            controller: _webhookController,
                            hint: 'Receives: conversation.started, conversation.ended, transcription, participant events, errors',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Interview Recordings management
                  _buildRecordingsCard(context, store),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      CustomButton(
                        text: 'Save Settings',
                        onPressed: _saveSettings,
                      ),
                      const SizedBox(width: 12),
                      CustomButton(
                        text: 'Reset to Defaults',
                        variant: ButtonVariant.secondary,
                        onPressed: _resetToDefaults,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
