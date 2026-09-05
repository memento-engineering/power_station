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

BdResult _depListReply(List<String> blockers) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({
    'schema_version': 1,
    'data': [
      for (final blocker in blockers)
        {'issue_id': 'pow-test', 'depends_on_id': blocker, 'type': 'blocks'},
    ],
  }),
  stderr: '',
);

BdResult _linkListReply(List<String> blockers) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({
    'schema_version': 1,
    'data': [
      for (final blocker in blockers)
        {
          'id': 'tgdog-link-$blocker',
          'issue_type': 'link',
          'status': 'open',
          'metadata': {
            'grid.link.from': 'pow-test',
            'grid.link.to': blocker,
            'grid.link.type': 'blocks',
          },
        },
    ],
  }),
  stderr: '',
);

/// Scripts the whole fresh FILING read: the substation store's exact query and
/// dependency rows, and the grid state store's open link beads.
Future<BdResult> Function(List<String>) _freshFiling(
  Bead fresh, {
  List<String> blockers = const [],
  List<String> links = const [],
}) =>
    (args) async => switch (args.first) {
      'query' => _queryReply(fresh),
      'dep' => _depListReply(blockers),
      'list' => _linkListReply(links),
      _ => throw StateError('unscripted bd call: \$args'),
    };

/// The three argv the fresh filing read spawns, in order.
const List<List<String>> _freshFilingCalls = [
  ['query', 'id=pow-test', '--all', '--json', '--limit', '0'],
  ['dep', 'list', 'pow-test', '--json'],
  ['list', '-t', 'link', '--status', 'open', '--json', '--limit', '0'],
];

/// A complete receipt of the retired shape: an actor, a UTC instant and a raw
/// store-HEAD git sha, which names no basis to re-derive.
const Map<String, dynamic> _legacyReceipt = {
  'validation_plan': 'dart test',
  'grid.approved_by': 'nico',
  'grid.approved_at': '2026-09-02T14:30:00.000Z',
  'grid.approved_rev': '9f1c2d3e4b5a69788899aabbccddeeff00112233',
};

/// The revision an approve run over [bead] with this dependency basis stamps.
String _revisionOf(
  Bead bead, {
  List<String> blockers = const [],
  Set<String> links = const {},
}) => const FilingContract().evaluate(bead, [
  for (final blocker in blockers)
    BeadDependency(issueId: bead.id, dependsOnId: blocker),
], linkedBlockers: links).approvalRevision;

/// [bead] carrying the receipt the approve verb would write for [rev].
Bead _stamped(Bead bead, String rev) => bead.copyWith(
  metadata: {
    ...bead.metadata,
    kApprovedByKey: 'nico',
    kApprovedAtKey: '2026-09-02T14:30:00.000Z',
    kApprovedRevKey: rev,
  },
);

