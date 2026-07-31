// lib/features/settings/sections/mailer_section.dart
//
// Settings category: where the candidate-invite emails are sent from. Points
// the app at the TalbotIQ mailer backend (see backend/README.md). Until a URL
// is saved here, the "Email Candidates" option on Create Interview stays hidden.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/utils/validators.dart';
import 'package:talbotiq/features/mailer/services/mailer_service.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/shared/widgets/apple_ui.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/custom_inputs.dart';

class MailerSection extends StatefulWidget {
  const MailerSection({super.key});

  @override
  State<MailerSection> createState() => _MailerSectionState();
}

class _MailerSectionState extends State<MailerSection> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  String? _urlError;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    _urlController = TextEditingController(text: store.mailerBaseUrl);
    _keyController = TextEditingController(text: store.mailerApiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _save() {
    final store = context.read<AppStore>();
    final url = _urlController.text.trim();
    // Optional: an empty URL simply turns the email feature off.
    final error = Validators.httpUrlError(url, required: false);
    if (error != null) {
      setState(() => _urlError = error);
      return;
    }
    setState(() => _urlError = null);
    store.setMailerBaseUrl(url);
    store.setMailerApiKey(_keyController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Mail server saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// Asks the server for its template list — proves the URL, the API key and
  /// the recruiter's own template access in one round trip.
  Future<void> _test() async {
    final url = _urlController.text.trim();
    if (Validators.httpUrlError(url, required: false) != null || url.isEmpty) {
      setState(() => _urlError = 'Enter the mail server URL first.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
      _urlError = null;
    });

    final service = MailerService(baseUrl: url, apiKey: _keyController.text.trim());
    try {
      // Scoped to the signed-in account, so this also proves that reading this
      // recruiter's own saved templates works — not just that the host is up.
      final catalog = await service.listTemplates(
        ownerEmail: FirebaseAuth.instance.currentUser?.email ?? '',
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = '${catalog.templates.length} template(s) available.';
      });
    } on MailerException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e.message;
      });
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppleSectionCard(
          title: 'Candidate Emails',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The TalbotIQ mailer service sends interview invites and stores '
                'your email templates. Leave the URL empty to turn candidate '
                'emails off.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'Mail Server URL',
                placeholder: 'https://mailer.talbotiq.com',
                controller: _urlController,
                keyboardType: TextInputType.url,
              ),
              if (_urlError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _urlError!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              CustomInputField(
                label: 'API Key (optional)',
                placeholder: 'Only if the server sets API_KEY',
                controller: _keyController,
                isPassword: true,
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testOk ? Icons.check_circle_outline : Icons.error_outline,
                      size: 18,
                      color: _testOk ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_testResult!, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Test Connection',
                      variant: ButtonVariant.outline,
                      height: 46,
                      isLoading: _testing,
                      onPressed: _testing ? () {} : _test,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      text: 'Save',
                      height: 46,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
