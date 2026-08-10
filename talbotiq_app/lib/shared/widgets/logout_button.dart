// lib/shared/widgets/logout_button.dart
//
// The single sign-out affordance used across the primary-tab app bars. Kept in
// one place so every surface signs out through the same AuthService seam.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/services/avatar_catalog.dart';

import 'package:talbotiq/features/auth/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  Future<void> _signOut(BuildContext context) async {
    // Read the provider before the first await — using `context` across an
    // async gap is unsafe once the widget may have been unmounted.
    final auth = context.read<AuthService>();
    final avatars = context.read<AvatarCatalog>();
    // No credential is cached on the device any more, but the avatar catalog is
    // org data — drop it so the next account on this device does not inherit
    // another org's avatar list.
    await avatars.clear();
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
