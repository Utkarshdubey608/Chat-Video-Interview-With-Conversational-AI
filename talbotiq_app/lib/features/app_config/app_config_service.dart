// lib/features/app_config/app_config_service.dart
//
// Per-recruiter (per-org) API keys. Each recruiter's keys live in the Firestore
// doc `recruiter_keys/{recruiterId}`, written from Settings by that recruiter.
//
// Candidates NEVER store org keys in their own AppStore/Settings (which would
// surface them in the UI). Instead, at the moment a candidate launches an
// assigned interview, we fetch that interview's recruiter keys and apply them
// to the in-memory service singletons ONLY — not persisted, not shown anywhere.
// Because each interview carries its recruiterId, one org's interview always
// uses that org's keys and never consumes another org's credentials.
//
// Note (accepted trade-off): since interviews are created on the candidate's
// device, the key is necessarily in memory at launch, so this hides keys from
// the app UI rather than being cryptographically secret. True secrecy would
// require a server-side proxy.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/app_store.dart';
import '../recruiter/services/recruiter_gemini_service.dart';

class AppConfigService {
  AppConfigService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String recruiterId) =>
      _db.collection('recruiter_keys').doc(recruiterId);

  /// Writes the recruiter's current [store] keys to their own key doc.
  Future<void> pushForRecruiter(String recruiterId, AppStore store) async {
    await _doc(recruiterId).set({
      'tavusKey': store.tavusKey,
      'deepgramKey': store.deepgramKey,
      'humeKey': store.humeKey,
      'awsKey': store.awsKey,
      'anthropicKey': store.anthropicKey,
      'geminiKey': store.geminiKey,
      'awsProxyUrl': store.awsProxyUrl,
      'webhookUrl': store.webhookUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetches [recruiterId]'s keys and applies them to the in-memory service
  /// singletons for the duration of a launch. Does NOT touch AppStore, so the
  /// candidate's own Settings/keys are untouched and org keys are never shown.
  ///
  /// Returns true if a usable Tavus key was found (callers guard video launch
  /// on this). Each call fully re-establishes the org's keys, so switching
  /// between interviews from different recruiters never mixes credentials.
  Future<bool> applyForRecruiter(String recruiterId, AppStore store) async {
    final snap = await _doc(recruiterId).get();
    final d = snap.data();
    if (d == null) return false;

    String k(String key) {
      final v = d[key];
      return v is String ? v.trim() : '';
    }

    final tavus = k('tavusKey');
    final gemini = k('geminiKey');
    // In-memory only — never persisted to the candidate's Settings. The video
    // results pipeline reads keys off AppStore, so they must live there (not
    // just the service singletons) for the duration of the session.
    store.applyEphemeralApiKeys(
      tavus: tavus,
      gemini: gemini,
      hume: k('humeKey'),
      deepgram: k('deepgramKey'),
    );
    // Chat scoring runs through a separate Gemini client.
    recruiterGeminiService.setKey(gemini);
    return tavus.isNotEmpty;
  }
}
