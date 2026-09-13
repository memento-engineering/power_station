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
  FakeBdRunner(this.sessions, {this.externalRefMatches = const <String>[]});

  /// The enveloped payload `bd list -t session --all --json` answers with.
  String sessions;

  /// The bead ids `bd list --external-ref gh-<n> --all --json` answers with.
  List<String> externalRefMatches;
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
      if (args.contains('--external-ref')) {
        return BdResult(
          exitCode: 0,
          stdout: jsonEncode(<String, Object?>{
            'schema_version': 1,
            'data': <Object?>[
              for (final id in externalRefMatches)
                <String, Object?>{'id': id, 'issue_type': 'task'},
            ],
          }),
          stderr: '',
        );
      }
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

/// One open-pull feedback observation. [body] is the PRIMARY attribution and
/// [branch] is deliberately free: no decision may depend on it.
NormalizedGitHubEvent event(
  PullRequestCheckState checkState, {
  String branch = 'org/lockfile-convention',
  String body = 'A human digest.\n\nRefs: tg-1\n',
  int number = 8,
  String headSha = 'abc123',
  bool stalled = false,
  DateTime? greenSince,
}) => NormalizedGitHubEvent.pullRequestFeedback(
  nodeId: 'PR_8',
  actor: 'nico',
  repository: 'o/r',
  substation: 'power',
  observationId: 'poll:pull-feedback:PR_8:$headSha:${checkState.name}',
  number: number,
  body: body,
  headBranch: branch,
  headSha: headSha,
  checkState: checkState,
  mergeability: PullRequestMergeability.mergeable,
  openedAt: DateTime.utc(2026, 9, 12, 8),
  updatedAt: DateTime.utc(2026, 9, 12, 9),
  greenSince: greenSince,
  observedAt: DateTime.utc(2026, 9, 12, 10),
  stalled: stalled,
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

  test('explicit pull references never depend on branch names', () async {
    // AC-2, both halves. A pull whose branch contains no bead id at all is
    // attributed from its ONE `Refs:` trailer, with no correlation read; a pull
    // with no trailer falls back to the ONE bead carrying `gh-<number>`.
    final trailered = FakeBdRunner(ledger(['tg-1']));
    await projection(trailered, FakeSender())(
      event(PullRequestCheckState.green),
    );
    expect(
      trailered.calls.map((call) => call.join(' ')),
      isNot(contains(contains('--external-ref'))),
      reason: 'a stated trailer costs no correlation read',
    );
    expect(trailered.calls.first, <String>[
      'list',
      '-t',
      'session',
      '--all',
      '--json',
      '--limit',
      '0',
    ]);
    expect(trailered.calls.last, <String>[
      'update',
      'tg-1',
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);

    final referenced = FakeBdRunner(
      ledger(['tg-1']),
      externalRefMatches: <String>['tg-1'],
    );
    await projection(referenced, FakeSender())(
      event(PullRequestCheckState.green, body: 'No trailer here.', number: 8),
    );
    expect(referenced.calls.first, <String>[
      'list',
      '--all',
      '--external-ref',
      'gh-8',
      '--json',
      '--limit',
      '0',
    ]);
    expect(referenced.calls.last.take(2), <String>['update', 'tg-1']);

    // And the branch itself is inert: `grid/tg-2` cannot override the trailer.
    final misleading = FakeBdRunner(ledger(['tg-1']));
    await projection(misleading, FakeSender())(
      event(PullRequestCheckState.green, branch: 'grid/tg-2'),
    );
    expect(misleading.calls.last.take(2), <String>['update', 'tg-1']);
  });

  test('unattributed pull feedback flares without effects', () async {
    // AC-3: reported, never dropped, and it mutates nothing.
    for (final shape
        in <
          ({
            String name,
            FakeBdRunner bd,
            NormalizedGitHubEvent event,
            String reason,
          })
        >[
          (
            name: 'two distinct trailers',
            bd: FakeBdRunner(ledger(['tg-1'])),
            event: event(
              PullRequestCheckState.green,
              body: 'Refs: tg-1\nRefs: tg-2\n',
            ),
            reason: '2 distinct Refs:',
          ),
          (
            name: 'no trailer and no external ref',
            bd: FakeBdRunner(ledger(['tg-1'])),
            event: event(PullRequestCheckState.green, body: 'No trailer.'),
            reason: '0 beads carry external ref gh-8',
          ),
          (
            name: 'no trailer and two external refs',
            bd: FakeBdRunner(
              ledger(['tg-1']),
              externalRefMatches: <String>['tg-1', 'tg-2'],
            ),
            event: event(PullRequestCheckState.green, body: 'No trailer.'),
            reason: '2 beads carry external ref gh-8',
          ),
        ]) {
      final sender = FakeSender();
      final reporter = RecordingReporter();
      final subject = projection(shape.bd, sender)
        ..bindReporter(reporter.report);

      await subject(shape.event);

      expect(sender.calls, isEmpty, reason: shape.name);
      expect(
        shape.bd.calls.map((call) => call.first),
        everyElement('list'),
        reason: '${shape.name} mutates nothing',
      );
      expect(reporter.flares, hasLength(1), reason: shape.name);
      expect(reporter.flares.single.name, kCiFeedbackUnattributedFlare);
      expect(reporter.flares.single.action, contains('#8'));
      expect('${reporter.flares.single.error}', contains(shape.reason));
    }
  });

  test('explicit grid pull feedback preserves actions', () async {
    // AC-6: a `grid/` pull carrying its trailer keeps the green-to-landing and
    // failing-to-rework-or-cap behavior EXACTLY — attribution just comes from
    // the trailer now rather than from the branch it happens to share.
    const branch = 'grid/tg-1';
    final green = FakeBdRunner(ledger(['tg-1', 'tg-1#r1']));
    await projection(green, FakeSender())(
      event(PullRequestCheckState.green, branch: branch),
    );
    expect(green.calls.last, <String>[
      'update',
      'tg-1',
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);

    final failing = FakeBdRunner(ledger(['tg-1', 'tg-1#r1']));
    final sender = FakeSender();
    await projection(failing, sender)(
      event(PullRequestCheckState.failing, branch: branch),
    );
    expect(sender.calls.single['beadId'], 'tg-1');
    expect(
      sender.calls.single['idempotencyKey'],
      'github-ci:tg-1:r1:abc123:failing',
    );
    expect(sender.calls.single['note'], contains('#8'));
    expect(sender.calls.single['note'], contains('abc123'));

    // The RETIRED rework keys still count toward the cap: an exact `work_bead`
    // match would drop exactly them and rework forever instead of gating.
    final capped = FakeBdRunner(
      ledger(['tg-1', 'tg-1#r1', 'tg-1#r2', 'tg-1#r3']),
    );
    final capSender = FakeSender();
    await projection(capped, capSender)(
      event(PullRequestCheckState.failing, branch: branch),
    );
    expect(capSender.calls, isEmpty);
    expect(
      capped.calls.firstWhere((call) => call.first == 'create'),
      containsAllInOrder(<String>[
        '--id',
        'tg-1-ci-rework-cap',
        '--title',
        'CI rework cap reached for tg-1',
        '--type',
        'gate',
      ]),
    );
  });

  test('no fact to act on performs no read past attribution', () async {
    for (final state in <PullRequestCheckState>[
      PullRequestCheckState.notReported,
      PullRequestCheckState.pending,
      PullRequestCheckState.inconclusive,
    ]) {
      final bd = FakeBdRunner(ledger(['tg-1']));
      final sender = FakeSender();
      await projection(bd, sender)(event(state));
      expect(sender.calls, isEmpty, reason: '$state acts on nothing');
      expect(
        bd.calls.map((call) => call.first),
        everyElement('list'),
        reason: '$state mutates nothing',
      );
    }
  });

  test('the stall crossing performs no merge or rework action', () async {
    // AC-7's other half: the second, stalled observation shares the fresh
    // one's head and state, so it shares its idempotency key and does nothing.
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender();
    final subject = projection(bd, sender);
    final greenSince = DateTime.utc(2026, 9, 12, 9);
    await subject(event(PullRequestCheckState.green, greenSince: greenSince));
    final afterFresh = bd.calls.length;
    await subject(
      event(PullRequestCheckState.green, greenSince: greenSince, stalled: true),
    );
    expect(sender.calls, isEmpty);
    expect(
      bd.calls.where((call) => call.first == 'update'),
      hasLength(1),
      reason: 'the crossing repeats no mutation',
    );
    expect(bd.calls.length, greaterThanOrEqualTo(afterFresh));
  });

  test('idempotency follows bead round and head identity', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender();
    final subject = projection(bd, sender);
    await subject(event(PullRequestCheckState.failing));
    await subject(event(PullRequestCheckState.failing));
    expect(sender.calls, hasLength(1));
    expect(
      sender.calls.single['idempotencyKey'],
      'github-ci:tg-1:r0:abc123:failing',
    );

    // A NEW head is a new fact; a bumped `updated_at` on the same head is not,
    // and the observation id deliberately takes no part in the key.
    await subject(event(PullRequestCheckState.failing, headSha: 'def456'));
    expect(sender.calls, hasLength(2));
    expect(
      sender.calls.last['idempotencyKey'],
      'github-ci:tg-1:r0:def456:failing',
    );

    bd.sessions = ledger(['tg-1', 'tg-1#r1']);
    await subject(event(PullRequestCheckState.failing));
    expect(sender.calls, hasLength(3));
    expect(
      sender.calls.last['idempotencyKey'],
      'github-ci:tg-1:r1:abc123:failing',
    );
  });

  test('overlapping deliveries coalesce', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender()..hold = Completer<void>();
    final subject = projection(bd, sender);
    final first = subject(event(PullRequestCheckState.failing));
    await Future<void>.delayed(Duration.zero);
    final second = subject(event(PullRequestCheckState.failing));
    sender.hold!.complete();
    await Future.wait([first, second]);
    expect(sender.calls, hasLength(1));
  });

  test('cap refusal becomes one gate', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    final subject = projection(bd, sender);
    await subject(event(PullRequestCheckState.failing));
    await subject(event(PullRequestCheckState.failing));
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

  test('one type-scoped session read replaces the export', () async {
    final bd = FakeBdRunner(ledger(['tg-1']));
    await projection(bd, FakeSender())(event(PullRequestCheckState.failing));

    expect(
      bd.calls.where((call) => call.first == 'list'),
      hasLength(1),
      reason: 'exactly ONE read per projected observation',
    );
    expect(
      bd.calls.map((call) => call.first),
      isNot(contains('export')),
      reason: 'a proxied-server store refuses export outright',
    );
  });

  test('a malformed session read still fails loudly', () async {
    // A store that answers nonsense is BROKEN, not a legitimate shape: the leg
    // keeps throwing so the observation stays pending and the cycle says so.
    await expectLater(
      projection(FakeBdRunner('bad'), FakeSender())(
        event(PullRequestCheckState.failing),
      ),
      throwsA(isA<BdException>()),
    );
  });

  test('a legacy check envelope is reported and acted on never', () async {
    // Nothing emits `checkConcluded` any more, but a cursor written before the
    // feedback poll changed shape can still replay one — and it states no pull
    // reference, only the head branch that stopped being an attribution.
    final bd = FakeBdRunner(ledger(['pow-2xmo']));
    final sender = FakeSender();
    final reporter = RecordingReporter();
    final subject = projection(bd, sender)..bindReporter(reporter.report);

    await subject(
      const NormalizedGitHubEvent.checkConcluded(
        nodeId: 'C_1',
        actor: 'actions',
        repository: 'o/r',
        substation: 'power',
        observationId: 'poll:check:C_1:2026-09-03T16:24:00Z:failure',
        headBranch: 'grid/pow-2xmo',
        checkName: 'build',
        conclusion: 'failure',
      ),
    );

    expect(bd.calls, isEmpty, reason: 'not even a correlation read');
    expect(sender.calls, isEmpty);
    expect(reporter.flares.single.name, kCiFeedbackIgnoredFlare);
    expect(reporter.flares.single.action, contains('grid/pow-2xmo'));
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

      await subject(event(PullRequestCheckState.failing));

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
        event(PullRequestCheckState.failing),
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

    await subject(event(PullRequestCheckState.failing));

    expect(mine.flares, isEmpty);
    expect(theirs.flares, hasLength(1));
  });

  test('a watched-issue observation is not this leg\'s work', () async {
    final projection = CiFeedbackProjection(
      bd: _RefusingRunner(),
      commandSender: _RefusingCommandSender(),
      gridRoot: '/unused',
      substation: 'power_station',
    );

    await projection(
      NormalizedGitHubEvent.issueCommented(
        nodeId: 'IC_first',
        actor: 'ricardoboss',
        repository: 'ricardoboss/radioactive_dart',
        substation: 'power_station',
        observationId: 'poll:issue-comment:IC_first',
        originatingBeadId: 'lunar_station-6p9',
        issueNodeId: 'I_kwDO',
        issueAuthor: 'nico',
        issueNumber: 1,
        commentId: 11,
        body: 'A reply.',
        url: 'https://github.test/1',
        updatedAt: DateTime.utc(2026, 9, 9, 11),
      ),
    );
    await projection(
      NormalizedGitHubEvent.watchedIssueStateChanged(
        nodeId: 'CE_closed',
        actor: 'ricardoboss',
        repository: 'ricardoboss/radioactive_dart',
        substation: 'power_station',
        observationId: 'poll:issue-state:CE_closed:closed_completed',
        originatingBeadId: 'lunar_station-6p9',
        issueNodeId: 'I_kwDO',
        issueAuthor: 'nico',
        issueNumber: 1,
        change: GitHubIssueWatchChange.closedCompleted,
        state: 'closed',
        stateReason: null,
        locked: false,
        url: null,
        updatedAt: DateTime.utc(2026, 9, 9, 13),
      ),
    );
  });
}

/// A runner that FAILS the test if the CI-feedback leg touches `bd` for a
/// watched-issue observation.
final class _RefusingRunner implements BdRunner {
  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) =>
      throw StateError('a watched issue has no session to correlate');
}

final class _RefusingCommandSender implements FeedbackCommandSender {
  @override
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  }) => throw StateError('a watched issue has no rework round');
}
