// lib/shared/widgets/logout_button.dart
//
// The single sign-out affordance used across the primary-tab app bars. Kept in
// one place so every surface signs out through the same AuthService seam.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/features/auth/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () => context.read<AuthService>().signOut(),
    );
  }
}
