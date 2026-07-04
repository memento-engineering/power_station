// Track H — the agent + land Capability impls + the git SourceControl (§6).
//
// The agent/land OPINIONS are real [Capability] impls: the agent produces the
// coding-agent spawn config (the full-bead prompt + the local-first working
// agreement), and `land` drives commit → push → PR through the pluggable
// [SourceControl] Service. The toy `verify` capability is GONE (M5 "The Circuit"
// — `verify` is now the adversarial committee; that wiring is proven end-to-end
// by circuit_acceptance_test.dart), so this file is the Agent/Land/GitSourceControl
// capability-UNIT file.
//
// ADR-0008 D2 / M4-P1 §6, Track H. Zero I/O — fakes only (the FT-2 result()
// tests read usage files a test writes into a temp dir; no real claude/git).
import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The capability's (ambient tree, per-step args) pair — the context rip-out
/// shape: the Bead/Workspace/ServiceBundle ride the tree as ambient values; the
/// per-step nodePath/cancel ride the args.
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
      ),
      ServiceBundle: ServiceBundle(sourceControl: sourceControl),
    },
  ),
  args: stepArgs('tg-1/agent'),
);

/// The ambient Workspace [_capCtx] mounts (for the brief-parity assertions).
Workspace _workspace() =>
    testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1');

/// A recording [SourceControl] (the land + provision Service, faked).
class _FakeSourceControl implements SourceControl {
  final List<String> calls = [];
  bool prOpens = true;
  bool canProvision = true;

  /// Workspaces this fake "already has" (so provision is idempotent in tests).
  final Set<String> existingWorkspaces = {};

  @override
  bool get canLand => true;

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
  }) async {
    if (existingWorkspaces.contains(workspaceDir)) {
      calls.add('provision-skip:$beadId');
      return;
    }
    if (!canProvision) return;
    existingWorkspaces.add(workspaceDir);
    calls.add('provision:$beadId:$workspaceDir');
  }

  @override
  Future<void> commitAll({required String workspaceDir, required String message}) async =>
      calls.add('commit:$workspaceDir:$message');

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async => calls.add('push:$remote:$branch');

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async {
    calls.add('pr:$branch->$baseBranch:$title');
    return prOpens ? const PrRef('https://github.com/memento/x/pull/7') : null;
  }
}

