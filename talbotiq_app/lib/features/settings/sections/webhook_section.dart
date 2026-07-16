// lib/views/settings/webhook_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/core/utils/validators.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';
import 'package:talbotiq/shared/widgets/apple_ui.dart';

/// Settings category: the Tavus event webhook URL.
class WebhookSection extends StatefulWidget {
  const WebhookSection({super.key});

  @override
  State<WebhookSection> createState() => _WebhookSectionState();
}

class _WebhookSectionState extends State<WebhookSection> {
  late TextEditingController _webhookController;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    final store = Provider.of<AppStore>(context, listen: false);
    _webhookController = TextEditingController(text: store.webhookUrl);
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  // Persists the webhook URL to the store. The URL is optional, but if provided
  // it must be a safe https(/localhost) URL — this blocks the SSRF / scheme
  // injection surface (javascript:, file://, metadata IPs) the field accepted.
  void _save() {
    final store = Provider.of<AppStore>(context, listen: false);
    final url = _webhookController.text.trim();
    final error = Validators.httpUrlError(url, required: false);
    if (error != null) {
      setState(() => _urlError = error);
      return;
    }

    setState(() => _urlError = null);
    store.setWebhookUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Webhook saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppleSectionCard(
          title: 'Webhook Configuration',
          subtitle: 'Receives real-time conversation events from Tavus',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomInputField(
                label: 'Webhook URL',
                placeholder: 'https://api.yourcompany.com/webhook/tavus',
                controller: _webhookController,
                onChanged: (_) {
                  if (_urlError != null) setState(() => _urlError = null);
                },
                hint: 'Receives: conversation.started, conversation.ended, transcription, participant events, errors',
              ),
              if (_urlError != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _urlError!,
                        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        CustomButton(text: 'Save Webhook', onPressed: _save),
      ],
    );
  }
}