/// The approved work the bound-receipt probes are about.
const Bead _approvedWork = Bead(
  id: 'pow-test',
  title: 'Approved work',
  description: 'A concrete brief',
  acceptanceCriteria: '- [ ] checked',
  metadata: {'validation_plan': 'dart test'},
  labels: [],
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
    // The grid home encloses the substation exactly as a `RawAssetGrid` does:
    // its state store is where the filing contract reads cross-store link
    // proofs from.
    InheritedSeed<sdk.GridRoot>(
      value: const sdk.GridRoot(path: '/work/grid'),
      child: _underSubstation(
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
_runSuccessfulRefusalRecheck(
  Bead fresh, {
  Bead snapshot = const Bead(id: 'pow-test', metadata: {}, labels: []),
  List<String> blockers = const [],
  List<String> links = const [],
}) async {
  final runner = _RecordingMountBdRunner(
    _freshFiling(fresh, blockers: blockers, links: links),
  );
  final roots = <String>[];
  final mounted = _mountEligibilityAsset((root) {
    roots.add(root);
    return runner;
  });
  expect(mounted.bundle(), isNotNull);

  final pending = mounted.bundle()!.mountEligibility!(snapshot);
  expect(
    _refusalClause(pending),
    'fresh mount-eligibility read pending: pow-test',
  );

  await pumpEventQueue();
  mounted.owner.flush();

  final decision = mounted.bundle()!.mountEligibility!(snapshot);
  expect(mounted.bundle()!.mountEligibility!(snapshot), decision);
  expect(runner.calls, _freshFilingCalls);
  // The work store is the SUBSTATION's; the link proofs come from the grid
  // home's state store, resolved from the ambient root.
  expect(roots, ['/work/ps', '/work/grid/.grid']);
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
        'approval: not approved - run the approve verb',
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
        const Bead(id: 'pow-test', metadata: _legacyReceipt, labels: []),
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
      // A COMPLETE legacy receipt names a store HEAD, not a filing basis:
      // there is nothing to re-derive, so it still mounts without a read.
      final decision = mounted.bundle()!.mountEligibility!(
        const Bead(id: 'pow-test', metadata: _legacyReceipt, labels: []),
      );
      expect(decision, isA<MountEligible>());
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'fresh approval checks reject changed bead and validation plan',
    () async {
      final rev = _revisionOf(_approvedWork);
      final snapshot = _stamped(_approvedWork, rev);

      // The receipt itself is excluded from the basis, so a stamped bead
      // evaluates back to the very revision it carries.
      expect(_revisionOf(snapshot), rev);

      final edited = await _runSuccessfulRefusalRecheck(
        _stamped(_approvedWork.copyWith(description: 'A rewritten brief'), rev),
        snapshot: snapshot,
      );
      expect(
        _refusalClause(edited.decision),
        'approval: stale - rerun the approve verb',
      );

      final replanned = await _runSuccessfulRefusalRecheck(
        _stamped(
          _approvedWork.copyWith(
            metadata: const {'validation_plan': 'dart analyze'},
          ),
          rev,
        ),
        snapshot: snapshot,
      );
      expect(
        _refusalClause(replanned.decision),
        'approval: stale - rerun the approve verb',
      );
    },
  );

  test('fresh approval checks reject changed dependency basis', () async {
    const wired = Bead(
      id: 'pow-test',
      title: 'Approved work',
      description:
          'A concrete brief. Blocked by: pow-one. '
          'BLOCKED on tg-89y8 across stores.',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
      labels: [],
    );
    final rev = _revisionOf(
      wired,
      blockers: const ['pow-one'],
      links: const {'tg-89y8'},
    );
    final snapshot = _stamped(wired, rev);

    final unchanged = await _runSuccessfulRefusalRecheck(
      snapshot,
      snapshot: snapshot,
      blockers: const ['pow-one'],
      links: const ['tg-89y8'],
    );
    expect(unchanged.decision, isA<MountEligible>());

    final unwired = await _runSuccessfulRefusalRecheck(
      snapshot,
      snapshot: snapshot,
      links: const ['tg-89y8'],
    );
    expect(
      _refusalClause(unwired.decision),
      'approval: stale - rerun the approve verb',
    );

    final unlinked = await _runSuccessfulRefusalRecheck(
      snapshot,
      snapshot: snapshot,
      blockers: const ['pow-one'],
    );
    expect(
      _refusalClause(unlinked.decision),
      'approval: stale - rerun the approve verb',
    );
  });

  test('unchanged bound receipt waits for matching fresh revision', () async {
    final snapshot = _stamped(_approvedWork, _revisionOf(_approvedWork));

    // Off the tree there is no evaluation to agree with, so the pure predicate
    // refuses rather than trusting the receipt on its face.
    expect(
      _refusalClause(mountEligibilityDecision(snapshot)),
      'approval: revision not evaluated - fresh filing read required',
    );

    // Mounted, the same receipt stays refused through the pending read and
    // becomes eligible only once the recomputed revision matches.
    final result = await _runSuccessfulRefusalRecheck(
      snapshot,
      snapshot: snapshot,
    );
    expect(result.decision, isA<MountEligible>());
  });

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
