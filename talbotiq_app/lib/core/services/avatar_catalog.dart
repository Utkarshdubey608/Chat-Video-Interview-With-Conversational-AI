// lib/core/services/avatar_catalog.dart
//
// Cached catalog of Tavus replicas (avatars) and personas.
//
// The list changes rarely — an org adds a replica now and then — but four screens
// need it: the candidate's practice launcher, the recruiter's create-interview
// form, and the recruiter's Replicas/Personas management pages. Each of those
// used to call the API on every open, so opening create-interview three times
// meant three round trips (and, per the server log, two upstream Tavus calls
// each, since replicas merges custom + stock).
//
// So: fetch once, keep it in SharedPreferences for [ttl], and only go back to
// the network when it has aged out or the user explicitly asks. Every screen
// shows a Refresh control, which is the ONLY thing that bypasses a fresh cache —
// nothing refetches behind the user's back.
//
// One instance, provided at the app root, so both roles share the same cache and
// a refresh on one screen is immediately visible on the others.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/shared/models/app_models.dart';

class AvatarCatalog extends ChangeNotifier {
  AvatarCatalog({TavusService? tavus, Duration? ttl})
      : _tavus = tavus ?? tavusService,
        ttl = ttl ?? const Duration(hours: 10);

  final TavusService _tavus;

  /// How long a cached catalog is considered current.
  final Duration ttl;

  static const String _prefsKey = 'talbotiq_avatar_catalog';

  List<TavusReplica> _replicas = const [];
  List<TavusPersona> _personas = const [];
  DateTime? _fetchedAt;
  bool _loading = false;
  String? _error;
  Future<void>? _inFlight;
  bool _restored = false;

  List<TavusReplica> get replicas => List.unmodifiable(_replicas);
  List<TavusPersona> get personas => List.unmodifiable(_personas);

  /// When the catalog was last fetched from Tavus, or null if never.
  DateTime? get fetchedAt => _fetchedAt;

  bool get isLoading => _loading;

  /// Set when the last fetch failed. Cached data (if any) is still served.
  String? get error => _error;

  bool get hasData => _replicas.isNotEmpty || _personas.isNotEmpty;

  /// True when there is no data, or what we have has outlived [ttl].
  bool get isStale {
    if (_fetchedAt == null || !hasData) return true;
    return DateTime.now().difference(_fetchedAt!) >= ttl;
  }

  /// "2 hours ago" — for the "last updated" line next to Refresh.
  String get ageLabel {
    final at = _fetchedAt;
    if (at == null) return 'never';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  /// Loads the catalog, using the cache when it is still fresh.
  ///
  /// Safe to call from every screen's `initState`: a fresh cache returns without
  /// touching the network, and concurrent callers share one in-flight fetch
  /// rather than each starting their own.
  Future<void> ensureLoaded() async {
    await _restoreOnce();
    if (!isStale) return;
    return _fetch();
  }

  /// Forces a fetch, ignoring the cache. Only ever called from a Refresh button.
  Future<void> refresh() async {
    await _restoreOnce();
    return _fetch(force: true);
  }

  Future<void> _fetch({bool force = false}) {
    // Coalesce: four screens mounting at once must not fire four fetches.
    final existing = _inFlight;
    if (existing != null && !force) return existing;

    final future = _doFetch();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _doFetch() async {
    _loading = true;
    _error = null;
    notifyListeners();

    // Two independent calls, settled INDEPENDENTLY.
    //
    // `Future.wait` is all-or-nothing: one failure discards the other's result.
    // That bit for real — a tunnel timed out the personas request while replicas
    // returned 200, and the successful avatar list was thrown away, leaving an
    // empty picker and a "504" the backend log flatly contradicted.
    //
    // Replicas are what the pickers actually need; personas are optional
    // decoration. So each is kept on its own merits.
    final replicas = await _attempt(_tavus.listReplicas);
    final personas = await _attempt(_tavus.listPersonas);

    if (replicas.value != null) _replicas = replicas.value!;
    if (personas.value != null) _personas = personas.value!;

    if (replicas.value != null) {
      // Stamped on the PRIMARY call succeeding. Requiring both would mean a
      // permanently-failing personas endpoint refetches replicas on every screen
      // open; a manual Refresh is the retry path.
      _fetchedAt = DateTime.now();
      await _persist();
    }

    // Only surface an error the user can act on: a failure that left the picker
    // usable (cached or freshly fetched replicas) is not worth a message.
    if (_replicas.isEmpty) {
      _error = replicas.error ?? personas.error;
    } else if (replicas.error != null) {
      _error = replicas.error;
    }
    if (replicas.error != null || personas.error != null) {
      debugPrint('AvatarCatalog: replicas=${replicas.error ?? 'ok'} '
          'personas=${personas.error ?? 'ok'}');
    }

    _loading = false;
    notifyListeners();
  }

  /// Runs one fetch, returning its value or its message — never throwing.
  Future<_Attempt<T>> _attempt<T>(Future<T> Function() run) async {
    try {
      return _Attempt(value: await run());
    } catch (e) {
      return _Attempt(error: e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── persistence ───────────────────────────────────────────────────────────

  /// Reads the cache from disk exactly once per instance.
  Future<void> _restoreOnce() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      _fetchedAt = DateTime.tryParse(data['fetchedAt'] as String? ?? '');
      _replicas = ((data['replicas'] as List?) ?? const [])
          .map((r) => TavusReplica.fromJson(r))
          .toList();
      _personas = ((data['personas'] as List?) ?? const [])
          .map((p) => TavusPersona.fromJson(p))
          .toList();
      notifyListeners();
    } catch (e) {
      // A malformed or schema-changed cache must not break the picker — treat it
      // as absent and refetch.
      debugPrint('AvatarCatalog: discarding unreadable cache ($e)');
      _replicas = const [];
      _personas = const [];
      _fetchedAt = null;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'fetchedAt': _fetchedAt?.toIso8601String(),
          'replicas': _replicas.map((r) => r.toJson()).toList(),
          'personas': _personas.map((p) => p.toJson()).toList(),
        }),
      );
    } catch (e) {
      // Losing the cache costs a refetch next launch, nothing more.
      debugPrint('AvatarCatalog: could not persist cache ($e)');
    }
  }

  /// Drops the cache from memory and disk. Used at sign-out so the next account
  /// on this device does not inherit another org's avatar list.
  Future<void> clear() async {
    _replicas = const [];
    _personas = const [];
    _fetchedAt = null;
    _error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Nothing actionable.
    }
  }
}

/// One settled fetch: a value or a message, never both, never a throw.
///
/// Exists so the two catalog calls can fail independently — see the note in
/// `_doFetch` about `Future.wait` discarding a successful result.
class _Attempt<T> {
  const _Attempt({this.value, this.error});
  final T? value;
  final String? error;
}
