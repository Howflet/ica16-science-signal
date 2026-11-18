import 'package:flutter/foundation.dart';

/// Development-only tools. On in debug/profile builds; off in a release
/// build unless you pass --dart-define=DEV_TOOLS=true.
const bool kDevTools =
    bool.fromEnvironment('DEV_TOOLS', defaultValue: !kReleaseMode);

enum TriviaFault { none, badEncoding, nonzeroCode, fourResults }

enum CommitFault { none, unavailable, resourceExhausted, slowCommit }

/// One-shot fault switches. Every injected failure is labelled
/// "[INJECTED]" in its message and in the trace so it can never be
/// mistaken for real cloud behaviour. The deployed rules are never touched.
class DevFaults extends ChangeNotifier {
  TriviaFault _trivia = TriviaFault.none;
  CommitFault _commit = CommitFault.none;
  bool _denyNextVerification = false;

  TriviaFault get trivia => _trivia;
  CommitFault get commit => _commit;
  bool get denyNextVerification => _denyNextVerification;

  set trivia(TriviaFault v) {
    _trivia = v;
    notifyListeners();
  }

  set commit(CommitFault v) {
    _commit = v;
    notifyListeners();
  }

  set denyNextVerification(bool v) {
    _denyNextVerification = v;
    notifyListeners();
  }

  TriviaFault takeTrivia() {
    final f = _trivia;
    trivia = TriviaFault.none;
    return f;
  }

  CommitFault takeCommit() {
    final f = _commit;
    commit = CommitFault.none;
    return f;
  }

  bool takeDenyVerification() {
    final f = _denyNextVerification;
    if (f) denyNextVerification = false;
    return f;
  }
}
