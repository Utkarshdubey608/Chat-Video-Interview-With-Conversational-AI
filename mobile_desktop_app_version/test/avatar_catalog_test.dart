// test/avatar_catalog_test.dart
//
// The point of AvatarCatalog is "don't call Tavus again for 10 hours unless the
// user asks", so these tests count calls rather than inspect output.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talbotiq/core/services/avatar_catalog.dart';
import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/shared/models/app_models.dart';

/// Counts calls and can be made to fail on demand.
class _CountingTavus extends TavusService {
  int replicaCalls = 0;
  int personaCalls = 0;
  bool fail = false;
  bool failReplicasOnly = false;
  bool failPersonasOnly = false;

  @override
  Future<List<TavusReplica>> listReplicas() async {
    replicaCalls++;
    if (fail || failReplicasOnly) throw Exception('network down');
    return [TavusReplica.fromJson({'replica_id': 'r1', 'replica_name': 'Ada'})];
  }

  @override
  Future<List<TavusPersona>> listPersonas() async {
    personaCalls++;
    if (fail || failPersonasOnly) throw Exception('gateway timeout');
    return [TavusPersona.fromJson({'persona_id': 'p1', 'persona_name': 'HR'})];
  }
}

void main() {
  late _CountingTavus tavus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tavus = _CountingTavus();
  });

  AvatarCatalog build({Duration? ttl}) =>
      AvatarCatalog(tavus: tavus, ttl: ttl ?? const Duration(hours: 10));

  test('first load fetches; a second load inside the window does not', () async {
    final catalog = build();

    await catalog.ensureLoaded();
    expect(tavus.replicaCalls, 1);
    expect(tavus.personaCalls, 1);
    expect(catalog.replicas, hasLength(1));

    // Re-opening any screen must not cost a round trip.
    await catalog.ensureLoaded();
    await catalog.ensureLoaded();
    expect(tavus.replicaCalls, 1);
  });

  test('an expired window refetches on the next load', () async {
    final catalog = build(ttl: Duration.zero);
    await catalog.ensureLoaded();
    await catalog.ensureLoaded();
    expect(tavus.replicaCalls, 2);
  });

  test('refresh always refetches, even when fresh', () async {
    final catalog = build();
    await catalog.ensureLoaded();
    expect(tavus.replicaCalls, 1);

    await catalog.refresh();
    expect(tavus.replicaCalls, 2);
  });

  test('concurrent loads share one fetch', () async {
    final catalog = build();
    // Four screens mounting at once must not fire four fetches.
    await Future.wait([
      catalog.ensureLoaded(),
      catalog.ensureLoaded(),
      catalog.ensureLoaded(),
      catalog.ensureLoaded(),
    ]);
    expect(tavus.replicaCalls, 1);
  });

  test('the cache survives a new instance, with no fetch', () async {
    await build().ensureLoaded();
    expect(tavus.replicaCalls, 1);

    // A fresh instance = an app relaunch.
    final revived = build();
    await revived.ensureLoaded();
    expect(tavus.replicaCalls, 1, reason: 'restored from prefs, not refetched');
    expect(revived.replicas, hasLength(1));
    expect(revived.fetchedAt, isNotNull);
  });

  test('a failed refresh keeps the cached list usable', () async {
    final catalog = build();
    await catalog.ensureLoaded();

    tavus.fail = true;
    await catalog.refresh();

    // Serving a stale avatar list beats emptying the picker.
    expect(catalog.replicas, hasLength(1));
    expect(catalog.error, contains('network down'));
  });

  test('a first load that fails reports it and leaves the catalog empty',
      () async {
    tavus.fail = true;
    final catalog = build();
    await catalog.ensureLoaded();

    expect(catalog.replicas, isEmpty);
    expect(catalog.error, isNotNull);
    expect(catalog.isStale, isTrue, reason: 'nothing cached, so still stale');
  });

  test('clear() drops memory and disk', () async {
    final catalog = build();
    await catalog.ensureLoaded();
    await catalog.clear();

    expect(catalog.replicas, isEmpty);
    expect(catalog.fetchedAt, isNull);

    // A new instance must not resurrect it from prefs.
    final revived = build();
    await revived.ensureLoaded();
    expect(tavus.replicaCalls, 2);
  });

  test('an unreadable cache is discarded rather than thrown', () async {
    SharedPreferences.setMockInitialValues(
        {'talbotiq_avatar_catalog': 'not json'});
    final catalog = build();
    await catalog.ensureLoaded();
    expect(catalog.replicas, hasLength(1), reason: 'refetched after discarding');
  });

  // ── partial failure ───────────────────────────────────────────────────────
  //
  // The incident: the tunnel timed out /api/tavus/personas while
  // /api/tavus/replicas returned 200. `Future.wait` discarded the successful
  // replicas with the failure, so the picker was empty and the app reported 504
  // for a call the backend had logged as OK.
  test('a personas failure does not discard successful replicas', () async {
    tavus.failPersonasOnly = true;
    final catalog = build();
    await catalog.ensureLoaded();

    expect(catalog.replicas, hasLength(1), reason: 'replicas succeeded');
    expect(catalog.personas, isEmpty);
    // The picker works, so there is nothing for the user to act on.
    expect(catalog.error, isNull);
    expect(catalog.fetchedAt, isNotNull, reason: 'primary call succeeded');
  });

  test('a partial success is cached, so reopening costs no round trip', () async {
    tavus.failPersonasOnly = true;
    await build().ensureLoaded();
    expect(tavus.replicaCalls, 1);

    final revived = build();
    await revived.ensureLoaded();
    expect(tavus.replicaCalls, 1, reason: 'served from cache');
    expect(revived.replicas, hasLength(1));
  });

  test('a replicas failure IS reported, since the picker is then empty',
      () async {
    tavus.failReplicasOnly = true;
    final catalog = build();
    await catalog.ensureLoaded();

    expect(catalog.replicas, isEmpty);
    expect(catalog.error, contains('network down'));
  });

  test('cached replicas survive a later replicas failure', () async {
    final catalog = build();
    await catalog.ensureLoaded();

    tavus.failReplicasOnly = true;
    await catalog.refresh();

    // Stale avatars beat an empty picker; the error rides alongside them.
    expect(catalog.replicas, hasLength(1));
    expect(catalog.error, contains('network down'));
  });

  test('ageLabel reads sensibly', () async {
    final catalog = build();
    expect(catalog.ageLabel, 'never');
    await catalog.ensureLoaded();
    expect(catalog.ageLabel, 'just now');
  });
}
