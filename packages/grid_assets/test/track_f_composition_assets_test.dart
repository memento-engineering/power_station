import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
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

class _BundleDependent extends StatelessSeed {
  const _BundleDependent(this.onBuild);
  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    onBuild();
    return const _Leaf();
  }
}

class _FakeGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(const PullRequestRef(url: 'https://x/pr/1'));
}

class _RecordingMountBdRunner implements BdRunner {
  _RecordingMountBdRunner(this._reply);

  final Future<BdResult> Function(List<String> args) _reply;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    return _reply(args);
  }
}

BdResult _queryReply(Bead bead) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({
    'schema_version': 1,
    'data': [bead.toJson()],
  }),
  stderr: '',
);

class _SourceControl implements SourceControl {
  @override
  String get baseBranch => 'main';
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String workspaceFor(String beadId) => '/work/$beadId';
  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}

class _Delivery implements DeliveryMethod {
  @override
  String get id => 'test';
  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async => const Ok();
}

class _Escalation implements EscalationHandler {
  @override
  String get id => 'test';
  @override
  Future<EscalationDecision> escalate(EscalationRequest request) async =>
      const ParkAtGate();
}

class _Trust implements Trust {
  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) async => TrustLevel.self;
}

class _Transport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) {}
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

Seed _underSubstation(String name, String root, Seed child) =>
    InheritedSeed<sdk.SubstationScope>(
      value: sdk.SubstationScope(name: name, root: root, prefix: name),
      child: child,
    );

({TreeOwner owner, ServiceBundle? Function() bundle}) _mountEligibilityAsset(
  BdRunner Function(String storeRoot) runnerFor,
) {
  ServiceBundle? observed;
  final owner = TreeOwner();
  owner.mountRoot(
    _underSubstation(
      'power_station',
      '/work/ps',
      MountEligibilityAssets(
        runnerFor: runnerFor,
        child: _Probe(
          (context) => observed = context
              .dependOnInheritedSeedOfExactType<ServiceBundle>(),
        ),
      ),
    ),
  );
  owner.flush();
  return (owner: owner, bundle: () => observed);
}

String? _refusalClause(MountEligibilityDecision decision) => switch (decision) {
  MountEligible() => null,
  MountRefused(:final clause) => clause,
};

Future<({MountEligibilityDecision decision, _RecordingMountBdRunner runner})>
_runSuccessfulRefusalRecheck(Bead fresh) async {
  final runner = _RecordingMountBdRunner((_) async => _queryReply(fresh));
  final mounted = _mountEligibilityAsset((root) {
    expect(root, '/work/ps');
    return runner;
  });
  expect(mounted.bundle(), isNotNull);

  const snapshot = Bead(id: 'pow-test', metadata: {}, labels: []);
  final pending = mounted.bundle()!.mountEligibility!(snapshot);
  expect(
    _refusalClause(pending),
    'fresh mount-eligibility read pending: pow-test',
  );

  await pumpEventQueue();
  mounted.owner.flush();

  final decision = mounted.bundle()!.mountEligibility!(snapshot);
  expect(mounted.bundle()!.mountEligibility!(snapshot), decision);
  expect(runner.calls, [
    ['query', 'id=pow-test', '--all', '--json', '--limit', '0'],
  ]);
  return (decision: decision, runner: runner);
}

Future<String> _runFailedRefusalRecheck(_RecordingMountBdRunner runner) async {
  final mounted = _mountEligibilityAsset((_) => runner);
  const snapshot = Bead(id: 'pow-test', metadata: {}, labels: []);

  expect(
    _refusalClause(mounted.bundle()!.mountEligibility!(snapshot)),
    'fresh mount-eligibility read pending: pow-test',
  );
  await pumpEventQueue();
  mounted.owner.flush();

  final clause = _refusalClause(mounted.bundle()!.mountEligibility!(snapshot));
  expect(clause, isNotNull);
  expect(mounted.bundle()!.mountEligibility!(snapshot), isA<MountRefused>());
  expect(runner.calls, [
    ['query', 'id=pow-test', '--all', '--json', '--limit', '0'],
  ]);
  return clause!;
}

