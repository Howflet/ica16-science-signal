import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/attempt.dart';
import '../models/quiz_round.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_api.dart';

/// signedOut -> loading -> playing -> readyToSubmit -> submitting
///   -> verifying -> cloudVerified
/// plus authError, requestError, saveUnknown, permissionDenied,
/// verificationUnavailable and collision.
enum Phase {
  signedOut,
  authError,
  loading,
  requestError,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
  collision,
}

/// How a cloud call failed, so each one gets its own wording.
enum CloudErrorKind {
  timeout,
  unavailable,
  resourceExhausted,
  unauthenticated,
  permissionDenied,
  verificationMismatch,
  other,
}

class TraceEntry {
  TraceEntry(this.message) : at = DateTime.now();
  final DateTime at;
  final String message;
}

class QuizController extends ChangeNotifier {
  QuizController({
    required FirebaseAuth auth,
    required this.trivia,
    required this.repo,
  }) : _auth = auth {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  static const cloudTimeout = Duration(seconds: 10);
  static const maxCloudTries = 5;

  final FirebaseAuth _auth;
  final TriviaApi trivia;
  final AttemptRepository repo;
  late final StreamSubscription<User?> _authSub;

  Phase _phase = Phase.signedOut;
  Phase get phase => _phase;

  User? _user;
  User? get user => _user;

  String? _authMessage;
  String? get authMessage => _authMessage;
  bool _signingIn = false;
  bool get signingIn => _signingIn;

  String? _requestMessage;
  String? get requestMessage => _requestMessage;

  QuizRound? _round;
  QuizRound? get round => _round;

  // Frozen at submit time; reused by every retry of this round.
  AttemptPayload? _payload;
  AttemptPayload? get payload => _payload;

  bool _commitAcknowledged = false;
  bool get commitAcknowledged => _commitAcknowledged;

  CommitOutcome? _commitOutcome;
  CommitOutcome? get commitOutcome => _commitOutcome;

  CloudErrorKind? _errorKind;
  CloudErrorKind? get errorKind => _errorKind;
  String? _cloudMessage;
  String? get cloudMessage => _cloudMessage;

  VerifiedAttempt? _verified;
  VerifiedAttempt? get verified => _verified;

  int _cloudTries = 0;
  int get cloudTries => _cloudTries;
  bool get canRetryCloud =>
      _cloudTries < maxCloudTries && !_cloudBusy && _writeInFlight == null;

  bool _cloudBusy = false;
  Future<CommitOutcome>? _writeInFlight;
  bool get writeInFlight => _writeInFlight != null;

  // Bumped whenever the signed-in user or the round changes. Any callback
  // that finishes under an older generation is ignored.
  int _generation = 0;

  final List<TraceEntry> trace = [];

  /// A submission or verification outcome is still open.
  bool get unresolved => const {
        Phase.submitting,
        Phase.verifying,
        Phase.saveUnknown,
        Phase.verificationUnavailable,
      }.contains(_phase);

  bool get canReplay => !unresolved && _user != null && _phase != Phase.loading;
  bool get canSignOut => !unresolved;

  // ---------------------------------------------------------------- auth

  Future<void> signIn(String email, String password) async {
    if (_signingIn) return;
    _signingIn = true;
    _authMessage = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      _log('Sign-in succeeded');
    } on FirebaseAuthException catch (e) {
      _authMessage = _authErrorText(e);
      _log('Sign-in failed: ${e.code}'); // never logs the password
      _setPhase(Phase.authError);
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (!canSignOut) return;
    await _auth.signOut();
  }

  void _onAuthChanged(User? u) {
    final previous = _user?.uid;
    if (u?.uid == previous) return;
    _generation++;
    if (previous != null && unresolved) {
      _log('Auth changed externally while a result was unresolved. '
          'Old round ${redact(_round?.roundId)} detached from this screen.');
    }
    _user = u;
    _clearRound();
    if (u == null) {
      _log('Signed out');
      _setPhase(Phase.signedOut);
    } else {
      _log('Signed in as uid ${redact(u.uid)}');
      _phase = Phase.signedOut; // drop any old unresolved phase silently
      startRound();
    }
  }

  String _authErrorText(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address is not valid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Wait a bit and try again.',
        'network-request-failed' => 'No network connection.',
        _ => 'Sign-in failed (${e.code}).',
      };

  // --------------------------------------------------------------- round

  Duration get triviaCooldown => trivia.cooldownRemaining;

  Future<void> startRound() async {
    final u = _user;
    if (u == null || _phase == Phase.loading || unresolved) return;
    final gen = ++_generation;
    _clearRound();
    _setPhase(Phase.loading);
    try {
      final questions = await trivia.fetch();
      if (gen != _generation) return;
      final id = repo.newRoundId(u.uid);
      _round = QuizRound(roundId: id, questions: questions);
      _log('Round ${redact(id)} started with ${questions.length} questions');
      _setPhase(Phase.playing);
    } on Exception catch (e) {
      if (gen != _generation) return;
      _requestMessage = e.toString();
      _log('Question request failed: $e');
      _setPhase(Phase.requestError);
    }
  }

  void select(bool answer) {
    final r = _round;
    if (r == null || _phase != Phase.playing) return;
    if (r.select(answer)) {
      _log('Q${r.index + 1}: chose $answer '
          '(${r.isCorrect(r.index) ? 'correct' : 'wrong'})');
      notifyListeners();
    } else {
      _log('Q${r.index + 1}: repeated tap ignored');
    }
  }

  void next() {
    final r = _round;
    if (r == null || _phase != Phase.playing || !r.currentAnswered) return;
    if (r.isLast) {
      _setPhase(Phase.readyToSubmit);
    } else {
      r.advance();
      notifyListeners();
    }
  }

  void replay() {
    if (!canReplay) return;
    _log('Replay requested');
    startRound();
  }

  void _clearRound() {
    _round = null;
    _payload = null;
    _commitAcknowledged = false;
    _commitOutcome = null;
    _errorKind = null;
    _cloudMessage = null;
    _verified = null;
    _cloudTries = 0;
    _requestMessage = null;
  }

  // --------------------------------------------------------------- cloud

  Future<void> submit() async {
    final r = _round;
    if (r == null || _phase != Phase.readyToSubmit || !r.allAnswered) return;
    _payload = AttemptPayload(correctCount: r.score);
    _log('Payload frozen: correctCount ${r.score}/5');
    await _runCloud();
  }

  /// User-triggered retry for the same round ID. Never automatic.
  Future<void> retryCloud() async {
    if (!canRetryCloud) return;
    if (!const {
      Phase.saveUnknown,
      Phase.verificationUnavailable,
      Phase.permissionDenied,
    }.contains(_phase)) {
      return;
    }
    _log('Retry ${_cloudTries + 1}/$maxCloudTries for same round ID');
    await _runCloud();
  }

  Future<void> _runCloud() async {
    final u = _user, r = _round, p = _payload;
    if (u == null || r == null || p == null || _cloudBusy) return;
    _cloudBusy = true;
    _cloudTries++;
    final uid = u.uid, roundId = r.roundId, gen = _generation;
    bool stale() =>
        gen != _generation ||
        _auth.currentUser?.uid != uid ||
        _round?.roundId != roundId;

    try {
      if (!_commitAcknowledged) {
        final reconcile = _phase == Phase.saveUnknown;
        _setPhase(Phase.submitting);
        if (reconcile) _log('Reconciling ${redact(roundId)} from server first');

        final write = repo.commit(
          uid: uid,
          roundId: roundId,
          payload: p,
          reconcileFirst: reconcile,
        );
        _trackWrite(write, uid, roundId, gen);

        try {
          final outcome = await write.timeout(cloudTimeout);
          if (stale()) return;
          _commitAcknowledged = true;
          _commitOutcome = outcome;
          _log(outcome == CommitOutcome.created
              ? 'Commit acknowledged: created ${redact(roundId)}'
              : 'Commit acknowledged: reused existing ${redact(roundId)}');
        } on TimeoutException {
          if (stale()) return;
          _fail(Phase.saveUnknown, CloudErrorKind.timeout,
              'No answer within 10 s. The save may still land, so it is '
              'marked unknown. Retry checks the server for this same ID '
              'before writing anything.');
          return;
        } on AttemptCollision catch (e) {
          if (stale()) return;
          _errorKind = null;
          _cloudMessage = e.toString();
          _log('Collision: $e');
          _setPhase(Phase.collision);
          return;
        } on FirebaseException catch (e) {
          if (stale()) return;
          _onWriteError(e);
          return;
        }
      }

      _setPhase(Phase.verifying);
      try {
        final v = await repo
            .verify(uid: uid, roundId: roundId, expected: p)
            .timeout(cloudTimeout);
        if (stale()) return;
        _verified = v;
        _errorKind = null;
        _cloudMessage = null;
        _log('Cloud verified ${redact(roundId)}: ${v.correctCount}/5 at '
            '${v.submittedAt.toIso8601String()}');
        _setPhase(Phase.cloudVerified);
      } on TimeoutException {
        if (stale()) return;
        _fail(Phase.verificationUnavailable, CloudErrorKind.timeout,
            'Write acknowledged; verification unavailable. '
            'The server read timed out.');
      } on VerificationFailed catch (e) {
        if (stale()) return;
        _fail(Phase.verificationUnavailable, CloudErrorKind.verificationMismatch,
            'Write acknowledged; verification unavailable. $e');
      } on FirebaseException catch (e) {
        if (stale()) return;
        final kind = _kindOf(e);
        _fail(Phase.verificationUnavailable, kind,
            'Write acknowledged; verification unavailable. '
            '${_kindText(kind)} (${e.message ?? e.code})');
      }
    } finally {
      _cloudBusy = false;
      notifyListeners();
    }
  }

  /// Watches the real write even after the UI gave up on it, so a late
  /// acknowledgement is recorded and overlapping writes are blocked.
  void _trackWrite(
      Future<CommitOutcome> write, String uid, String roundId, int gen) {
    _writeInFlight = write;
    write.then((outcome) {
      if (gen != _generation || _round?.roundId != roundId) return;
      if (_phase == Phase.saveUnknown && !_commitAcknowledged) {
        _commitAcknowledged = true;
        _commitOutcome = outcome;
        _cloudMessage = 'Late acknowledgement: the earlier write did land. '
            'Tap retry to verify it on the server.';
        _log('Late commit acknowledgement for ${redact(roundId)}');
      }
    }, onError: (_) {}).whenComplete(() {
      if (identical(_writeInFlight, write)) _writeInFlight = null;
      notifyListeners();
    });
  }

  void _onWriteError(FirebaseException e) {
    final kind = _kindOf(e);
    final text = '${_kindText(kind)} (${e.message ?? e.code})';
    if (kind == CloudErrorKind.permissionDenied ||
        kind == CloudErrorKind.unauthenticated) {
      _fail(Phase.permissionDenied, kind,
          'The server refused this write. Nothing was saved. $text');
    } else {
      _fail(Phase.saveUnknown, kind,
          'Save not confirmed. $text Retry reconciles this same ID first.');
    }
  }

  void _fail(Phase phase, CloudErrorKind kind, String message) {
    _errorKind = kind;
    _cloudMessage = message;
    _log('${phase.name}: [${kind.name}] $message');
    _setPhase(phase);
  }

  CloudErrorKind _kindOf(FirebaseException e) => switch (e.code) {
        'unavailable' => CloudErrorKind.unavailable,
        'resource-exhausted' => CloudErrorKind.resourceExhausted,
        'unauthenticated' => CloudErrorKind.unauthenticated,
        'permission-denied' => CloudErrorKind.permissionDenied,
        'deadline-exceeded' => CloudErrorKind.timeout,
        _ => CloudErrorKind.other,
      };

  static String _kindText(CloudErrorKind k) => switch (k) {
        CloudErrorKind.timeout => 'Timed out.',
        CloudErrorKind.unavailable => 'Cloud service unavailable or offline.',
        CloudErrorKind.resourceExhausted => 'Cloud quota exhausted.',
        CloudErrorKind.unauthenticated => 'Not signed in on the server.',
        CloudErrorKind.permissionDenied => 'Permission denied.',
        CloudErrorKind.verificationMismatch => 'Server document did not match.',
        CloudErrorKind.other => 'Unexpected cloud error.',
      };

  // ------------------------------------------------------------- helpers

  void _setPhase(Phase p) {
    if (_phase != p) _log('state: ${_phase.name} -> ${p.name}');
    _phase = p;
    notifyListeners();
  }

  void _log(String m) {
    trace.add(TraceEntry(m));
    if (trace.length > 300) trace.removeAt(0);
    debugPrint('[trace] $m');
  }

  /// Shows only the last four characters of an ID in logs and evidence.
  static String redact(String? id) =>
      id == null
          ? '-'
          : '…${id.length <= 4 ? id : id.substring(id.length - 4)}';

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
