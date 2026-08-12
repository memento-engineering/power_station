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
