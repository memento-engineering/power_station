import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
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

/// A minted gate as [PrefixedStateStoreRunner] holds it.
final class MintedGate {
  MintedGate(this.id, this.title, this.metadata);

  final String id;
  final String title;
  final Map<String, Object?> metadata;
}

/// The grid STATE store as bd actually behaves about ids: it mints
/// `<prefix>-<n>` when `create` states no `--id`, and REFUSES — verbatim — any
/// `--id` that does not carry its own prefix. Sessions are answered from
/// [sessions]; the type-scoped gate list is answered from what it minted.
final class PrefixedStateStoreRunner implements BdRunner {
  PrefixedStateStoreRunner(this.prefix, this.sessions);

  final String prefix;

  /// The enveloped session list; reassign it to model a re-key.
  String sessions;
  final calls = <List<String>>[];
  final gates = <MintedGate>[];

  /// Every prefix-mismatch refusal this store answered.
  final refusals = <String>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.of(args));
    switch (args.first) {
      case 'list':
        if (args.contains('gate')) {
          return BdResult(
            exitCode: 0,
            stdout: jsonEncode(<String, Object?>{
              'schema_version': 1,
              'data': <Object?>[
                for (final gate in gates)
                  <String, Object?>{
                    'id': gate.id,
                    'title': gate.title,
                    'issue_type': 'gate',
                    'status': 'open',
                    'metadata': gate.metadata,
                  },
              ],
            }),
            stderr: '',
          );
        }
        return BdResult(exitCode: 0, stdout: sessions, stderr: '');
      case 'create':
        final idAt = args.indexOf('--id');
        if (idAt != -1 && !args[idAt + 1].startsWith('$prefix-')) {
          final refusal =
              "Error: prefix mismatch: database uses '$prefix-' but ID "
              "'${args[idAt + 1]}' doesn't match (use --force to override)";
          refusals.add(refusal);
          return BdResult(exitCode: 1, stdout: '', stderr: refusal);
        }
        final id = idAt != -1
            ? args[idAt + 1]
            : '$prefix-${(gates.length + 1).toString().padLeft(4, '0')}';
        final metadataAt = args.indexOf('--metadata');
        gates.add(
          MintedGate(
            id,
            args[args.indexOf('--title') + 1],
            metadataAt == -1
                ? <String, Object?>{}
                : (jsonDecode(args[metadataAt + 1]) as Map<String, Object?>),
          ),
        );
        return BdResult(
          exitCode: 0,
          stdout: jsonEncode(<String, Object?>{'id': id}),
          stderr: '',
        );
      case 'update':
        final gate = gates.firstWhere((gate) => gate.id == args[1]);
        for (var i = 0; i < args.length - 1; i++) {
          if (args[i] != '--set-metadata') continue;
          final pair = args[i + 1];
          final eq = pair.indexOf('=');
          gate.metadata[pair.substring(0, eq)] = pair.substring(eq + 1);
        }
        return const BdResult(exitCode: 0, stdout: '{}', stderr: '');
    }
    return const BdResult(exitCode: 0, stdout: '{}', stderr: '');
  }
}

/// The scope's OWN work store: it records every argv and answers [result].
///
/// A DISTINCT fake from [FakeBdRunner] on purpose. The two rails are separate
/// stores, and a shared fake would let a test pass while the landing mark went
/// to the state store — the exact defect the split exists to close.
final class FakeWorkBdRunner implements BdRunner {
  FakeWorkBdRunner({
    this.result = const BdResult(exitCode: 0, stdout: '', stderr: ''),
  });

  /// The result the landing-ready mutation answers with.
  BdResult result;
  final calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.of(args));
    return result;
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

/// The substation every fixture here is mounted under: `tg-…` work beads in a
/// store at `/work/power`.
const sdk.SubstationScope kScope = sdk.SubstationScope(
  name: 'power',
  root: '/work/power',
  prefix: 'tg',
);

