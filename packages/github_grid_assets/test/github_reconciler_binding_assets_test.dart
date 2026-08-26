import 'dart:convert';

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

  test('sink admits only self actors as deferred intake', () async {
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
    expect(runner.argvs, hasLength(2));
    expect(
      runner.argvs.last,
      containsAllInOrder([
        'create',
        '--type',
        'chore',
        '--defer',
        '9999-12-31',
        '--external-ref',
        'github:I_1',
      ]),
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
}
