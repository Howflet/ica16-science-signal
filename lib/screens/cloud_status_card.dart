import 'package:flutter/material.dart';

import '../services/attempt_repository.dart';
import '../state/quiz_controller.dart';

/// The one place that decides what the user is told about the cloud.
/// "Save failed" and "verification unavailable" look deliberately different:
/// red cross vs. amber cloud-with-question-mark.
class CloudStatusCard extends StatelessWidget {
  const CloudStatusCard({super.key, required this.controller});
  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);

    late Color tone;
    late IconData icon;
    late String title;
    String? body = c.cloudMessage;
    Widget? action;
    var busy = false;

    final retry = FilledButton.icon(
      onPressed: c.canRetryCloud ? c.retryCloud : null,
      icon: const Icon(Icons.refresh),
      label: Text(c.writeInFlight
          ? 'Waiting for the earlier write…'
          : c.cloudTries >= QuizController.maxCloudTries
              ? 'Retry limit reached'
              : 'Retry same round (${c.cloudTries}/${QuizController.maxCloudTries})'),
    );

    switch (c.phase) {
      case Phase.readyToSubmit:
        tone = theme.colorScheme.primary;
        icon = Icons.cloud_upload_outlined;
        title = 'Ready to save';
        body = 'Your score is final. Submitting saves it to your account '
            'and then reads it back from the server.';
        action = FilledButton.icon(
          onPressed: c.submit,
          icon: const Icon(Icons.send),
          label: const Text('Submit score'),
        );
      case Phase.submitting:
        tone = theme.colorScheme.primary;
        icon = Icons.cloud_upload;
        title = 'Saving…';
        body = 'Committing this round to the cloud.';
        busy = true;
      case Phase.verifying:
        tone = theme.colorScheme.primary;
        icon = Icons.cloud_sync;
        title = 'Write acknowledged. Verifying on the server…';
        body = 'Reading the exact document back, skipping any cache.';
        busy = true;
      case Phase.cloudVerified:
        final v = c.verified!;
        tone = const Color(0xFF1B7F3B);
        icon = Icons.verified;
        title = 'Cloud verified';
        body = 'Server copy: ${v.correctCount}/5, saved '
            '${_fmt(v.submittedAt)}'
            '${c.commitOutcome == CommitOutcome.reusedExisting ? ' (existing record reused, no duplicate)' : ''}.';
      case Phase.saveUnknown:
        tone = const Color(0xFF8A5A00);
        icon = Icons.help_outline;
        title = 'Save status unknown';
        action = retry;
      case Phase.verificationUnavailable:
        tone = const Color(0xFF8A5A00);
        icon = Icons.cloud_off;
        title = 'Write acknowledged; verification unavailable.';
        body = '${c.cloudMessage ?? ''}\n\nYour score was accepted by the '
            'server. It was not deleted and will not be saved again. '
            'Retry reads the same round back.';
        action = retry;
      case Phase.permissionDenied:
        tone = theme.colorScheme.error;
        icon = Icons.block;
        title = 'Save failed: permission denied';
        action = retry;
      case Phase.collision:
        tone = theme.colorScheme.error;
        icon = Icons.call_split;
        title = 'Collision: this round ID already holds a different score';
      default:
        return const SizedBox.shrink();
    }

    return Card(
      color: tone.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tone, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            busy
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, color: tone))
                : Icon(icon, color: tone, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: tone, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body),
          ],
          if (c.errorKind != null) ...[
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(Icons.label_important_outline, size: 16, color: tone),
              label: Text('error: ${c.errorKind!.name}'),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ]),
      ),
    );
  }

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}
