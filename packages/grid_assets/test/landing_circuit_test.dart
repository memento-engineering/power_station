// The LANDING circuit (bead `tg-rm5`) — rebase → revalidate → land, unit-level
// (the full-kernel wiring is proven end-to-end by
// `acceptance/circuit_acceptance_test.dart`). Zero I/O — fakes only.
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

({FakeTreeContext context, StepArgs args}) _capCtx({
  SourceControl? sourceControl,
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
      ServiceBundle: ServiceBundle(sourceControl: sourceControl),
    },
  ),
  args: stepArgs('tg-1/land/rebase'),
);

/// A minimal [SourceControl] fake with `canLand` settable — [RebaseCapability]/
/// [RevalidateCapability] only read `canLand` off it (the workspace/branch
/// layout methods are never called by either).
class _FakeLandableSourceControl implements SourceControl {
  _FakeLandableSourceControl({this.canLand = true});

  @override
  bool canLand;

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
  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) async {}
  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {}
  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async => null;
}

void main() {
  group('RebaseCapability', () {
    test('no SourceControl wired → Ok, no git call at all (commit-only '
        'posture, --land off)', () async {
      final runner = RecordingGitRunner();
      final c = _capCtx();
      final outcome = await RebaseCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(runner.calls, isEmpty);
    });

    test('canLand=false → Ok, no git call at all', () async {
      final runner = RecordingGitRunner();
      final c = _capCtx(
        sourceControl: _FakeLandableSourceControl(canLand: false),
      );
      final outcome = await RebaseCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(runner.calls, isEmpty);
    });

    test('a clean fetch+rebase → Ok({outcome: clean})', () async {
      final runner = RecordingGitRunner();
      final c = _capCtx(sourceControl: _FakeLandableSourceControl());
      final outcome = await RebaseCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'outcome': 'clean'});
      expect(runner.subcommands, ['fetch', 'rebase']);
      expect(runner.calls[0].args, ['fetch', 'origin', 'main']);
      expect(runner.calls[1].args, ['rebase', 'origin/main']);
    });

    test('a fetch failure → Failed (an operational error, not a human gate)',
        () async {
      final runner = RecordingGitRunner()..exitCode = 1;
      final c = _capCtx(sourceControl: _FakeLandableSourceControl());
      final outcome = await RebaseCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Failed>());
      expect(runner.subcommands, ['fetch'],
          reason: 'a fetch failure never attempts the rebase');
    });

    test('a rebase conflict aborts the rebase and Gates with the git output '
        'as provenance — never a silent force', () async {
      final runner = _ConflictingRebaseRunner();
      final c = _capCtx(sourceControl: _FakeLandableSourceControl());
      final outcome = await RebaseCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect(
        (outcome as Gate).reason,
        contains('CONFLICT (content): Merge conflict in a.txt'),
      );
      expect(
        runner.subcommands,
        ['fetch', 'rebase', 'rebase'],
        reason: 'the second rebase call is the --abort',
      );
      expect(runner.calls.last.args, ['rebase', '--abort']);
    });
  });

  group('RevalidateCapability', () {
    test('no SourceControl wired → Ok, no shell exec at all (commit-only '
        'posture, --land off)', () async {
      final runner = RecordingShellRunner();
      final c = _capCtx();
      final outcome = await RevalidateCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(runner.calls, isEmpty);
    });

    test('canLand=false → Ok, no shell exec at all', () async {
      final runner = RecordingShellRunner();
      final c = _capCtx(
        sourceControl: _FakeLandableSourceControl(canLand: false),
      );
      final outcome = await RevalidateCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(runner.calls, isEmpty);
    });

    test('re-runs the bead\'s OWN validation_plan; a clean exit → '
        'Ok({outcome: passed})', () async {
      final runner = RecordingShellRunner();
      final richBead = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'melos test'},
      );
      final c = _capCtx(
        sourceControl: _FakeLandableSourceControl(),
        beadOverride: richBead,
      );
      final outcome = await RevalidateCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'outcome': 'passed'});
      expect(runner.calls.single.command, 'melos test');
      expect(runner.calls.single.workingDirectory, '/w/tg-1');
    });

    test('a plan-less bead defaults to `false` (an explicit non-zero) — '
        'Gates rather than silently passing', () async {
      // The recording fake doesn't actually EXEC the command — it just
      // returns a canned result — so exitCode is set explicitly to model
      // what a real `false` would do (never silently pass).
      final runner = RecordingShellRunner()..exitCode = 1;
      final c = _capCtx(sourceControl: _FakeLandableSourceControl());
      final outcome = await RevalidateCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect(runner.calls.single.command, 'false');
    });

    test('a non-zero validation_plan Gates with the captured output as '
        'provenance — never a silent advance', () async {
      final runner = RecordingShellRunner()..exitCode = 1;
      final richBead = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'melos test'},
      );
      final c = _capCtx(
        sourceControl: _FakeLandableSourceControl(),
        beadOverride: richBead,
      );
      final outcome = await RevalidateCapability(runner: runner)
          .run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect((outcome as Gate).reason, contains('revalidate failed'));
    });
  });

  group('buildCircuitReceipt', () {
    test('assembles the rebase/revalidate outcomes + the review route\'s '
        'grade provenance when all three are present', () {
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
      final receipt =
          buildCircuitReceipt(beadId: 'tg-1', siblings: siblings);
      expect(receipt, contains('## Circuit receipt'));
      expect(receipt, contains('- rebase: clean'));
      expect(receipt, contains('- revalidate: passed'));
      expect(
        receipt,
        contains(
          '- review: grades=code-validation=A,spec-adherence=B '
          'spread=1 rule=all-approve',
        ),
      );
    });

    test('defaults to clean/passed and omits the review line when siblings '
        'carry no data (the offline test-harness gap, never a real gap in '
        'production — land only runs once rebase/revalidate genuinely '
        'advanced)', () {
      const receipt = SiblingView();
      final body =
          buildCircuitReceipt(beadId: 'tg-1', siblings: receipt);
      expect(body, contains('- rebase: clean'));
      expect(body, contains('- revalidate: passed'));
      expect(body, isNot(contains('- review:')));
    });
  });

  group('kLandingCircuit shape', () {
    test('rebase → revalidate → land, in dependency order; land is the '
        'terminal', () {
      expect(kLandingCircuit.id, 'landing');
      expect(kLandingCircuit.terminalStepId, 'land');
      final byId = {for (final s in kLandingCircuit.steps) s.stepId: s};
      expect(byId['rebase']!.dependsOn, isEmpty);
      expect(byId['revalidate']!.dependsOn, {'rebase'});
      expect(byId['land']!.dependsOn, {'revalidate'});
    });
  });
}

/// A [GitRunner] fake that fails ONLY the `rebase` (not `fetch`) call with a
/// realistic conflict transcript — [RebaseCapability]'s conflict-Gate path.
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

  List<String> get subcommands =>
      [for (final c in calls) c.args.isNotEmpty ? c.args.first : ''];
}
