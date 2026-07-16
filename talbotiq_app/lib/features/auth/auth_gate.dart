// lib/features/auth/auth_gate.dart
//
// The root router. Reacts to FirebaseAuth state:
//   - signed out            → LoginPage
//   - signed in + recruiter → RecruiterHome
//   - signed in + candidate → CandidateHome
// Role comes from the users/{uid} doc (live stream, so a freshly-created doc
// re-routes without a restart).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/features/interviews/candidate/candidate_shell.dart';
import 'package:talbotiq/features/interviews/recruiter/recruiter_shell.dart';
import 'package:talbotiq/features/auth/app_role.dart';
import 'package:talbotiq/features/auth/auth_service.dart';
import 'package:talbotiq/features/auth/login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = authSnap.data;
        if (user == null) return const LoginPage();

        return StreamBuilder<AppRole>(
          stream: auth.roleStream(user.uid),
          builder: (context, roleSnap) {
            if (!roleSnap.hasData) return const _Loading();
            return roleSnap.data == AppRole.recruiter
                ? const RecruiterShell()
                : const CandidateShell();
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
