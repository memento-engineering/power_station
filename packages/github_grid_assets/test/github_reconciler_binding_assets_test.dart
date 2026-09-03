import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show Provider;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
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
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    final data = args.first == 'list'
        ? <Object?>[]
        : <String, Object?>{'id': 'pow-intake'};
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode(<String, Object?>{'schema_version': 1, 'data': data}),
      stderr: '',
    );
  }
}

final class _StateBdRunner implements BdRunner {
  _StateBdRunner(this.export);

  /// The payload this fake returns for `bd export --all`.
  String export;
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    return args.first == 'export'
        ? BdResult(exitCode: 0, stdout: export, stderr: '')
        : const BdResult(exitCode: 0, stdout: '{}', stderr: '');
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

/// One `bd export --all` payload holding one session bead per work-bead key.
String _sessionLedger(List<String> workBeads) => jsonEncode([
  for (var i = 0; i < workBeads.length; i++)
    {
      'id': 'grid_state-session-$i',
      'issue_type': 'session',
      'metadata': {'work_bead': workBeads[i]},
    },
]);

/// A transport serving one open self-authored issue, one `grid/pow-test` pull,
/// and one completed check with [conclusion].
final class _SeatTransport implements GitHubHttpTransport {
  _SeatTransport(this.conclusion);

  final String conclusion;

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
            'head': {'ref': 'grid/pow-test', 'sha': 'abc'},
          },
        ]),
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

/// Builds a REAL reconciler over the tree-provided cursors and sink, polling
/// once on `start()` and then not again inside a test's lifetime.
final class _SeatFactory {
  final runtimes = <GitHubReconcilerRuntime>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    required ExplorationTransport? transport,
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
      interval: const Duration(hours: 1),
    );
    runtimes.add(runtime);
    return runtime;
  }
}

Future<void> _waitFor(bool Function() ready, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(description);
}

int _verbCount(_StateBdRunner bd, String verb) =>
    bd.argvs.where((argv) => argv.first == verb).length;

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
  String? gridRoot,
  GitHubAppClient? client,
  _StateBdRunner? stateBd,
  FeedbackCommandSender? sender,
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
          stateRunnerFor: (_) => stateBd,
          child: inner,
        );
  final Seed seat = Provider<sdk.SubstationScope>.value(
    scope,
    child: Provider<GitHubAppClient>.value(
      client ?? _client,
      child: binding,
    ),
  );
  return sdk.ProviderScope(
    child: gridRoot == null
        ? seat
        : Provider<sdk.GridRoot>.value(
            sdk.GridRoot(path: gridRoot),
            child: seat,
          ),
  );
}

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
}) => GitHubReconcilerConfig(
  owner: owner,
  repository: repository,
  substation: 'seat',
  installationId: 'installation',
  arm: arm,
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
);

void main() {
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
        runner: _BdRunner(),
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
    expect(value.substation, 'seat');
    expect((value.bd as ProcessBdRunner).workspaceRoot, '/grid/.grid');
    expect(value.commandSender, isA<ResidentFeedbackCommandSender>());
  });

  test('no grid root provides no projection and leaves intake working', () async {
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
  });

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

  for (final seat in [
    (
      name: 'a red check on a grid branch reworks its bead exactly once',
      conclusion: 'failure',
      ledger: ['pow-test'],
      reworks: 1,
      landingReady: 0,
      gates: 0,
    ),
    (
      name: 'a green check marks landing-ready and reworks nothing',
      conclusion: 'success',
      ledger: ['pow-test'],
      reworks: 0,
      landingReady: 1,
      gates: 0,
    ),
    (
      name: 'a red check at the rework cap gates instead of reworking',
      conclusion: 'failure',
      ledger: ['pow-test', 'pow-test#r3'],
      reworks: 0,
      landingReady: 0,
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
      final owner = TreeOwner();
      addTearDown(() => factory.runtimes.single.stop());
      addTearDown(owner.dispose);
      owner.mountRoot(
        _seatTree(
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

      await _waitFor(
        () =>
            sender.calls.length +
                _verbCount(stateBd, 'update') +
                _verbCount(stateBd, 'create') ==
            1,
        'the armed seat produced no CI feedback effect for '
        '${seat.conclusion}',
      );

      expect(sender.calls, hasLength(seat.reworks));
      expect(_verbCount(stateBd, 'update'), seat.landingReady);
      expect(_verbCount(stateBd, 'create'), seat.gates);
      if (seat.reworks == 1) {
        expect(sender.calls.single['beadId'], 'pow-test');
        expect(sender.calls.single['gridRoot'], temporary.path);
      }
      if (seat.landingReady == 1) {
        expect(
          stateBd.argvs.firstWhere((argv) => argv.first == 'update'),
          containsAllInOrder([
            'pow-test',
            '--set-metadata',
            'grid.landing_ready=true',
          ]),
        );
      }
      if (seat.gates == 1) {
        expect(
          stateBd.argvs.firstWhere((argv) => argv.first == 'create'),
          containsAllInOrder([
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
        containsAllInOrder(['--external-ref', 'github:I_1']),
      );
    });
  }
}
