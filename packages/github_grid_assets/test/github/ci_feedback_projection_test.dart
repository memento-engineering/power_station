import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

/// The verbatim refusal a PROXIED-SERVER store answers `bd export` with. Every
/// org store and lunar's own state store run in that mode, so this fake is the
/// production posture: a leg that reaches export at all is dead on arrival.
const String kProxiedExportRefusal =
    'Error: export is not supported in proxied-server mode';

final class FakeBdRunner implements BdRunner {
  FakeBdRunner(this.sessions);

  /// The enveloped payload `bd list -t session --all --json` answers with.
  String sessions;
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
      return const BdResult(
        exitCode: 1,
        stdout: '',
        stderr: kProxiedExportRefusal,
      );
    }
    if (args.first == 'list') {
      return BdResult(exitCode: 0, stdout: sessions, stderr: '');
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

/// Every flare the projection reported, in report order.
final class RecordingReporter {
  final flares = <({String name, String action, Object error})>[];

  void report(
    String name,
    String action,
    Object error,
    StackTrace stackTrace,
  ) => flares.add((name: name, action: action, error: error));
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

/// One session row per key, in the version-1 `{schema_version, data}` envelope
/// `bd list --json` returns. [ids] overrides the generated session ids.
String ledger(List<String> keys, {List<String>? ids}) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (var i = 0; i < keys.length; i++)
      {
        'id': ids == null ? 'session-$i' : ids[i],
        'issue_type': 'session',
        'metadata': {'work_bead': keys[i]},
      },
  ],
});

CiFeedbackProjection projection(FakeBdRunner bd, FakeSender sender) =>
    CiFeedbackProjection(
      bd: bd,
      commandSender: sender,
      gridRoot: '/grid',
      substation: 'power',
    );

void main() {
  test('a concluded workflow run never enters the feedback logic', () async {
    // No session read, no rework, no landing mark, no gate: a workflow run is
    // intake's, and the sealed union makes that disjointness a compile error
    // to break rather than a comment to forget.
    final bd = FakeBdRunner('{"schema_version":1,"data":[]}');
    final sender = FakeSender();
    final projection = CiFeedbackProjection(
      bd: bd,
      commandSender: sender,
      gridRoot: '/grid',
      substation: 'seat',
    );

    await projection(
      const NormalizedGitHubEvent.workflowRunConcluded(
        nodeId: 'WFR_1',
        actor: 'memento/power_station',
        repository: 'memento/power_station',
        substation: 'seat',
        observationId: 'poll:run:WFR_1:2026-09-07T06:11:00Z:failure',
        runId: 9001,
        runNumber: 128,
        workflowPath: '.github/workflows/ci.yaml',
        workflowName: 'CI',
        event: 'schedule',
        headBranch: 'grid/pow-test',
        headSha: 'abcdef0',
        conclusion: 'failure',
        htmlUrl: 'https://github.test/runs/9001',
        failedJobs: <WorkflowRunFailedJob>[],
      ),
    );

    expect(bd.calls, isEmpty, reason: 'not even the session read runs');
    expect(sender.calls, isEmpty);
  });

  test('one type-scoped session read replaces the export', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    await projection(bd, FakeSender())(event('failure'));

    expect(bd.calls.first, <String>[
      'list',
      '-t',
      'session',
      '--all',
      '--json',
      '--limit',
      '0',
    ]);
    expect(
      bd.calls.where((call) => call.first == 'list'),
      hasLength(1),
      reason: 'exactly ONE read per projected check',
    );
    expect(
      bd.calls.map((call) => call.first),
      isNot(contains('export')),
      reason: 'a proxied-server store refuses export outright',
    );
  });

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

    bd.sessions = ledger(['tg-1', 'tg-1#r1']);
    await subject(event('failure'));
    expect(sender.calls, hasLength(2));
    expect(sender.calls.last['idempotencyKey'], 'github-ci:tg-1:r1:build:obs');
  });

  test('the RETIRED rework keys still count toward the round', () async {
    // The scoped read is deliberately NOT narrowed by a `work_bead` metadata
    // equality: `tg-1#r1`/`#r2`/`#r3` are the retired ledger `maxReworkRound`
    // counts, and an exact match would drop exactly them — silently reworking
    // forever instead of gating at the cap.
    final bd = FakeBdRunner(ledger(['tg-1', 'tg-1#r1', 'tg-1#r2', 'tg-1#r3']));
    final sender = FakeSender();
    await projection(bd, sender)(event('failure'));

    expect(sender.calls, isEmpty);
    expect(
      bd.calls.firstWhere((call) => call.first == 'create'),
      containsAllInOrder(<String>['--id', 'tg-1-ci-rework-cap']),
    );
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

  test('a malformed session read still fails loudly', () async {
    // A store that answers nonsense is BROKEN, not a legitimate shape: the leg
    // keeps throwing so the observation stays pending and the cycle says so.
    await expectLater(
      projection(FakeBdRunner('bad'), FakeSender())(event('failure')),
      throwsA(isA<BdException>()),
    );
  });

  for (final shape in <({String name, String sessions, String reason})>[
    (
      name: 'no live session',
      sessions: '{"schema_version":1,"data":[]}',
      reason: 'found 0',
    ),
    (
      name: 'two current sessions',
      sessions: ledger(['tg-1', 'tg-1']),
      reason: 'found 2',
    ),
    (
      name: 'a current session with a blank id',
      sessions: ledger(['tg-1'], ids: ['   ']),
      reason: 'carries no id',
    ),
  ]) {
    test('${shape.name} is IGNORED and flared, never thrown', () async {
      final bd = FakeBdRunner(shape.sessions);
      final sender = FakeSender();
      final reporter = RecordingReporter();
      final subject = projection(bd, sender)..bindReporter(reporter.report);

      await subject(event('failure'));

      expect(sender.calls, isEmpty);
      expect(
        bd.calls.map((call) => call.first),
        <String>['list'],
        reason: 'an ignored shape mutates nothing',
      );
      expect(reporter.flares, hasLength(1));
      expect(reporter.flares.single.name, kCiFeedbackIgnoredFlare);
      expect(reporter.flares.single.action, contains('tg-1'));
      expect('${reporter.flares.single.error}', contains(shape.reason));
    });
  }

  test('an ignored shape without a bound reporter is still not a throw', () {
    // The seat binds the rail; a bare projection has none. Silence is the only
    // thing lost — never the acknowledgement the outbox needs.
    expect(
      projection(FakeBdRunner('{"schema_version":1,"data":[]}'), FakeSender())(
        event('failure'),
      ),
      completes,
    );
  });

  test('unbinding is owner-scoped', () async {
    final subject = projection(
      FakeBdRunner('{"schema_version":1,"data":[]}'),
      FakeSender(),
    );
    final mine = RecordingReporter();
    final theirs = RecordingReporter();
    final CiFeedbackReporter mineReporter = mine.report;
    subject
      ..bindReporter(mineReporter)
      ..bindReporter(theirs.report)
      // MY binding was already replaced; unbinding it must not silence THEIRS.
      ..unbindReporter(mineReporter);

    await subject(event('failure'));

    expect(mine.flares, isEmpty);
    expect(theirs.flares, hasLength(1));
  });
}
