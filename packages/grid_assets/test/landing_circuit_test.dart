// The LANDING PREPARATION circuit (bead `tg-rm5`) — rebase → revalidate,
// unit-level (the full-kernel wiring is proven end-to-end by
// `acceptance/circuit_acceptance_test.dart`; the DELIVERY seam that replaced the
// old `land` step has its own suite in `delivery_test.dart`). Fakes only, no I/O.
//
// The ARMED axis is the BUNDLE now, not the source control: "is landing armed?"
// became "which delivery method did this substation bind?", and none is a valid
// binding (M5 D-4a). So a bound `ServiceBundle.delivery` is what makes these two
// steps do real git; unbound, both no-op with ZERO calls.
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show GridAssetDefinition;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';
import 'support/asset_resolution_fixture.dart';

/// The station-generated registry this seat resolves against: one
/// unconditional skill and one gated behind a package the facts may or may not
/// carry — so a FACTS change moves the guard's own path set.
final sdk.GridAssetRegistry _assetRegistry = sdk.GridAssetRegistry(
  <sdk.GridAssetPackDefinition>[
    sdk.GridAssetPackDefinition(
      package: kFixturePackage,
      assets: <GridAssetDefinition>[
        fixtureSkill('discover'),
        fixtureSkill('gated', selector: const sdk.RequiresPackage('grid_sdk')),
      ],
    ),
  ],
);

/// The facts observed at the seat's root; [packages] decides whether the gated
/// asset is selected.
SubstationFactsSnapshot _assetFacts({
  Iterable<String> packages = const <String>[kFixturePackage],
}) => SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
  const SubstationKey('seat'): SubstationFacts(
    root: '/w/seat',
    dartPackages: packages,
    packageRoots: const <String, String>{kFixturePackage: '/packs/fixture'},
  ),
});

/// What the resolver says this seat's worktree assets ARE — the value the guard
/// must pass to `git ls-files`, computed the ONE way.
List<String> _ownedPaths(SubstationFactsSnapshot snapshot) => resolveGridAssets(
  registry: _assetRegistry,
  snapshot: snapshot,
  substation: const SubstationKey('seat'),
).artifactsUnder(kWorktreeOverlaySubtrees).map((a) => a.relativePath).toList();

/// A rebase/revalidate context whose ambient bundle binds [delivery] (null ⇒ the
/// commit-only arm). The source control is always present and provisioning-only
/// — neither step reads it.
({FakeTreeContext context, StepArgs args}) _capCtx({
  DeliveryMethod? delivery,
  Bead? beadOverride,
  SubstationFactsSnapshot? facts,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: beadOverride ?? bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: '/w/tg-1',
        branch: 'grid/tg-1',
        baseBranch: 'main',
      ),
      ServiceBundle: ServiceBundle(
        sourceControl: _FakeSourceControl(),
        delivery: delivery,
      ),
      // The ONE resolution's inputs, ambient exactly as the station mounts them.
      SubstationFactsSnapshot: facts ?? _assetFacts(),
      sdk.SubstationScope: const sdk.SubstationScope(
        name: 'seat',
        root: '/w/seat',
        prefix: 'seat',
      ),
    },
  ),
  args: stepArgs('tg-1/land/rebase'),
);

/// The provisioning-only [SourceControl] a substation always has (M5 D-4a
/// stripped commit/push/PR off the interface).
class _FakeSourceControl implements SourceControl {
  @override
  String workspaceFor(String beadId) => '/w/$beadId';
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String get baseBranch => 'main';
  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}

/// A bound [DeliveryMethod] — its mere PRESENCE is what arms rebase/revalidate;
/// neither step ever actuates it (only the root's terminal advance does).
class _FakeDelivery implements DeliveryMethod {
  @override
  String get id => 'fake';
  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async => const Ok();
}

class _FixedShellRunner implements ShellRunner {
  _FixedShellRunner(this.result);

  final ShellRunResult result;
  final calls = <({String workingDirectory, String command})>[];

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async {
    calls.add((workingDirectory: workingDirectory, command: command));
    return result;
  }
}