/// A [GitRunner] fake whose `git status --porcelain` reports residue
/// (uncommitted paths remain) while every other command (add/commit/push)
/// succeeds clean — the "botched land silently committed a SUBSET" scenario
/// (tg-x1j r1).
class _ResidueGitRunner implements GitRunner {
  final List<({String workDir, List<String> args})> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    if (args.isNotEmpty && args.first == 'status') {
      return const GitRunResult(
        exitCode: 0,
        output: ' M lib/src/circuit/session_scope.dart',
      );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

/// A [GitRunner] fake whose `git status --porcelain` probe itself fails (a
/// non-zero exit) while every other command succeeds — the fail-closed
/// "couldn't verify" path, distinct from a confirmed-dirty result.
class _ProbeFailGitRunner implements GitRunner {
  final List<({String workDir, List<String> args})> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    if (args.isNotEmpty && args.first == 'status') {
      return const GitRunResult(exitCode: 1, output: 'fatal: not a git repository');
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

void main() {
  group('Track H — the capabilities reproduce P0 configs/orchestration', () {
    test('AgentCapability spawns headless claude WRAPPED for usage capture in '
        'the worktree (FT-2)', () {
      final c = _capCtx();
      final cfg = const AgentCapability().spawn(c.context, c.args);
      // FT-2: the claude invocation is wrapped in `sh -c` so its
      // `--output-format json` result envelope redirects to the per-step
      // telemetry file; the claude argv (the rendered brief included) rides as
      // sh positional params ("$@"), byte-identical — only the output format +
      // the stdout redirection change.
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(cfg.args[1], contains('.grid/telemetry/tg-1_agent.usage.json'));
      expect(cfg.args[1], contains(r'exec "$@"'));
      expect(cfg.args[2], 'grid-claude'); // $0 label
      // $1.. — the exact claude invocation ("$@" execs it verbatim).
      expect(cfg.args[3], 'claude');
      expect(cfg.args[4], '--dangerously-skip-permissions');
      expect(cfg.args[5], '--output-format');
      expect(cfg.args[6], 'json');
      expect(cfg.args[7], '-p');
      // The rich prompt rides as the FINAL positional (byte-identical brief).
      expect(cfg.args.last, contains('Bead `tg-1`'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('AgentCapability carries the FULL bead + local-first working agreement',
        () {
      final rich = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
        design: 'Use a lossy inter-station gossip bus.',
        acceptanceCriteria: 'A peer heartbeat surfaces within 1s.',
        notes: 'Coexistence-safe; do not touch gc.',
        metadata: const {'rig': 'tgdog'},
      );
      final prompt = buildAgentBrief(rich, _workspace()).render();
      // The full bead — a title-only prompt would starve the agent (A36).
      expect(prompt, contains('# Wire the federation bus'));
      expect(prompt, contains('substation `tgdog`'));
      expect(prompt, contains('## Task\nConnect The Studio to The Dashboard.'));
      expect(prompt, contains('## Design\nUse a lossy inter-station gossip bus.'));
      expect(prompt, contains('## Acceptance criteria'));
      expect(prompt, contains('## Notes\nCoexistence-safe; do not touch gc.'));
      // The local-first working agreement (commit, no push, no PR).
      expect(prompt, contains('/w/tg-1'));
      expect(prompt, contains('branch `grid/tg-1`'));
      expect(prompt, contains('COMMIT'));
      expect(prompt, contains('Do NOT push and do NOT open a pull request'));
      // tg-p9q: completion is OBSERVED via process-exit, never DECLARED — the
      // dangling `grid step --advance` instruction is gone.
      expect(prompt, isNot(contains('grid step --advance')));
    });

    test('AgentCapability prompt omits empty bead sections + the substation '
        'parenthetical', () {
      // An empty bead: only the header + the working agreement, no Task/Design.
      final prompt = buildAgentBrief(bead('tg-1'), _workspace()).render();
      expect(prompt, contains('# work bead tg-1'));
      expect(prompt, contains('Bead `tg-1`.'));
      expect(prompt, isNot(contains('## Task')));
      expect(prompt, isNot(contains('## Design')));
      expect(prompt, isNot(contains('substation `'))); // no rig metadata
      expect(prompt, contains('## Working agreement'));
    });

    test('AgentCapability interpretEvent: clean exit completes, non-zero / death '
        'fails', () {
      const cap = AgentCapability();
      expect(
        cap.interpretEvent(const Exited(name: 'x', exitCode: 0)),
        StepSignal.complete,
      );
      expect(
        cap.interpretEvent(const Exited(name: 'x', exitCode: 1)),
        StepSignal.failed,
      );
      expect(cap.interpretEvent(const Died(name: 'x')), StepSignal.failed);
    });

    test('LandCapability drives commit → push → PR and returns Ok(pr_url)', () async {
      final sc = _FakeSourceControl();
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'pr_url': 'https://github.com/memento/x/pull/7'});
      expect(sc.calls, [
        'commit:/w/tg-1:grid: land tg-1',
        'push:origin:grid/tg-1',
        'pr:grid/tg-1->main:grid: tg-1',
      ]);
    });

    test('LandCapability threads the FULL circuit receipt into the PR body '
        'when sc is a ReceiptCapableSourceControl (GitSourceControl always is '
        '— tg-rm5, the receipt-regression fix)', () async {
      final git = RecordingGitRunner();
      final pr = FakePrOpener();
      final sc = GitSourceControl(gitOps: GitOps(git), prOpener: pr);
      final context = FakeTreeContext(
        values: {
          Bead: bead('tg-1'),
          Workspace: testWorkspace(
            'tg-1',
            workspaceDir: '/w/tg-1',
            branch: 'grid/tg-1',
          ),
          ServiceBundle: ServiceBundle(sourceControl: sc),
          SiblingView: const SiblingView(
            results: {
              'tg-1/review/route': {
                'grades': 'code-validation=A',
                'spread': '0',
                'rule': 'all-approve',
              },
              'tg-1/land/rebase': {'outcome': 'clean'},
              'tg-1/land/revalidate': {'outcome': 'passed'},
            },
          ),
        },
      );
      final outcome = await const LandCapability().run(
        context,
        stepArgs('tg-1/land/land'),
      );
      expect(outcome, isA<Ok>());
      expect(pr.opened, hasLength(1));
      expect(pr.opened.single.body, contains('## Circuit receipt'));
      expect(pr.opened.single.body, contains('- rebase: clean'));
      expect(pr.opened.single.body, contains('- revalidate: passed'));
      expect(
        pr.opened.single.body,
        contains('grades=code-validation=A spread=0 rule=all-approve'),
      );
    });

    test('LandCapability GATES when commitAll left the tree a SUBSET of the '
        'reviewed tree (tg-x1j r1 — a botched land silently committed a '
        'subset, stripping edits from the PR) — never pushes, never opens a '
        'PR', () async {
      final git = _ResidueGitRunner();
      final pr = FakePrOpener();
      final sc = GitSourceControl(gitOps: GitOps(git), prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect((outcome as Gate).reason, contains('SUBSET'));
      expect(
        git.calls.map((c) => c.args.first),
        isNot(contains('push')),
        reason: 'never pushes a tree with uncommitted residue',
      );
      expect(pr.opened, isEmpty, reason: 'never opens a PR on residue');
    });

    test('LandCapability GATES when the post-commit clean-tree probe itself '
        'fails (fail-closed — an unreadable status is never silently trusted '
        'clean)', () async {
      final git = _ProbeFailGitRunner();
      final pr = FakePrOpener();
      final sc = GitSourceControl(gitOps: GitOps(git), prOpener: pr);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect(pr.opened, isEmpty);
    });

    test('LandCapability skips the residue check entirely when sc is a plain '
        'SourceControl (a bare test fake) — the SAME opt-in posture as the '
        'circuit-receipt check', () async {
      // _FakeSourceControl is NOT a TreeVerifiableSourceControl — proceeds
      // straight to push/PR exactly as before this bead.
      final sc = _FakeSourceControl();
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
    });

    test('LandCapability does NOT thread a body when sc is a plain '
        'SourceControl (a bare test fake, or a future non-Git impl) — it '
        'still lands correctly through the unwidened interface method',
        () async {
      final sc = _FakeSourceControl();
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(sc.calls.last, 'pr:grid/tg-1->main:grid: tg-1');
    });

    test('LandCapability with NO source control no-ops to Ok (offline-safe)',
        () async {
      final c = _capCtx();
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
    });

    test('LandCapability fails when the PR does not open', () async {
      final sc = _FakeSourceControl()..prOpens = false;
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Failed>());
    });

    test('LandCapability no-ops to Ok when a SourceControl is present but land '
        'is NOT wired (canLand=false) — provision-only, commit-only arm', () async {
      // A provision-only GitSourceControl (no gitOps/prOpener) ⇒ canLand false.
      const sc = GitSourceControl();
      expect(sc.canLand, isFalse);
      final c = _capCtx(sourceControl: sc);
      final outcome = await const LandCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>(), reason: 'deferred land is Ok, not Failed');
    });

    test('GitSourceControl.provisionWorkspace no-ops when provisioning is not '
        'wired (no provisioner) — never throws', () async {
      await const GitSourceControl().provisionWorkspace(
        beadId: 'tg-1',
        workspaceDir: '/does/not/exist/anywhere',
      );
      // Reaching here without throwing is the assertion (offline no-op).
    });

    test('workspaceFor/branchFor/baseBranch derive the layout — and an EMPTY '
        'root path yields the ABSOLUTE synthetic, never a CWD-relative path '
        '(the E3 review fix)', () {
      // A real root → the canonical per-bead worktree layout (byte-identical to
      // the deleted EffectContext.worktreeFor).
      const real = GitSourceControl(
        root: RootCheckout(path: '/root', defaultBranch: 'trunk', substation: 'tgdog'),
      );
      expect(real.workspaceFor('tg-1'), '/root/.grid/worktrees/tgdog/tg-1');
      expect(real.branchFor('tg-1'), 'grid/tg-1');
      expect(real.baseBranch, 'trunk');

      // No root → the absolute synthetic.
      expect(const GitSourceControl().workspaceFor('tg-1'), '/grid/worktrees/tg-1');
      expect(const GitSourceControl().baseBranch, 'main');

      // EMPTY-path root (the dry-run synthetic) → STILL the absolute synthetic,
      // NOT a CWD-relative `.grid/worktrees/...` (p.join would drop the empty
      // leading segment). This is the E3 latent-footgun fix + byte-parity restore.
      const emptyRoot = GitSourceControl(
        root: RootCheckout(path: '', defaultBranch: 'main', substation: 'tgdog'),
      );
      expect(emptyRoot.workspaceFor('tg-1'), '/grid/worktrees/tg-1');
      expect(emptyRoot.workspaceFor('tg-1').startsWith('/'), isTrue,
          reason: 'must be absolute — never spawn against the CWD');
    });
  });

  group('GitSourceControl implements TreeVerifiableSourceControl (bead '
      'tg-bns — land must verify it committed the WHOLE reviewed tree, not '
      'just no-op-ed commitAll)', () {
    test('a clean `git status --porcelain` -> null (nothing to report)',
        () async {
      final sc = GitSourceControl(gitOps: GitOps(RecordingGitRunner()));
      expect(
        await sc.uncommittedResidue(workspaceDir: '/w/tg-1'),
        isNull,
      );
    });

    test('a dirty status -> a non-null residue description', () async {
      final sc = GitSourceControl(gitOps: GitOps(_ResidueGitRunner()));
      final residue = await sc.uncommittedResidue(workspaceDir: '/w/tg-1');
      expect(residue, isNotNull);
      expect(residue, contains('uncommitted'));
    });

    test('a status probe error fails closed — never silently trusted clean',
        () async {
      final sc = GitSourceControl(gitOps: GitOps(_ProbeFailGitRunner()));
      final residue = await sc.uncommittedResidue(workspaceDir: '/w/tg-1');
      expect(residue, isNotNull);
    });
  });

  group('Track H — AgentCapability.result() usage telemetry (FT-2)', () {
    // The result() hook reads the harness's `--output-format json` envelope from
    // the per-step telemetry file; here a test writes it into a temp workspace.
    ({FakeTreeContext context, StepArgs args}) resultCtx(String workspaceDir) => (
      context: FakeTreeContext(values: {
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: workspaceDir,
          branch: 'grid/tg-1',
        ),
      }),
      args: stepArgs('tg-1/agent'),
    );

    void writeUsage(String workspaceDir, String content) {
      File(p.join(workspaceDir, usageReportPath('tg-1/agent')))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test('returns tokens/cost/turns/duration when the harness wrote an envelope',
        () async {
      final dir = Directory.systemTemp.createTempSync('agent-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      writeUsage(
        dir.path,
        '{"duration_ms": 900, "num_turns": 4, "total_cost_usd": 0.03, '
        '"usage": {"input_tokens": 12, "output_tokens": 34}}',
      );
      final c = resultCtx(dir.path);
      final out = await const AgentCapability().result(c.context, c.args);
      expect(out, {
        'tokensIn': '12',
        'tokensOut': '34',
        'costUsd': '0.03',
        'numTurns': '4',
        'harnessDurationMs': '900',
      });
    });

    test('an ABSENT envelope ⇒ null (telemetry never fails the step)', () async {
      final dir = Directory.systemTemp.createTempSync('agent-usage-absent-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = resultCtx(dir.path);
      expect(await const AgentCapability().result(c.context, c.args), isNull);
    });

    test('a MALFORMED envelope ⇒ null (telemetry never fails the step)',
        () async {
      final dir = Directory.systemTemp.createTempSync('agent-usage-bad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      writeUsage(dir.path, '{ not json');
      final c = resultCtx(dir.path);
      expect(await const AgentCapability().result(c.context, c.args), isNull);
    });
  });

  group('AgentCapability materializes the grid.dart pub linkage at provision '
      'time (tg-ucz — the "provision-time pub linkage" gap)', () {
    late Directory worktree;

    setUp(() {
      worktree = Directory.systemTemp.createTempSync('agent-link-worktree-');
    });

    tearDown(() {
      if (worktree.existsSync()) worktree.deleteSync(recursive: true);
    });

    ({FakeTreeContext context, StepArgs args}) ctxAt(
      String workspaceDir, {
      Map<String, dynamic> metadata = const {},
    }) => (
      context: FakeTreeContext(
        values: {
          Bead: bead('tg-1').copyWith(metadata: metadata),
          Workspace: testWorkspace(
            'tg-1',
            workspaceDir: workspaceDir,
            branch: 'grid/tg-1',
          ),
        },
      ),
      args: stepArgs('tg-1/agent'),
    );

    Map<String, dynamic> envelopeWith(
      List<PubLink> links, {
      String version = kDartAssetsVersion,
    }) => {
      kDartDomainKey: {
        'assets_version': version,
        'payload': {'pub': PubLinkConfig(links: links).toJson()},
      },
    };

    File overridesFile() =>
        File(p.join(worktree.path, kPubspecOverridesFile));

    test('(a) envelope + links → pubspec_overrides.yaml at the worktree root '
        'with an absolutized path', () {
      final c = ctxAt(
        worktree.path,
        metadata: envelopeWith(const [
          PubLink(package: 'genesis_tree', devPath: '../genesis/packages/tree'),
        ]),
      );
      const cap = AgentCapability(devRoot: '/dev/root');
      cap.spawn(c.context, c.args);
      expect(overridesFile().existsSync(), isTrue);
      expect(
        overridesFile().readAsStringSync(),
        contains("path: '/dev/genesis/packages/tree'"),
      );
    });

    test('(b) no grid.dart envelope on the bead → spawn succeeds, no file '
        'written', () {
      final c = ctxAt(worktree.path);
      const cap = AgentCapability(devRoot: '/dev/root');
      expect(() => cap.spawn(c.context, c.args), returnsNormally);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('(b) an envelope with only PINNED (no dev-path) links → a stale '
        'GENERATED overrides file is cleared', () {
      // A prior spawn (or `dart link`) generated the file for a dev link…
      const service = DartLinkService();
      service.applySync(
        metadata: envelopeWith(const [
          PubLink(package: 'genesis_tree', devPath: '/abs/genesis/packages/tree'),
        ]),
        context: PubLinkContext.worktree,
        workspaceDir: worktree.path,
      );
      expect(overridesFile().existsSync(), isTrue);

      // …a later bead revision drops the dev override (pins-only): the stale
      // generated file is cleared, never left dangling.
      final c = ctxAt(
        worktree.path,
        metadata: envelopeWith(const [
          PubLink(package: 'genesis_tree', hosted: '^0.1.3'),
        ]),
      );
      const cap = AgentCapability(devRoot: '/dev/root');
      cap.spawn(c.context, c.args);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('(c) a breaking assets_version is refused WHOLE — spawn THROWS '
        '(routes Failed to supervision, ADR-0008 Decision 10); never a '
        'half-applied file', () {
      final c = ctxAt(
        worktree.path,
        metadata: envelopeWith(const [
          PubLink(package: 'genesis_tree', devPath: '/abs/genesis/packages/tree'),
        ], version: '9.9.9'),
      );
      const cap = AgentCapability(devRoot: '/dev/root');
      expect(() => cap.spawn(c.context, c.args), throwsStateError);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('a workspace that does not exist yet (offline/dry-run — '
        'GitSourceControl never materializes one there) skips silently, '
        'never throws', () {
      final missing = p.join(worktree.path, 'does-not-exist');
      final c = ctxAt(
        missing,
        metadata: envelopeWith(const [
          PubLink(package: 'genesis_tree', devPath: '/abs/genesis/packages/tree'),
        ]),
      );
      const cap = AgentCapability(devRoot: '/dev/root');
      expect(() => cap.spawn(c.context, c.args), returnsNormally);
    });
  });
}
