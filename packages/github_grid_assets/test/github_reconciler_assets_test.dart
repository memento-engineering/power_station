import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
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

/// A transport that answers every request "nothing changed", counts what it
/// was asked, and can HOLD a request open so a probe observes the tree while a
/// cycle is genuinely in flight.
final class _GatedTransport implements GitHubHttpTransport {
  final requests = <GitHubHttpRequest>[];
  Completer<void>? gate;

  int get calls => requests.length;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    if (gate case final open?) await open.future;
    return const GitHubHttpResponse(statusCode: 304, body: '');
  }
}

/// A transport answering a SCRIPT of responses in order — the foreign lane's
/// two GETs (the issue resource, then its timeline).
final class _ScriptedTransport implements GitHubHttpTransport {
  _ScriptedTransport(this._responses);

  final List<GitHubHttpResponse> _responses;
  final requests = <GitHubHttpRequest>[];

  /// Every `Authorization` value this transport was handed, so a probe can
  /// prove which credential reached which lane.
  List<String?> get authorizations => <String?>[
    for (final request in requests) request.headers['Authorization'],
  ];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('unscripted foreign read: ${request.uri}');
    }
    return _responses.removeAt(0);
  }
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

/// A runtime that never reaches GitHub. It overrides NOTHING: the runtime has
/// no lifecycle left to fake — whether this seat reconciles is now a fact about
/// the station's query, which every probe below reads there.
final class _RecordingRuntime extends GitHubReconcilerRuntime {
  _RecordingRuntime({
    required GitHubAppClient client,
    required super.coordinator,
  }) : super(
         installationId: 'installation',
         reconciler: GitHubReconciler(
           owner: 'owner',
           repository: 'repository',
           substation: 'substation',
           client: client,
           cursors: _Cursors(),
           emit: (_) async {},
         ),
       );
}

final class _Factory {
  _Factory({this.failOn = -1});

  /// The zero-based construction that THROWS instead of returning a runtime.
  /// -1 — the default — is a factory that always succeeds.
  final int failOn;

  /// The error a failing construction throws, held so a probe can assert the
  /// SAME object reached the caller rather than a look-alike.
  final failure = StateError('the replacement runtime refuses to be built');

  final configs = <GitHubReconcilerConfig>[];
  final transports = <ExplorationTransport?>[];
  final runtimes = <_RecordingRuntime>[];
  final foreignClients = <GitHubReadClient?>[];
  final coordinators = <GitHubPollCoordinator>[];

  GitHubReconcilerRuntime create({
    required GitHubReconcilerConfig config,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    required ExplorationTransport? transport,
    required GitHubReadClient? foreignClient,
    required GitHubPollCoordinator coordinator,
  }) {
    configs.add(config);
    transports.add(transport);
    foreignClients.add(foreignClient);
    coordinators.add(coordinator);
    // The ATTEMPT is recorded first: a construction that refuses is still a
    // construction this seat asked for.
    if (configs.length - 1 == failOn) throw failure;
    final runtime = _RecordingRuntime(client: client, coordinator: coordinator);
    runtimes.add(runtime);
    return runtime;
  }
}

/// A second App client identity, for the probes that REPLACE one.
GitHubAppClient _otherClient() => GitHubAppClient(
  config: _appConfig,
  tokens: _Tokens(),
  transport: _Transport(),
);

/// A stable event sink: one instance, so a rebuild that changes nothing else
/// really does change nothing.
Future<void> _sink(NormalizedGitHubEvent event) async {}