/// A `dart pub get` preamble on a seat with an outdated lockfile — the block
/// that buried the real failure in bead `pow-gy41`'s live receipt.
/// Deliberately longer than 3000 characters on its own.
String _pubAdviceBlock({int packages = 70}) {
  final buffer = StringBuffer()
    ..writeln('Resolving dependencies in `/w/tg-1`...')
    ..writeln('Downloading packages...');
  for (var i = 0; i < packages; i++) {
    buffer.writeln('  outdated_package_number_$i 1.0.$i (2.0.$i available)');
  }
  buffer
    ..writeln('Got 120 dependencies!')
    ..writeln(
      '$packages packages have newer versions incompatible with dependency '
      'constraints.',
    )
    ..writeln('Try `dart pub outdated` for more information.');
  return buffer.toString();
}

/// What `dart test` prints when it fails — the part an operator actually needs,
/// and the part the old HEAD truncation threw away.
const _dartTestFailure = '''
00:02 +512 -1: test/foo_test.dart: renders the widget [E]
  Expected: <42>
    Actual: <41>
  package:test_api                     expect
  test/foo_test.dart 88:7              main.<fn>

00:02 +512 -1: Some tests failed.''';

void main() {
  group('RebaseCapability', () {
    test(
      'NO delivery bound → Advance, no git call at all (the commit-only '
      'arm: nothing leaves the station, so there is nothing to rebase ONTO)',
      () async {
        final runner = RecordingGitRunner();
        final c = _capCtx();
        final outcome = await RebaseCapability(
          runner: runner,
          assetRegistry: _assetRegistry,
        ).route(c.context, c.args);
        expect(outcome, isA<Advance>());
        expect(runner.calls, isEmpty);
      },
    );

    test('a clean fetch+rebase → Advance({outcome: clean})', () async {
      final runner = RecordingGitRunner();
      final c = _capCtx(delivery: _FakeDelivery());
      final outcome = await RebaseCapability(
        runner: runner,
        assetRegistry: _assetRegistry,
      ).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect((outcome as Advance).payload, {'outcome': 'clean'});
      expect(runner.subcommands, ['ls-files', 'status', 'fetch', 'rebase']);
      expect(runner.calls[2].args, ['fetch', 'origin', 'main']);
      expect(runner.calls[3].args, ['rebase', 'origin/main']);
    });

    test('only materializer-owned dirt is restored before rebase', () async {
      final runner = _MaterializerAwareRebaseRunner(
        tracked: '.claude/skills/discover/SKILL.md\n',
      );
      final c = _capCtx(delivery: _FakeDelivery());
      final outcome = await RebaseCapability(
        runner: runner,
        assetRegistry: _assetRegistry,
      ).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect(runner.subcommands, [
        'ls-files',
        'restore',
        'status',
        'fetch',
        'rebase',
      ]);
      expect(runner.calls[0].args, [
        'ls-files',
        '--',
        ..._ownedPaths(_assetFacts()),
      ]);
      expect(runner.calls[1].args, [
        'restore',
        '--source=HEAD',
        '--staged',
        '--worktree',
        '--',
        '.claude/skills/discover/SKILL.md',
      ]);
    });

    test(
      'rendered dirt plus real dirt blocks and names the real path',
      () async {
        final runner = _MaterializerAwareRebaseRunner(
          tracked: '.claude/skills/discover/SKILL.md\n',
          status: ' M lib/src/agent_work.dart\n',
        );
        final c = _capCtx(delivery: _FakeDelivery());
        final outcome = await RebaseCapability(
          runner: runner,
          assetRegistry: _assetRegistry,
        ).route(c.context, c.args);
        expect(outcome, isA<Escalate>());
        expect(
          (outcome as Escalate).reason,
          contains('lib/src/agent_work.dart'),
        );
        expect(runner.subcommands, ['ls-files', 'restore', 'status']);
      },
    );

    test('materializer cleanup git failure is loud', () async {
      final runner = _MaterializerAwareRebaseRunner(
        tracked: '.claude/skills/discover/SKILL.md\n',
        failSubcommand: 'restore',
      );
      final c = _capCtx(delivery: _FakeDelivery());
      await expectLater(
        RebaseCapability(
          runner: runner,
          assetRegistry: _assetRegistry,
        ).route(c.context, c.args),
        throwsA(isA<RouteFailure>()),
      );
      expect(runner.subcommands, ['ls-files', 'restore']);
    });

    test(
      'a fetch failure → a thrown RouteFailure (an operational error, not a '
      'human hold; a route has no failure ARM, so throwing IS the channel)',
      () async {
        final runner = _MaterializerAwareRebaseRunner(
          tracked: '',
          failSubcommand: 'fetch',
        );
        final c = _capCtx(delivery: _FakeDelivery());
        await expectLater(
          RebaseCapability(
            runner: runner,
            assetRegistry: _assetRegistry,
          ).route(c.context, c.args),
          throwsA(isA<RouteFailure>()),
        );
        expect(runner.subcommands, [
          'ls-files',
          'status',
          'fetch',
        ], reason: 'a fetch failure never attempts the rebase');
      },
    );

    test(
      'a rebase conflict aborts the rebase and ESCALATES with the git output '
      'as provenance — never a silent force',
      () async {
        final runner = _ConflictingRebaseRunner();
        final c = _capCtx(delivery: _FakeDelivery());
        final outcome = await RebaseCapability(
          runner: runner,
          assetRegistry: _assetRegistry,
        ).route(c.context, c.args);
        expect(outcome, isA<Escalate>());
        expect(
          (outcome as Escalate).reason,
          contains('CONFLICT (content): Merge conflict in a.txt'),
        );
        expect(runner.subcommands, [
          'ls-files',
          'status',
          'fetch',
          'rebase',
          'rebase',
        ], reason: 'the second rebase call is the --abort');
        expect(runner.calls.last.args, ['rebase', '--abort']);
      },
    );
  });

  group('the pre-rebase guard rides the ONE resolution', () {
    test('resolver-selected owned paths change with substation facts across '
        'rebase', () async {
      // BEFORE: the gated asset's package is absent, so the guard owns two
      // paths. AFTER: the package appears and the guard owns four — the SAME
      // move the provision writer just made.
      final before = _assetFacts();
      final after = _assetFacts(
        packages: const <String>[kFixturePackage, 'grid_sdk'],
      );
      expect(_ownedPaths(before), hasLength(2));
      expect(_ownedPaths(after), hasLength(4));

      final firstRunner = _MaterializerAwareRebaseRunner(
        tracked: '${_ownedPaths(before).join('\n')}\n',
      );
      final firstOutcome =
          await RebaseCapability(
            runner: firstRunner,
            assetRegistry: _assetRegistry,
          ).route(
            _capCtx(delivery: _FakeDelivery(), facts: before).context,
            stepArgs('tg-1/land/rebase'),
          );
      final secondRunner = _MaterializerAwareRebaseRunner(
        tracked: '${_ownedPaths(after).join('\n')}\n',
      );
      final secondOutcome =
          await RebaseCapability(
            runner: secondRunner,
            assetRegistry: _assetRegistry,
          ).route(
            _capCtx(delivery: _FakeDelivery(), facts: after).context,
            stepArgs('tg-1/land/rebase'),
          );

      expect(firstOutcome, isA<Advance>());
      expect(secondOutcome, isA<Advance>());
      expect(firstRunner.calls[0].args, [
        'ls-files',
        '--',
        ..._ownedPaths(before),
      ]);
      expect(secondRunner.calls[0].args, [
        'ls-files',
        '--',
        ..._ownedPaths(after),
      ]);
      expect(
        secondRunner.calls[0].args,
        isNot(firstRunner.calls[0].args),
        reason:
            'a facts change moves the guard set, exactly as it moves the '
            'writer set',
      );
      // The restore is the EXACT selected set, never a subtree prefix.
      expect(secondRunner.calls[1].args, [
        'restore',
        '--source=HEAD',
        '--staged',
        '--worktree',
        '--',
        ..._ownedPaths(after),
      ]);

      // Generated residue under BOTH harness heads is the writer's own render:
      // the rebase proceeds.
      final generatedResidue = _MaterializerAwareRebaseRunner(
        tracked: '${_ownedPaths(after).join('\n')}\n',
        status:
            ' M ${p.join('.claude', 'skills', 'discover', 'SKILL.md')}\n'
            '?? ${p.join('.agents', 'skills', 'gated', '.gitignore')}\n',
      );
      final proceeds =
          await RebaseCapability(
            runner: generatedResidue,
            assetRegistry: _assetRegistry,
          ).route(
            _capCtx(delivery: _FakeDelivery(), facts: after).context,
            stepArgs('tg-1/land/rebase'),
          );
      expect(proceeds, isA<Advance>());
      expect(generatedResidue.subcommands, [
        'ls-files',
        'restore',
        'status',
        'fetch',
        'rebase',
      ]);

      // Unrelated residue still REFUSES — exit-code-led, advice-stripped, and
      // TAIL-cut through the shared helpers
      // (`power_station#captured-process-output-escalates-tail-first`).
      const unrelated = ' M lib/src/agent_work.dart';
      final mixed = _MaterializerAwareRebaseRunner(
        tracked: '${_ownedPaths(after).join('\n')}\n',
        status:
            ' M ${p.join('.claude', 'skills', 'discover', 'SKILL.md')}\n'
            '$unrelated\n',
      );
      final refused =
          await RebaseCapability(
            runner: mixed,
            assetRegistry: _assetRegistry,
          ).route(
            _capCtx(delivery: _FakeDelivery(), facts: after).context,
            stepArgs('tg-1/land/rebase'),
          );
      expect(refused, isA<Escalate>());
      expect(
        (refused as Escalate).reason,
        'rebase refused (exit 0): uncommitted changes remain outside '
        'materialized assets: '
        '${landReasonTail(planOutputWithoutPubAdvice(unrelated), kRevalidateReasonTailChars)}',
      );
      expect(mixed.subcommands, ['ls-files', 'restore', 'status']);
    });

    test(
      'a RENAME out of a materialized head still refuses — both sides of the '
      'record must be generated territory',
      () async {
        final runner = _MaterializerAwareRebaseRunner(
          tracked: '',
          status:
              'R  ${p.join('.claude', 'skills', 'discover', 'SKILL.md')} -> '
              '${p.join('docs', 'SKILL.md')}\n',
        );
        final outcome =
            await RebaseCapability(
              runner: runner,
              assetRegistry: _assetRegistry,
            ).route(
              _capCtx(delivery: _FakeDelivery()).context,
              stepArgs('tg-1/land/rebase'),
            );

        expect(outcome, isA<Escalate>());
        expect(
          (outcome as Escalate).reason,
          contains(p.join('docs', 'SKILL.md')),
        );
      },
    );

    test('a rename WITHIN the materialized heads (quoted paths included) does '
        'not block the rebase', () async {
      final runner = _MaterializerAwareRebaseRunner(
        tracked: '',
        status:
            'R  "${p.join('.claude', 'skills', 'a b', 'SKILL.md')}" -> '
            '"${p.join('.agents', 'skills', 'a b', 'SKILL.md')}"\n',
      );
      final outcome =
          await RebaseCapability(
            runner: runner,
            assetRegistry: _assetRegistry,
          ).route(
            _capCtx(delivery: _FakeDelivery()).context,
            stepArgs('tg-1/land/rebase'),
          );

      expect(outcome, isA<Advance>());
    });

    test('a status FAILURE is loud, and a cancelled route throws before the '
        'refusal is even assembled', () async {
      final failing = _MaterializerAwareRebaseRunner(
        tracked: '',
        failSubcommand: 'status',
      );
      await expectLater(
        RebaseCapability(runner: failing, assetRegistry: _assetRegistry).route(
          _capCtx(delivery: _FakeDelivery()).context,
          stepArgs('tg-1/land/rebase'),
        ),
        throwsA(isA<RouteFailure>()),
      );

      final cancel = CancelToken()..cancel();
      final cancelled = _MaterializerAwareRebaseRunner(
        tracked: '${_ownedPaths(_assetFacts()).join('\n')}\n',
      );
      await expectLater(
        RebaseCapability(
          runner: cancelled,
          assetRegistry: _assetRegistry,
        ).route(
          _capCtx(delivery: _FakeDelivery()).context,
          StepArgs(nodePath: 'tg-1/land/rebase', cancel: cancel),
        ),
        throwsA(same(kRouteCancelled)),
      );
      expect(cancelled.subcommands, ['ls-files']);
    });

    test('with NO registry injected the guard skips restoration entirely — the '
        'explicit disabled posture, not a silent empty set', () async {
      final runner = _MaterializerAwareRebaseRunner(tracked: 'ignored\n');
      final outcome = await RebaseCapability(runner: runner).route(
        _capCtx(delivery: _FakeDelivery()).context,
        stepArgs('tg-1/land/rebase'),
      );

      expect(outcome, isA<Advance>());
      expect(runner.subcommands, ['status', 'fetch', 'rebase']);
    });
  });

  group('RevalidateCapability', () {
    test('NO delivery bound → Advance, no shell exec at all (the commit-only '
        'arm)', () async {
      final runner = RecordingShellRunner();
      final c = _capCtx();
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect(runner.calls, isEmpty);
    });

    test('re-runs the bead\'s OWN validation_plan; a clean exit → '
        'Advance({outcome: passed})', () async {
      final runner = RecordingShellRunner();
      final richBead = bead(
        'tg-1',
      ).copyWith(metadata: const {'validation_plan': 'melos test'});
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect((outcome as Advance).payload, {'outcome': 'passed'});
      expect(runner.calls.single.command, 'melos test');
      expect(runner.calls.single.workingDirectory, '/w/tg-1');
    });

    test('a plan-less bead defaults to `false` (an explicit non-zero) — '
        'ESCALATES rather than silently passing', () async {
      // The recording fake doesn't actually EXEC the command — it just
      // returns a canned result — so exitCode is set explicitly to model
      // what a real `false` would do (never silently pass).
      final runner = RecordingShellRunner()..exitCode = 1;
      final c = _capCtx(delivery: _FakeDelivery());
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      expect(runner.calls.single.command, 'false');
    });

    test('a non-zero validation_plan ESCALATES with the captured output as '
        'provenance — never a silent advance', () async {
      final runner = RecordingShellRunner()..exitCode = 1;
      final richBead = bead(
        'tg-1',
      ).copyWith(metadata: const {'validation_plan': 'melos test'});
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      expect((outcome as Escalate).reason, 'revalidate failed (exit 1): ');
      expect((outcome).reason, isNot(contains('candidate missing commands')));
    });

    test('exit 127 retains output and appends candidate commands', () async {
      final runner = _FixedShellRunner(
        const ShellRunResult(exitCode: 127, output: 'sh: rg: not found'),
      );
      final richBead = bead(
        'tg-1',
      ).copyWith(metadata: const {'validation_plan': 'rg needle'});
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      expect(
        (outcome as Escalate).reason,
        'revalidate failed (exit 127); '
        'exit 127 — candidate missing commands: rg: '
        'sh: rg: not found',
      );
      expect(runner.calls.single.command, 'rg needle');
    });

    test('the pub advisory block is stripped and the TAIL kept — the fatal '
        'line survives exactly where the old HEAD truncation cut it '
        '(pow-gy41)', () async {
      final noise = _pubAdviceBlock();
      expect(noise.length, greaterThan(3000), reason: 'the receipt shape');
      final runner = _FixedShellRunner(
        ShellRunResult(exitCode: 1, output: '$noise$_dartTestFailure'),
      );
      final richBead = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'dart pub get && dart test'},
      );
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      final reason = (outcome as Escalate).reason;
      expect(reason, startsWith('revalidate failed (exit 1): '));
      expect(reason, contains('test/foo_test.dart: renders the widget [E]'));
      expect(reason, contains('Some tests failed.'));
      expect(reason, isNot(contains(' available)')));
      expect(reason, isNot(contains('… (truncated)')));
      expect(reason.length, lessThanOrEqualTo(1600));
    });

    test(
      'output still over the tail budget after stripping is cut at the '
      'START — landReasonTail\'s leading …, never the head (pow-gy41)',
      () async {
        final long = '${'noise line\n' * 400}FATAL: the real error';
        final runner = _FixedShellRunner(
          ShellRunResult(exitCode: 2, output: long),
        );
        final richBead = bead(
          'tg-1',
        ).copyWith(metadata: const {'validation_plan': 'dart test'});
        final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
        final outcome = await RevalidateCapability(
          runner: runner,
        ).route(c.context, c.args);
        expect(outcome, isA<Escalate>());
        final reason = (outcome as Escalate).reason;
        expect(reason, startsWith('revalidate failed (exit 2): …'));
        expect(reason, endsWith('FATAL: the real error'));
        expect(
          reason.length,
          kRevalidateReasonTailChars + 29,
          reason: 'the 28-char prefix + the … cut marker + the last 1500 chars',
        );
      },
    );
  });

  group('buildCircuitReceipt', () {
    test(
      'assembles the landing circuit\'s OWN provenance — rebase/revalidate; '
      'the review grades line MOVED to PrSection.committeeGrades (pow-8dx)',
      () {
        const siblings = SiblingView(
          results: {
            'tg-1/review/route': {
              'grades': 'code-validation=A,spec-adherence=B',
              'spread': '1',
              'rule': 'all-approve',
            },
            'tg-1/land/rebase': {'outcome': 'clean'},
            'tg-1/land/revalidate': {'outcome': 'passed'},
          },
        );
        final receipt = buildCircuitReceipt(beadId: 'tg-1', siblings: siblings);
        expect(receipt, contains('## Circuit receipt'));
        expect(receipt, contains('- rebase: clean'));
        expect(receipt, contains('- revalidate: passed'));
        expect(receipt, isNot(contains('- review:')));
      },
    );

    test('defaults to clean/passed when siblings carry no data (the offline '
        'test-harness gap, never a real gap in production — land only runs once '
        'rebase/revalidate genuinely advanced)', () {
      final receipt = buildCircuitReceipt(
        beadId: 'tg-1',
        siblings: const SiblingView(),
      );
      expect(receipt, contains('- rebase: clean'));
      expect(receipt, contains('- revalidate: passed'));
    });
  });

  group('kLandingCircuit shape', () {
    test('rebase → revalidate, in dependency order; revalidate is the terminal '
        '— the circuit PREPARES and carries NO land step (the PR is no longer a '
        'step: the root circuit\'s terminal route actuates delivery)', () {
      expect(kLandingCircuit.id, 'landing');
      expect(kLandingCircuit.terminalStepId, 'revalidate');
      final byId = {for (final s in kLandingCircuit.steps) s.stepId: s};
      expect(byId.keys.toList(), ['rebase', 'revalidate']);
      expect(byId['rebase']!.dependsOn, isEmpty);
      expect(byId['revalidate']!.dependsOn, {'rebase'});
      expect(byId['land'], isNull);
    });
  });

  group('rework-aware delivery helpers (tg-w3c)', () {
    test('isPrAlreadyOpen detects gh\'s "already exists" refusal only', () {
      expect(
        isPrAlreadyOpen(
          'a pull request for branch "grid/tg-1" into branch "main" already '
          'exists:\nhttps://github.com/memento/x/pull/9',
        ),
        isTrue,
      );
      expect(
        isPrAlreadyOpen('gh pr create failed: authentication required'),
        isFalse,
      );
    });

    test('extractPrUrl pulls the PR url from gh output (a create stdout OR the '
        '"already exists" refusal line), else null', () {
      expect(
        extractPrUrl('…already exists:\nhttps://github.com/memento/x/pull/9'),
        'https://github.com/memento/x/pull/9',
      );
      expect(
        extractPrUrl('https://github.com/memento/x/pull/42\n'),
        'https://github.com/memento/x/pull/42',
      );
      expect(extractPrUrl('no url in this output'), isNull);
    });

    test('landReasonTail keeps the TAIL (the fatal line git/gh print LAST, '
        'since the engine truncates a reason to its FIRST chars), marking a '
        'cut with a leading …', () {
      expect(landReasonTail('short reason'), 'short reason');
      final long = '${'x' * 500}FATAL: the real error';
      final tail = landReasonTail(long, 40);
      expect(tail, startsWith('…'));
      expect(tail, endsWith('FATAL: the real error'));
      expect(tail.length, 41, reason: '… + the last 40 chars');
    });
  });

  group('planOutputWithoutPubAdvice (pow-gy41)', () {
    test('drops pub\'s version-advice lines and both of its trailers', () {
      const input =
          'Resolving dependencies in `/w/tg-1`...\n'
          'Downloading packages...\n'
          '  _fe_analyzer_shared 96.0.0 (107.0.0 available)\n'
          '  analyzer 10.2.0 (14.3.0 available)\n'
          'Got 120 dependencies!\n'
          '44 packages have newer versions incompatible with dependency '
          'constraints.\n'
          'Try `dart pub outdated` for more information.\n'
          'Some tests failed.';
      expect(
        planOutputWithoutPubAdvice(input),
        'Resolving dependencies in `/w/tg-1`...\n'
        'Downloading packages...\n'
        'Got 120 dependencies!\n'
        'Some tests failed.',
      );
    });

    test('leaves every non-advisory line BYTE-IDENTICAL — a lookalike that '
        'merely CONTAINS " available)" mid-line survives whole', () {
      const input =
          'Expected: <42>\n'
          '  analyzer 10.2.0 (14.3.0 available) — cited inside a failure\n'
          '\n'
          '  test/foo_test.dart 88:7  main.<fn>\n'
          'Some tests failed.';
      expect(planOutputWithoutPubAdvice(input), input);
    });

    test('empty output stays empty', () {
      expect(planOutputWithoutPubAdvice(''), '');
    });
  });

  // The ONE assembler every captured-output failure reason rides (bead
  // `pow-39tl`). The bracket holds the ADAPTER and nothing else — the optional
  // diagnostic opens the message, ahead of the log it explains — so the
  // rendered prefix is the same string whether or not a call site names a
  // cause.
  group('capturedOutputReason (bead `pow-39tl`)', () {
    test('is exit-code-led, adapter-named, and keeps the TAIL', () {
      final long = 'FIRST-LINE\n${'x' * 4000}\nFATAL: bd is not on PATH';
      final reason = capturedOutputReason(
        verb: 'specify',
        adapter: 'acp',
        output: long,
        exitCode: 3,
      );
      expect(reason, startsWith('specify failed (exit 3) [acp]: …'));
      expect(reason, contains('FATAL: bd is not on PATH'));
      expect(reason, isNot(contains('FIRST-LINE')));
      expect(
        reason,
        'specify failed (exit 3) [acp]: '
        '${landReasonTail(long, kRevalidateReasonTailChars)}',
      );
    });

    test('a diagnostic opens the message and does NOT move the prefix', () {
      final long = 'HEAD-OF-LOG\n${'y' * 4000}\nbd: command not found';
      final reason = capturedOutputReason(
        verb: 'specify',
        adapter: 'acp',
        output: long,
        exitCode: 0,
        diagnostic: 'declared completion artifact is not durable',
      );
      // The SAME prefix as the no-diagnostic rendering above: the adapter is
      // the bracket's only tenant, so an operator greps one shape.
      expect(reason, startsWith('specify failed (exit 0) [acp]: '));
      expect(
        reason,
        'specify failed (exit 0) [acp]: '
        'declared completion artifact is not durable — '
        '${landReasonTail(long, kRevalidateReasonTailChars)}',
      );
      expect(reason, contains('bd: command not found'));
      expect(reason, isNot(contains('HEAD-OF-LOG')));
    });

    test('a null exit code and empty output stay honest', () {
      expect(
        capturedOutputReason(
          verb: 'specify',
          adapter: 'acp',
          output: '   ',
          diagnostic: 'artifact probe failed',
        ),
        'specify failed (exit unknown) [acp]: '
        'artifact probe failed — <no output captured>',
      );
    });

    test('output inside the budget rides whole, with no cut marker', () {
      expect(
        capturedOutputReason(
          verb: 'acp agent',
          adapter: 'acp',
          output: '  FATAL: could not authenticate\n',
          exitCode: 3,
          diagnostic: 'exited before protocol completion',
        ),
        'acp agent failed (exit 3) [acp]: '
        'exited before protocol completion — FATAL: could not authenticate',
      );
    });
  });
}

