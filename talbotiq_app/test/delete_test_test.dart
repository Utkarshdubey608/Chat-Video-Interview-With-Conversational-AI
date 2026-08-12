// test/delete_test_test.dart
//
// Regression tests for "Delete entire test", which silently did nothing.
//
// Two separate faults in `deleteTest`'s legacy-id fallback:
//
//   1. It did `_col.doc(testId).get()` on an interview id that does not exist
//      for any modern test. `firestore.rules` gates interview reads on
//      `resource.data.recruiterId`, which cannot be evaluated for a missing
//      document — so Firestore answers PERMISSION_DENIED rather than a snapshot
//      with `exists == false`. That exception propagated and aborted the delete
//      before a single batch was committed.
//   2. It then cast the result `as QueryDocumentSnapshot`. A snapshot from
//      `doc().get()` is a plain DocumentSnapshot, so that cast threw even when
//      the read succeeded — which is what broke the legacy path itself.
//
// SCOPE NOTE: fake_cloud_firestore enforces no rules, so a missing-document get
// returns `exists == false` instead of throwing. Fault (1) therefore cannot be
// reproduced here — it is handled by the `on FirebaseException` guard and was
// diagnosed from the reported log. Fault (2) IS covered: the legacy test below
// fails against the old cast.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InterviewRepository repo;

  const recruiter = 'rec-1';
  const testId = 'test_1785495787380910';

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = InterviewRepository(firestore: db);
  });

  Future<void> seedInterview(String id, {String owner = recruiter}) =>
      db.collection('interviews').doc(id).set({
        'recruiterId': owner,
        'testId': testId,
        'candidateEmail': 'a@b.com',
        'candidateEmailLower': 'a@b.com',
        'title': 'Backend Engineer',
      });

  test('removes every candidate of the test, and the dashboard row', () async {
    await seedInterview('iv-1');
    await seedInterview('iv-2');
    await db.collection('tests').doc(testId).set({'recruiterId': recruiter});

    expect(await repo.deleteTest(testId, recruiter), 2);

    expect((await db.collection('interviews').get()).docs, isEmpty);
    // The metadata doc goes last, so a partial failure leaves the test visible
    // rather than orphaning candidate rows nothing links to.
    expect((await db.collection('tests').get()).docs, isEmpty);
  });

  test("never touches another recruiter's interviews", () async {
    await seedInterview('mine');
    await seedInterview('theirs', owner: 'rec-2');

    expect(await repo.deleteTest(testId, recruiter), 1);

    final left = await db.collection('interviews').get();
    expect(left.docs.single.id, 'theirs');
  });

  test('removes a legacy test grouped under its own interview id', () async {
    // Pre-`testId` tests grouped under the interview's OWN id, so the query
    // finds nothing and the fallback is the only route to them. This is the case
    // the `as QueryDocumentSnapshot` cast used to throw on.
    await db.collection('interviews').doc(testId).set({
      'recruiterId': recruiter,
      'candidateEmail': 'a@b.com',
    });

    expect(await repo.deleteTest(testId, recruiter), 1);
    expect((await db.collection('interviews').get()).docs, isEmpty);
  });

  test('the legacy fallback still respects ownership', () async {
    await db.collection('interviews').doc(testId).set({
      'recruiterId': 'rec-2',
      'candidateEmail': 'a@b.com',
    });

    expect(await repo.deleteTest(testId, recruiter), 0);
    expect((await db.collection('interviews').get()).docs, hasLength(1));
  });

  test('invalid input is a no-op', () async {
    await seedInterview('iv-1');
    expect(await repo.deleteTest('', recruiter), 0);
    expect(await repo.deleteTest(testId, ''), 0);
    expect((await db.collection('interviews').get()).docs, hasLength(1));
  });
}
