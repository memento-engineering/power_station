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

  group('LandCapability — rework-aware delivery (tg-w3c: the land step is '
      'rework-unaware — a rebased branch\'s push is refused, gh pr create '
      'errors "already exists", the DONE bead escalates)', () {
    // The land step of the landing circuit (`land/land`).
    StepArgs landArgs() => stepArgs('tg-1/land/land');

    test('a rework round rebased the branch + round one\'s PR is still OPEN: '
        'the push is FORCE-WITH-LEASE and the open PR is REUSED → Ok(pr_url), '
        'never an escalation', () async {
      final git = RecordingGitRunner();
      final pr = _AlreadyOpenPrOpener('https://github.com/memento/x/pull/9');
      final sc = GitSourceControl(gitOps: GitOps(git), gitRunner: git, prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, landArgs());
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {
        'pr_url': 'https://github.com/memento/x/pull/9',
      });
      // The push carried `--force-with-lease` ALWAYS (it is the circuit's own
      // branch; the lease guards a racing writer) — never a plain push a
      // rebase refuses non-fast-forward.
      final push = git.calls
          .map((call) => call.args)
          .firstWhere((a) => a.isNotEmpty && a.first == 'push');
      expect(push, ['push', '--force-with-lease', '-u', 'origin', 'grid/tg-1']);
    });

    test('an already-open PR whose url gh did not print is STILL reused (the '
        'branch is delivered, the PR exists) → Ok, never an escalation',
        () async {
      final git = RecordingGitRunner();
      final pr = _AlreadyOpenPrOpener(''); // "already exists" with no url line
      final sc = GitSourceControl(gitOps: GitOps(git), gitRunner: git, prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, landArgs());
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'pr_url': ''});
    });

    test('a force-with-lease push the lease REFUSES (a racing writer moved the '
        'remote) → Failed with the git stderr TAIL as the reason (FT-1 '
        'failureReason), and NEVER opens a PR — never a swallowed push',
        () async {
      final git = _RejectedPushRunner();
      final pr = FakePrOpener();
      final sc = GitSourceControl(gitOps: GitOps(git), gitRunner: git, prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, landArgs());
      expect(outcome, isA<Failed>());
      expect(
        (outcome as Failed).reason,
        contains('force-with-lease push refused'),
      );
      expect(outcome.reason, contains('[rejected]'),
          reason: 'the git stderr tail is stamped so the operator sees WHY');
      expect(pr.opened, isEmpty, reason: 'a refused push never opens a PR');
    });

    test('the normal fresh-open path still lands (force-push + create) → '
        'Ok(pr_url) with the circuit receipt as the PR body', () async {
      final git = RecordingGitRunner();
      final pr = FakePrOpener(url: 'https://github.com/memento/x/pull/7');
      final sc = GitSourceControl(gitOps: GitOps(git), gitRunner: git, prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, landArgs());
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {
        'pr_url': 'https://github.com/memento/x/pull/7',
      });
      expect(git.subcommands, contains('push'));
      expect(pr.opened.single.body, contains('## Circuit receipt'));
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

/// A [PrOpener] that always REFUSES with gh's "a pull request … already exists"
/// transcript (round one's PR is still open) — the rework-round idempotency
/// case. [existingUrl] is echoed on the refusal's url line ('' models a gh that
/// printed no url).
class _AlreadyOpenPrOpener implements PrOpener {
  _AlreadyOpenPrOpener(this.existingUrl);

  final String existingUrl;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.failed(
    PrOpenFailure(
      'gh pr create failed: a pull request for branch "$branch" into branch '
      '"$baseBranch" already exists:\n$existingUrl',
    ),
  );
}

/// A [GitRunner] whose `push` fails (exit 1) with a realistic force-with-lease
/// REJECTION transcript, while add/commit/status succeed — the "lease refused
/// (a racing writer moved the remote)" path. The fatal line is LAST, so the
/// land step's stderr-tail stamping is exercised.
class _RejectedPushRunner implements GitRunner {
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.isNotEmpty && args.first == 'push') {
      return const GitRunResult(
        exitCode: 1,
        output: 'To github.com:memento/x.git\n'
            ' ! [rejected]        grid/tg-1 -> grid/tg-1 (stale info)\n'
            'error: failed to push some refs to '
            "'github.com:memento/x.git'",
      );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}
