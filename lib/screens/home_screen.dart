import 'dart:async';

import 'package:flutter/material.dart';

import '../dev/dev_faults.dart';
import '../state/quiz_controller.dart';
import 'cloud_status_card.dart';
import 'dev_panel_screen.dart';
import 'history_screen.dart';
import 'sign_in_view.dart';

const kCorrect = Color(0xFF1B7F3B);
const kWrong = Color(0xFFB3261E);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller, required this.faults});

  final QuizController controller;
  final DevFaults faults;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final signedIn = c.user != null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Science Signal'),
            actions: [
              if (signedIn)
                IconButton(
                  tooltip: 'Saved rounds (server)',
                  icon: const Icon(Icons.cloud_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HistoryScreen(controller: c))),
                ),
              if (kDevTools)
                IconButton(
                  tooltip: 'Developer tools',
                  icon: const Icon(Icons.bug_report_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          DevPanelScreen(controller: c, faults: faults))),
                ),
              if (signedIn)
                IconButton(
                  tooltip: c.canSignOut
                      ? 'Sign out'
                      : 'Sign out is locked until this result is resolved',
                  icon: const Icon(Icons.logout),
                  onPressed: c.canSignOut ? c.signOut : null,
                ),
            ],
          ),
          body: SafeArea(child: _body(c)),
        );
      },
    );
  }

  Widget _body(QuizController c) {
    switch (c.phase) {
      case Phase.signedOut:
      case Phase.authError:
        return SignInView(controller: c);
      case Phase.loading:
        return const _Loading();
      case Phase.requestError:
        return _RequestError(controller: c);
      case Phase.playing:
        return _QuestionView(controller: c);
      case Phase.readyToSubmit:
      case Phase.submitting:
      case Phase.verifying:
      case Phase.cloudVerified:
      case Phase.saveUnknown:
      case Phase.permissionDenied:
      case Phase.verificationUnavailable:
      case Phase.collision:
        return _ReviewView(controller: c);
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Fetching five Science & Nature questions…'),
        ]),
      );
}

class _RequestError extends StatefulWidget {
  const _RequestError({required this.controller});
  final QuizController controller;
  @override
  State<_RequestError> createState() => _RequestErrorState();
}

class _RequestErrorState extends State<_RequestError> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final wait = c.triviaCooldown;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_tethering_error, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text("Couldn't load a playable round",
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(c.requestMessage ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: wait > Duration.zero ? null : c.startRound,
            icon: const Icon(Icons.refresh),
            label: Text(wait > Duration.zero
                ? 'Retry in ${wait.inSeconds + 1}s'
                : 'Try again'),
          ),
        ]),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({required this.controller});
  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.round!;
    final theme = Theme.of(context);
    final picked = r.selectionFor(r.index);
    final answered = picked != null;
    final right = answered && r.isCorrect(r.index);

    Widget choice(bool value) {
      final isPicked = picked == value;
      final isAnswer = r.current.correctAnswer == value;
      Color? bg;
      IconData? icon;
      if (answered && isPicked) {
        bg = isAnswer ? kCorrect : kWrong;
        icon = isAnswer ? Icons.check_circle : Icons.cancel;
      } else if (answered && isAnswer) {
        icon = Icons.check_circle_outline;
      }
      return Expanded(
        child: SizedBox(
          height: 64,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: bg != null ? Colors.white : null,
              disabledBackgroundColor: bg,
              disabledForegroundColor: bg != null ? Colors.white : null,
            ),
            onPressed: answered ? null : () => c.select(value),
            icon: Icon(icon ?? (value ? Icons.thumb_up_alt_outlined : Icons.thumb_down_alt_outlined)),
            label: Text(value ? 'True' : 'False',
                style: const TextStyle(fontSize: 18)),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Text('Question ${r.index + 1} of ${r.total}',
              style: theme.textTheme.titleMedium),
          const Spacer(),
          Text('Round ${QuizController.redact(r.roundId)}',
              style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (r.index + (answered ? 1 : 0)) / r.total,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(r.current.text, style: theme.textTheme.titleLarge),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [choice(true), const SizedBox(width: 12), choice(false)]),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: !answered
              ? Text('Pick True or False to continue.',
                  key: const ValueKey('hint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium)
              : Container(
                  key: ValueKey(right),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (right ? kCorrect : kWrong).withValues(alpha: 0.1),
                    border: Border.all(color: right ? kCorrect : kWrong),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(right ? Icons.check_circle : Icons.cancel,
                        color: right ? kCorrect : kWrong),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        right
                            ? 'Correct!'
                            : 'Not quite. The answer is '
                                '${r.current.correctAnswer ? 'True' : 'False'}.',
                        style: TextStyle(
                            color: right ? kCorrect : kWrong,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: answered ? c.next : null,
          child: Text(r.isLast ? 'See results' : 'Continue'),
        ),
        const SizedBox(height: 8),
        Text('Score so far: ${r.score}', textAlign: TextAlign.center),
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.controller});
  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.round!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('You scored ${r.score}/${r.total}',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Round ${QuizController.redact(r.roundId)}',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        CloudStatusCard(controller: c),
        const SizedBox(height: 16),
        Text('Review', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < r.total; i++)
          Card(
            child: ListTile(
              leading: Icon(
                r.isCorrect(i) ? Icons.check_circle : Icons.cancel,
                color: r.isCorrect(i) ? kCorrect : kWrong,
                semanticLabel: r.isCorrect(i) ? 'Correct' : 'Wrong',
              ),
              title: Text('${i + 1}. ${r.questions[i].text}'),
              subtitle: Text(
                'Your answer: ${r.selectionFor(i)! ? 'True' : 'False'} · '
                'Correct: ${r.questions[i].correctAnswer ? 'True' : 'False'}',
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: c.canReplay ? c.replay : null,
          icon: const Icon(Icons.replay),
          label: Text(c.canReplay
              ? 'Play a new round'
              : 'Replay locked until this result is resolved'),
        ),
      ],
    );
  }
}
