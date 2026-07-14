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

import '../../core/security/recruiter_credentials.dart';
import '../../core/security/recruiter_credentials_repository.dart';
import '../../providers/app_store.dart';
import '../recruiter/services/recruiter_gemini_service.dart';

class AppConfigService {
  AppConfigService({RecruiterCredentialsRepository? repository})
      : _repo = repository ?? FirestoreRecruiterCredentialsRepository();

  final RecruiterCredentialsRepository _repo;

  /// Writes the recruiter's current [store] keys to their own credentials doc.
  Future<void> pushForRecruiter(String recruiterId, AppStore store) {
    final creds = RecruiterCredentials(
      tavusKey: store.tavusKey,
      deepgramKey: store.deepgramKey,
      humeKey: store.humeKey,
      awsKey: store.awsKey,
      anthropicKey: store.anthropicKey,
      geminiKey: store.geminiKey,
      awsProxyUrl: store.awsProxyUrl,
      webhookUrl: store.webhookUrl,
    );
    return _repo.save(recruiterId, creds);
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
