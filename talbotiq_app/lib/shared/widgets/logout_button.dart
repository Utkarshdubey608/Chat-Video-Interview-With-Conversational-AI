// lib/shared/widgets/logout_button.dart
//
// The single sign-out affordance used across the primary-tab app bars. Kept in
// one place so every surface signs out through the same AuthService seam.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/features/auth/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  Future<void> _signOut(BuildContext context) async {
    // Read the provider before the first await — using `context` across an
    // async gap is unsafe once the widget may have been unmounted.
    final auth = context.read<AuthService>();
    // Nothing credential-shaped is cached on the device any more, so signing out
    // is just signing out. (This used to also wipe cloud-synced API keys.)
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
