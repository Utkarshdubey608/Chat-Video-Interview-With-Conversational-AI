// lib/views/settings/api_credentials_section.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/core/services/deepgram_service.dart';
import 'package:talbotiq/core/services/gemini_service.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/shared/widgets/apple_ui.dart';

/// Settings category: API keys, the AWS Rekognition proxy URL, connection
/// tests, and a reset-to-defaults action. Owns its own controllers and Save.
class ApiCredentialsSection extends StatefulWidget {
  const ApiCredentialsSection({super.key});

  @override
  State<ApiCredentialsSection> createState() => ApiCredentialsSectionState();
}

class ApiCredentialsSectionState extends State<ApiCredentialsSection> {
  late TextEditingController _tavusController;
  late TextEditingController _deepgramController;
  late TextEditingController _humeController;
  late TextEditingController _awsController;
  late TextEditingController _anthropicController;
  late TextEditingController _geminiController;
  late TextEditingController _awsProxyUrlController;

  bool _showTavus = false;
  bool _showDeepgram = false;
  bool _showHume = false;
  bool _showAws = false;
  bool _showAnthropic = false;
  bool _showGemini = false;

  String _tavusTestState = 'idle'; // 'idle', 'testing', 'ok', 'fail'
  String _dgTestState = 'idle';
  String _humeTestState = 'idle';
  String _geminiTestState = 'idle';

