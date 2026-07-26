// lib/shared/widgets/logout_button.dart
//
// The single sign-out affordance used across the primary-tab app bars. Kept in
// one place so every surface signs out through the same AuthService seam.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/auth/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  Future<void> _signOut(BuildContext context) async {
    // Read providers before the first await — using `context` across an
    // async gap is unsafe once the widget may have been unmounted.
    final store = context.read<AppStore>();
    final auth = context.read<AuthService>();
    // Clear the cloud-synced API keys from local storage before signing out,
    // so the next person to open the app on this device can't reuse them.
    await store.clearApiKeys();
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () => _signOut(context),
    );
  }
}
