import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dev/dev_faults.dart';
import '../state/quiz_controller.dart';

/// DEVELOPMENT ONLY. Fault switches (T03, T09, T12, timeout ambiguity),
/// rule probes (T10, T11) and the state trace. Every injected failure is
/// labelled [INJECTED]. Nothing here changes the deployed rules.
class DevPanelScreen extends StatefulWidget {
  const DevPanelScreen(
      {super.key, required this.controller, required this.faults});
  final QuizController controller;
  final DevFaults faults;

  @override
  State<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends State<DevPanelScreen> {
  final _otherUid = TextEditingController();
  final _existingId = TextEditingController();
  final List<String> _probeLog = [];
  bool _busy = false;

  QuizController get c => widget.controller;
  FirebaseFirestore get db => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _existingId.text = c.verified?.roundId ?? '';
  }

  @override
  void dispose() {
    _otherUid.dispose();
    _existingId.dispose();
    super.dispose();
  }

  Future<void> _probe(String label, Future<void> Function() op) async {
    setState(() => _busy = true);
    String line;
    try {
      await op().timeout(const Duration(seconds: 10));
      line = '$label → ALLOWED (unexpected)';
    } on FirebaseException catch (e) {
      line = '$label → rejected: ${e.code}';
    } on Exception catch (e) {
      line = '$label → error: $e';
    }
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _probeLog.insert(0, '$stamp  $line');
      _busy = false;
    });
  }

  Map<String, Object> _valid({int count = 3}) => {
        'schemaVersion': 1,
        'variant': 'B',
        'categoryId': 17,
        'questionCount': 5,
        'correctCount': count,
        'submittedAt': FieldValue.serverTimestamp(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = c.user?.uid;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.faults, c]),
      builder: (context, _) {
        final f = widget.faults;
        return Scaffold(
          appBar: AppBar(title: const Text('Developer tools')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.amber.shade100,
                child: const Text(
                    'DEVELOPMENT ONLY. Injected failures are one-shot, labelled '
                    '[INJECTED], and never touch the deployed security rules.'),
              ),
              _section(theme, 'Question request faults (T03)'),
              SegmentedButton<TriviaFault>(
                segments: const [
                  ButtonSegment(value: TriviaFault.none, label: Text('None')),
                  ButtonSegment(
                      value: TriviaFault.badEncoding, label: Text('Bad %')),
                  ButtonSegment(
                      value: TriviaFault.nonzeroCode, label: Text('Code≠0')),
                  ButtonSegment(
                      value: TriviaFault.fourResults, label: Text('4 results')),
                ],
                selected: {f.trivia},
                onSelectionChanged: (s) => f.trivia = s.first,
              ),
              const Text('Applies to the next round you start.'),
              _section(theme, 'Commit faults (T12, timeout)'),
              SegmentedButton<CommitFault>(
                segments: const [
                  ButtonSegment(value: CommitFault.none, label: Text('None')),
                  ButtonSegment(
                      value: CommitFault.unavailable, label: Text('Unavail.')),
                  ButtonSegment(
                      value: CommitFault.resourceExhausted,
                      label: Text('Quota')),
                  ButtonSegment(
                      value: CommitFault.slowCommit, label: Text('Slow 13s')),
                ],
                selected: {f.commit},
                onSelectionChanged: (s) => f.commit = s.first,
              ),
              const Text('Applies to the next commit attempt only.'),
              _section(theme, 'Verification fault (T09)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Deny the next verification read (permission-denied)'),
                subtitle: const Text(
                    'The commit stays real. Only the first read after it is denied.'),
                value: f.denyNextVerification,
                onChanged: (v) => f.denyNextVerification = v,
              ),
              _section(theme, 'Your identity'),
              Row(children: [
                Expanded(child: SelectableText('uid: ${uid ?? '(signed out)'}')),
                if (uid != null)
                  IconButton(
                    tooltip: 'Copy uid',
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(ClipboardData(text: uid)),
                  ),
              ]),
              _section(theme, 'Cross-user probe (T10)'),
              TextField(
                controller: _otherUid,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: "Other user's uid (user A)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: _busy || uid == null || _otherUid.text.trim().isEmpty
                      ? null
                      : () => _probe('Read other user\'s attempts', () async {
                            await db
                                .collection('users')
                                .doc(_otherUid.text.trim())
                                .collection('attempts')
                                .get(const GetOptions(source: Source.server));
                          }),
                  child: const Text('Read their path'),
                ),
                OutlinedButton(
                  onPressed: _busy || uid == null || _otherUid.text.trim().isEmpty
                      ? null
                      : () => _probe('Write to other user\'s path', () async {
                            final ref = db
                                .collection('users')
                                .doc(_otherUid.text.trim())
                                .collection('attempts')
                                .doc();
                            await ref.set(_valid());
                          }),
                  child: const Text('Write their path'),
                ),
              ]),
              _section(theme, 'Invalid payload probes (T11)'),
              TextField(
                controller: _existingId,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Existing round ID of yours (for the update test)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: _busy || uid == null
                      ? null
                      : () => _probe('Create with correctCount 6', () async {
                            await c.repo.attempts(uid).doc().set(_valid(count: 6));
                          }),
                  child: const Text('Score 6'),
                ),
                OutlinedButton(
                  onPressed: _busy || uid == null
                      ? null
                      : () => _probe('Create with extra field', () async {
                            await c.repo
                                .attempts(uid)
                                .doc()
                                .set({..._valid(), 'studentName': 'x'});
                          }),
                  child: const Text('Extra field'),
                ),
                OutlinedButton(
                  onPressed: _busy || uid == null || _existingId.text.trim().isEmpty
                      ? null
                      : () => _probe('Update existing round', () async {
                            await c.repo
                                .ref(uid, _existingId.text.trim())
                                .update({'correctCount': 5});
                          }),
                  child: const Text('Update existing'),
                ),
                OutlinedButton(
                  onPressed: _busy || uid == null || _existingId.text.trim().isEmpty
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          String line;
                          try {
                            final v = await c.repo
                                .verify(uid: uid, roundId: _existingId.text.trim());
                            line = 'Re-read original → ${v.correctCount}/5, '
                                '${v.submittedAt.toLocal()} (unchanged check)';
                          } on Exception catch (e) {
                            line = 'Re-read original → $e';
                          }
                          setState(() {
                            _probeLog.insert(0, line);
                            _busy = false;
                          });
                        },
                  child: const Text('Re-read original'),
                ),
              ]),
              if (_probeLog.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final l in _probeLog)
                  Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
              _section(theme, 'State trace'),
              Row(children: [
                Text('Phase: ${c.phase.name}'),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy trace'),
                  onPressed: () => Clipboard.setData(ClipboardData(
                      text: c.trace
                          .map((t) => '${t.at.toIso8601String()}  ${t.message}')
                          .join('\n'))),
                ),
              ]),
              for (final t in c.trace.reversed.take(80))
                Text(
                  '${t.at.toIso8601String().substring(11, 23)}  ${t.message}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: theme.textTheme.titleMedium),
      );
}
