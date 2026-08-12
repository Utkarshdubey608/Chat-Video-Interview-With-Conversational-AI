// lib/features/auth/desktop_access_denied_page.dart
//
// Talbotiq Desktop is a recruiter-only client. A candidate account can still
// authenticate successfully (Firebase auth itself doesn't know about desktop
// scoping), so AuthGate routes them here instead of CandidateShell — never
// into recruiter functionality, and never silently. The only action offered
// is signing out; there is no candidate UI on desktop to fall back to.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/auth/auth_service.dart';
import 'package:provider/provider.dart';

class DesktopAccessDeniedPage extends StatelessWidget {
  const DesktopAccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_outlined,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 20),
                Text(
                  'This account cannot use Talbotiq Desktop',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'Talbotiq Desktop is built for recruiters. This account is '
                  'set up as a candidate — please continue on the Talbotiq '
                  'mobile or web app instead.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.read<AuthService>().signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
