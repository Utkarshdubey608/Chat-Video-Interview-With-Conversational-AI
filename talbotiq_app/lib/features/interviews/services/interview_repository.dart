// lib/features/interviews/services/interview_repository.dart
//
// Firestore access for the `interviews` collection. Role-scoped queries:
//   - recruiters watch interviews they created (recruiterId == uid)
//   - candidates watch interviews assigned to them (candidateEmailLower == email)
// Security rules (firestore.rules) enforce the same scoping server-side.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/interview.dart';

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
        .map((s) => s.docs.map(Interview.fromDoc).toList());
  }

  /// Live list of interviews assigned to a candidate email, newest first.
  Stream<List<Interview>> watchForCandidate(String candidateEmail) {
    return _col
        .where('candidateEmailLower', isEqualTo: normalizeEmail(candidateEmail))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Interview.fromDoc).toList());
  }

  Future<Interview?> getById(String id) async {
    final doc = await _col.doc(id).get();
    return doc.exists ? Interview.fromDoc(doc) : null;
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
    final batch = _db.batch();
    for (final doc in q.docs) {
      batch.update(doc.reference, {
        'resultPublished': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
