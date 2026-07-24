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
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A rebase/revalidate context whose ambient bundle binds [delivery] (null ⇒ the
/// commit-only arm). The source control is always present and provisioning-only
/// — neither step reads it.
({FakeTreeContext context, StepArgs args}) _capCtx({
  DeliveryMethod? delivery,
  Bead? beadOverride,
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
        ...kWorktreeOverlaySubtrees,
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
        RebaseCapability(runner: runner).route(c.context, c.args),
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
          RebaseCapability(runner: runner).route(c.context, c.args),
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
      expect((outcome as Escalate).reason, 'revalidate failed: ');
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
        'revalidate failed: sh: rg: not found; '
        'exit 127 — candidate missing commands: rg',
      );
      expect(runner.calls.single.command, 'rg needle');
    });
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
