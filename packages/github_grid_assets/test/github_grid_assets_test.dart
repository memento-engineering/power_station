import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
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
  const _SourceControl();
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

Seed _providers({
  required bool ops,
  required bool opener,
  required Seed child,
}) {
  var wired = child;
  if (opener) {
    wired = Provider<PrOpener>.value(_FakePrOpener(), child: wired);
  }
  if (ops) {
    wired = Provider<GitOps>.value(GitOps(_FakeGitRunner()), child: wired);
  }
  return wired;
}

void main() {
  test(
    'binds only with checkout, ops, and opener and preserves bundle fields',
    () {
      const sourceControl = _SourceControl();
      final escalation = _Escalation();
      final trust = _Trust();
      const floor = TrustFloor(TrustLevel.self);
      final transport = _Transport();
      final ambient = ServiceBundle(
        sourceControl: sourceControl,
        escalation: escalation,
        trust: trust,
        trustFloor: floor,
        transport: transport,
      );
      ServiceBundle? bound;
      final owner = TreeOwner();
      owner.mountRoot(
        sdk.ProviderScope(
          child: _providers(
            ops: true,
            opener: true,
            child: InheritedSeed<ServiceBundle>(
              value: ambient,
              child: GitHubGridAssets(
                child: _Probe(
                  (context) => bound = context
                      .dependOnInheritedSeedOfExactType<ServiceBundle>(),
                ),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      expect(bound!.sourceControl, same(sourceControl));
      expect(bound!.delivery, isA<GitHubPrDelivery>());
      expect(bound!.escalation, same(escalation));
      expect(bound!.trust, same(trust));
      expect(bound!.trustFloor, same(floor));
      expect(bound!.transport, same(transport));
    },
  );

  for (final halves in [(true, false), (false, true), (false, false)]) {
    test('stays unbound with ops=${halves.$1}, opener=${halves.$2}', () {
      const ambient = ServiceBundle(sourceControl: _SourceControl());
      ServiceBundle? observed;
      final owner = TreeOwner();
      final root = owner.mountRoot(
        sdk.ProviderScope(
          child: _providers(
            ops: halves.$1,
            opener: halves.$2,
            child: const InheritedSeed<ServiceBundle>(
              value: ambient,
              child: GitHubGridAssets(child: _Leaf()),
            ),
          ),
        ),
      );
      owner.flush();
      void walk(Branch branch) {
        if (branch is InheritedBranch<ServiceBundle>) observed = branch.value;
        branch.visitChildren(walk);
      }

      walk(root);
      expect(observed!.delivery, isNull);
    });
  }

  test('standalone asset never conjures delivery without source control', () {
    final owner = TreeOwner();
    final root = owner.mountRoot(
      sdk.ProviderScope(
        child: _providers(
          ops: true,
          opener: true,
          child: const GitHubGridAssets(child: _Leaf()),
        ),
      ),
    );
    owner.flush();
    var bundles = 0;
    void walk(Branch branch) {
      if (branch is InheritedBranch<ServiceBundle>) bundles++;
      branch.visitChildren(walk);
    }

    walk(root);
    expect(bundles, 0);
  });

  test('composition mounts independently while delivery is unbound', () {
    const knob = PrComposition(trailerToken: 'Bead');
    PrComposition? observed;
    final owner = TreeOwner();
    final root = owner.mountRoot(
      const sdk.ProviderScope(
        child: GitHubGridAssets(composition: knob, child: _Leaf()),
      ),
    );
    owner.flush();
    void walk(Branch branch) {
      if (branch is InheritedBranch<PrComposition>) observed = branch.value;
      branch.visitChildren(walk);
    }

    walk(root);
    expect(observed, same(knob));
  });

  test('provider transitions bind and unbind delivery', () async {
    late _HostState host;
    ServiceBundle? observed;
    final probe = _Probe(
      (context) =>
          observed = context.dependOnInheritedSeedOfExactType<ServiceBundle>(),
    );
    Seed describe(bool opener) => _providers(
      ops: true,
      opener: opener,
      child: InheritedSeed<ServiceBundle>(
        value: const ServiceBundle(sourceControl: _SourceControl()),
        child: GitHubGridAssets(child: probe),
      ),
    );
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () => describe(false),
        ),
      ),
    );
    owner.flush();
    expect(observed!.delivery, isNull);
    host.swap(() => describe(true));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();
    expect(observed!.delivery, isA<GitHubPrDelivery>());
    host.swap(() => describe(false));
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();
    expect(observed!.delivery, isNull);
  });

  test('equal delivery derivation does not notify dependents', () async {
    final ops = GitOps(_FakeGitRunner());
    final opener = _FakePrOpener();
    late _HostState host;
    var builds = 0;
    final dependent = _BundleDependent(() => builds++);
    Seed describe() => Provider<GitOps>.value(
      ops,
      child: Provider<PrOpener>.value(
        opener,
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(sourceControl: _SourceControl()),
          child: GitHubGridAssets(child: dependent),
        ),
      ),
    );
    final owner = TreeOwner();
    owner.mountRoot(
      sdk.ProviderScope(
        child: _Host(onCreate: (state) => host = state, describe: describe),
      ),
    );
    owner.flush();
    expect(builds, 1);
    host.swap(describe);
    owner.flush();
    await Future<void>.delayed(Duration.zero);
    owner.flush();
    expect(builds, 1);
  });
}
