// lib/features/auth/app_role.dart
//
// The two account roles. A user's role is chosen at sign-up and stored on their
// `users/{uid}` Firestore doc; login routes by the stored role (see AuthGate).

enum AppRole { recruiter, candidate }

extension AppRoleX on AppRole {
  /// Stable wire value stored in Firestore.
  String get wire => this == AppRole.recruiter ? 'recruiter' : 'candidate';

  /// Human label for the UI.
  String get label => this == AppRole.recruiter ? 'Recruiter' : 'Candidate';

  static AppRole fromWire(String? value) =>
      value == 'recruiter' ? AppRole.recruiter : AppRole.candidate;
}
