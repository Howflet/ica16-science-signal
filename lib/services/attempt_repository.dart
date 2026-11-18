import 'package:cloud_firestore/cloud_firestore.dart';

import '../dev/dev_faults.dart';
import '../models/attempt.dart';

enum CommitOutcome { created, reusedExisting }

/// The stored document has the same ID but different fixed fields.
/// We never overwrite it.
class AttemptCollision implements Exception {
  AttemptCollision(this.storedCount, this.submittedCount);
  final Object? storedCount;
  final int submittedCount;
  @override
  String toString() =>
      'Round ID already holds correctCount $storedCount; '
      'this device tried $submittedCount. Not overwritten.';
}

/// The server answered, but the document failed the verification checks.
class VerificationFailed implements Exception {
  VerificationFailed(this.problems);
  final List<String> problems;
  @override
  String toString() => 'Verification failed: ${problems.join('; ')}';
}

/// All Firestore access for attempts goes through here.
class AttemptRepository {
  AttemptRepository({FirebaseFirestore? db, DevFaults? faults})
      : _db = db ?? FirebaseFirestore.instance,
        _faults = faults;

  final FirebaseFirestore _db;
  final DevFaults? _faults;

  CollectionReference<Map<String, dynamic>> attempts(String uid) =>
      _db.collection('users').doc(uid).collection('attempts');

  DocumentReference<Map<String, dynamic>> ref(String uid, String roundId) =>
      attempts(uid).doc(roundId);

  /// Generates a round ID locally. This does NOT create a server record.
  String newRoundId(String uid) => attempts(uid).doc().id;

  /// Create-once transaction.
  ///
  /// If [reconcileFirst] is set (we are in saveUnknown), a server-only read
  /// of the same ID happens before anything else, so an earlier commit that
  /// we never heard back from is found instead of written twice.
  ///
  /// The callback only reads and sets. No ID generation, no UI changes, no
  /// other services, because Firestore may run it more than once.
  Future<CommitOutcome> commit({
    required String uid,
    required String roundId,
    required AttemptPayload payload,
    bool reconcileFirst = false,
  }) async {
    final fault = _faults?.takeCommit() ?? CommitFault.none;
    switch (fault) {
      case CommitFault.unavailable:
        throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
            message: '[INJECTED] Service unavailable before commit.');
      case CommitFault.resourceExhausted:
        throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'resource-exhausted',
            message: '[INJECTED] Quota exhausted before commit.');
      case CommitFault.slowCommit:
        // Real commit, just late: lets us watch the 10 s UI timeout fire
        // while the underlying operation still finishes.
        await Future<void>.delayed(const Duration(seconds: 13));
      case CommitFault.none:
        break;
    }

    final docRef = ref(uid, roundId);

    if (reconcileFirst) {
      final snap = await docRef.get(const GetOptions(source: Source.server));
      if (snap.exists) {
        final data = snap.data()!;
        if (payload.matches(data)) return CommitOutcome.reusedExisting;
        throw AttemptCollision(data['correctCount'], payload.correctCount);
      }
    }

    return _db.runTransaction<CommitOutcome>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) {
        tx.set(docRef, payload.toCreateMap());
        return CommitOutcome.created;
      }
      final data = snap.data()!;
      if (payload.matches(data)) return CommitOutcome.reusedExisting;
      throw AttemptCollision(data['correctCount'], payload.correctCount);
    });
  }

  /// Server-only read of the exact document, checked field by field.
  Future<VerifiedAttempt> verify({
    required String uid,
    required String roundId,
    AttemptPayload? expected,
  }) async {
    if (_faults?.takeDenyVerification() ?? false) {
      throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: '[INJECTED] Verification read denied (dev hook). '
              'Deployed rules are unchanged.');
    }
    final snap =
        await ref(uid, roundId).get(const GetOptions(source: Source.server));
    final problems = <String>[];
    final v = VerifiedAttempt.fromServerSnapshot(snap,
        expected: expected, problems: problems);
    if (v == null) throw VerificationFailed(problems);
    return v;
  }

  /// Most recent attempts for this user, straight from the server.
  Future<List<VerifiedAttempt>> recent(String uid, {int limit = 10}) async {
    final q = await attempts(uid)
        .orderBy('submittedAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.server));
    return [
      for (final d in q.docs) ?VerifiedAttempt.fromServerSnapshot(d),
    ];
  }
}
