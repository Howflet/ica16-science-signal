import 'package:flutter_test/flutter_test.dart';
import 'package:science_signal/models/question.dart';
import 'package:science_signal/models/quiz_round.dart';

Map<String, dynamic> _q(String text,
        {String correct = 'True',
        String? incorrect,
        String category = 'Science%20%26%20Nature',
        String difficulty = 'medium',
        String type = 'boolean'}) =>
    {
      'type': type,
      'difficulty': difficulty,
      'category': category,
      'question': text,
      'correct_answer': correct,
      'incorrect_answers': [incorrect ?? (correct == 'True' ? 'False' : 'True')],
    };

Map<String, dynamic> _body(List<Map<String, dynamic>> results, {int code = 0}) =>
    {'response_code': code, 'results': results};

List<Map<String, dynamic>> _five() => [
      _q('The%20Earth%20orbits%20the%20Sun.'),
      _q('Water%20boils%20at%2050%C2%B0C%20at%20sea%20level.', correct: 'False'),
      _q('DNA%20stands%20for%20%22deoxyribonucleic%20acid%22.'),
      _q('Sound%20travels%20faster%20than%20light.', correct: 'False'),
      _q('Humans%20have%2023%20pairs%20of%20chromosomes.'),
    ];

void main() {
  group('TriviaParser (T02/T03)', () {
    test('decodes RFC 3986 strings with Uri.decodeComponent', () {
      final qs = TriviaParser.parse(statusCode: 200, json: _body(_five()));
      expect(qs, hasLength(5));
      expect(qs[0].text, 'The Earth orbits the Sun.');
      expect(qs[1].text, 'Water boils at 50°C at sea level.');
      expect(qs[2].text, 'DNA stands for "deoxyribonucleic acid".');
      expect(qs[1].correctAnswer, isFalse);
    });

    test('rejects non-200 status', () {
      expect(() => TriviaParser.parse(statusCode: 500, json: _body(_five())),
          throwsA(isA<InvalidTriviaData>()));
    });

    test('rejects nonzero response_code', () {
      expect(() => TriviaParser.parse(statusCode: 200, json: _body([], code: 1)),
          throwsA(isA<InvalidTriviaData>()));
    });

    test('rejects four results', () {
      expect(
          () => TriviaParser.parse(
              statusCode: 200, json: _body(_five().take(4).toList())),
          throwsA(isA<InvalidTriviaData>()));
    });

    test('rejects malformed percent encoding', () {
      final r = _five()..[2] = _q('Broken%20%E0%A4%A');
      expect(() => TriviaParser.parse(statusCode: 200, json: _body(r)),
          throwsA(isA<InvalidTriviaData>()));
    });

    test('rejects answers that are not exactly True/False', () {
      final r = _five()..[0] = _q('x', correct: 'Yes', incorrect: 'No');
      expect(() => TriviaParser.parse(statusCode: 200, json: _body(r)),
          throwsA(isA<InvalidTriviaData>()));
      final r2 = _five()..[0] = _q('x', correct: 'True', incorrect: 'True');
      expect(() => TriviaParser.parse(statusCode: 200, json: _body(r2)),
          throwsA(isA<InvalidTriviaData>()));
    });

    test('rejects wrong category, difficulty or type', () {
      for (final bad in [
        _q('x', category: 'History'),
        _q('x', difficulty: 'hard'),
        _q('x', type: 'multiple'),
      ]) {
        final r = _five()..[0] = bad;
        expect(() => TriviaParser.parse(statusCode: 200, json: _body(r)),
            throwsA(isA<InvalidTriviaData>()));
      }
    });

    test('an HTML unescaper would not be enough', () {
      // "%20" is not an HTML entity, so only URL decoding fixes it.
      expect(Uri.decodeComponent('Science%20%26%20Nature'), 'Science & Nature');
    });
  });

  group('QuizRound (T04/T05)', () {
    QuizRound round() => QuizRound(
          roundId: 'abc123',
          questions:
              TriviaParser.parse(statusCode: 200, json: _body(_five())),
        );

    test('two correct answers give 2/5', () {
      final r = round();
      // answers: T, F, T, F, T are correct. Get exactly two right.
      for (final a in [true, false, false, true, false]) {
        expect(r.select(a), isTrue);
        r.advance();
      }
      expect(r.allAnswered, isTrue);
      expect(r.score, 2);
    });

    test('repeated taps cannot change the answer or add points', () {
      final r = round();
      expect(r.select(true), isTrue); // correct
      expect(r.select(true), isFalse);
      expect(r.select(false), isFalse);
      expect(r.score, 1);
      expect(r.selectionFor(0), isTrue);
    });

    test('cannot continue without a selection', () {
      final r = round();
      expect(r.advance(), isFalse);
      expect(r.index, 0);
    });

    test('a new round starts clean', () {
      final r1 = round()..select(true);
      final r2 = round();
      expect(r1.score, 1);
      expect(r2.score, 0);
      expect(r2.selectionFor(0), isNull);
    });
  });
}
