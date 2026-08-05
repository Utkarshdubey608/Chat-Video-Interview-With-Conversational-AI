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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Both streams are cached rather than created inline in build().
  //
  // StreamBuilder keys off stream IDENTITY: handing it a new Stream instance
  // makes it unsubscribe, resubscribe, and reset to ConnectionState.waiting —
  // which here renders _Loading() and DESTROYS the whole signed-in subtree
  // (CandidateShell/RecruiterShell and everything under them). Calling
  // auth.authStateChanges() / auth.roleStream(uid) directly in build() minted
  // a fresh stream on every rebuild, so any incidental rebuild of this widget
  // silently tore down the candidate's screen mid-flow. That is what made
  // _launchVideo see `mounted == false` after the system check returned true,
  // and abort back to the interview list with no error.
  Stream<User?>? _authStream;
  String? _roleUid;
  Stream<AppRole>? _roleStream;

  /// Last role successfully resolved for the signed-in user, so a momentary
  /// dataless emission from [_roleStream] doesn't collapse the tree.
  AppRole? _lastRole;

  Stream<User?> _authStreamFor(AuthService auth) =>
      _authStream ??= auth.authStateChanges();

  Stream<AppRole> _roleStreamFor(AuthService auth, String uid) {
    if (_roleUid != uid) {
      _roleUid = uid;
      _roleStream = auth.roleStream(uid);
    }
    return _roleStream!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: _authStreamFor(auth),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = authSnap.data;
        if (user == null) {
          // Drop the cached role/stream so the next account never inherits the
          // previous one's.
          _lastRole = null;
          _roleUid = null;
          _roleStream = null;
          return const LoginPage();
        }

        return StreamBuilder<AppRole>(
          stream: _roleStreamFor(auth, user.uid),
          builder: (context, roleSnap) {
            // Keep the last known role while the stream is momentarily
            // dataless (e.g. a transient Firestore reconnect). Dropping to
            // _Loading() here would unmount the live interview subtree for the
            // same reason described above.
            final role = roleSnap.data ?? _lastRole;
            if (role == null) return const _Loading();
            _lastRole = role;
            return role == AppRole.recruiter
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
