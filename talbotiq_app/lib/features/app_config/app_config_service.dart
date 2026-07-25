// lib/features/app_config/app_config_service.dart
//
// Per-recruiter (per-org) API keys. This service is the application-level policy
// layer; the actual storage/transport of credentials lives behind
// [RecruiterCredentialsRepository] so it can be swapped for a server-side proxy
// without touching this file's callers (Settings for the recruiter write path,
// candidate launch for the read path).
//
// ── Security note (unchanged intent, now behind a seam) ──────────────────────
// Because interviews are currently created on the candidate's device, org keys
// must be in memory at launch. This hides keys from the app UI but is NOT
// cryptographic secrecy. The production fix is a server-side proxy — see
// core/security/recruiter_credentials_repository.dart and functions/. Wiring
// this service to the proxy is a DI change (inject ProxyRecruiterCredentials-
// Repository + route launch through the gateway), no call-site changes needed.

import 'package:talbotiq/core/security/recruiter_credentials.dart';
import 'package:talbotiq/core/security/recruiter_credentials_repository.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';

class AppConfigService {
  AppConfigService({
    RecruiterCredentialsRepository? repository,
    RecruiterCredentialsRepository? candidateRepository,
  })  : _repo = repository ?? FirestoreRecruiterCredentialsRepository(),
        _candidateRepo = candidateRepository ??
            FirestoreRecruiterCredentialsRepository(
                collection: 'candidate_keys');

  final RecruiterCredentialsRepository _repo;

  /// A candidate's own personal key backup — a separate, owner-only-read
  /// Firestore collection (`candidate_keys/{uid}`), distinct from
  /// `recruiter_keys` which candidate devices broadly read at launch.
  final RecruiterCredentialsRepository _candidateRepo;

  RecruiterCredentials _credsFromStore(AppStore store) => RecruiterCredentials(
        tavusKey: store.tavusKey,
        deepgramKey: store.deepgramKey,
        humeKey: store.humeKey,
        awsKey: store.awsKey,
        anthropicKey: store.anthropicKey,
        geminiKey: store.geminiKey,
        awsProxyUrl: store.awsProxyUrl,
        webhookUrl: store.webhookUrl,
      );

  void _applyCredsToStore(RecruiterCredentials creds, AppStore store) {
    store.applyCloudApiKeys(
      tavus: creds.tavusKey,
      deepgram: creds.deepgramKey,
      hume: creds.humeKey,
      aws: creds.awsKey,
      anthropic: creds.anthropicKey,
      gemini: creds.geminiKey,
      awsProxyUrl: creds.awsProxyUrl,
      webhookUrl: creds.webhookUrl,
    );
  }

  /// Writes the recruiter's current [store] keys to their own credentials doc.
  Future<void> pushForRecruiter(String recruiterId, AppStore store) =>
      _repo.save(recruiterId, _credsFromStore(store));

  /// Fetches [recruiterId]'s own credentials from Firestore and persists them
  /// to the device's local storage. Called once at login so a recruiter's
  /// keys are available on this device without re-entering them; the caller
  /// is responsible for clearing them again at logout (see
  /// [AppStore.clearApiKeys]).
  Future<void> pullForRecruiter(String recruiterId, AppStore store) async {
    _applyCredsToStore(await _repo.fetch(recruiterId), store);
  }

  /// Writes a candidate's current [store] keys to their own `candidate_keys`
  /// doc (owner-only — never read by anyone else's interview launch).
  Future<void> pushForCandidate(String uid, AppStore store) =>
      _candidateRepo.save(uid, _credsFromStore(store));

  /// Fetches a candidate's own credentials from Firestore and persists them to
  /// local storage. Mirrors [pullForRecruiter] for the candidate role.
  Future<void> pullForCandidate(String uid, AppStore store) async {
    _applyCredsToStore(await _candidateRepo.fetch(uid), store);
  }

  /// Fetches [recruiterId]'s credentials and applies them to the in-memory
  /// service singletons for the duration of a launch. Does NOT touch the
  /// candidate's own persisted Settings, so org keys are never shown or saved.
  ///
  /// Returns true if a usable Tavus key was found (callers guard video launch
  /// on this). [overrides] are per-test key overrides (from
  /// `Interview.keyOverrides`): any non-empty entry wins over the stored key.
  Future<bool> applyForRecruiter(
    String recruiterId,
    AppStore store, {
    Map<String, String> overrides = const {},
  }) async {
    final creds =
        (await _repo.fetch(recruiterId)).withOverrides(overrides);

    // In-memory only — never persisted to the candidate's Settings. The video
    // results pipeline reads keys off AppStore, so they must live there (not
    // just the service singletons) for the duration of the session.
    store.applyEphemeralApiKeys(
      tavus: creds.tavusKey,
      gemini: creds.geminiKey,
      hume: creds.humeKey,
      deepgram: creds.deepgramKey,
    );
    // Chat scoring runs through a separate Gemini client.
    recruiterGeminiService.setKey(creds.geminiKey);
    return creds.tavusKey.isNotEmpty;
  }
}
