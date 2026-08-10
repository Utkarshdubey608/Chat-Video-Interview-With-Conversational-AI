// lib/features/interviews/services/interview_repository.dart
//
// Firestore access for the `interviews` collection. Role-scoped queries:
//   - recruiters watch interviews they created (recruiterId == uid)
//   - candidates watch interviews assigned to them (candidateEmailLower == email)
// Security rules (firestore.rules) enforce the same scoping server-side.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/test_summary.dart';

/// Owns all Firestore access for the `interviews` collection: CRUD plus the
/// recruiter/candidate query streams and the attempt/status/result mutations.
/// UI and controllers go through this repository — no widget touches Firestore
/// directly.
class InterviewRepository {
  InterviewRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('interviews');

  /// Per-batch metadata, one doc per `testId` (see [TestSummary]). Lets the
  /// dashboard page over tests instead of reading every interview to group them.
  CollectionReference<Map<String, dynamic>> get _tests =>
      _db.collection('tests');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// Creates a new assigned interview; returns the created id.
  Future<String> create(Interview interview) async {
    final ref = await _col.add(interview.toCreateMap());
    return ref.id;
  }

  // ── Paged reads ───────────────────────────────────────────────────────────
  //
  // `watchForRecruiter` below streams the recruiter's ENTIRE collection. That
  // is fine for the analytics dashboard (which must aggregate everything) but
  // does not scale for the candidate list: 1,000+ candidates means one huge
  // read and 1,000 widgets. The methods here fetch bounded pages instead, and
  // use Firestore's count() aggregate so the UI can still show TRUE totals
  // ("312 candidates") without downloading the rows to count them.

  /// Default candidates per page. Small enough to render instantly, large
  /// enough that a recruiter rarely pages more than once or twice.
  static const int defaultPageSize = 25;

  /// Fetches one page of the recruiter's interviews, newest first.
  ///
  /// Pass [startAfter] (the previous page's [PagedInterviews.lastDoc]) to get
  /// the next page. Optionally narrow to a single [testId], or to candidates
  /// whose email starts with [emailPrefix].
  ///
  /// Cursor is the document snapshot, not a `createdAt` value: `createdAt` is
  /// a server timestamp and reads back momentarily null on a just-created doc,
  /// which would make a value-based cursor skip or repeat rows.
  Future<PagedInterviews> fetchRecruiterPage({
    required String recruiterId,
    int limit = defaultPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    String? testId,
    String? emailPrefix,
  }) async {
    if (recruiterId.isEmpty) return const PagedInterviews.empty();

    // The recruiterId equality must stay on every query: firestore.rules
    // grants recruiter reads via `resource.data.recruiterId == uid`, and
    // dropping it makes the query unprovable and fails with permission-denied.
    Query<Map<String, dynamic>> q =
        _col.where('recruiterId', isEqualTo: recruiterId);
    if (testId != null && testId.isNotEmpty) {
      q = q.where('testId', isEqualTo: testId);
    }

    final prefix = emailPrefix?.trim().toLowerCase() ?? '';
    if (prefix.isEmpty) {
      q = q.orderBy('createdAt', descending: true);
    } else {
      // A range filter forces its field to be the first orderBy, so an email
      // search is ordered by email rather than recency. \uf8ff is the highest
      // code point Firestore sorts, making [prefix, prefix+\uf8ff) a
      // "starts-with" range.
      q = q
          .where('candidateEmailLower', isGreaterThanOrEqualTo: prefix)
          .where('candidateEmailLower', isLessThan: '$prefix\uf8ff')
          .orderBy('candidateEmailLower');
    }

    if (startAfter != null) q = q.startAfterDocument(startAfter);

    // Ask for one extra row: if it comes back there is another page, and we
    // learn that without a second round trip.
    final snap = await q.limit(limit + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > limit;
    final pageDocs = hasMore ? docs.sublist(0, limit) : docs;

    return PagedInterviews(
      items: _parseDocs(pageDocs),
      lastDoc: pageDocs.isEmpty ? null : pageDocs.last,
      hasMore: hasMore,
    );
  }

  /// Server-side count of the recruiter's interviews, optionally scoped to one
  /// [testId] and/or [status]. Uses Firestore's count() aggregate, which bills
  /// far less than reading the documents and does not transfer them, so the UI
  /// can show real totals while only holding a page in memory.
  Future<int> countForRecruiter({
    required String recruiterId,
    String? testId,
    InterviewStatus? status,
  }) async {
    if (recruiterId.isEmpty) return 0;
    try {
      Query<Map<String, dynamic>> q =
          _col.where('recruiterId', isEqualTo: recruiterId);
      if (testId != null && testId.isNotEmpty) {
        q = q.where('testId', isEqualTo: testId);
      }
      if (status != null) {
        q = q.where('status', isEqualTo: status.wire);
      }
      final agg = await q.count().get();
      return agg.count ?? 0;
    } catch (e) {
      // A missing composite index or offline device must not break the list —
      // callers treat -1 as "unknown" and fall back to the loaded count.
      debugPrint('InterviewRepository.countForRecruiter failed: $e');
      return -1;
    }
  }

  /// Live list of interviews a recruiter created, newest first.
  ///
  /// UNBOUNDED — reads every matching document. Keep this for consumers that
  /// genuinely need the whole corpus (the analytics dashboard aggregates over
  /// it). List UIs should use [fetchRecruiterPage] instead.
  Stream<List<Interview>> watchForRecruiter(String recruiterId) {
    return _col
        .where('recruiterId', isEqualTo: recruiterId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => _parseDocs(s.docs));
  }

  /// Live list of interviews assigned to a candidate email, newest first.
  Stream<List<Interview>> watchForCandidate(String candidateEmail) {
    return _col
        .where('candidateEmailLower', isEqualTo: normalizeEmail(candidateEmail))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => _parseDocs(s.docs));
  }

