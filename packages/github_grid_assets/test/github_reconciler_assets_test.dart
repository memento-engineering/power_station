import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
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

final class _Flares implements ExplorationTransport {
  final first = Completer<({String name, Map<String, String> data})>();

  @override
  void flare(String name, Map<String, String> data) {
    if (!first.isCompleted) {
      first.complete((name: name, data: Map<String, String>.of(data)));
    }
  }
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
  final transports = <ExplorationTransport?>[];
  final runtimes = <_RecordingRuntime>[];
  final foreignClients = <GitHubReadClient?>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    required ExplorationTransport? transport,
    required GitHubReadClient? foreignClient,
  }) {
    configs.add(config);
    transports.add(transport);
    foreignClients.add(foreignClient);
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
  ExplorationTransport? transport,
  EnvironmentReader? environment,
  GitHubHttpTransportFactory? foreignTransportFactory,
}) => InheritedSeed<ServiceBundle>(
  value: ServiceBundle(transport: transport),
  child: Provider<GitHubAppClient>.value(
    _client,
    child: Provider<GitHubCursorStore>.value(
      _Cursors(),
      child: Provider<GitHubEventSink>.value(
        (_) async {},
        child: GitHubReconcilerAssets(
          config: config,
          runtimeFactory: factory.create,
          environment: environment ?? platformEnvironment,
          foreignTransportFactory:
              foreignTransportFactory ?? createGitHubHttpTransport,
          child: GitHubGridAssets(
            child: _Probe(
              (context) => observe(context.watch<GitHubReconcilerRuntime>()),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('the config carries workflow-run policy into the reconciler', () {
    final rule = WorkflowRunIntakeRule(
      workflowPath: '.github/workflows/ci.yaml',
      validationPlan: 'dart test',
    );
    final off = GitHubReconcilerConfig(
      owner: 'memento',
      repository: 'power_station',
      substation: 'power_station',
      installationId: 'installation',
    );
    expect(off.workflowRuns, isEmpty, reason: 'feature-off is the default');
    expect(off.defaultBranch, 'main');

    final runtime = createGitHubReconcilerRuntime(
      config: GitHubReconcilerConfig(
        owner: 'memento',
        repository: 'power_station',
        substation: 'power_station',
        installationId: 'installation',
        defaultBranch: 'm3-runtime',
        workflowRuns: [rule],
      ),
      client: _client,
      cursors: _Cursors(),
      emit: (_) async {},
      transport: null,
      foreignClient: null,
    );
    addTearDown(runtime.stop);

    expect(runtime.reconciler.workflowRuns, [same(rule)]);
    expect(runtime.reconciler.defaultBranch, 'm3-runtime');

    final plain = createGitHubReconcilerRuntime(
      config: off,
      client: _client,
      cursors: _Cursors(),
      emit: (_) async {},
      transport: null,
      foreignClient: null,
    );
    addTearDown(plain.stop);
    expect(plain.reconciler.workflowRuns, isEmpty);
  });

  test('live config constructs and starts at consumer', () async {
    final factory = _Factory();
    final flares = _Flares();
    GitHubReconcilerRuntime? observed;
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _runtimeTree(
          config: _config('one'),
          factory: factory,
          observe: (runtime) => observed = runtime,
          transport: flares,
        ),
      ),
    );
    owner.flush();

    expect(factory.configs, hasLength(1));
    expect(factory.transports.single, same(flares));
    expect(observed, same(factory.runtimes.single));
    expect(factory.runtimes.single.starts, 1);

    owner.unmountRoot();
    await Future<void>.delayed(Duration.zero);
    expect(factory.runtimes.single.stops, 1);
  });

  test(
    'production factory flares throwing cycles with seat and repo',
    () async {
      final flares = _Flares();
      final runtime = createGitHubReconcilerRuntime(
        config: _config('owner'),
        client: _client,
        cursors: _Cursors(),
        emit: (_) async {},
        transport: flares,
        foreignClient: null,
      );

      runtime.start();
      try {
        final report = await flares.first.future.timeout(
          const Duration(seconds: 1),
        );
        expect(report.name, 'reconciler.cycleFailed');
        expect(report.data, containsPair('seat', 'power_station'));
        expect(report.data, containsPair('repository', 'owner/power_station'));
        expect(report.data['error'], contains('GitHubPollException'));
        expect(report.data['stack_trace'], isNotEmpty);
      } finally {
        await runtime.stop();
      }
    },
  );

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

  group('outbound issue watches', () {
    /// Mounts [tree] under a provider scope and flushes it, exactly as the
    /// live-config probes above do.
    void mount(Seed tree) {
      final owner = TreeOwner();
      owner.mountRoot(sdk.ProviderScope(child: tree));
      owner.flush();
      addTearDown(owner.unmountRoot);
    }

    const foreign = GitHubIssueWatch(
      originatingBeadId: 'lunar_station-6p9',
      owner: 'ricardoboss',
      repository: 'radioactive_dart',
      issueNumber: 1,
    );
    const installedOnly = GitHubIssueWatch(
      originatingBeadId: 'pow-1rn',
      owner: 'memento',
      repository: 'power_station',
      issueNumber: 7,
    );

    GitHubReconcilerConfig config({
      List<GitHubIssueWatch> watches = const <GitHubIssueWatch>[],
      String? tokenVariable,
      Duration? spacing,
    }) => GitHubReconcilerConfig(
      owner: 'memento',
      repository: 'power_station',
      substation: 'power_station',
      installationId: 'installation',
      issueWatches: watches,
      foreignReadTokenVariable: tokenVariable,
      foreignMinimumSpacing: spacing ?? kUnauthenticatedGitHubMinimumSpacing,
    );

    test('the defaults are the feature-off values', () {
      final off = config();
      expect(off.issueWatches, isEmpty);
      expect(off.foreignReadTokenVariable, isNull);
      expect(off.foreignMinimumSpacing, const Duration(seconds: 65));
      expect(
        createGitHubReconcilerRuntime(
          config: off,
          client: _client,
          cursors: _Cursors(),
          emit: (_) async {},
          transport: null,
          foreignClient: null,
        ).reconciler.issueWatches,
        isEmpty,
      );
    });

    test('no foreign watch constructs no transport and reads no variable', () {
      var environmentReads = 0;
      var transportBuilds = 0;
      final factory = _Factory();
      for (final watches in <List<GitHubIssueWatch>>[
        const <GitHubIssueWatch>[],
        const <GitHubIssueWatch>[installedOnly],
      ]) {
        mount(
          _runtimeTree(
            config: config(watches: watches, tokenVariable: 'TOKEN'),
            factory: factory,
            observe: (_) {},
            environment: () {
              environmentReads++;
              return const <String, String>{};
            },
            foreignTransportFactory: () {
              transportBuilds++;
              return _Transport();
            },
          ),
        );
      }

      expect(environmentReads, 0);
      expect(transportBuilds, 0);
      expect(factory.foreignClients, everyElement(isNull));
      expect(factory.configs.last.issueWatches, hasLength(lessThan(2)));
    });

    test('a foreign watch builds ONE token-less read client', () {
      var transportBuilds = 0;
      final factory = _Factory();
      mount(
        _runtimeTree(
          config: config(watches: const <GitHubIssueWatch>[foreign]),
          factory: factory,
          observe: (_) {},
          environment: () => const <String, String>{},
          foreignTransportFactory: () {
            transportBuilds++;
            return _Transport();
          },
        ),
      );

      expect(transportBuilds, 1);
      final client = factory.foreignClients.single;
      expect(client, isNotNull);
      expect(client!.isAuthenticated, isFalse);
    });

    test('a nonblank token variable is resolved and used', () {
      final factory = _Factory();
      mount(
        _runtimeTree(
          config: config(
            watches: const <GitHubIssueWatch>[foreign],
            tokenVariable: 'GITHUB_FOREIGN_READ_TOKEN',
          ),
          factory: factory,
          observe: (_) {},
          environment: () => const <String, String>{
            'GITHUB_FOREIGN_READ_TOKEN': 'personal',
          },
          foreignTransportFactory: _Transport.new,
        ),
      );

      expect(factory.foreignClients.single!.isAuthenticated, isTrue);
    });

    test('a blank token variable stays the token-less posture', () {
      final factory = _Factory();
      mount(
        _runtimeTree(
          config: config(
            watches: const <GitHubIssueWatch>[foreign],
            tokenVariable: 'GITHUB_FOREIGN_READ_TOKEN',
          ),
          factory: factory,
          observe: (_) {},
          environment: () => const <String, String>{
            'GITHUB_FOREIGN_READ_TOKEN': '   ',
          },
          foreignTransportFactory: _Transport.new,
        ),
      );

      expect(factory.foreignClients.single!.isAuthenticated, isFalse);
    });

    test('the watch list reaches the reconciler through the factory', () {
      final factory = _Factory();
      mount(
        _runtimeTree(
          config: config(
            watches: const <GitHubIssueWatch>[foreign, installedOnly],
          ),
          factory: factory,
          observe: (_) {},
          environment: () => const <String, String>{},
          foreignTransportFactory: _Transport.new,
        ),
      );

      expect(factory.configs.single.issueWatches, <GitHubIssueWatch>[
        foreign,
        installedOnly,
      ]);
    });
  });
}
