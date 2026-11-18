import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dev/dev_faults.dart';
import '../models/question.dart';

class RateLimited implements Exception {
  RateLimited(this.wait);
  final Duration wait;
  @override
  String toString() =>
      'Please wait ${wait.inSeconds + 1}s before asking OpenTDB again.';
}

class TriviaRequestFailed implements Exception {
  TriviaRequestFailed(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Fetches the exact Class B URL. One request per user action, at most one
/// request every five seconds, never retried automatically.
class TriviaApi {
  TriviaApi({http.Client? client, DevFaults? faults})
      : _client = client ?? http.Client(),
        _faults = faults;

  static final url = Uri.parse(
      'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium'
      '&type=boolean&encode=url3986');
  static const minGap = Duration(seconds: 5);
  static const timeout = Duration(seconds: 10);

  final http.Client _client;
  final DevFaults? _faults;
  DateTime? _lastRequest;

  Duration get cooldownRemaining {
    final last = _lastRequest;
    if (last == null) return Duration.zero;
    final left = minGap - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  Future<List<Question>> fetch() async {
    final fault = _faults?.takeTrivia() ?? TriviaFault.none;
    if (fault != TriviaFault.none) {
      // Fed through the same parser as a real response. No network call.
      return TriviaParser.parse(statusCode: 200, json: _fakeBody(fault));
    }

    final wait = cooldownRemaining;
    if (wait > Duration.zero) throw RateLimited(wait);
    _lastRequest = DateTime.now();

    final http.Response res;
    try {
      res = await _client.get(url).timeout(timeout);
    } on TimeoutException {
      throw TriviaRequestFailed('OpenTDB did not answer within 10 seconds.');
    } on Exception catch (e) {
      throw TriviaRequestFailed('Network error reaching OpenTDB ($e).');
    }

    Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException {
      throw InvalidTriviaData('response is not valid JSON');
    }
    return TriviaParser.parse(statusCode: res.statusCode, json: body);
  }

  Map<String, dynamic> _fakeBody(TriviaFault fault) {
    Map<String, dynamic> q(String text, {String correct = 'True'}) => {
          'type': 'boolean',
          'difficulty': 'medium',
          'category': 'Science%20%26%20Nature',
          'question': text,
          'correct_answer': correct,
          'incorrect_answers': [correct == 'True' ? 'False' : 'True'],
        };
    final five = [
      for (var i = 1; i <= 5; i++) q('%5BINJECTED%5D%20Sample%20question%20$i'),
    ];
    switch (fault) {
      case TriviaFault.badEncoding:
        five[2] = q('%5BINJECTED%5D%20Broken%20%E0%A4%A');
        return {'response_code': 0, 'results': five};
      case TriviaFault.nonzeroCode:
        return {'response_code': 1, 'results': <Object>[]};
      case TriviaFault.fourResults:
        return {'response_code': 0, 'results': five.take(4).toList()};
      case TriviaFault.none:
        return {'response_code': 0, 'results': five};
    }
  }
}