/// A projection over an EXPLICIT pair of stores. There is no default work
/// runner shared with [bd]: every fixture states which store it expects the
/// landing mark to reach.
CiFeedbackProjection projection(
  BdRunner bd,
  FakeSender sender, {
  FakeWorkBdRunner? workBd,
  sdk.SubstationScope scope = kScope,
}) => CiFeedbackProjection(
  bd: bd,
  workBd: workBd ?? FakeWorkBdRunner(),
  scope: scope,
  commandSender: sender,
  gridRoot: '/grid',
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
      workBd: FakeWorkBdRunner(),
      scope: const sdk.SubstationScope(
        name: 'seat',
        root: '/work/seat',
        prefix: 'tg',
      ),
      commandSender: sender,
      gridRoot: '/grid',
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
    final trailerWork = FakeWorkBdRunner();
    await projection(trailered, FakeSender(), workBd: trailerWork)(
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
    expect(trailerWork.calls.single, <String>[
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
    final referencedWork = FakeWorkBdRunner();
    await projection(referenced, FakeSender(), workBd: referencedWork)(
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
    expect(referencedWork.calls.single.take(2), <String>['update', 'tg-1']);

    // And the branch itself is inert: `grid/tg-2` cannot override the trailer.
    final misleading = FakeBdRunner(ledger(['tg-1']));
    final misleadingWork = FakeWorkBdRunner();
    await projection(misleading, FakeSender(), workBd: misleadingWork)(
      event(PullRequestCheckState.green, branch: 'grid/tg-2'),
    );
    expect(misleadingWork.calls.single.take(2), <String>['update', 'tg-1']);
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
    final greenWork = FakeWorkBdRunner();
    await projection(green, FakeSender(), workBd: greenWork)(
      event(PullRequestCheckState.green, branch: branch),
    );
    expect(greenWork.calls.single, <String>[
      'update',
      'tg-1',
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);
    expect(
      green.calls.map((call) => call.first),
      everyElement('list'),
      reason: 'the STATE store sees no work-bead mutation',
    );

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
    final create = capped.calls.firstWhere((call) => call.first == 'create');
    expect(
      create,
      containsAllInOrder(<String>[
        '--title',
        'CI rework cap reached for tg-1',
        '--type',
        'gate',
      ]),
    );
    // The id is the STATE store's to mint: a `--id` here carried the work
    // bead's prefix into a store that refuses every id but its own.
    expect(create, isNot(contains('--id')));
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
    final work = FakeWorkBdRunner();
    final sender = FakeSender();
    final subject = projection(bd, sender, workBd: work);
    final greenSince = DateTime.utc(2026, 9, 12, 9);
    await subject(event(PullRequestCheckState.green, greenSince: greenSince));
    final afterFresh = bd.calls.length;
    await subject(
      event(PullRequestCheckState.green, greenSince: greenSince, stalled: true),
    );
    expect(sender.calls, isEmpty);
    expect(
      work.calls.where((call) => call.first == 'update'),
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
        '--title',
        'CI rework cap reached for tg-1',
        '--type',
        'gate',
      ]),
    );
    expect(creates.single, isNot(contains('--id')));
    final metadata =
        jsonDecode(creates.single[creates.single.indexOf('--metadata') + 1])
            as Map<String, Object?>;
    expect(metadata['work_bead'], 'tg-1');
    expect(metadata['node'], 'tg-1/ci-feedback');
    expect(metadata['blocks'], 'session-0');
    expect(metadata['rig'], 'power');
  });

  test('the cap gate is minted under the STATE store\'s prefix, never the '
      'work bead\'s', () async {
    // THE LIVE FAILURE, reproduced: lunar's state store mints `tranquility-`
    // and the red work bead is `tg-…`. Every tick used to die on bd's
    // `prefix mismatch` refusal of `--id tg-…-ci-rework-cap`, and the whole
    // reconciliation obligation stuck behind that one bead.
    final state = PrefixedStateStoreRunner('tranquility', ledger(['tg-1']));
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    final reporter = RecordingReporter();
    final subject = projection(state, sender)..bindReporter(reporter.report);

    await expectLater(subject(event(PullRequestCheckState.failing)), completes);

    expect(state.gates, hasLength(1));
    final gate = state.gates.single;
    expect(gate.id, startsWith('tranquility-'));
    expect(gate.id, isNot(contains('tg-1-ci-rework-cap')));
    expect(gate.title, 'CI rework cap reached for tg-1');
    expect(gate.metadata['work_bead'], 'tg-1');
    expect(gate.metadata['node'], 'tg-1/ci-feedback');
    expect(gate.metadata['blocks'], 'session-0');
    expect(state.refusals, isEmpty, reason: 'no prefix-mismatch refusal');
    expect(reporter.flares, isEmpty);
    expect(
      state.calls.where((call) => call.first == 'create').single,
      isNot(contains('--id')),
    );
  });

  test('an OPEN cap gate for the same session and node is refreshed, not '
      'duplicated', () async {
    // With no fixed id there is no `already exists` collision to lean on, so
    // dedup is a READ: a restarted projection (empty in-memory guard) that
    // meets the same red head finds the open gate and refreshes its reason.
    final state = PrefixedStateStoreRunner('tranquility', ledger(['tg-1']));
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    await projection(state, sender)(event(PullRequestCheckState.failing));
    expect(state.gates, hasLength(1));

    final restarted = projection(state, sender);
    await restarted(event(PullRequestCheckState.failing, headSha: 'def456'));

    expect(state.gates, hasLength(1), reason: 'one stable gate, refreshed');
    expect(state.gates.single.metadata['reason'], contains('def456'));
    final probe = state.calls.where(
      (call) => call.first == 'list' && call.contains('gate'),
    );
    expect(probe, isNotEmpty, reason: 'dedup is a type-scoped read');
    expect(
      state.calls.where((call) => call.first == 'update').single,
      containsAllInOrder(<String>[state.gates.single.id, '--set-metadata']),
    );
  });

  test('a RE-KEYED session on a capped bead refreshes the bead\'s one open '
      'cap gate and never mints a second', () async {
    // Dedup is per WORK BEAD, as the retired `<bead>-ci-rework-cap` id made
    // it. The first session on tg-1 is gated; the operator then re-keys it
    // (the old session retires to `tg-1#r1`, a NEW session takes `tg-1`) and
    // the resident restarts. The same red head arriving for the new session
    // must find the gate its predecessor left, not mint a second open one.
    final state = PrefixedStateStoreRunner(
      'tranquility',
      ledger(['tg-1'], ids: ['tranquility-s1']),
    );
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    await projection(state, sender)(event(PullRequestCheckState.failing));
    expect(state.gates, hasLength(1));
    expect(state.gates.single.metadata['blocks'], 'tranquility-s1');

    state.sessions = ledger(
      ['tg-1#r1', 'tg-1'],
      ids: ['tranquility-s1', 'tranquility-s2'],
    );
    final restarted = projection(state, sender);
    await restarted(event(PullRequestCheckState.failing));

    expect(
      state.gates,
      hasLength(1),
      reason: 'exactly ONE open cap gate for the capped work bead',
    );
    expect(state.calls.where((call) => call.first == 'create'), hasLength(1));
    final gate = state.gates.single;
    expect(gate.metadata['work_bead'], 'tg-1');
    expect(gate.metadata['node'], 'tg-1/ci-feedback');
    expect(
      gate.metadata['blocks'],
      'tranquility-s2',
      reason: 'the gate follows the CURRENT session the engine joins through',
    );
  });

  test('another bead\'s open cap gate is never refreshed in place of this '
      'bead\'s', () async {
    final state = PrefixedStateStoreRunner(
      'tranquility',
      ledger(['tg-1', 'tg-2'], ids: ['tranquility-s1', 'tranquility-s2']),
    );
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    final subject = projection(state, sender);
    await subject(event(PullRequestCheckState.failing));
    await subject(
      event(
        PullRequestCheckState.failing,
        body: 'A human digest.\n\nRefs: tg-2\n',
        number: 9,
      ),
    );

    expect(state.gates, hasLength(2));
    expect(state.gates.map((gate) => gate.metadata['work_bead']), [
      'tg-1',
      'tg-2',
    ]);
    expect(state.calls.where((call) => call.first == 'update'), isEmpty);
  });

  test('a cap gate the state store refuses is flared for THAT bead and '
      'the next bead still gates', () async {
    // The isolation half: one bead's refused write is one bead's flare. The
    // leg returns normally, so the observation acks and the cycle reaches
    // every other bead — instead of throwing the shared obligation tick.
    const refusal =
        "Error: prefix mismatch: database uses 'tranquility-' but ID "
        "'tg-1-ci-rework-cap' doesn't match (use --force to override)";
    final state = FakeBdRunner(ledger(['tg-1', 'tg-2']))
      ..results.add(const BdResult(exitCode: 1, stdout: '', stderr: refusal));
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    final reporter = RecordingReporter();
    final subject = projection(state, sender)..bindReporter(reporter.report);

    await expectLater(subject(event(PullRequestCheckState.failing)), completes);
    await expectLater(
      subject(
        event(
          PullRequestCheckState.failing,
          body: 'A human digest.\n\nRefs: tg-2\n',
          number: 9,
        ),
      ),
      completes,
    );

    final creates = state.calls.where((call) => call.first == 'create');
    expect(creates, hasLength(2), reason: 'tg-2 was still gated');
    expect(creates.last, contains('CI rework cap reached for tg-2'));
    expect(reporter.flares, hasLength(1));
    expect(reporter.flares.single.name, kCiFeedbackCapGateUnresolvedFlare);
    expect('${reporter.flares.single.error}', contains('tg-1'));
    expect('${reporter.flares.single.error}', isNot(contains('tg-2')));
    expect('${reporter.flares.single.error}', contains(refusal));

    // The refused decision's key is RELEASED, so a DISTINCT later delivery of
    // the same red head retries the mint. Whether the reconciler ever makes
    // such a delivery is the cycle's business, pinned in
    // reconciler_delivery_test.dart: only when the pull itself moves.
    await subject(event(PullRequestCheckState.failing));
    expect(
      state.calls.where((call) => call.first == 'create'),
      hasLength(3),
      reason: 'the retry reaches the store',
    );
    expect(reporter.flares, hasLength(1), reason: 'the retry succeeded');
  });

  test('a refused cap gate without a bound reporter still completes', () {
    final state = FakeBdRunner(ledger(['tg-1']))
      ..results.add(
        const BdResult(exitCode: 1, stdout: '', stderr: 'store refused'),
      );
    final sender = FakeSender()
      ..result = const FeedbackCommandRefused('rework_round_cap', 'cap');
    expect(
      projection(state, sender)(event(PullRequestCheckState.failing)),
      completes,
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

  test('the landing mark reaches the scoped work store, never the state '
      'store', () async {
    // The DEFECT, stated as a test: the landing-ready `update` used to run
    // through the state-store runner, where no substation's work bead has ever
    // lived. Every armed substation's prefix routes to its own store now.
    for (final seat
        in <({String bead, String name, String root, String prefix})>[
          (
            bead: 'butane_flutter-wmgt',
            name: 'butane_flutter',
            root: '/work/butane_flutter',
            prefix: 'butane_flutter',
          ),
          (
            bead: 'swift-infer-097',
            name: 'swift-infer',
            root: '/work/swift-infer',
            prefix: 'swift-infer',
          ),
          (
            bead: 'pow-5ljz',
            name: 'power_station',
            root: '/work/power_station',
            prefix: 'pow',
          ),
        ]) {
      final state = FakeBdRunner(ledger([seat.bead]));
      final work = FakeWorkBdRunner();
      final reporter = RecordingReporter();
      final subject = projection(
        state,
        FakeSender(),
        workBd: work,
        scope: sdk.SubstationScope(
          name: seat.name,
          root: seat.root,
          prefix: seat.prefix,
        ),
      )..bindReporter(reporter.report);

      await subject(
        event(PullRequestCheckState.green, body: 'Refs: ${seat.bead}\n'),
      );

      expect(work.calls.single, <String>[
        'update',
        seat.bead,
        '--actor',
        'github-feedback',
        '--set-metadata',
        'grid.landing_ready=true',
      ], reason: seat.bead);
      expect(
        state.calls.map((call) => call.first),
        everyElement('list'),
        reason: '${seat.bead}: the state store answers reads only',
      );
      expect(reporter.flares, isEmpty, reason: seat.bead);
    }
  });

  test(
    'a bead the work store cannot resolve flares once, never throws',
    () async {
      // The store's OWN words, carried whole: a `sql: no rows` refusal is a
      // shape a store legitimately holds, so it degrades instead of wedging the
      // cycle before its poll.
      const stderr =
          'Error resolving tg-1: get tg-1: sql: no rows in result set';
      final state = FakeBdRunner(ledger(['tg-1']));
      final work = FakeWorkBdRunner(
        result: const BdResult(exitCode: 1, stdout: '', stderr: stderr),
      );
      final reporter = RecordingReporter();
      final subject = projection(state, FakeSender(), workBd: work)
        ..bindReporter(reporter.report);

      await expectLater(subject(event(PullRequestCheckState.green)), completes);

      expect(reporter.flares, hasLength(1));
      final flare = reporter.flares.single;
      expect(flare.name, kCiFeedbackLandingUnresolvedFlare);
      expect(flare.action, contains('tg-1'));
      expect('${flare.error}', contains('tg-1'));
      expect('${flare.error}', contains('/work/power'));
      expect('${flare.error}', contains(stderr));
      expect(
        state.calls.map((call) => call.first),
        everyElement('list'),
        reason: 'the failed mark never falls back to the state store',
      );

      // ONE flare per idempotency key, not one per cycle: the key stays handled
      // because the decision RETURNED rather than threw.
      await subject(event(PullRequestCheckState.green));
      expect(reporter.flares, hasLength(1));
      expect(work.calls, hasLength(1));
    },
  );

  test('a bead this scope does not own is refused before any update', () async {
    // The mutation-ownership guard, LOUD: a `tg-…` bead under a `pow` seat is
    // a wiring bug, and writing it into the wrong store would be silent.
    final state = FakeBdRunner(ledger(['tg-1']));
    final work = FakeWorkBdRunner();
    final reporter = RecordingReporter();
    final subject = projection(
      state,
      FakeSender(),
      workBd: work,
      scope: const sdk.SubstationScope(
        name: 'power_station',
        root: '/work/power_station',
        prefix: 'pow',
      ),
    )..bindReporter(reporter.report);

    await expectLater(subject(event(PullRequestCheckState.green)), completes);

    expect(work.calls, isEmpty, reason: 'a foreign bead costs no write');
    expect(state.calls.map((call) => call.first), everyElement('list'));
    expect(reporter.flares.single.name, kCiFeedbackLandingUnresolvedFlare);
    expect('${reporter.flares.single.error}', contains('tg-1'));
    expect('${reporter.flares.single.error}', contains('/work/power_station'));
    expect('${reporter.flares.single.error}', contains('prefix pow'));
  });

  test('an unresolvable landing mark without a bound reporter still '
      'completes', () {
    // Silence is the only thing a missing rail costs — never the
    // acknowledgement the outbox needs to advance past this observation.
    expect(
      projection(
        FakeBdRunner(ledger(['tg-1'])),
        FakeSender(),
        workBd: FakeWorkBdRunner(
          result: const BdResult(exitCode: 1, stdout: '', stderr: 'no rows'),
        ),
      )(event(PullRequestCheckState.green)),
      completes,
    );
  });

  test('a watched-issue observation is not this leg\'s work', () async {
    final projection = CiFeedbackProjection(
      bd: _RefusingRunner(),
      workBd: _RefusingRunner(),
      scope: const sdk.SubstationScope(
        name: 'power_station',
        root: '/unused',
        prefix: 'pow',
      ),
      commandSender: _RefusingCommandSender(),
      gridRoot: '/unused',
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
