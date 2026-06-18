// lib/views/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../core/constants/colors.dart';
import '../providers/app_store.dart';
import '../core/services/tavus_service.dart';
import '../core/services/deepgram_service.dart';
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

  @override
  void initState() {
    super.initState();
    final store = Provider.of<AppStore>(context, listen: false);
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
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: AppColors.success,
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
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      print(e);
      setState(() => _tavusTestState = 'fail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger,
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
            const SnackBar(
              content: Text('Deepgram Nova-3 connected successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        setState(() => _dgTestState = 'fail');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deepgram connection failed: ${res['message']}'),
              backgroundColor: AppColors.danger,
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
            backgroundColor: AppColors.danger,
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
            const SnackBar(
              content: Text('Hume AI connected successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        setState(() => _humeTestState = 'fail');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hume returned HTTP ${res.statusCode}'),
              backgroundColor: AppColors.danger,
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
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Reset Settings?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Are you sure you want to reset all settings and clear stored API keys?',
            style: TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
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
                  const SnackBar(
                    content: Text('Reset completed'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeyField({
    required String label,
    required String hint,
    required String placeholder,
    required TextEditingController controller,
    required bool show,
    required VoidCallback toggleShow,
    Widget? trailingStatus,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            if (trailingStatus != null) trailingStatus,
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: !show,
          style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'Courier'),
          decoration: InputDecoration(
            hintText: placeholder,
            suffixIcon: IconButton(
              icon: Icon(
                show ? Icons.visibility : Icons.visibility_off,
                color: AppColors.textMuted,
                size: 18,
              ),
              onPressed: toggleShow,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _getStatusIndicator(String state) {
    if (state == 'testing') {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(AppColors.textMuted)),
      );
    }
    if (state == 'ok') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 14),
          SizedBox(width: 4),
          Text('Connected', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      );
    }
    if (state == 'fail') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: AppColors.danger, size: 14),
          SizedBox(width: 4),
          Text('Failed', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                          const Text(
                            'Platform Config',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage API credentials and platform behaviour.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
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
                          const Text(
                            'API Credentials',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Keys are stored locally in your browser and never sent to TalbotIQ servers.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            label: 'Tavus API Key',
                            hint: 'Required — from tavus.io → Settings → API Keys',
                            placeholder: 'ta_xxxxxxxxxxxxxxxxxxxxxxxx',
                            controller: _tavusController,
                            show: _showTavus,
                            toggleShow: () => setState(() => _showTavus = !_showTavus),
                            trailingStatus: _getStatusIndicator(_tavusTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            label: 'Deepgram API Key',
                            hint: 'Optional — transcription & pace analysis (Nova-3)',
                            placeholder: 'Token xxxxxxxxxxxxxxxx',
                            controller: _deepgramController,
                            show: _showDeepgram,
                            toggleShow: () => setState(() => _showDeepgram = !_showDeepgram),
                            trailingStatus: _getStatusIndicator(_dgTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            label: 'Hume AI API Key',
                            hint: 'Optional — voice prosody & sentiment scoring',
                            placeholder: 'hume_xxxxxxxx',
                            controller: _humeController,
                            show: _showHume,
                            toggleShow: () => setState(() => _showHume = !_showHume),
                            trailingStatus: _getStatusIndicator(_humeTestState),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            label: 'Google Gemini Key',
                            hint: 'Optional — Gemini-powered ATS scorecard analysis (2.5 Flash)',
                            placeholder: 'AIza…',
                            controller: _geminiController,
                            show: _showGemini,
                            toggleShow: () => setState(() => _showGemini = !_showGemini),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
                            label: 'AWS Access Key',
                            hint: 'Optional — Rekognition facial analysis',
                            placeholder: 'AKIA…',
                            controller: _awsController,
                            show: _showAws,
                            toggleShow: () => setState(() => _showAws = !_showAws),
                          ),
                          const SizedBox(height: 20),

                          _buildKeyField(
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
                                height: 32,
                                onPressed: _testTavus,
                                isLoading: _tavusTestState == 'testing',
                              ),
                              CustomButton(
                                text: 'Test Deepgram Connection',
                                variant: ButtonVariant.outline,
                                height: 32,
                                onPressed: _testDeepgram,
                                isLoading: _dgTestState == 'testing',
                              ),
                              CustomButton(
                                text: 'Test Hume Connection',
                                variant: ButtonVariant.outline,
                                height: 32,
                                onPressed: _testHume,
                                isLoading: _humeTestState == 'testing',
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Divider(color: AppColors.border),
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
                          const Text(
                            'Webhook Configuration',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Receives real-time conversation events from Tavus',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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


