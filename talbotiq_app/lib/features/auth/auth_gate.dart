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

import '../interviews/candidate/candidate_home.dart';
import '../interviews/recruiter/recruiter_home.dart';
import 'app_role.dart';
import 'auth_service.dart';
import 'login_page.dart';

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
                ? const RecruiterHome()
                : const CandidateHome();
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