  /// Parses a snapshot's docs one at a time, dropping any single document that
  /// fails to parse. A malformed record therefore can't break the whole
  /// dashboard — the remaining valid interviews still render.
  List<Interview> _parseDocs(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Interview>[];
    for (final doc in docs) {
      try {
        out.add(Interview.fromDoc(doc));
      } catch (e) {
        debugPrint('InterviewRepository: skipping bad doc ${doc.id}: $e');
      }
    }
    return out;
  }

  Future<Interview?> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      return doc.exists ? Interview.fromDoc(doc) : null;
    } catch (e) {
      // Permission-denied or a malformed document should surface as "not
      // found" to the caller rather than leaking a raw Firestore/parse error.
      debugPrint('InterviewRepository.getById($id) failed: $e');
      return null;
    }
  }

  /// Updates the editable fields of an existing interview.
  Future<void> update(Interview interview) {
    return _col.doc(interview.id).update(interview.toUpdateMap());
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Records one more attempt (called when the candidate launches).
  Future<void> incrementAttempt(String id) {
    return _col.doc(id).update({
      'attemptsUsed': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateStatus(String id, InterviewStatus status) {
    return _col.doc(id).update({
      'status': status.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks an interview completed and stores an (unpublished) result. The
  /// candidate does not see it until the recruiter publishes.
  Future<void> completeWithResult(String id, Map<String, dynamic> result) {
    return _col.doc(id).update({
      'status': InterviewStatus.completed.wire,
      'result': result,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Recruiter saves an edited/manual result (does not change publish state).
  Future<void> saveResult(String id, Map<String, dynamic> result) {
    return _col.doc(id).update({
      'result': result,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Show/hide a single candidate's result.
  Future<void> setPublished(String id, bool published) {
    return _col.doc(id).update({
      'resultPublished': published,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  // ── Tests (batch metadata) ────────────────────────────────────────────────

  /// Records/updates the metadata doc for a test. Called when a test is created
  /// or edited, and by [backfillTests]. merge:true keeps this idempotent.
  Future<void> upsertTest(TestSummary test) {
    if (test.testId.isEmpty) return Future.value();
    return _tests.doc(test.testId).set(test.toMap(), SetOptions(merge: true));
  }

  /// One page of the recruiter's tests, newest first.
  Future<PagedTests> fetchTestsPage({
    required String recruiterId,
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    if (recruiterId.isEmpty) return const PagedTests.empty();
    Query<Map<String, dynamic>> q = _tests
        .where('recruiterId', isEqualTo: recruiterId)
        .orderBy('createdAt', descending: true);
    if (startAfter != null) q = q.startAfterDocument(startAfter);

    final snap = await q.limit(limit + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > limit;
    final pageDocs = hasMore ? docs.sublist(0, limit) : docs;

    final out = <TestSummary>[];
    for (final d in pageDocs) {
      try {
        out.add(TestSummary.fromDoc(d));
      } catch (e) {
        debugPrint('InterviewRepository: skipping bad test doc ${d.id}: $e');
      }
    }
    return PagedTests(
      items: out,
      lastDoc: pageDocs.isEmpty ? null : pageDocs.last,
      hasMore: hasMore,
    );
  }

  /// Creates the `tests` metadata docs for a recruiter's pre-existing
  /// interviews — the one-off migration for tests created before this
  /// collection existed.
  ///
  /// Reads every interview for the recruiter ONCE (the very cost this
  /// collection exists to avoid, paid a single time), derives one summary per
  /// distinct `testId`, and batch-writes them. Fully idempotent thanks to
  /// merge:true, so a repeat run is harmless and it doubles as a "rebuild the
  /// test index" repair action. Returns how many test docs were written.
  Future<int> backfillTests(String recruiterId) async {
    if (recruiterId.isEmpty) return 0;
    final snap =
        await _col.where('recruiterId', isEqualTo: recruiterId).get();

    // Keep the newest interview per test: its title/type/createdAt is the most
    // representative for the batch.
    final byTest = <String, Interview>{};
    for (final doc in snap.docs) {
      Interview i;
      try {
        i = Interview.fromDoc(doc);
      } catch (e) {
        debugPrint('backfillTests: skipping bad doc ${doc.id}: $e');
        continue;
      }
      final key = i.testId.isNotEmpty ? i.testId : i.id;
      final existing = byTest[key];
      if (existing == null ||
          (i.createdAt != null &&
              (existing.createdAt == null ||
                  i.createdAt!.isAfter(existing.createdAt!)))) {
        byTest[key] = i;
      }
    }
    if (byTest.isEmpty) return 0;

    // Firestore caps a batch at 500 writes; stay well under.
    const chunk = 400;
    final summaries =
        byTest.values.map(TestSummary.fromInterview).toList(growable: false);
    for (var i = 0; i < summaries.length; i += chunk) {
      final end =
          (i + chunk < summaries.length) ? i + chunk : summaries.length;
      final batch = _db.batch();
      for (final t in summaries.sublist(i, end)) {
        batch.set(_tests.doc(t.testId), t.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    }
    debugPrint('backfillTests: wrote ${summaries.length} test doc(s)');
    return summaries.length;
  }

  /// Clears one candidate's RESPONSE while keeping them assigned to the test:
  /// drops the stored result, un-publishes it, and resets the status so they can
  /// take it again. Distinct from [delete], which removes the assignment
  /// entirely.
  Future<void> clearResult(String id) {
    return _col.doc(id).update({
      'result': FieldValue.delete(),
      'resultPublished': false,
      'status': InterviewStatus.assigned.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes an ENTIRE test: every candidate assignment/response belonging to
  /// [testId], plus the test's own metadata doc. Irreversible.
  ///
  /// Returns how many candidate documents were removed. Ownership is verified
  /// against [recruiterId] on the query, so this can never reach another
  /// recruiter's data even if a stale testId is passed.
  Future<int> deleteTest(String testId, String recruiterId) async {
    if (testId.isEmpty || recruiterId.isEmpty) return 0;

    final q = await _col
        .where('recruiterId', isEqualTo: recruiterId)
        .where('testId', isEqualTo: testId)
        .get();

    // References, not snapshots: a snapshot from `doc().get()` is a
    // DocumentSnapshot, NOT a QueryDocumentSnapshot, so collecting snapshots
    // forced an unsafe downcast on the legacy path below that threw at runtime.
    final refs = q.docs.map((d) => d.reference).toList();

    // Tests created before `testId` was populated group under the interview's
    // OWN id, so that document would not match the query above. Include it, but
    // only after confirming it belongs to this recruiter.
    if (refs.every((r) => r.id != testId)) {
      try {
        final legacy = await _col.doc(testId).get();
        if (legacy.exists && legacy.data()?['recruiterId'] == recruiterId) {
          refs.add(legacy.reference);
        }
      } on FirebaseException catch (e) {
        // EXPECTED for every test created since `testId` existed: there is no
        // interview document at that id, and `firestore.rules` gates reads on
        // `resource.data.recruiterId` — which cannot be evaluated for a missing
        // document, so Firestore answers PERMISSION_DENIED rather than handing
        // back a snapshot with `exists == false`.
        //
        // Letting that propagate aborted the whole delete before a single batch
        // was committed, so "delete test" failed and left everything in place.
        // Absence of a legacy document is not an error.
        debugPrint('deleteTest: no legacy doc at $testId (${e.code})');
      }
    }

    // Firestore hard-caps a batch at 500 writes; stay well under and commit
    // chunk by chunk.
    const chunk = 400;
    for (var i = 0; i < refs.length; i += chunk) {
      final end = (i + chunk < refs.length) ? i + chunk : refs.length;
      final batch = _db.batch();
      for (final ref in refs.sublist(i, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    // Remove the metadata doc last: if anything above fails, the test still
    // shows on the dashboard rather than leaving orphaned candidate rows that
    // nothing links to.
    try {
      await _tests.doc(testId).delete();
    } catch (e) {
      debugPrint('deleteTest: metadata doc cleanup failed for $testId: $e');
    }
    return refs.length;
  }

  /// "End test" — publish results for every candidate of [testId] owned by
  /// [recruiterId], in one batch.
  Future<void> publishTest(String testId, String recruiterId) async {
    final q = await _col
        .where('recruiterId', isEqualTo: recruiterId)
        .where('testId', isEqualTo: testId)
        .get();

    // Only publish candidates who actually took the test: a completed status
    // with a stored result. Untaken/incomplete assignments are left untouched
    // so they aren't wrongly marked published.
    final publishable = q.docs.where((doc) {
      final d = doc.data();
      return d['status'] == InterviewStatus.completed.wire &&
          d['result'] != null;
    }).toList();

    // Firestore hard-caps a batch at 500 writes; chunk well under that and
    // commit each chunk sequentially.
    const int chunkSize = 450;
    for (var i = 0; i < publishable.length; i += chunkSize) {
      final end = (i + chunkSize < publishable.length)
          ? i + chunkSize
          : publishable.length;
      final batch = _db.batch();
      for (final doc in publishable.sublist(i, end)) {
        batch.update(doc.reference, {
          'resultPublished': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }
}

/// One page of interviews plus the cursor needed to fetch the next.
class PagedInterviews {
  final List<Interview> items;

  /// Cursor for the next page — pass as `startAfter`. Null when the page is
  /// empty.
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  /// Whether at least one more document exists after this page.
  final bool hasMore;

  const PagedInterviews({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });

  const PagedInterviews.empty()
      : items = const [],
        lastDoc = null,
        hasMore = false;
}

/// One page of test summaries plus the cursor for the next.
class PagedTests {
  final List<TestSummary> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const PagedTests({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });

  const PagedTests.empty()
      : items = const [],
        lastDoc = null,
        hasMore = false;
}
