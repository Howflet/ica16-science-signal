import 'package:cloud_firestore/cloud_firestore.dart';

/// The five fixed fields of a Class B attempt. The sixth field,
/// submittedAt, is always FieldValue.serverTimestamp() on write and a
/// resolved Timestamp on a verified read.
///
/// Path: users/{authenticatedUid}/attempts/{roundId}
class AttemptPayload {
  const AttemptPayload({required this.correctCount});

  static const schemaVersion = 1;
  static const variant = 'B';
  static const categoryId = 17;
  static const questionCount = 5;

  final int correctCount;

  /// Exactly six fields. The round ID is the document ID, not a field.
  Map<String, Object> toCreateMap() => {
        'schemaVersion': schemaVersion,
        'variant': variant,
        'categoryId': categoryId,
        'questionCount': questionCount,
        'correctCount': correctCount,
        'submittedAt': FieldValue.serverTimestamp(),
      };

  /// Compares the five non-timestamp fields against a stored document.
  bool matches(Map<String, dynamic> data) =>
      data['schemaVersion'] == schemaVersion &&
      data['variant'] == variant &&
      data['categoryId'] == categoryId &&
      data['questionCount'] == questionCount &&
      data['correctCount'] == correctCount;
}

/// A document that passed every check of the verification contract.
class VerifiedAttempt {
  const VerifiedAttempt({
    required this.roundId,
    required this.correctCount,
    required this.submittedAt,
  });

  final String roundId;
  final int correctCount;
  final DateTime submittedAt;

  /// Checks a server snapshot: exists, exactly the six fields, fixed values,
  /// a resolved timestamp, not from cache, no pending writes.
  /// Returns null with a reason in [problems] if anything is off.
  static VerifiedAttempt? fromServerSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap, {
    AttemptPayload? expected,
    List<String>? problems,
  }) {
    void fail(String why) => problems?.add(why);
    if (!snap.exists) {
      fail('document does not exist on the server');
      return null;
    }
    if (snap.metadata.isFromCache) fail('snapshot came from cache');
    if (snap.metadata.hasPendingWrites) fail('snapshot has pending writes');
    final d = snap.data()!;
    const keys = {
      'schemaVersion',
      'variant',
      'categoryId',
      'questionCount',
      'correctCount',
      'submittedAt'
    };
    if (d.keys.toSet().length != keys.length || !d.keys.toSet().containsAll(keys)) {
      fail('unexpected field set: ${d.keys.toList()}');
    }
    if (d['schemaVersion'] != AttemptPayload.schemaVersion) fail('schemaVersion');
    if (d['variant'] != AttemptPayload.variant) fail('variant');
    if (d['categoryId'] != AttemptPayload.categoryId) fail('categoryId');
    if (d['questionCount'] != AttemptPayload.questionCount) fail('questionCount');
    final count = d['correctCount'];
    if (count is! int || count < 0 || count > 5) fail('correctCount out of range');
    if (expected != null && count != expected.correctCount) {
      fail('correctCount $count does not match submitted ${expected.correctCount}');
    }
    final ts = d['submittedAt'];
    if (ts is! Timestamp) fail('submittedAt is not a resolved timestamp');
    if (problems != null && problems.isNotEmpty) return null;
    return VerifiedAttempt(
      roundId: snap.id,
      correctCount: count as int,
      submittedAt: (ts as Timestamp).toDate(),
    );
  }
}
