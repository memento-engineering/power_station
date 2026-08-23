import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
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

class _Host extends StatefulSeed {
  const _Host({required this.onCreate, required this.describe});

  final void Function(_HostState) onCreate;
  final Seed Function() describe;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Seed Function()? _next;

  @override
  void initState() => seed.onCreate(this);

  void swap(Seed Function() describe) => setState(() => _next = describe);

  @override
  Seed build(TreeContext context) => (_next ?? seed.describe)();
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

final class _AmbientOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(const PullRequestRef(url: 'https://ambient'));
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

  var starts = 0;
  var stops = 0;
  var _running = false;

  @override
  void start() {
    if (_running) return;
    _running = true;
    starts++;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    stops++;
  }
}

final class _Factory {
  final configs = <GitHubReconcilerConfig>[];
  final runtimes = <_RecordingRuntime>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
  }) {
    configs.add(config);
    final runtime = _RecordingRuntime(client: client);
    runtimes.add(runtime);
    return runtime;
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

GitHubReconcilerConfig _config(
  String owner, {
  GitHubReconcilerArm arm = GitHubReconcilerArm.live,
}) => GitHubReconcilerConfig(
  owner: owner,
  repository: 'power_station',
  substation: 'power_station',
  installationId: 'installation',
  arm: arm,
);

Seed _runtimeTree({
  required GitHubReconcilerConfig? config,
  required _Factory factory,
  required void Function(GitHubReconcilerRuntime?) observe,
}) => Provider<GitHubAppClient>.value(
  _client,
  child: Provider<GitHubCursorStore>.value(
    _Cursors(),
    child: Provider<GitHubEventSink>.value(
      (_) async {},
      child: GitHubReconcilerAssets(
        config: config,
        runtimeFactory: factory.create,
        child: GitHubGridAssets(
          child: _Probe(
            (context) => observe(context.watch<GitHubReconcilerRuntime>()),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('live config constructs and starts at consumer', () async {
    final factory = _Factory();
    GitHubReconcilerRuntime? observed;
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _runtimeTree(
          config: _config('one'),
          factory: factory,
          observe: (runtime) => observed = runtime,
        ),
      ),
    );
    owner.flush();

    expect(factory.configs, hasLength(1));
    expect(observed, same(factory.runtimes.single));
    expect(factory.runtimes.single.starts, 1);

    owner.unmountRoot();
    await Future<void>.delayed(Duration.zero);
    expect(factory.runtimes.single.stops, 1);
  });

  test('disposal stops runtime once', () async {
    final factory = _Factory();
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _runtimeTree(
          config: _config('one'),
          factory: factory,
          observe: (_) {},
        ),
      ),
    );
    owner.flush();
    owner.unmountRoot();
    await Future<void>.delayed(Duration.zero);
    expect(factory.runtimes.single.starts, 1);
    expect(factory.runtimes.single.stops, 1);
  });

  test('inert arms construct nothing', () {
    for (final config in <GitHubReconcilerConfig?>[
      null,
      _config('one', arm: GitHubReconcilerArm.dry),
      _config('one', arm: GitHubReconcilerArm.offline),
    ]) {
      final factory = _Factory();
      GitHubReconcilerRuntime? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _runtimeTree(
            config: config,
            factory: factory,
            observe: (runtime) => observed = runtime,
          ),
        ),
      );
      owner.flush();
      expect(factory.configs, isEmpty);
      expect(observed, isNull);
      owner.unmountRoot();
    }
  });

  test('config replacement re-provides runtime', () async {
    final factory = _Factory();
    final observations = <GitHubReconcilerRuntime?>[];
    late _HostState host;
    Seed describe(GitHubReconcilerConfig config) => _runtimeTree(
      config: config,
      factory: factory,
      observe: observations.add,
    );
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(_config('one')),
        ),
      ),
    );
    owner.flush();
    final first = factory.runtimes.single;

    host.swap(() => describe(_config('two')));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();

    expect(factory.configs.map((value) => value.owner), ['one', 'two']);
    expect(observations.last, same(factory.runtimes.last));
    expect(factory.runtimes.last, isNot(same(first)));
    expect(first.stops, 1);
    expect(factory.runtimes.last.starts, 1);

    owner.unmountRoot();
    await Future<void>.delayed(Duration.zero);
    expect(factory.runtimes.last.stops, 1);
  });

  test('app opener provider', () {
    final ambient = _AmbientOpener();
    PrOpener? configured;
    PrOpener? unconfigured;

    void mount(GitHubAppConfig? config, void Function(PrOpener?) observe) {
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: Provider<GitHubAppClient>.value(
            _client,
            child: Provider<PrOpener>.value(
              ambient,
              child: GitHubPrOpenerAssets(
                config: config,
                owner: 'owner',
                repository: 'repository',
                child: _Probe((context) => observe(context.watch<PrOpener>())),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      owner.unmountRoot();
    }

    mount(_appConfig, (opener) => configured = opener);
    mount(null, (opener) => unconfigured = opener);
    expect(configured, isA<GitHubAppPrOpener>());
    expect(unconfigured, same(ambient));
  });

  test('provider preserves intake invariant', () {
    final source = File(
      'lib/src/assets/github_reconciler_assets.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Ready')));
    expect(source, isNot(contains('bd create')));
    expect(source, isNot(contains('FileSystemWatcher')));
    expect(source, isNot(contains('Timer')));
  });
}
