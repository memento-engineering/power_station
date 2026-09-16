import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show StationTrajectoryRecorder, StuckObligationAccountant;
import 'package:grid_sdk/grid_sdk.dart' show ObligationQuery, Provider;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_trajectory/grid_trajectory.dart' as traj;
import 'package:test/test.dart';

class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

class _Probe extends StatelessSeed {
  const _Probe(this.read);

  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}

final class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

final class _Transport implements GitHubHttpTransport {
  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async =>
      const GitHubHttpResponse(statusCode: 500, body: 'unused');
}

final class _Cursors implements GitHubCursorStore {
  @override
  Future<GitHubReconcilerCursor> load() async => const GitHubReconcilerCursor();

  @override
  Future<void> save(GitHubReconcilerCursor cursor) async {}
}

final class _RecordingRuntime extends GitHubReconcilerRuntime {
  _RecordingRuntime({required GitHubAppClient client})
    : super(
        installationId: 'installation',
        reconciler: GitHubReconciler(
          owner: 'owner',
          repository: 'repository',
          substation: 'substation',
          client: client,
          cursors: _Cursors(),
          emit: (_) async {},
        ),
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );
}

final class _Factory {
  final configs = <GitHubReconcilerConfig>[];
  final cursors = <GitHubCursorStore>[];
  final emits = <GitHubEventSink>[];
  final transports = <ExplorationTransport?>[];
  final runtimes = <_RecordingRuntime>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    required ExplorationTransport? transport,
    required GitHubReadClient? foreignClient,
  }) {
    configs.add(config);
    this.cursors.add(cursors);
    emits.add(emit);
    transports.add(transport);
    final runtime = _RecordingRuntime(client: client);
    runtimes.add(runtime);
    return runtime;
  }
}

final class _BdRunner implements BdRunner {
  _BdRunner({this.filed});

  /// The bead the approval preflight reads back, or null for "not found".
  final Map<String, Object?>? filed;
  final argvs = <List<String>>[];

  List<List<String>> verb(String name) =>
      argvs.where((argv) => argv.first == name).toList();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    final Object data = switch (args.first) {
      'list' || 'dep' => <Object?>[],
      'query' => filed == null ? <Object?>[] : <Object?>[filed],
      _ => <String, Object?>{'id': 'pow-intake'},
    };
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode(<String, Object?>{'schema_version': 1, 'data': data}),
      stderr: '',
    );
  }
}

/// The seat's own nightly rule.
WorkflowRunIntakeRule _nightlyRule() => WorkflowRunIntakeRule(
  workflowPath: '.github/workflows/ci.yaml',
  validationPlan: 'dart test',
  events: const {'schedule'},
);

/// One concluded run of [repository], matching [_nightlyRule] by default.
NormalizedGitHubEvent _runEvent({
  String repository = 'memento/power_station',
}) => NormalizedGitHubEvent.workflowRunConcluded(
  nodeId: 'WFR_1',
  actor: repository,
  repository: repository,
  substation: 'seat',
  observationId: 'poll:run:WFR_1:2026-09-07T06:11:00Z:failure',
  runId: 9001,
  runNumber: 128,
  workflowPath: '.github/workflows/ci.yaml',
  workflowName: 'CI',
  event: 'schedule',
  headBranch: 'main',
  headSha: 'abcdef0',
  conclusion: 'failure',
  htmlUrl: 'https://github.test/memento/power_station/actions/runs/9001',
  failedJobs: const [
    WorkflowRunFailedJob(jobName: 'test', failedStepName: 'dart test'),
  ],
);

/// The bead the seat's approval preflight reads back for a sound filing.
const _filedBug = <String, Object?>{
  'id': 'pow-intake',
  'title': 'a red nightly',
  'description': 'The nightly failed.',
  'acceptance_criteria': '- [ ] AC-1 — CI is green; falsifier: `dart test`',
  'issue_type': 'bug',
  'priority': 1,
  'metadata': <String, Object?>{'validation_plan': 'dart test'},
};

/// The seat's grid STATE store, in PROXIED-SERVER mode: it answers the
/// type-scoped session list and REFUSES `export`, exactly as every org store
/// and lunar's own state store do.
final class _StateBdRunner implements BdRunner {
  _StateBdRunner(this.sessions);