class _MaterializerAwareRebaseRunner implements GitRunner {
  _MaterializerAwareRebaseRunner({
    required this.tracked,
    this.status = '',
    this.failSubcommand,
  });

  final String tracked;
  final String status;
  final String? failSubcommand;
  final List<({String workDir, List<String> args})> calls = [];

  List<String> get subcommands => [for (final call in calls) call.args.first];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    if (args.first == failSubcommand) {
      return GitRunResult(exitCode: 1, output: '${args.first} failed');
    }
    return switch (args.first) {
      'ls-files' => GitRunResult(exitCode: 0, output: tracked),
      'status' => GitRunResult(exitCode: 0, output: status),
      _ => const GitRunResult(exitCode: 0, output: ''),
    };
  }
}

/// A [GitRunner] fake that fails ONLY the `rebase` (not `fetch`) call with a
/// realistic conflict transcript — [RebaseCapability]'s conflict-Escalate path.
class _ConflictingRebaseRunner implements GitRunner {
  final List<({String workDir, List<String> args})> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    if (args.first == 'rebase' && args.length > 1 && args[1] != '--abort') {
      return const GitRunResult(
        exitCode: 1,
        output: 'CONFLICT (content): Merge conflict in a.txt',
      );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }

  List<String> get subcommands => [
    for (final c in calls) c.args.isNotEmpty ? c.args.first : '',
  ];
}
