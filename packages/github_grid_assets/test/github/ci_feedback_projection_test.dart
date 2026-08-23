import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

final class FakeBdRunner implements BdRunner {
  FakeBdRunner(this.export);
  String export;
  final calls = <List<String>>[];
  final results = <BdResult>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.of(args));
    if (args.first == 'export') {
      return BdResult(exitCode: 0, stdout: export, stderr: '');
    }
    return results.isEmpty
        ? const BdResult(exitCode: 0, stdout: '{}', stderr: '')
        : results.removeAt(0);
  }
}

final class FakeSender implements FeedbackCommandSender {
  FeedbackCommandResult result = const FeedbackCommandCompleted({});
  final calls = <Map<String, String>>[];
  Completer<void>? hold;

  @override
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  }) async {
    calls.add({
      'gridRoot': gridRoot,
      'beadId': beadId,
      'note': note,
      'idempotencyKey': idempotencyKey,
    });
    await hold?.future;
    return result;
  }
}

NormalizedGitHubEvent event(String conclusion, {String branch = 'grid/tg-1'}) =>
    NormalizedGitHubEvent.checkConcluded(
      nodeId: 'n',
      actor: 'a',
      repository: 'o/r',
      substation: 'power',
      observationId: 'obs',
      headBranch: branch,
      checkName: 'build',
      conclusion: conclusion,
    );

String ledger(List<String> keys) => jsonEncode([
  for (var i = 0; i < keys.length; i++)
    {
      'id': 'session-$i',
      'issue_type': 'session',
      'metadata': {'work_bead': keys[i]},
    },
]);

CiFeedbackProjection projection(FakeBdRunner bd, FakeSender sender) =>
    CiFeedbackProjection(
      bd: bd,
      commandSender: sender,
      gridRoot: '/grid',
      substation: 'power',
    );

void main() {
  test('idempotency follows bead round and check identity', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender();
    final subject = projection(bd, sender);
    await subject(event('failure'));
    await subject(event('failure'));
    expect(sender.calls, hasLength(1));
    expect(
      sender.calls.single['idempotencyKey'],
      'github-ci:tg-1:r0:build:obs',
    );

    bd.export = ledger(['tg-1', 'tg-1#r1']);
    await subject(event('failure'));
    expect(sender.calls, hasLength(2));
    expect(sender.calls.last['idempotencyKey'], 'github-ci:tg-1:r1:build:obs');
  });

  test('overlapping deliveries coalesce', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender()..hold = Completer<void>();
    final subject = projection(bd, sender);
    final first = subject(event('failure'));
    await Future<void>.delayed(Duration.zero);
    final second = subject(event('failure'));
    sender.hold!.complete();
    await Future.wait([first, second]);
    expect(sender.calls, hasLength(1));
  });

  test('cap refusal becomes one gate', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    final subject = projection(bd, sender);
    await subject(event('failure'));
    await subject(event('failure'));
    final creates = bd.calls.where((call) => call.first == 'create').toList();
    expect(creates, hasLength(1));
    expect(
      creates.single,
      containsAllInOrder([
        '--id',
        'tg-1-ci-rework-cap',
        '--title',
        'CI rework cap reached for tg-1',
        '--type',
        'gate',
      ]),
    );
  });

  test('green preserves ledger and marks landing-ready', () async {
    final bd = FakeBdRunner(ledger(['tg-1', 'tg-1#r1']));
    final sender = FakeSender();
    await projection(bd, sender)(event('success'));
    expect(sender.calls, isEmpty);
    expect(bd.calls.last, [
      'update',
      'tg-1',
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);
  });

  test('out-of-scope checks perform no effects', () async {
    final bd = FakeBdRunner('not json');
    final sender = FakeSender();
    await projection(bd, sender)(event('failure', branch: 'main'));
    expect(bd.calls, isEmpty);
    expect(sender.calls, isEmpty);
  });

  test('malformed and ambiguous exports fail loudly', () async {
    final sender = FakeSender();
    await expectLater(
      projection(FakeBdRunner('bad'), sender)(event('failure')),
      throwsStateError,
    );
    await expectLater(
      projection(FakeBdRunner(ledger(['tg-1', 'tg-1'])), sender)(
        event('failure'),
      ),
      throwsStateError,
    );
  });
}
