import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/attempt.dart';
import '../state/quiz_controller.dart';

/// Server-only view of this user's saved rounds. Used for T07: restart,
/// sign in as the same user, and pull the same round ID back.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});
  final QuizController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _idField = TextEditingController();
  late Future<List<VerifiedAttempt>> _recent;
  String? _lookupResult;
  bool _lookupBusy = false;

  String get _uid => widget.controller.user!.uid;

  @override
  void initState() {
    super.initState();
    _recent = widget.controller.repo.recent(_uid);
  }

  @override
  void dispose() {
    _idField.dispose();
    super.dispose();
  }

  Future<void> _lookup([String? id]) async {
    final roundId = (id ?? _idField.text).trim();
    if (roundId.isEmpty) return;
    _idField.text = roundId;
    setState(() {
      _lookupBusy = true;
      _lookupResult = null;
    });
    String result;
    try {
      final v = await widget.controller.repo
          .verify(uid: _uid, roundId: roundId)
          .timeout(QuizController.cloudTimeout);
      result = 'Server read OK for ${QuizController.redact(v.roundId)}: '
          '${v.correctCount}/5, submittedAt ${v.submittedAt.toLocal()}, '
          'not from cache, no pending writes.';
    } on FirebaseException catch (e) {
      result = 'Server read failed: ${e.code}. ${e.message ?? ''}';
    } on Exception catch (e) {
      result = 'Server read failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _lookupBusy = false;
      _lookupResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved rounds')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Signed in as uid ${QuizController.redact(_uid)}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _idField,
            decoration: InputDecoration(
              labelText: 'Round ID',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Read from server',
                icon: const Icon(Icons.cloud_download_outlined),
                onPressed: _lookupBusy ? null : _lookup,
              ),
            ),
            onSubmitted: (_) => _lookup(),
          ),
          if (_lookupBusy) const LinearProgressIndicator(),
          if (_lookupResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(_lookupResult!),
            ),
          const SizedBox(height: 20),
          Row(children: [
            Text('Most recent (server)', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh from server',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _recent = widget.controller.repo.recent(_uid);
              }),
            ),
          ]),
          FutureBuilder<List<VerifiedAttempt>>(
            future: _recent,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                final e = snap.error;
                return Text(
                    'Could not load from server: '
                    '${e is FirebaseException ? e.code : e}',
                    style: TextStyle(color: theme.colorScheme.error));
              }
              final items = snap.data!;
              if (items.isEmpty) return const Text('No saved rounds yet.');
              return Column(children: [
                for (final a in items)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: Text('${a.correctCount}/5'),
                      subtitle: Text('${a.roundId}\n${a.submittedAt.toLocal()}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Copy round ID',
                        icon: const Icon(Icons.copy),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: a.roundId)),
                      ),
                      onTap: () => _lookup(a.roundId),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
