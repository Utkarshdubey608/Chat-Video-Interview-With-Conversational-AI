// lib/features/settings/sections/mailer_section.dart
//
// Settings category: the status of candidate-invite email.
//
// Read-only by design. The backend URL is compiled in via
// `--dart-define=BACKEND_BASE_URL` (see lib/core/net/backend_config.dart), and
// there is no API key to enter — the mailer authenticates the same way every
// other backend call does. What remains useful is a connection test: it proves
// the deployed backend is reachable AND that this recruiter's own saved
// templates load, which is what "Email Candidates" depends on.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:talbotiq/core/net/backend_config.dart';
import 'package:talbotiq/features/mailer/services/mailer_service.dart';
import 'package:talbotiq/shared/widgets/apple_ui.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';

class MailerSection extends StatefulWidget {
  const MailerSection({super.key});

  @override
  State<MailerSection> createState() => _MailerSectionState();
}

class _MailerSectionState extends State<MailerSection> {
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  /// Asks the server for its template list — proves the backend is reachable and
  /// that this recruiter's own template access works, in one round trip.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final service = MailerService();
    try {
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
    final configured = BackendConfig.isConfigured;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppleSectionCard(
          title: 'Candidate Emails',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Interview invites and your saved email templates are handled by '
                'the TalbotIQ backend. It is configured when the app is built, so '
                'there is nothing to enter here.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _statusRow(
                theme,
                ok: configured,
                label: configured ? 'Backend' : 'Backend not configured',
                detail: configured
                    ? BackendConfig.baseUrl
                    : BackendConfig.configHint ?? '',
              ),
              if (configured && BackendConfig.isLocal) ...[
                const SizedBox(height: 8),
                Text(
                  'This is a local development server — it will not be reachable '
                  'from a real device.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                _statusRow(theme, ok: _testOk, label: _testResult!),
              ],
              const SizedBox(height: 20),
              CustomButton(
                text: 'Test Connection',
                variant: ButtonVariant.outline,
                height: 46,
                isLoading: _testing,
                onPressed: (_testing || !configured) ? () {} : _test,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusRow(
    ThemeData theme, {
    required bool ok,
    required String label,
    String? detail,
  }) {
    final colour = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 18,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              if (detail != null && detail.isNotEmpty)
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Courier',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