  /// The enveloped payload this fake returns for `bd list -t session --all`.
  String sessions;
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    return switch (args.first) {
      'export' => const BdResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Error: export is not supported in proxied-server mode',
      ),
      'list' => BdResult(exitCode: 0, stdout: sessions, stderr: ''),
      _ => const BdResult(exitCode: 0, stdout: '{}', stderr: ''),
    };
  }
}

final class _RecordingFeedbackSender implements FeedbackCommandSender {
  final calls = <Map<String, String>>[];

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
      'idempotencyKey': idempotencyKey,
    });
    return const FeedbackCommandCompleted({});
  }
}

/// One enveloped `bd list -t session --all --json` payload holding one session
/// bead per work-bead key.
String _sessionLedger(List<String> workBeads) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (var i = 0; i < workBeads.length; i++)
      {
        'id': 'grid_state-session-$i',
        'issue_type': 'session',
        'metadata': {'work_bead': workBeads[i]},
      },
  ],
});

/// A transport serving one open self-authored issue, one pull request stating
/// [bead] in a `Refs:` trailer, its full resource, and one completed check with
/// [conclusion].
///
/// [bead] and [branch] are INPUTS: every armed substation — org and private —
/// opens pulls through this same seat shape, and the branch takes no part in
/// any decision, so a private seat differs from the org one only in the bead
/// its body states.
final class _SeatTransport implements GitHubHttpTransport {
  _SeatTransport(this.conclusion, {this.bead = 'pow-test'})
    : branch = 'grid/$bead';

  final String conclusion;
  final String bead;
  final String branch;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    final path = request.uri.path;
    if (path.endsWith('/issues')) {
      return GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode([
          {
            'node_id': 'I_1',
            'updated_at': '2026-08-23T00:00:00Z',
            'state': 'open',
            'number': 42,
            'title': 'Issue title',
            'body': 'Issue body',
            'user': {'login': 'nico'},
          },
        ]),
      );
    }
    if (path.endsWith('/pulls')) {
      return GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode([
          {
            'node_id': 'pr',
            'number': 8,
            'body': 'A human digest.\n\nRefs: $bead\n',
            'user': {'login': 'nico'},
            'created_at': '2026-08-23T00:00:00Z',
            'updated_at': '2026-08-23T00:00:00Z',
            'head': {'ref': branch, 'sha': 'abc'},
          },
        ]),
      );
    }
    // The FULL resource, the only place `mergeable` lives.
    if (path.contains('/pulls/')) {
      return GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode({'mergeable': true}),
      );
    }
    return GitHubHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'check_runs': [
          {
            'node_id': 'check',
            'status': 'completed',
            'conclusion': conclusion,
            'completed_at': '2026-08-23T00:00:00Z',
            'name': 'build',
            'app': {'slug': 'actions'},
          },
        ],
      }),
    );
  }
}

/// Builds a REAL reconciler over the tree-provided cursors and sink. It polls
/// when — and only when — the station's registered query is asked to repair.
final class _SeatFactory {
  final runtimes = <GitHubReconcilerRuntime>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    required ExplorationTransport? transport,
    required GitHubReadClient? foreignClient,
  }) {
    final runtime = GitHubReconcilerRuntime(
      installationId: config.installationId,
      reconciler: GitHubReconciler(
        owner: config.owner,
        repository: config.repository,
        substation: config.substation,
        client: client,
        cursors: cursors,
        emit: emit,
      ),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );
    runtimes.add(runtime);
    return runtime;
  }
}

int _verbCount(_StateBdRunner bd, String verb) =>
    bd.argvs.where((argv) => argv.first == verb).length;

/// Every argv this runner saw whose verb is [verb].
List<List<String>> _verbs(_StateBdRunner bd, String verb) =>
    bd.argvs.where((argv) => argv.first == verb).toList();

/// The landing-ready mutations [bd] received, whichever bead they name.
List<List<String>> _landingMarks(_BdRunner bd) => bd.argvs
    .where(
      (argv) =>
          argv.first == 'update' && argv.contains('grid.landing_ready=true'),
    )
    .toList();

/// An appender that is neither fenced out nor halted and appends nothing.
///
/// The github obligation repairs GITHUB, never the log — a pass carrying it
/// stays quiet — so an append reaching here is a contract break, not a fixture
/// gap.
final class _TickAppender implements traj.TickAppender {
  @override
  bool get isInert => false;

  @override
  bool get isHalted => false;