void main() {
  test(
    'MountEligibilityAssets preserves services, injects, and rebuilds',
    () async {
      final sourceControl = _SourceControl();
      final delivery = _Delivery();
      final escalation = _Escalation();
      final trust = _Trust();
      const floor = TrustFloor(TrustLevel.self);
      final transport = _Transport();
      late _HostState host;
      ServiceBundle? observed;
      final probe = _Probe(
        (context) => observed = context
            .dependOnInheritedSeedOfExactType<ServiceBundle>(),
      );
      Seed describe(ServiceBundle bundle) => InheritedSeed<ServiceBundle>(
        value: bundle,
        child: MountEligibilityAssets(child: probe),
      );
      final first = ServiceBundle(
        sourceControl: sourceControl,
        delivery: delivery,
        escalation: escalation,
        trust: trust,
        trustFloor: floor,
        transport: transport,
      );
      final owner = TreeOwner();
      owner.mountRoot(
        _Host(
          onCreate: (state) => host = state,
          describe: () => describe(first),
        ),
      );
      owner.flush();
      expect(observed!.sourceControl, same(sourceControl));
      expect(observed!.delivery, same(delivery));
      expect(observed!.escalation, same(escalation));
      expect(observed!.trust, same(trust));
      expect(observed!.trustFloor, same(floor));
      expect(observed!.transport, same(transport));
      expect(observed!.mountEligibility, same(mountEligibilityDecision));

      final replacement = ServiceBundle(sourceControl: _SourceControl());
      host.swap(() => describe(replacement));
      owner.flush();
      await Future<void>.delayed(Duration.zero);
      owner.flush();
      expect(observed!.sourceControl, same(replacement.sourceControl));
    },
  );

  test('MountEligibilityAssets defaults trusted without ambient bundle', () {
    ServiceBundle? observed;
    final owner = TreeOwner();
    owner.mountRoot(
      MountEligibilityAssets(
        child: _Probe(
          (context) => observed = context
              .dependOnInheritedSeedOfExactType<ServiceBundle>(),
        ),
      ),
    );
    owner.flush();
    expect(observed!.trustFloor, const TrustFloor(TrustLevel.trusted));
    expect(observed!.mountEligibility, same(mountEligibilityDecision));
  });

  test(
    'MountEligibilityAssets refusal recheck reports approval from fresh state',
    () async {
      final result = await _runSuccessfulRefusalRecheck(
        const Bead(
          id: 'pow-test',
          metadata: {'validation_plan': 'dart test'},
          labels: [],
        ),
      );
      expect(
        _refusalClause(result.decision),
        'approval: missing grid.approved label',
      );
    },
  );

  test(
    'MountEligibilityAssets refusal recheck preserves validation first',
    () async {
      final result = await _runSuccessfulRefusalRecheck(
        const Bead(id: 'pow-test', metadata: {}, labels: []),
      );
      expect(_refusalClause(result.decision), 'validation_plan: missing');
    },
  );

  test(
    'MountEligibilityAssets refusal recheck clears a stale refusal',
    () async {
      final result = await _runSuccessfulRefusalRecheck(
        const Bead(
          id: 'pow-test',
          metadata: {
            'validation_plan': 'dart test',
            'grid.approved_at': '2026-09-02T14:30:00.000Z',
          },
          labels: ['grid.approved'],
        ),
      );
      expect(result.decision, isA<MountEligible>());
    },
  );

  test(
    'MountEligibilityAssets eligible snapshot is synchronous and query-free',
    () {
      final runner = _RecordingMountBdRunner(
        (_) async => throw StateError('eligible snapshot queried bd'),
      );
      final mounted = _mountEligibilityAsset((_) => runner);

      expect(mounted.bundle(), isNotNull);
      final decision = mounted.bundle()!.mountEligibility!(
        const Bead(
          id: 'pow-test',
          metadata: {
            'validation_plan': 'dart test',
            'grid.approved_at': '2026-09-02T14:30:00.000Z',
          },
          labels: ['grid.approved'],
        ),
      );
      expect(decision, isA<MountEligible>());
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'MountEligibilityAssets failed refusal recheck is a loud refusal',
    () async {
      final clause = await _runFailedRefusalRecheck(
        _RecordingMountBdRunner(
          (_) async => const BdResult(
            exitCode: 1,
            stdout: '',
            stderr: 'query failed at store',
          ),
        ),
      );
      expect(clause, contains('fresh mount-eligibility read failed'));
      expect(clause, contains('query failed at store'));
    },
  );

  test(
    'MountEligibilityAssets timed-out refusal recheck is a loud refusal',
    () async {
      final clause = await _runFailedRefusalRecheck(
        _RecordingMountBdRunner(
          (_) => Future<BdResult>.error(
            const BdTimeoutException(
              command: ['bd', 'query', 'id=pow-test'],
              timeout: Duration(seconds: 15),
            ),
          ),
        ),
      );
      expect(clause, contains('fresh mount-eligibility read failed'));
      expect(clause, contains('bd timed out after 15000ms'));
    },
  );

  test('GitGridAssets stays deterministic and commit-only while offline', () {
    ServiceBundle? observed;
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _underSubstation(
          'power_station',
          '/work/ps',
          GitGridAssets(
            child: _Probe(
              (context) => observed = context
                  .dependOnInheritedSeedOfExactType<ServiceBundle>(),
            ),
          ),
        ),
      ),
    );
    owner.flush();
    final sourceControl = observed!.sourceControl!;
    expect(sourceControl, isA<GitSourceControl>());
    expect(
      sourceControl.workspaceFor('pow-1'),
      '/work/ps/.grid/worktrees/power_station/pow-1',
    );
    expect(sourceControl.branchFor('pow-1'), 'grid/pow-1');
    expect(sourceControl.baseBranch, 'main');
    expect(observed!.delivery, isNull);
  });

  test('GitGridAssets watches and rebinds StationGitService', () async {
    final first = StationGitService(
      runner: _FakeGitRunner(),
      prOpener: _FakePrOpener(),
    );
    final second = StationGitService(
      runner: _FakeGitRunner(),
      prOpener: _FakePrOpener(),
    );
    ServiceBundle? observed;
    late _HostState host;
    final probe = _Probe(
      (context) =>
          observed = context.dependOnInheritedSeedOfExactType<ServiceBundle>(),
    );
    Seed describe(StationGitService service) =>
        Provider<StationGitService>.value(
          service,
          child: _underSubstation(
            'power_station',
            '/work/ps',
            GitGridAssets(child: probe),
          ),
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
    final before = observed!.sourceControl;
    host.swap(() => describe(second));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();
    expect(observed!.sourceControl, isNot(same(before)));
    expect(
      observed!.sourceControl!.workspaceFor('pow-2'),
      '/work/ps/.grid/worktrees/power_station/pow-2',
    );
  });

  test(
    'DerivedServiceBundleSeed notifies only for changed derivation inputs',
    () async {
      late _HostState host;
      var builds = 0;
      final dependent = _BundleDependent(() => builds++);
      Seed describe(Object input) => DerivedServiceBundleSeed(
        value: const ServiceBundle(),
        derivedFrom: [input],
        child: dependent,
      );
      final owner = TreeOwner();
      owner.mountRoot(
        _Host(onCreate: (state) => host = state, describe: () => describe('a')),
      );
      owner.flush();
      expect(builds, 1);
      host.swap(() => describe('a'));
      owner.flush();
      await Future<void>.delayed(Duration.zero);
      owner.flush();
      expect(builds, 1);
      host.swap(() => describe('b'));
      owner.flush();
      await Future<void>.delayed(Duration.zero);
      owner.flush();
      expect(builds, 2);
    },
  );

  test('GitGridAssets refuses loudly without SubstationScope', () {
    final owner = TreeOwner();
    expect(() {
      owner.mountRoot(
        const sdk.ProviderScope(child: GitGridAssets(child: _Leaf())),
      );
      owner.flush();
    }, throwsStateError);
  });

  test('GitServices remains a subscribing compatibility carrier', () {
    const services = GitServices();
    GitServices? observed;
    final owner = TreeOwner();
    owner.mountRoot(
      InheritedSeed<GitServices>(
        value: services,
        child: _Probe((context) => observed = GitServices.maybeOf(context)),
      ),
    );
    owner.flush();
    expect(observed, same(services));
  });
}
