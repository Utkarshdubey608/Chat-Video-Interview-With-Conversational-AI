// lib/features/interviews/services/interview_repository.dart
//
// Firestore access for the `interviews` collection. Role-scoped queries:
//   - recruiters watch interviews they created (recruiterId == uid)
//   - candidates watch interviews assigned to them (candidateEmailLower == email)
// Security rules (firestore.rules) enforce the same scoping server-side.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/interview.dart';

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

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// Creates a new assigned interview; returns the created id.
  Future<String> create(Interview interview) async {
    final ref = await _col.add(interview.toCreateMap());
    return ref.id;
  }

  /// Live list of interviews a recruiter created, newest first.
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