/// The distinct consecutive values in [observations] — what a probe watching
/// availability actually claims, with a repeated build of an unchanged posture
/// collapsed away.
List<GitHubReconcilerRuntime?> _sequence(
  List<GitHubReconcilerRuntime?> observations,
) {
  final sequence = <GitHubReconcilerRuntime?>[];
  for (final observation in observations) {
    if (sequence.isEmpty || !identical(sequence.last, observation)) {
      sequence.add(observation);
    }
  }
  return sequence;
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

/// The station rung a live seat is composed under: a [sdk.TrajectoryConfig]
/// registering [queries] as the tick's obligation extensions.
Seed _station(List<sdk.ObligationQuery> queries, {required Seed child}) =>
    InheritedSeed<sdk.TrajectoryConfig>(
      value: sdk.TrajectoryConfig(obligationQueryExtensions: queries),
      child: child,
    );

Seed _runtimeTree({
  required GitHubReconcilerConfig? config,
  required _Factory factory,
  required void Function(GitHubReconcilerRuntime?) observe,
  required GitHubReconciliationQuery query,
  ExplorationTransport? transport,
  EnvironmentReader? environment,
  GitHubHttpTransportFactory? foreignTransportFactory,
}) => _station(
  <sdk.ObligationQuery>[query],
  child: _seatTree(
    config: config,
    factory: factory,
    observe: observe,
    transport: transport,
    environment: environment,
    foreignTransportFactory: foreignTransportFactory,
  ),
);

/// Wraps a seat in whatever rung owns the station's poll coordinator.
typedef _CoordinatorRung = Seed Function(Seed child);

/// The PRODUCTION rung: the station asset, which creates and owns the
/// coordinator itself.
Seed _stationCoordinator(Seed child) =>
    GitHubPollCoordinatorAssets(child: child);

/// The seat itself, WITHOUT the station rung — so a probe can mount it under a
/// deliberately wrong registration.
///
/// [coordinatorRung] defaults to the production station asset. A probe hands
/// its own to adopt a coordinator IT owns (`Provider.value`), or to mount the
/// seat under no coordinator at all.
///
/// [appClient] false mounts NO `GitHubAppClient` provider at all — the seat's
/// required dependency is ABSENT rather than merely different, which is the
/// only way this substrate can state absence. [cursors] and [emit] default to a
/// fresh instance each call; a probe that needs an input-EQUAL rebuild passes
/// its own and holds them stable.
Seed _seatTree({
  required GitHubReconcilerConfig? config,
  required _Factory factory,
  required void Function(GitHubReconcilerRuntime?) observe,
  ExplorationTransport? transport,
  EnvironmentReader? environment,
  GitHubHttpTransportFactory? foreignTransportFactory,
  GitHubAppClient? client,
  GitHubCursorStore? cursors,
  GitHubEventSink? emit,
  bool appClient = true,
  _CoordinatorRung coordinatorRung = _stationCoordinator,
}) {
  final GitHubEventSink sink = emit ?? (_) async {};
  Seed seat = Provider<GitHubCursorStore>.value(
    cursors ?? _Cursors(),
    child: Provider<GitHubEventSink>.value(
      sink,
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
  );
  if (appClient) {
    seat = Provider<GitHubAppClient>.value(client ?? _client, child: seat);
  }
  return coordinatorRung(
    InheritedSeed<ServiceBundle>(
      value: ServiceBundle(transport: transport),
      child: seat,
    ),
  );
}

/// Reads from the tree and passes its child STRAIGHT THROUGH — a [Nest] link,
/// so several production seats stack and each is observed at its own rung,
/// above the next seat's providers.
final class _Observer extends SingleChildStatelessSeed {
  const _Observer(this.read);

  final void Function(TreeContext) read;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    read(context);
    return child;
  }
}

/// ONE repository seat as production composes it: the REAL
/// [createGitHubReconcilerRuntime], over this seat's own client, cursors and
/// sink, and no coordinator of its own — it takes the station's.
List<SingleChildSeed> _productionSeat({
  required GitHubReconcilerConfig config,
  required GitHubHttpTransport transport,
  required void Function(GitHubReconcilerRuntime?) observe,
  EnvironmentReader? environment,
  GitHubHttpTransportFactory? foreignTransportFactory,
}) => <SingleChildSeed>[
  Provider<GitHubAppClient>.value(
    GitHubAppClient(
      config: _appConfig,
      tokens: _Tokens(),
      transport: transport,
    ),
  ),
  Provider<GitHubCursorStore>.value(_Cursors()),
  Provider<GitHubEventSink>.value((_) async {}),
  GitHubReconcilerAssets(
    config: config,
    environment: environment ?? platformEnvironment,
    foreignTransportFactory:
        foreignTransportFactory ?? createGitHubHttpTransport,
  ),
  _Observer((context) => observe(context.watch<GitHubReconcilerRuntime>())),
];

/// A live repository value on [installation], spaced at zero so these probes
/// measure SERIALIZATION and never a wall clock.
GitHubReconcilerConfig _repository({
  required String repository,
  required String installation,
  List<GitHubIssueWatch> watches = const <GitHubIssueWatch>[],
  String? tokenVariable,
}) => GitHubReconcilerConfig(
  owner: 'memento',
  repository: repository,
  substation: repository,
  installationId: installation,
  minimumSpacing: Duration.zero,
  issueWatches: watches,
  foreignReadTokenVariable: tokenVariable,
  foreignMinimumSpacing: Duration.zero,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A watch on a repository this App is NOT installed on — the foreign lane's
/// reason to exist.
const GitHubIssueWatch _foreignWatch = GitHubIssueWatch(
  originatingBeadId: 'pow-eup0',
  owner: 'ricardoboss',
  repository: 'radioactive_dart',
  issueNumber: 1,
);

/// The minimum an open, unlocked issue resource answers with.
const String _issueBody =
    '{"node_id":"I_1","user":{"login":"ricardoboss"},"state":"open",'
    '"locked":false,"updated_at":"2026-09-21T00:00:00Z",'
    '"html_url":"https://github.test/issues/1"}';

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
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );

    expect(runtime.reconciler.workflowRuns, [same(rule)]);
    expect(runtime.reconciler.defaultBranch, 'm3-runtime');

    final plain = createGitHubReconcilerRuntime(
      config: off,
      client: _client,
      cursors: _Cursors(),
      emit: (_) async {},
      transport: null,
      foreignClient: null,
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );
    expect(plain.reconciler.workflowRuns, isEmpty);
  });

  test('station-owned coordinator serializes production runtimes sharing an '
      'installation', () async {
    // The DEFECT this bead retires: two production-created runtimes for one
    // installation used to hold a coordinator each, so both spent the same
    // allowance at once. The whole composition is production here — the real
    // factory, one station rung, two repository seats — because a test that
    // injects a coordinator it shared itself cannot see this at all.
    final blocked = _GatedTransport()..gate = Completer<void>();
    final waiting = _GatedTransport();
    final query = GitHubReconciliationQuery();
    var created = 0;
    GitHubReconcilerRuntime? one;
    GitHubReconcilerRuntime? two;

    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _station(
          <sdk.ObligationQuery>[query],
          child: Nest(
            children: <SingleChildSeed>[
              GitHubPollCoordinatorAssets(
                coordinatorFactory: () {
                  created++;
                  return GitHubPollCoordinator(minimumSpacing: Duration.zero);
                },
              ),
              ..._productionSeat(
                config: _repository(
                  repository: 'one',
                  installation: 'installation',
                ),
                transport: blocked,
                observe: (runtime) => one = runtime,
              ),
              ..._productionSeat(
                config: _repository(
                  repository: 'two',
                  installation: 'installation',
                ),
                transport: waiting,
                observe: (runtime) => two = runtime,
              ),
            ],
            child: const _Leaf(),
          ),
        ),
      ),
    );
    owner.flush();

    expect(created, 1, reason: 'the station creates ONE, for both seats');
    expect(one, isNotNull);
    expect(two, isNotNull);
    expect(
      one!.coordinator,
      same(two!.coordinator),
      reason: 'the identical tree-created instance reaches both runtimes',
    );
    expect(query.attached, <GitHubReconcilerRuntime>[one!, two!]);

    final cycles = Future.wait(<Future<void>>[one!.runOnce(), two!.runOnce()]);
    await _settle();

    expect(blocked.calls, 1, reason: 'the first cycle holds the budget');
    expect(
      waiting.calls,
      0,
      reason: 'the SECOND repository makes no request at all until it is free',
    );

    blocked.gate!.complete();
    await cycles;
    expect(waiting.calls, 2, reason: 'and then runs its own full cycle');
  });

  test('different installation and foreign quotas start independently', () async {
    // The falsifier for the probe above, and the boundary the bead protects:
    // serialization is BY KEY, so another installation is another budget — and
    // the foreign issue-watch lane, which has its own 60-per-hour allowance and
    // its own credential, is not installation budgeting at all.
    final blocked = _GatedTransport()..gate = Completer<void>();
    final elsewhere = _GatedTransport();
    final foreign = _ScriptedTransport(<GitHubHttpResponse>[
      GitHubHttpResponse(statusCode: 200, body: _issueBody, headers: const {}),
      const GitHubHttpResponse(statusCode: 200, body: '[]'),
    ]);
    final query = GitHubReconciliationQuery();
    GitHubReconcilerRuntime? held;
    GitHubReconcilerRuntime? other;

    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _station(
          <sdk.ObligationQuery>[query],
          child: Nest(
            children: <SingleChildSeed>[
              const GitHubPollCoordinatorAssets(),
              ..._productionSeat(
                config: _repository(
                  repository: 'one',
                  installation: 'installation',
                ),
                transport: blocked,
                observe: (runtime) => held = runtime,
              ),
              ..._productionSeat(
                config: _repository(
                  repository: 'watcher',
                  installation: 'other',
                  watches: const <GitHubIssueWatch>[_foreignWatch],
                  tokenVariable: 'GITHUB_FOREIGN_READ_TOKEN',
                ),
                transport: elsewhere,
                observe: (runtime) => other = runtime,
                environment: () => const <String, String>{
                  'GITHUB_FOREIGN_READ_TOKEN': 'personal',
                },
                foreignTransportFactory: () => foreign,
              ),
            ],
            child: const _Leaf(),
          ),
        ),
      ),
    );
    owner.flush();

    expect(held!.coordinator, same(other!.coordinator));

    final cycles = Future.wait(<Future<void>>[
      held!.runOnce(),
      other!.runOnce(),
    ]);
    await _settle();

    expect(blocked.calls, 1, reason: 'installation one is still in flight');
    expect(
      elsewhere.calls,
      2,
      reason: 'another installation key is another budget entirely',
    );
    expect(
      foreign.requests.map((request) => request.uri.path),
      <String>[
        '/repos/ricardoboss/radioactive_dart/issues/1',
        '/repos/ricardoboss/radioactive_dart/issues/1/timeline',
      ],
      reason: 'the foreign lane ran while the installation lane was blocked',
    );

    // NO credential crosses the boundary in either direction.
    expect(foreign.authorizations, everyElement('Bearer personal'));
    expect(
      elsewhere.requests.map((request) => request.headers['Authorization']),
      everyElement('Bearer token'),
    );

    blocked.gate!.complete();
    await cycles;
  });

  test(
    'coordinator provider replacement removal and disposal detach exactly once',
    () async {
      final factory = _Factory();
      final query = GitHubReconciliationQuery();
      final first = GitHubPollCoordinator(minimumSpacing: Duration.zero);
      final second = GitHubPollCoordinator(minimumSpacing: Duration.zero);
      late _HostState host;
      // ONE seat description under three coordinator postures: the only thing
      // a swap changes is who owns the budget above it.
      final seat = _seatTree(
        config: _config('one'),
        factory: factory,
        observe: (_) {},
        coordinatorRung: (child) => child,
      );
      Seed describe(GitHubPollCoordinator? coordinator) => _station(
        <sdk.ObligationQuery>[query],
        child: coordinator == null
            ? seat
            : Provider<GitHubPollCoordinator>.value(coordinator, child: seat),
      );
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => describe(first),
          ),
        ),
      );
      owner.flush();

      expect(factory.coordinators, <GitHubPollCoordinator>[first]);
      expect(query.attached, <GitHubReconcilerRuntime>[
        factory.runtimes.single,
      ]);

      // A REBUILD over the same coordinator is not a replacement: identity is
      // what the seat compares, so the runtime and its cursor tail stand.
      host.swap(() => describe(first));
      owner.flush();
      await _settle();
      owner.flush();
      expect(factory.runtimes, hasLength(1));
      expect(query.attached, <GitHubReconcilerRuntime>[
        factory.runtimes.single,
      ]);

      // A REPLACED coordinator is exactly one handover: the superseded runtime
      // is off the tick before its successor is on it.
      host.swap(() => describe(second));
      owner.flush();
      await _settle();
      owner.flush();
      expect(factory.coordinators, <GitHubPollCoordinator>[first, second]);
      expect(factory.runtimes, hasLength(2));
      expect(query.attached, <GitHubReconcilerRuntime>[factory.runtimes.last]);

      // REMOVED: a live seat with no station rung REFUSES, by name — and it is
      // already off the tick when it does, not left spending a budget nobody
      // owns. Deliberately the LAST thing done to this owner and never
      // disposed: a reconcile that threw leaves the substrate holding a child
      // slot it already unmounted, so `dispose` would double-unmount it. There
      // is nothing left attached to clean up, which is the assertion below.
      host.swap(() => describe(null));
      expect(
        owner.flush,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('GitHubPollCoordinatorAssets'),
              contains('installation'),
            ),
          ),
        ),
      );
      expect(query.attached, isEmpty, reason: 'detached BEFORE the refusal');
      expect(
        factory.runtimes,
        hasLength(2),
        reason: 'a refused seat builds none',
      );

      // DISPOSAL, and what a LATER station gets. The tree owns the value, so
      // nothing rides the tick and no budget survives the station that spent
      // it — every mount is handed an instance of its own.
      final coordinators = <GitHubPollCoordinator>[];
      for (var mount = 0; mount < 2; mount++) {
        final station = TreeOwner();
        final mounted = _Factory();
        final stationQuery = GitHubReconciliationQuery();
        station.mountRoot(
          sdk.ProviderScope(
            child: _runtimeTree(
              config: _config('one'),
              factory: mounted,
              observe: (_) {},
              query: stationQuery,
            ),
          ),
        );
        station.flush();
        expect(stationQuery.attached, hasLength(1));
        coordinators.add(mounted.coordinators.single);
        station.dispose();
        expect(stationQuery.attached, isEmpty, reason: 'disposal detaches');
      }
      expect(coordinators.first, isNot(same(coordinators.last)));
      expect(coordinators, isNot(contains(same(first))));
      expect(coordinators, isNot(contains(same(second))));
    },
  );

  test(
    'live assets attach only to the query registered in TrajectoryConfig',
    () async {
      final factory = _Factory();
      final flares = _Flares();
      final registered = GitHubReconciliationQuery();
      final unregistered = GitHubReconciliationQuery();
      GitHubReconcilerRuntime? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _runtimeTree(
            config: _config('one'),
            factory: factory,
            observe: (runtime) => observed = runtime,
            query: registered,
            transport: flares,
          ),
        ),
      );
      owner.flush();

      expect(factory.configs, hasLength(1));
      expect(factory.transports.single, same(flares));
      expect(observed, same(factory.runtimes.single));
      expect(registered.attached, <GitHubReconcilerRuntime>[
        factory.runtimes.single,
      ]);
      expect(
        unregistered.attached,
        isEmpty,
        reason: 'a query the station did not register gets no seat',
      );

      owner.unmountRoot();
      expect(registered.attached, isEmpty);
    },
  );

  test('live assets refuse missing or duplicate registered queries', () {
    void mount(List<sdk.ObligationQuery> registration, _Factory factory) {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        sdk.ProviderScope(
          child: _station(
            registration,
            child: _seatTree(
              config: _config('one'),
              factory: factory,
              observe: (_) {},
            ),
          ),
        ),
      );
      owner.flush();
    }

    for (final registration in <List<sdk.ObligationQuery>>[
      // NO registration at all — including an ambient config that never
      // mentions GitHub, which is the wedge this bead exists to prevent.
      const <sdk.ObligationQuery>[],
      const <sdk.ObligationQuery>[_OtherQuery()],
      <sdk.ObligationQuery>[
        GitHubReconciliationQuery(),
        GitHubReconciliationQuery(),
      ],
    ]) {
      final expected = registration
          .whereType<GitHubReconciliationQuery>()
          .length;
      final factory = _Factory();
      expect(
        () => mount(registration, factory),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('TrajectoryConfig.obligationQueryExtensions'),
              contains('offers $expected'),
            ),
          ),
        ),
        reason: 'registering $expected GitHub queries is a REFUSAL',
      );
      expect(factory.runtimes, isEmpty, reason: 'a refused seat runs nothing');
    }

    // The falsifier: selection is BY TYPE, so a station obligation that is not
    // the GitHub one neither satisfies the requirement nor breaks it.
    final query = GitHubReconciliationQuery();
    final factory = _Factory();
    mount(<sdk.ObligationQuery>[const _OtherQuery(), query], factory);
    expect(query.attached, <GitHubReconcilerRuntime>[factory.runtimes.single]);
  });

  test('a registered query replacement moves the SAME runtime', () async {
    final factory = _Factory();
    final first = GitHubReconciliationQuery();
    final second = GitHubReconciliationQuery();
    late _HostState host;
    // ONE seat description, two registrations over it: the only thing the swap
    // changes is which query the station registered.
    final seat = _seatTree(
      config: _config('one'),
      factory: factory,
      observe: (_) {},
    );
    Seed describe(GitHubReconciliationQuery query) =>
        _station(<sdk.ObligationQuery>[query], child: seat);
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(first),
        ),
      ),
    );
    owner.flush();
    final runtime = factory.runtimes.single;
    expect(first.attached, <GitHubReconcilerRuntime>[runtime]);

    host.swap(() => describe(second));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();

    expect(
      factory.runtimes,
      hasLength(1),
      reason: 'only the SCHEDULE moved; the seat kept its cursor tail',
    );
    expect(first.attached, isEmpty);
    expect(second.attached, <GitHubReconcilerRuntime>[runtime]);
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
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );

      // The station's pass is what runs it, and the throw is what the pass
      // accounts for — the flare is the seat's own copy of the same news.
      await expectLater(runtime.runOnce(), throwsA(isA<GitHubPollException>()));

      final report = await flares.first.future.timeout(
        const Duration(seconds: 1),
      );
      expect(report.name, 'reconciler.cycleFailed');
      expect(report.data, containsPair('seat', 'power_station'));
      expect(report.data, containsPair('repository', 'owner/power_station'));
      expect(report.data['error'], contains('GitHubPollException'));
      expect(report.data['stack_trace'], isNotEmpty);
    },
  );

  test('unmount detaches reconciliation from the station tick', () async {
    final factory = _Factory();
    final query = GitHubReconciliationQuery();
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _runtimeTree(
          config: _config('one'),
          factory: factory,
          observe: (_) {},
          query: query,
        ),
      ),
    );
    owner.flush();
    expect(query.attached, hasLength(1));

    owner.unmountRoot();

    expect(query.attached, isEmpty);
    // And the station's next pass really does nothing for this seat: the
    // client above answers 500, so a reached runtime would have thrown.
    expect(await query.repair(const <Map<String, String?>>[]), isEmpty);
  });

  test('inert arms construct nothing', () {
    for (final config in <GitHubReconcilerConfig?>[
      null,
      _config('one', arm: GitHubReconcilerArm.dry),
      _config('one', arm: GitHubReconcilerArm.offline),
    ]) {
      final factory = _Factory();
      final query = GitHubReconciliationQuery();
      GitHubReconcilerRuntime? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _runtimeTree(
            config: config,
            factory: factory,
            observe: (runtime) => observed = runtime,
            query: query,
          ),
        ),
      );
      owner.flush();
      expect(factory.configs, isEmpty);
      expect(observed, isNull);
      expect(query.attached, isEmpty, reason: 'an inert arm rides no tick');
      owner.unmountRoot();
    }
  });

  test('config replacement re-provides runtime', () async {
    final factory = _Factory();
    final query = GitHubReconciliationQuery();
    final observations = <GitHubReconcilerRuntime?>[];
    late _HostState host;
    Seed describe(GitHubReconcilerConfig config) => _runtimeTree(
      config: config,
      factory: factory,
      observe: observations.add,
      query: query,
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
    expect(
      query.attached,
      <GitHubReconcilerRuntime>[factory.runtimes.last],
      reason: 'the superseded seat stops riding the tick at handover',
    );

    owner.unmountRoot();
    expect(query.attached, isEmpty);
  });

  test('an input-equal rebuild owns no effect', () async {
    // The whole point of projecting an immutable, value-equal input: a parent
    // that re-describes this seat with a FRESH but equivalent configuration and
    // the SAME implementations hands the lifecycle no dependency pass at all.
    final factory = _Factory();
    final query = GitHubReconciliationQuery();
    final cursors = _Cursors();
    final observations = <GitHubReconcilerRuntime?>[];
    late _HostState host;
    Seed describe() => _station(
      <sdk.ObligationQuery>[query],
      child: _seatTree(
        // A NEW config object every time, equal to the last one by value.
        config: _config('one'),
        factory: factory,
        observe: observations.add,
        client: _client,
        cursors: cursors,
        emit: _sink,
      ),
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(onCreate: (state) => host = state, describe: describe),
      ),
    );
    owner.flush();
    final runtime = factory.runtimes.single;
    expect(query.attached, <GitHubReconcilerRuntime>[runtime]);
    // A SECOND seat joins the same station query behind this one. The tick's
    // set is insertion-ordered, so a release-and-reattach this seat never
    // needed would show up here as a reordering.
    final other = _RecordingRuntime(
      client: _client,
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );
    query.attach(other);

    host.swap(describe);
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();

    expect(
      factory.configs,
      hasLength(1),
      reason: 'an equivalent description constructs nothing',
    );
    expect(
      query.attached,
      <GitHubReconcilerRuntime>[runtime, other],
      reason:
          'the SAME attachment stands, in place: an input-equal description '
          'never reaches the lifecycle, so nothing is released or re-attached',
    );
    expect(observations.last, same(runtime));
  });

  test('dependency appearance, replacement, disappearance and unmount move '
      'runtime availability', () async {
    final factory = _Factory();
    final query = GitHubReconciliationQuery();
    final cursors = _Cursors();
    final observations = <GitHubReconcilerRuntime?>[];
    final second = _otherClient();
    late _HostState host;
    Seed describe(GitHubAppClient? client) => _station(
      <sdk.ObligationQuery>[query],
      child: _seatTree(
        config: _config('one'),
        factory: factory,
        observe: observations.add,
        client: client,
        appClient: client != null,
        cursors: cursors,
        emit: _sink,
      ),
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    Future<void> swap(GitHubAppClient? client) async {
      host.swap(() => describe(client));
      owner.flush();
      await Future<void>.delayed(Duration.zero);
      owner.flush();
    }

    // ABSENT: the App client this seat needs is not in the tree at all.
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(null),
        ),
      ),
    );
    owner.flush();
    expect(factory.configs, isEmpty);
    expect(query.attached, isEmpty);

    await swap(_client); // PRESENT
    final first = factory.runtimes.single;
    expect(query.attached, <GitHubReconcilerRuntime>[first]);

    await swap(second); // REPLACED
    expect(factory.runtimes, hasLength(2));
    expect(
      query.attached,
      <GitHubReconcilerRuntime>[factory.runtimes.last],
      reason: 'the superseded seat left the tick as the replacement joined',
    );

    await swap(null); // ABSENT again
    expect(
      query.attached,
      isEmpty,
      reason: 'a seat missing a required dependency rides no tick',
    );
    expect(factory.runtimes, hasLength(2), reason: 'losing one builds nothing');

    await swap(_client); // PRESENT again
    expect(factory.runtimes, hasLength(3));
    expect(query.attached, <GitHubReconcilerRuntime>[factory.runtimes.last]);

    expect(_sequence(observations), <GitHubReconcilerRuntime?>[
      null,
      factory.runtimes[0],
      factory.runtimes[1],
      null,
      factory.runtimes[2],
    ]);

    owner.unmountRoot();
    expect(query.attached, isEmpty);
  });

  test('a de-registered station query refuses and drops the seat from the '
      'tick', () async {
    final factory = _Factory();
    final query = GitHubReconciliationQuery();
    final cursors = _Cursors();
    late _HostState host;
    Seed describe(List<sdk.ObligationQuery> registration) => _station(
      registration,
      child: _seatTree(
        config: _config('one'),
        factory: factory,
        observe: (_) {},
        client: _client,
        cursors: cursors,
        emit: _sink,
      ),
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(<sdk.ObligationQuery>[query]),
        ),
      ),
    );
    owner.flush();
    expect(query.attached, hasLength(1));

    expect(
      () {
        host.swap(() => describe(const <sdk.ObligationQuery>[]));
        owner.flush();
      },
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('offers 0'),
        ),
      ),
    );
    expect(
      query.attached,
      isEmpty,
      reason:
          'the refusal releases the old attachment BEFORE it throws: a seat '
          'the station no longer schedules must ride no tick',
    );
  });

  test('a replacement construction failure detaches the old runtime and '
      'rethrows', () async {
    final factory = _Factory(failOn: 1);
    final query = GitHubReconciliationQuery();
    final cursors = _Cursors();
    final observations = <GitHubReconcilerRuntime?>[];
    final second = _otherClient();
    final third = _otherClient();
    late _HostState host;
    Seed describe(GitHubAppClient client) => _station(
      <sdk.ObligationQuery>[query],
      child: _seatTree(
        config: _config('one'),
        factory: factory,
        observe: observations.add,
        client: client,
        cursors: cursors,
        emit: _sink,
      ),
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(_client),
        ),
      ),
    );
    owner.flush();
    final first = factory.runtimes.single;
    expect(query.attached, <GitHubReconcilerRuntime>[first]);

    expect(
      () {
        host.swap(() => describe(second));
        owner.flush();
      },
      throwsA(same(factory.failure)),
      reason: 'the construction error reaches the caller, unwrapped',
    );
    expect(
      query.attached,
      isEmpty,
      reason:
          'the superseded seat was released BEFORE the replacement was '
          'attempted, so a failed construction leaves nothing riding the tick',
    );
    expect(
      factory.runtimes,
      <GitHubReconcilerRuntime>[first],
      reason: 'a refused construction produces no runtime to attach',
    );

    // A later CHANGED dependency pass still attaches exactly ONE replacement.
    host.swap(() => describe(third));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();

    expect(factory.runtimes, hasLength(2));
    expect(query.attached, <GitHubReconcilerRuntime>[factory.runtimes.last]);
    expect(observations.last, same(factory.runtimes.last));
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

    /// A fresh registration per mount: these probes read the FACTORY, never
    /// the tick, so each tree gets its own query and nothing is shared.
    GitHubReconciliationQuery query() => GitHubReconciliationQuery();

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
          coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
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
            query: query(),
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
          query: query(),
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
          query: query(),
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
          query: query(),
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
          query: query(),
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

/// A station obligation that is NOT the GitHub one — the falsifier for
/// "selected from the registration by type".
final class _OtherQuery extends sdk.ObligationQuery {
  const _OtherQuery();

  @override
  String get name => 'not-github';

  @override
  String get sql => 'SELECT 1';

  @override
  Future<List<sdk.ObligationAppend>> repair(
    List<Map<String, String?>> rows,
  ) async => const <sdk.ObligationAppend>[];
}