  @override
  Future<traj.AppendOutcome> append(
    traj.TrajectoryRecord record, {
    String? substation,
    traj.TrajectoryProvenance provenance = traj.TrajectoryProvenance.observed,
    String? provenanceBasis,
    DateTime? occurredAt,
  }) async => throw StateError('the github obligation appends nothing');

  @override
  Future<void> doltCommitIfDue() async {}
}

/// Answers the obligation's standing `SELECT 1` with its one constant row.
final class _TickDb implements traj.TrajectoryDb {
  @override
  Future<traj.SqlResult> execute(
    String sql, [
    Map<String, dynamic>? params,
  ]) async => const traj.SqlResult(
    rows: <Map<String, String?>>[
      <String, String?>{'github_reconciliation_due': '1'},
    ],
  );

  @override
  Future<void> close() async {}
}

/// One REFUSING pass against the github obligation — the shape the tick
/// recorded every 30 s while the landing mark threw.
traj.TrajectoryTickPass _refusingPass() => traj.TrajectoryTickPass(
  startedAt: DateTime.utc(2026, 9, 14),
  disposition: traj.TickPassDisposition.ran,
  queriesRun: 1,
  refusals: const <traj.TickRefusal>[
    traj.TickRefusal(
      kind: traj.TickRefusalKind.queryFailed,
      query: 'github-reconciliation',
      reason:
          'Bad state: landing-ready mutation failed: Error resolving '
          'pow-5ljz: get pow-5ljz: sql: no rows in result set',
    ),
  ],
);

/// An accountant already streaking at one short of its flare threshold — the
/// station state a stuck seat leaves behind.
StuckObligationAccountant _streakingAccountant() {
  final accountant = StuckObligationAccountant(
    recorder: StationTrajectoryRecorder.disabled(),
    station: 'tranquility',
  );
  for (var pass = 0; pass < 4; pass++) {
    accountant.observe(_refusingPass());
  }
  return accountant;
}

/// The FULL seat stack: binding -> GitHubReconcilerAssets -> GitHubGridAssets.
///
/// [gridRoot] null mounts no `GridRoot` (the offline posture). [stateBd] null
/// keeps the production `stateRunnerFor`, so a test can assert the derived
/// state-store root.
Seed _seatTree({
  required sdk.SubstationScope scope,
  required GitHubReconcilerConfig config,
  required BdRunner runner,
  required GitHubReconcilerRuntimeFactory runtimeFactory,
  required void Function(CiFeedbackProjection?, GitHubEventSink?) observe,
  GitHubReconciliationQuery? query,
  String? gridRoot,
  GitHubAppClient? client,
  _StateBdRunner? stateBd,
  FeedbackCommandSender? sender,
  void Function()? stateRunnerCount,
}) {
  final inner = GitHubReconcilerAssets(
    config: config,
    runtimeFactory: runtimeFactory,
    child: GitHubGridAssets(
      child: _Probe((context) {
        observe(
          context.watch<CiFeedbackProjection>(),
          context.watch<GitHubEventSink>(),
        );
      }),
    ),
  );
  final trust = GitHubSelfTrust(githubUser: 'nico');
  final binding = stateBd == null
      ? GitHubReconcilerBindingAssets(
          config: config,
          runner: runner,
          trust: trust,
          feedbackCommandSender: sender,
          child: inner,
        )
      : GitHubReconcilerBindingAssets(
          config: config,
          runner: runner,
          trust: trust,
          feedbackCommandSender: sender,
          stateRunnerFor: (_) {
            stateRunnerCount?.call();
            return stateBd;
          },
          child: inner,
        );
  final Seed seat = Provider<sdk.SubstationScope>.value(
    scope,
    child: Provider<GitHubAppClient>.value(client ?? _client, child: binding),
  );
  return sdk.ProviderScope(
    child: _registeredUnder(
      query,
      child: gridRoot == null
          ? seat
          : Provider<sdk.GridRoot>.value(
              sdk.GridRoot(path: gridRoot),
              child: seat,
            ),
    ),
  );
}

/// The station rung every live seat composes under: a [sdk.TrajectoryConfig]
/// registering [query] — a fresh one when the probe does not name it, since a
/// probe that never asks the query to repair only needs the registration to
/// EXIST.
Seed _registeredUnder(
  GitHubReconciliationQuery? query, {
  required Seed child,
}) => InheritedSeed<sdk.TrajectoryConfig>(
  value: sdk.TrajectoryConfig(
    obligationQueryExtensions: <ObligationQuery>[
      query ?? GitHubReconciliationQuery(),
    ],
  ),
  child: child,
);