  // Debounces local auto-save so every keystroke doesn't individually trigger
  // a full AppStore persist. Deliberately local-only — this NEVER pushes to
  // the cloud; that stays a separate, explicit action ("Save to Cloud" in
  // SettingsPage), which flushes via commitToStore() itself regardless of
  // whether this timer has fired yet.
  Timer? _autoSaveTimer;

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), commitToStore);
  }

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
  }

  /// Re-reads AppStore's current key values into the text fields. The
  /// controllers are only seeded once in [initState], so anything that
  /// changes AppStore's keys from outside this widget (e.g. "Retrieve from
  /// Cloud" in SettingsPage) must call this explicitly or the fields keep
  /// showing stale text even though the underlying store — and prefs — did
  /// update.
  void refreshFromStore() {
    final store = Provider.of<AppStore>(context, listen: false);
    setState(() {
      _tavusController.text = store.tavusKey;
      _deepgramController.text = store.deepgramKey;
      _humeController.text = store.humeKey;
      _awsController.text = store.awsKey;
      _anthropicController.text = store.anthropicKey;
      _geminiController.text = store.geminiKey;
      _awsProxyUrlController.text = store.awsProxyUrl;
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _tavusController.dispose();
    _deepgramController.dispose();
    _humeController.dispose();
    _awsController.dispose();
    _anthropicController.dispose();
    _geminiController.dispose();
    _awsProxyUrlController.dispose();
    super.dispose();
  }

  // Writes all credential fields back to the store, without any UI feedback —
  // shared by the explicit "Save Credentials" button and by SettingsPage's
  // "Save to Cloud" (which must push whatever's currently typed here, not
  // whichever value AppStore last held).
  void commitToStore() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setTavusKey(_tavusController.text.trim());
    store.setDeepgramKey(_deepgramController.text.trim());
    store.setHumeKey(_humeController.text.trim());
    store.setAwsKey(_awsController.text.trim());
    store.setAnthropicKey(_anthropicController.text.trim());
    store.setGeminiKey(_geminiController.text.trim());
    store.setAwsProxyUrl(_awsProxyUrlController.text.trim());
  }

  // Verifies the Tavus key by listing replicas.
  Future<void> _testTavus() async {
    if (_tavusController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Tavus API Key first')),
      );
      return;
    }
    setState(() => _tavusTestState = 'testing');
    // Test with the unsaved field value but restore the previously configured
    // key afterwards, so a test never permanently changes global app state.
    final previousKey = tavusService.getKey();
    try {
      tavusService.setKey(_tavusController.text.trim());
      final replicas = await tavusService.listReplicas();
      if (!mounted) return;
      setState(() => _tavusTestState = 'ok');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected — ${replicas.length} replica(s) found'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      debugPrint('$e');
      if (!mounted) return;
      setState(() => _tavusTestState = 'fail');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      tavusService.setKey(previousKey);
    }
  }

  // Verifies the Deepgram key against its test endpoint.
  Future<void> _testDeepgram() async {
    if (_deepgramController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Deepgram API Key first')),
      );
      return;
    }
    setState(() => _dgTestState = 'testing');
    // Test with the unsaved field value but restore the previously configured
    // key afterwards, so a test never permanently changes global app state.
    final previousKey = deepgramService.getKey();
    try {
      deepgramService.setKey(_deepgramController.text.trim());
      final res = await deepgramService.testConnection();
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() => _dgTestState = 'ok');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Deepgram Nova-3 connected successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        setState(() => _dgTestState = 'fail');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deepgram connection failed: ${res['message']}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _dgTestState = 'fail');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      deepgramService.setKey(previousKey);
    }
  }

  // Verifies the Hume key against the batch jobs endpoint.
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
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _humeTestState = 'ok');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Hume AI connected successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        setState(() => _humeTestState = 'fail');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hume returned HTTP ${res.statusCode}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _humeTestState = 'fail');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hume connection failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Trims an HTTP error body down to something a SnackBar can reasonably show.
  String _shortBody(String body) =>
      body.length > 160 ? '${body.substring(0, 160)}…' : body;

  // Verifies the Gemini key with a minimal generateContent call — the SAME
  // method (and x-goog-api-key header auth) the app's actual scoring pipeline
  // uses (see GeminiService.analyze). Deliberately NOT models.list: that
  // method can reject a perfectly valid generateContent-scoped key with a
  // confusing "ACCESS_TOKEN_TYPE_UNSUPPORTED" depending on the key's Cloud
  // Console restrictions, so testing it would give a false negative.
  //
  // Also deliberately mirrors GeminiService.analyze()'s generationConfig
  // (responseMimeType: 'application/json' + safetySettings), not just a bare
  // "ping" — a key/project can happily return 200 for a trivial text-only
  // request while the real scoring call still fails, because JSON mode isn't
  // enabled for that project/model tier, or the config combination itself is
  // rejected. Keeping maxOutputTokens tiny (unlike the real call's 20000)
  // keeps this test fast; it only needs to prove the CONFIG is accepted, not
  // exercise a long generation.
  Future<void> _testGemini() async {
    if (_geminiController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Gemini API Key first')),
      );
      return;
    }
    setState(() => _geminiTestState = 'testing');
    try {
      final key = _geminiController.text.trim();
      final res = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Reply with exactly this JSON object: {"ok": true}'}
              ]
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 50,
            'responseMimeType': 'application/json',
          },
          'safetySettings': GeminiService.safetySettings,
        }),
      );
      debugPrint('[TestGemini] status=${res.statusCode} body=${res.body}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _geminiTestState = 'ok');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Gemini connected successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        setState(() => _geminiTestState = 'fail');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Gemini returned HTTP ${res.statusCode}: ${_shortBody(res.body)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _geminiTestState = 'fail');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gemini connection failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Confirms, then clears every stored credential and preference.
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

  // Pastes clipboard text into the given field.
  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
      return;
    }
    controller.text = text;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  // A single obscured API-key field with paste, show/hide and status.
  Widget _buildKeyField({
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
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: !show,
          onChanged: (_) => _scheduleAutoSave(),
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
                  icon: Icon(Icons.content_paste, color: theme.colorScheme.onSurfaceVariant, size: 20),
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

  // Small connected/failed/testing indicator shown next to a key label.
  Widget _statusIndicator(String state) {
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
          Text('Connected', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );
    }
    if (state == 'fail') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: theme.colorScheme.error, size: 16),
          const SizedBox(width: 6),
          Text('Failed', style: TextStyle(color: theme.colorScheme.error, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppleSectionCard(
          title: 'API Credentials',
          subtitle: 'Keys are stored locally on this device and never sent to TalbotIQ servers.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                _buildKeyField(
                  label: 'Tavus API Key',
                  hint: 'Required — from tavus.io → Settings → API Keys',
                  placeholder: 'ta_xxxxxxxxxxxxxxxxxxxxxxxx',
                  controller: _tavusController,
                  show: _showTavus,
                  toggleShow: () => setState(() => _showTavus = !_showTavus),
                  trailingStatus: _statusIndicator(_tavusTestState),
                ),
                const SizedBox(height: 20),

                _buildKeyField(
                  label: 'Deepgram API Key',
                  hint: 'Optional — transcription & pace analysis (Nova-3)',
                  placeholder: 'Token xxxxxxxxxxxxxxxx',
                  controller: _deepgramController,
                  show: _showDeepgram,
                  toggleShow: () => setState(() => _showDeepgram = !_showDeepgram),
                  trailingStatus: _statusIndicator(_dgTestState),
                ),
                const SizedBox(height: 20),

                _buildKeyField(
                  label: 'Hume AI API Key',
                  hint: 'Optional — voice prosody & sentiment scoring',
                  placeholder: 'hume_xxxxxxxx',
                  controller: _humeController,
                  show: _showHume,
                  toggleShow: () => setState(() => _showHume = !_showHume),
                  trailingStatus: _statusIndicator(_humeTestState),
                ),
                const SizedBox(height: 20),

                _buildKeyField(
                  label: 'Google Gemini Key',
                  hint: 'Optional — Gemini-powered ATS scorecard analysis (2.5 Flash)',
                  placeholder: 'AIza…',
                  controller: _geminiController,
                  show: _showGemini,
                  toggleShow: () => setState(() => _showGemini = !_showGemini),
                  trailingStatus: _statusIndicator(_geminiTestState),
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

                // Connection test buttons
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
                    CustomButton(
                      text: 'Test Gemini Connection',
                      variant: ButtonVariant.outline,
                      height: 40,
                      onPressed: _testGemini,
                      isLoading: _geminiTestState == 'testing',
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
                  onChanged: (_) => _scheduleAutoSave(),
                  hint: 'Optional — Lambda function URL (production) or http://localhost:3002/analyze-face (local dev). Enables facial analysis. The AWS secret stays server-side in the proxy, never in the app.',
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Changes save automatically on this device.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CustomButton(
              text: 'Reset to Defaults',
              variant: ButtonVariant.secondary,
              onPressed: _resetToDefaults,
            ),
          ],
        ),
      ],
    );
  }
}
