/// One validated, decoded Science & Nature true/false question.
class Question {
  const Question({required this.text, required this.correctAnswer});

  final String text;

  /// true means the correct answer is "True".
  final bool correctAnswer;
}

/// Thrown when OpenTDB gives us something we refuse to play with.
class InvalidTriviaData implements Exception {
  InvalidTriviaData(this.reason);
  final String reason;

  @override
  String toString() => 'Invalid question data: $reason';
}

/// Validates and decodes a raw OpenTDB (encode=url3986) response body.
///
/// Every rule from the Class B brief lives here so it can be unit tested
/// without a network: status 200, response_code 0, exactly five results,
/// URL-component decoding, category/difficulty/type checks, and an answer
/// set of exactly {True, False}.
class TriviaParser {
  static const expectedCount = 5;
  static const expectedCategory = 'Science & Nature';

  static List<Question> parse({required int statusCode, required Object? json}) {
    if (statusCode != 200) {
      throw InvalidTriviaData('HTTP status $statusCode (expected 200)');
    }
    if (json is! Map<String, dynamic>) {
      throw InvalidTriviaData('response body is not a JSON object');
    }
    final code = json['response_code'];
    if (code != 0) {
      throw InvalidTriviaData('API response_code $code (expected 0)');
    }
    final results = json['results'];
    if (results is! List) {
      throw InvalidTriviaData('missing results list');
    }
    if (results.length != expectedCount) {
      throw InvalidTriviaData(
          'got ${results.length} results (expected exactly $expectedCount)');
    }
    return [
      for (var i = 0; i < results.length; i++) _parseOne(results[i], i + 1),
    ];
  }

  static Question _parseOne(Object? raw, int number) {
    if (raw is! Map<String, dynamic>) {
      throw InvalidTriviaData('question $number is not an object');
    }
    final category = _decodeField(raw, 'category', number);
    final difficulty = _decodeField(raw, 'difficulty', number);
    final type = _decodeField(raw, 'type', number);
    final text = _decodeField(raw, 'question', number);
    final correct = _decodeField(raw, 'correct_answer', number);

    final incorrectRaw = raw['incorrect_answers'];
    if (incorrectRaw is! List || incorrectRaw.length != 1) {
      throw InvalidTriviaData(
          'question $number needs exactly one incorrect answer');
    }
    final incorrect = _decode(incorrectRaw.single, 'incorrect_answers', number);

    if (category != expectedCategory) {
      throw InvalidTriviaData('question $number category is "$category"');
    }
    if (difficulty != 'medium') {
      throw InvalidTriviaData('question $number difficulty is "$difficulty"');
    }
    if (type != 'boolean') {
      throw InvalidTriviaData('question $number type is "$type"');
    }
    if (text.trim().isEmpty) {
      throw InvalidTriviaData('question $number has empty text');
    }
    final answers = {correct, incorrect};
    if (answers.length != 2 || !answers.containsAll(['True', 'False'])) {
      throw InvalidTriviaData(
          'question $number answers are "$correct" / "$incorrect", '
          'expected exactly True and False');
    }
    return Question(text: text, correctAnswer: correct == 'True');
  }

  static String _decodeField(Map<String, dynamic> raw, String key, int number) =>
      _decode(raw[key], key, number);

  static String _decode(Object? value, String key, int number) {
    if (value is! String || value.isEmpty) {
      throw InvalidTriviaData('question $number is missing "$key"');
    }
    try {
      // The endpoint uses RFC 3986 percent encoding, so this is the right
      // decoder. An HTML unescaper would leave "%20" untouched.
      return Uri.decodeComponent(value);
    } on ArgumentError {
      throw InvalidTriviaData('question $number has malformed encoding in "$key"');
    } on FormatException {
      throw InvalidTriviaData('question $number has malformed encoding in "$key"');
    }
  }
}