final _appConfig = GitHubAppConfig(
  appId: 'app',
  installationId: 1,
  apiBaseUri: Uri.parse('https://api.github.test'),
);

final _client = GitHubAppClient(
  config: _appConfig,
  tokens: _Tokens(),
  transport: _Transport(),
);

GitHubReconcilerConfig _config({
  required String owner,
  required String repository,
  GitHubReconcilerArm arm = GitHubReconcilerArm.live,
  List<WorkflowRunIntakeRule> workflowRuns = const <WorkflowRunIntakeRule>[],
}) => GitHubReconcilerConfig(
  owner: owner,
  repository: repository,
  substation: 'seat',
  installationId: 'installation',
  arm: arm,
  workflowRuns: workflowRuns,
);

Seed _boundTree({
  required sdk.SubstationScope scope,
  required GitHubReconcilerConfig config,
  required BdRunner runner,
  required GitHubReconcilerRuntimeFactory runtimeFactory,
  required void Function(
    GitHubCursorStore?,
    GitHubEventSink?,
    GitHubReconcilerRuntime?,
  )
  observe,
}) => sdk.ProviderScope(
  child: _registeredUnder(
    null,
    child: Provider<sdk.SubstationScope>.value(
      scope,
      child: Provider<GitHubAppClient>.value(
        _client,
        child: GitHubReconcilerBindingAssets(
          config: config,
          runner: runner,
          trust: GitHubSelfTrust(githubUser: 'nico'),
          child: GitHubReconcilerAssets(
            config: config,
            runtimeFactory: runtimeFactory,
            child: _Probe((context) {
              observe(
                context.watch<GitHubCursorStore>(),
                context.watch<GitHubEventSink>(),
                context.watch<GitHubReconcilerRuntime>(),
              );
            }),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('the sink self-approves the seat\'s OWN workflow failure', () async {
    final runner = _BdRunner(filed: _filedBug);
    GitHubEventSink? sink;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _boundTree(
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(
          owner: 'memento',
          repository: 'power_station',
          workflowRuns: [_nightlyRule()],
        ),
        runner: runner,
        runtimeFactory: _Factory().create,
        observe: (_, value, __) => sink = value,
      ),
    );
    owner.flush();

    await sink!(_runEvent());

    expect(
      runner.verb('create').single,
      containsAllInOrder([
        'create',
        '--type',
        'bug',
        '--priority',
        '1',
        '--external-ref',
        'github:WFR_1',
      ]),
    );
    final updates = runner.verb('update');
    expect(updates, hasLength(2));
    expect(
      updates.first,
      containsAllInOrder([
        'update',
        'pow-intake',
        '--acceptance',
        '--set-metadata',
        'github.workflow_path=.github/workflows/ci.yaml',
      ]),
    );
    expect(
      updates.last,
      containsAllInOrder([
        '--actor',
        'github-workflow',
        '--set-metadata',
        'grid.approved_by=github-workflow',
      ]),
      reason: 'the approve verb rides the SEAT runner, opening no bd channel',
    );
  });

  test('a fork run of another repository is never filed', () async {
    final runner = _BdRunner(filed: _filedBug);
    GitHubEventSink? sink;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _boundTree(
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(
          owner: 'memento',
          repository: 'power_station',
          workflowRuns: [_nightlyRule()],
        ),
        runner: runner,
        runtimeFactory: _Factory().create,
        observe: (_, value, __) => sink = value,
      ),
    );
    owner.flush();

    await sink!(_runEvent(repository: 'forker/power_station'));

    expect(runner.argvs, isEmpty);
  });

  test('a seat declaring no rule files no workflow run at all', () async {
    final runner = _BdRunner(filed: _filedBug);
    GitHubEventSink? sink;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _boundTree(
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(owner: 'memento', repository: 'power_station'),
        runner: runner,
        runtimeFactory: _Factory().create,
        observe: (_, value, __) => sink = value,
      ),
    );
    owner.flush();

    await sink!(_runEvent());

    expect(runner.argvs, isEmpty);
  });

  test('the state runner is built once and shared with approval', () {
    var built = 0;
    final stateBd = _StateBdRunner(_sessionLedger(const []));
    CiFeedbackProjection? projection;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _seatTree(
        gridRoot: '/grid',
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(
          owner: 'memento',
          repository: 'power_station',
          workflowRuns: [_nightlyRule()],
        ),
        runner: _BdRunner(),
        runtimeFactory: _Factory().create,
        stateBd: stateBd,
        stateRunnerCount: () => built++,
        observe: (value, _) => projection = value,
      ),
    );
    owner.flush();

    expect(built, 1, reason: 'approval reuses the feedback state runner');
    expect(projection!.bd, same(stateBd));
  });

  test('live binding provides both seams and constructs the runtime', () {
    final factory = _Factory();
    GitHubCursorStore? cursors;
    GitHubEventSink? sink;
    GitHubReconcilerRuntime? runtime;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _boundTree(
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(owner: 'memento', repository: 'power_station'),
        runner: _BdRunner(),
        runtimeFactory: factory.create,
        observe: (c, s, r) {
          cursors = c;
          sink = s;
          runtime = r;
        },
      ),
    );
    owner.flush();

    expect(cursors, isA<FileGitHubCursorStore>());
    expect(sink, isNotNull);
    expect(factory.configs, hasLength(1));
    expect(factory.cursors.single, same(cursors));
    expect(factory.emits.single, same(sink));
    expect(factory.transports.single, isNull);
    expect(runtime, same(factory.runtimes.single));
  });

  test('inert arms provide nothing and construct no runtime', () {
    for (final arm in [GitHubReconcilerArm.dry, GitHubReconcilerArm.offline]) {
      final config = _config(owner: 'o', repository: 'r', arm: arm);
      final factory = _Factory();
      final runner = _BdRunner();
      GitHubCursorStore? cursors;
      GitHubEventSink? sink;
      GitHubReconcilerRuntime? runtime;
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _registeredUnder(
            null,
            child: Provider<GitHubAppClient>.value(
              _client,
              child: GitHubReconcilerBindingAssets(
                config: config,
                runner: runner,
                trust: GitHubSelfTrust(githubUser: 'nico'),
                child: GitHubReconcilerAssets(
                  config: config,
                  runtimeFactory: factory.create,
                  child: _Probe((context) {
                    cursors = context.watch<GitHubCursorStore>();
                    sink = context.watch<GitHubEventSink>();
                    runtime = context.watch<GitHubReconcilerRuntime>();
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      expect(cursors, isNull);
      expect(sink, isNull);
      expect(runtime, isNull);
      expect(factory.configs, isEmpty);
      expect(runner.argvs, isEmpty);
      owner.dispose();
    }
  });

  test('cursor path is per scope root and repository', () {
    final paths = <String>[];
    for (final seat in [
      (root: '/work/one', owner: 'memento', repository: 'power_station'),
      (root: '/work/two', owner: 'nico', repository: 'lunar_station'),
    ]) {
      final owner = TreeOwner();
      owner.mountRoot(
        _boundTree(
          scope: sdk.SubstationScope(
            name: seat.repository,
            root: seat.root,
            prefix: 'pow',
          ),
          config: _config(owner: seat.owner, repository: seat.repository),
          runner: _BdRunner(),
          runtimeFactory: _Factory().create,
          observe: (cursors, _, __) {
            paths.add((cursors! as FileGitHubCursorStore).cursorPath);
          },
        ),
      );
      owner.flush();
      owner.dispose();
    }
    expect(paths, [
      '/work/one/.grid/github/memento-power_station.cursor.json',
      '/work/two/.grid/github/nico-lunar_station.cursor.json',
    ]);
    expect(paths.toSet(), hasLength(2));
  });

  test('sink admits only self actors as OPEN intake', () async {
    final runner = _BdRunner();
    GitHubEventSink? sink;
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _boundTree(
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(owner: 'memento', repository: 'power_station'),
        runner: runner,
        runtimeFactory: _Factory().create,
        observe: (_, value, __) => sink = value,
      ),
    );
    owner.flush();

    await sink!(
      const NormalizedGitHubEvent.issueOpened(
        nodeId: 'I_1',
        actor: 'nico',
        repository: 'memento/power_station',
        substation: 'seat',
        observationId: 'obs-1',
        number: 42,
        title: 'Issue title',
        body: 'Issue body',
      ),
    );
    expect(runner.argvs, hasLength(3));
    expect(
      runner.argvs[1],
      containsAllInOrder([
        'create',
        '--type',
        'chore',
        '--priority',
        '2',
        '--external-ref',
        'github:I_1',
      ]),
    );
    expect(runner.argvs[1], isNot(contains('--defer')));
    expect(
      runner.argvs[2],
      containsAllInOrder(['update', '--set-metadata', 'github.node_id=I_1']),
    );

    runner.argvs.clear();
    await sink!(
      const NormalizedGitHubEvent.issueOpened(
        nodeId: 'I_2',
        actor: 'somebody-else',
        repository: 'memento/power_station',
        substation: 'seat',
        observationId: 'obs-2',
        number: 43,
        title: 'External issue',
        body: '',
      ),
    );
    expect(runner.argvs, isEmpty);
  });

  test('a live seat provides a state-store feedback projection', () {
    CiFeedbackProjection? projection;
    GitHubEventSink? sink;
    final runner = _BdRunner();
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      _seatTree(
        gridRoot: '/grid',
        scope: const sdk.SubstationScope(
          name: 'seat',
          root: '/work/seat',
          prefix: 'pow',
        ),
        config: _config(owner: 'memento', repository: 'power_station'),
        runner: runner,
        runtimeFactory: _Factory().create,
        observe: (value, seam) {
          projection = value;
          sink = seam;
        },
      ),
    );
    owner.flush();

    expect(sink, isNotNull);
    final value = projection;
    expect(value, isNotNull);
    expect(value!.gridRoot, '/grid');
    expect(value.substation, 'seat', reason: 'derived from the scope name');
    expect((value.bd as ProcessBdRunner).workspaceRoot, '/grid/.grid');
    expect(
      value.workBd,
      same(runner),
      reason: 'the WORK rail is the seat runner, never a second bd channel',
    );
    expect(
      value.scope,
      const sdk.SubstationScope(
        name: 'seat',
        root: '/work/seat',
        prefix: 'pow',
      ),
    );
    expect(value.commandSender, isA<ResidentFeedbackCommandSender>());
  });

  test(
    'no grid root provides no projection and leaves intake working',
    () async {
      CiFeedbackProjection? projection;
      GitHubEventSink? sink;
      final runner = _BdRunner();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _seatTree(
          scope: const sdk.SubstationScope(
            name: 'seat',
            root: '/work/seat',
            prefix: 'pow',
          ),
          config: _config(owner: 'memento', repository: 'power_station'),
          runner: runner,
          runtimeFactory: _Factory().create,
          observe: (value, seam) {
            projection = value;
            sink = seam;
          },
        ),
      );
      owner.flush();

      expect(projection, isNull);
      expect(sink, isNotNull);
      await sink!(
        const NormalizedGitHubEvent.issueOpened(
          nodeId: 'I_1',
          actor: 'nico',
          repository: 'memento/power_station',
          substation: 'seat',
          observationId: 'obs-1',
          number: 42,
          title: 'Issue title',
          body: 'Issue body',
        ),
      );
      expect(
        runner.argvs.firstWhere((argv) => argv.first == 'create'),
        containsAllInOrder(['--external-ref', 'github:I_1']),
      );
    },
  );

  test('an inert arm provides no projection even under a grid root', () {
    for (final arm in [GitHubReconcilerArm.dry, GitHubReconcilerArm.offline]) {
      CiFeedbackProjection? projection;
      final owner = TreeOwner();
      owner.mountRoot(
        _seatTree(
          gridRoot: '/grid',
          scope: const sdk.SubstationScope(
            name: 'seat',
            root: '/work/seat',
            prefix: 'pow',
          ),
          config: _config(owner: 'o', repository: 'r', arm: arm),
          runner: _BdRunner(),
          runtimeFactory: _Factory().create,
          observe: (value, _) => projection = value,
        ),
      );
      owner.flush();
      expect(projection, isNull, reason: 'arm $arm must stay inert');
      owner.dispose();
    }
  });

  for (final seat in <({String substation, String bead, String prefix})>[
    // PRIVATE substations first: the defect was reported as theirs, and it
    // never was — their only difference from the org seat is the prefix
    // their store mints.
    (
      substation: 'butane_flutter',
      bead: 'butane_flutter-wmgt',
      prefix: 'butane_flutter',
    ),
    (substation: 'swift-infer', bead: 'swift-infer-097', prefix: 'swift-infer'),
    (
      substation: 'radioactive_dart',
      bead: 'radioactive_dart-097',
      prefix: 'radioactive_dart',
    ),
    (substation: 'power_station', bead: 'pow-test', prefix: 'pow'),
  ]) {
    test('a green check marks ${seat.bead} landing-ready in its OWN '
        'store', () async {
      final temporary = await Directory.systemTemp.createTemp('gh-seat-');
      addTearDown(() => temporary.delete(recursive: true));
      final stateBd = _StateBdRunner(_sessionLedger(<String>[seat.bead]));
      final workBd = _BdRunner();
      final sender = _RecordingFeedbackSender();
      final factory = _SeatFactory();
      final query = GitHubReconciliationQuery();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _seatTree(
          query: query,
          gridRoot: temporary.path,
          scope: sdk.SubstationScope(
            name: seat.substation,
            root: temporary.path,
            prefix: seat.prefix,
          ),
          config: _config(owner: 'memento', repository: 'power_station'),
          runner: workBd,
          stateBd: stateBd,
          sender: sender,
          client: GitHubAppClient(
            config: _appConfig,
            tokens: _Tokens(),
            transport: _SeatTransport('success', bead: seat.bead),
          ),
          runtimeFactory: factory.create,
          observe: (_, __) {},
        ),
      );
      owner.flush();
      expect(query.attached, <GitHubReconcilerRuntime>[
        factory.runtimes.single,
      ]);

      // THE STATION'S OWN PASS, over the real tick: the obligation runs, the
      // seat reconciles, and the accountant that was four refusals deep reads
      // the result.
      final accountant = _streakingAccountant();
      expect(accountant.streaks['github-reconciliation'], 4);
      final tick = traj.TrajectoryTick(
        appender: _TickAppender(),
        db: _TickDb(),
        queries: <ObligationQuery>[query],
        onPass: accountant.observe,
      );
      addTearDown(tick.dispose);
      final pass = await tick.runPass();

      expect(pass.ran, isTrue);
      expect(
        pass.queriesRun,
        1,
        reason: 'the obligation RAN — an empty refusal list is not a skip',
      );
      expect(pass.refusals, isEmpty, reason: 'the obligation no longer wedges');
      expect(
        accountant.streaks,
        isEmpty,
        reason: 'a clean pass resets the streak to 0',
      );

      // The mark landed in the SCOPED WORK store, exactly once...
      expect(_landingMarks(workBd).single, <String>[
        'update',
        seat.bead,
        '--actor',
        'github-feedback',
        '--set-metadata',
        'grid.landing_ready=true',
      ]);
      // ...the state store answered reads and nothing else...
      expect(
        stateBd.argvs.map((argv) => argv.first),
        everyElement('list'),
        reason: 'no work-bead mutation reaches the grid state store',
      );
      // ...neither store was asked to CLOSE the bead (the governor's manual
      // bridge is not what this leg does)...
      expect(stateBd.argvs.map((argv) => argv.first), isNot(contains('close')));
      expect(workBd.argvs.map((argv) => argv.first), isNot(contains('close')));
      expect(sender.calls, isEmpty, reason: 'a green check reworks nothing');
      // ...and the issue poll BEHIND the feedback still reached intake.
      expect(
        workBd.argvs.where((argv) => argv.first == 'create'),
        hasLength(1),
      );
      expect(
        workBd.argvs.firstWhere((argv) => argv.first == 'create'),
        containsAllInOrder(<String>['--external-ref', 'github:I_1']),
      );
    });
  }

  for (final seat in [
    (
      name: 'a red check on a grid branch reworks its bead exactly once',
      conclusion: 'failure',
      ledger: ['pow-test'],
      reworks: 1,
      gates: 0,
    ),
    (
      name: 'a red check at the rework cap gates instead of reworking',
      conclusion: 'failure',
      ledger: ['pow-test', 'pow-test#r3'],
      reworks: 0,
      gates: 1,
    ),
  ]) {
    test(seat.name, () async {
      final temporary = await Directory.systemTemp.createTemp('gh-seat-');
      addTearDown(() => temporary.delete(recursive: true));
      final stateBd = _StateBdRunner(_sessionLedger(seat.ledger));
      final workBd = _BdRunner();
      final sender = _RecordingFeedbackSender();
      final factory = _SeatFactory();
      final query = GitHubReconciliationQuery();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _seatTree(
          query: query,
          gridRoot: temporary.path,
          scope: sdk.SubstationScope(
            name: 'seat',
            root: temporary.path,
            prefix: 'pow',
          ),
          config: _config(owner: 'memento', repository: 'power_station'),
          runner: workBd,
          stateBd: stateBd,
          sender: sender,
          client: GitHubAppClient(
            config: _appConfig,
            tokens: _Tokens(),
            transport: _SeatTransport(seat.conclusion),
          ),
          runtimeFactory: factory.create,
          observe: (_, __) {},
        ),
      );
      owner.flush();

      // THE STATION'S PASS, made explicit: mounting armed nothing, and this
      // is the one call that makes the seat reconcile.
      expect(query.attached, <GitHubReconcilerRuntime>[
        factory.runtimes.single,
      ]);
      expect(
        sender.calls.length +
            _verbCount(stateBd, 'update') +
            _verbCount(stateBd, 'create'),
        0,
        reason: 'a mounted seat produces no CI feedback until the tick runs',
      );
      await query.repair(const <Map<String, String?>>[]);

      expect(sender.calls, hasLength(seat.reworks));
      expect(_verbCount(stateBd, 'create'), seat.gates);
      // The CAP GATE is a state-store bead and stays one; the landing mark is
      // the only rail that moved.
      expect(_verbCount(stateBd, 'update'), 0);
      expect(_landingMarks(workBd), isEmpty);
      if (seat.reworks == 1) {
        expect(sender.calls.single['beadId'], 'pow-test');
        expect(sender.calls.single['gridRoot'], temporary.path);
      }
      if (seat.gates == 1) {
        expect(
          _verbs(stateBd, 'create').single,
          containsAllInOrder(<String>[
            '--id',
            'pow-test-ci-rework-cap',
            '--type',
            'gate',
          ]),
        );
      }
      // Intake is unchanged: the check produced no work-store bead, and the
      // open issue still projected exactly one deferred bead.
      expect(
        workBd.argvs.where((argv) => argv.first == 'create'),
        hasLength(1),
      );
      expect(
        workBd.argvs.firstWhere((argv) => argv.first == 'create'),
        containsAllInOrder(<String>['--external-ref', 'github:I_1']),
      );
    });
  }

  group('the watch projection', () {
    /// Mounts a live seat and hands back the projection value it provides.
    GitHubIssueWatchProjection? mount(
      BdRunner runner, {
      GitHubReconcilerArm arm = GitHubReconcilerArm.live,
    }) {
      GitHubIssueWatchProjection? projection;
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        sdk.ProviderScope(
          child: Provider<sdk.SubstationScope>.value(
            const sdk.SubstationScope(
              name: 'seat',
              root: '/work/seat',
              prefix: 'pow',
            ),
            child: Provider<GitHubAppClient>.value(
              _client,
              child: GitHubReconcilerBindingAssets(
                config: _config(
                  owner: 'memento',
                  repository: 'power_station',
                  arm: arm,
                ),
                runner: runner,
                trust: GitHubSelfTrust(githubUser: 'nico'),
                child: _Probe((context) {
                  projection = context.watch<GitHubIssueWatchProjection>();
                }),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      return projection;
    }

    test('a live seat provides one, sharing the seat runner', () async {
      final runner = _BdRunner();
      final projection = mount(runner);
      expect(projection, isNotNull);

      await projection!(
        NormalizedGitHubEvent.issueCommented(
          nodeId: 'IC_first',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: 'seat',
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

      expect(runner.argvs, hasLength(1));
      expect(
        runner.argvs.single.take(2).toList(),
        <String>['update', 'lunar_station-6p9'],
        reason: 'ONE bd channel — the seat runner both projections share',
      );
    });

    test('both projections resolve the SAME notion of self', () async {
      final runner = _BdRunner();
      final projection = mount(runner)!;

      // The seat's admitted human login is SELF for a watch, exactly as it is
      // for intake; an unrelated login is not.
      await projection(
        NormalizedGitHubEvent.issueCommented(
          nodeId: 'IC_other',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: 'seat',
          observationId: 'poll:issue-comment:IC_other',
          originatingBeadId: 'lunar_station-6p9',
          issueNodeId: 'I_kwDO',
          issueAuthor: 'someone-else',
          issueNumber: 1,
          commentId: 12,
          body: 'Not ours.',
          url: 'https://github.test/1',
          updatedAt: DateTime.utc(2026, 9, 9, 11),
        ),
      );

      expect(runner.argvs, isEmpty);
    });

    test('an inert arm provides no watch projection', () {
      for (final arm in const <GitHubReconcilerArm>[
        GitHubReconcilerArm.dry,
        GitHubReconcilerArm.offline,
      ]) {
        expect(mount(_BdRunner(), arm: arm), isNull);
      }
    });
  });
}
