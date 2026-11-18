import 'question.dart';

/// In-memory state for one five-question round.
///
/// Scoring is derived from the saved selections, so each question can be
/// worth at most one point no matter how many times a button is tapped.
class QuizRound {
  QuizRound({required this.roundId, required List<Question> questions})
      : questions = List.unmodifiable(questions);

  final String roundId;
  final List<Question> questions;
  final Map<int, bool> _selections = {};
  int _index = 0;

  int get index => _index;
  int get total => questions.length;
  Question get current => questions[_index];
  bool get isLast => _index == questions.length - 1;

  bool? selectionFor(int i) => _selections[i];
  bool get currentAnswered => _selections.containsKey(_index);
  bool get allAnswered => _selections.length == questions.length;

  /// Saves an answer for the current question. Returns false (and changes
  /// nothing) if this question already has an answer.
  bool select(bool answer) {
    if (currentAnswered) return false;
    _selections[_index] = answer;
    return true;
  }

  /// Moves forward. Requires a selection first.
  bool advance() {
    if (!currentAnswered || isLast) return false;
    _index++;
    return true;
  }

  bool isCorrect(int i) =>
      _selections.containsKey(i) && _selections[i] == questions[i].correctAnswer;

  int get score {
    var s = 0;
    for (var i = 0; i < questions.length; i++) {
      if (isCorrect(i)) s++;
    }
    return s;
  }
}
