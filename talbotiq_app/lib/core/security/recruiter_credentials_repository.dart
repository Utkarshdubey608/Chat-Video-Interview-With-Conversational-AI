// lib/core/security/recruiter_credentials_repository.dart
//
// The single seam through which recruiter/org API credentials are read and
// written. Isolating this lets us migrate off the current (insecure) model —
// where raw keys are stored in Firestore and read by candidate devices — to a
// server-side proxy WITHOUT touching every caller.
//
// ── Security context (OWASP Mobile M1/M9: hardcoded/leaked secrets) ──────────
// The `recruiter_keys/{recruiterId}` doc holds billable third-party secrets
// (Tavus, Gemini, Hume, Deepgram, Anthropic, AWS). Today `firestore.rules`
// allows any signed-in user to READ it, because a candidate's device needs the
// keys to create the Tavus conversation / run scoring client-side. That means
// the keys are, by construction, only "hidden" from the UI — not secret.
//
// The production architecture (see functions/ and ConversationGateway/
// ScoringGateway) moves those calls SERVER-SIDE: the candidate device asks a
// Cloud Function to create the conversation / score the interview; the function
// reads the keys with the Admin SDK and returns only the result. Keys never
// leave the backend, and the `recruiter_keys` read rule can then be locked to
// the owning recruiter.
//
// This file provides both implementations behind one interface so the switch is
// a one-line DI change once the backend is deployed.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:talbotiq/core/security/recruiter_credentials.dart';

abstract class RecruiterCredentialsRepository {
  /// Reads a recruiter/org's credentials.
  Future<RecruiterCredentials> fetch(String recruiterId);

  /// Persists a recruiter's own credentials (recruiter-only path).
  Future<void> save(String recruiterId, RecruiterCredentials creds);
}

/// Current transport: reads/writes `recruiter_keys/{recruiterId}` directly.
///
/// NOTE: this is only as secure as `firestore.rules`. It is the correct path
/// for the RECRUITER writing their own keys, and an acceptable transitional
/// path for candidate reads until the proxy (below) is deployed. See the file
/// header for the migration.
class FirestoreRecruiterCredentialsRepository
    implements RecruiterCredentialsRepository {
  FirestoreRecruiterCredentialsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String recruiterId) =>
      _db.collection('recruiter_keys').doc(recruiterId);

  @override
  Future<RecruiterCredentials> fetch(String recruiterId) async {
    final snap = await _doc(recruiterId).get();
    return RecruiterCredentials.fromMap(snap.data() ?? const {});
  }

  @override
  Future<void> save(String recruiterId, RecruiterCredentials creds) {
    return _doc(recruiterId).set(
      {...creds.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}

/// Production transport placeholder: the candidate device must NEVER receive
/// raw keys. Instead, launch/scoring go through [ConversationGateway] /
/// [ScoringGateway] (Cloud Functions), and this repository is used only by the
/// recruiter to write their own keys via an authenticated callable.
///
/// TODO(backend): implement against the deployed Cloud Functions
/// (`saveRecruiterKeys` callable) and remove candidate-side `fetch`. Requires
/// the functions in functions/ to be deployed and their base URL configured.
class ProxyRecruiterCredentialsRepository
    implements RecruiterCredentialsRepository {
  @override
  Future<RecruiterCredentials> fetch(String recruiterId) {
    throw UnimplementedError(
      'Candidate devices must not read raw recruiter keys. Route launch/scoring '
      'through the Cloud Functions gateway (see functions/).',
    );
  }

  @override
  Future<void> save(String recruiterId, RecruiterCredentials creds) {
    throw UnimplementedError(
      'TODO(backend): call the authenticated `saveRecruiterKeys` Cloud Function.',
    );
  }
}
