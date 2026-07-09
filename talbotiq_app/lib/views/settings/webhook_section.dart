// lib/views/settings/webhook_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_store.dart';
import '../../widgets/custom_buttons.dart';
import '../../widgets/custom_inputs.dart';
import '../../widgets/apple_ui.dart';

/// Settings category: the Tavus event webhook URL.
class WebhookSection extends StatefulWidget {
  const WebhookSection({super.key});

  @override
  State<WebhookSection> createState() => _WebhookSectionState();
}

class _WebhookSectionState extends State<WebhookSection> {
  late TextEditingController _webhookController;

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

  // Persists the webhook URL to the store.
  void _save() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setWebhookUrl(_webhookController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Webhook saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppleSectionCard(
          title: 'Webhook Configuration',
          subtitle: 'Receives real-time conversation events from Tavus',
          child: CustomInputField(
            label: 'Webhook URL',
            placeholder: 'https://api.yourcompany.com/webhook/tavus',
            controller: _webhookController,
            hint: 'Receives: conversation.started, conversation.ended, transcription, participant events, errors',
          ),
        ),
        const SizedBox(height: 24),
        CustomButton(text: 'Save Webhook', onPressed: _save),
      ],
    );
  }
}
