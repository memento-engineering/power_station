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
      ServiceBundle: const ServiceBundle(),
    },
  ),
  args: stepArgs('tg-1/agent'),
);

/// The ambient Workspace [_capCtx] mounts (for the brief-parity assertions).
Workspace _workspace() =>
    testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1');

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
      // $1.. — the exact claude invocation ("$@" execs it verbatim). The model
      // is ALWAYS named (bead `pow-edp`): a build spawns in the BUILD role, so
      // absent a station/bead override it rides the FRONTIER tier (opus) — never
      // the claude CLI's own default, which silently fell back to fable.
      expect(cfg.args[3], 'claude');
      expect(cfg.args[4], '--dangerously-skip-permissions');
      expect(cfg.args[5], '--model');
      expect(cfg.args[6], kFrontierModelDefault);
      expect(cfg.args[7], '--output-format');
      expect(cfg.args[8], 'json');
      expect(cfg.args[9], '-p');
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

    test('the agreement DEMANDS the commit and gives the tracker to the station '
        '— stated as focus + ownership, never as a prohibition', () {
      // THE BUG (2026-07-16, pow-8b3 + pow-2c6): a codex build agent claimed and
      // then CLOSED its own work bead — faithfully following the SOLO workflow
      // the repo's own CLAUDE.md teaches. Closing the bead drops it from the
      // work frontier, so SessionScope took the DESIGNED positive-terminal
      // unmount on the agent's OWN live session: the node froze at
      // `agent.state: running` and a bounce could not recover it (the bead was
      // already closed, so there was nothing left to re-drive).
      //
      // The agreement already fenced the station-owned verbs it knew about
      // (push, PR); the bead lifecycle was simply missing. It is stated the way
      // the house states these — DEMAND the deliverable and name the OWNER —
      // never as a prohibition, and never by disclosing the failure.
      final prompt = buildAgentBrief(bead('tg-1'), _workspace()).render();
      expect(prompt, contains('Your ONE deliverable is the COMMIT'));
      expect(prompt, contains('leave the tracker to the station'));
    });

    test('the agreement never NAMES the tracker verbs nor DISCLOSES the failure '
        '— a prohibition puts the forbidden act in the agent\'s attention', () {
      // The house prompt rule: demand the thing we want, do not enumerate what
      // we fear. Naming `bd close` is what puts `bd close` in front of the
      // agent, and narrating the unmount cascade teaches it about machinery it
      // has no business modelling. Anti-disclosure is a checkable property, so
      // it is checked — this is the guard that keeps a well-meaning "just add a
      // DON'T" from creeping back in.
      final prompt = buildAgentBrief(bead('tg-1'), _workspace()).render();
      expect(prompt, isNot(contains('bd close')));
      expect(prompt, isNot(contains('--claim')));
      expect(prompt, isNot(contains('bd update')));
      expect(prompt, isNot(contains('Do NOT TOUCH')));
      // The failure mode itself stays undisclosed — the agent needs the OWNER,
      // not the blast radius.
      expect(prompt, isNot(contains('unmount')));
      expect(prompt, isNot(contains('stranded')));
    });

    test('the working agreement closes with the D-H genesis_tree doctrine — '
        'every coding agent this station spawns carries it (bead tg-kx1)', () {
      // Companion to the_grid's GridDelegate D-H fix (ADR-0008): the doctrine
      // rides the ONE prompt every coding agent receives, so it reaches every
      // spawned agent. Static text — no bead/path interpolation, so it survives
      // the Q3′ reference-inflation fence (track_e) untouched.
      final agreement = buildAgentBrief(bead('tg-1'), _workspace()).workingAgreement;
      expect(agreement, contains('D-H doctrine'));
      expect(agreement, contains('Always watch deps'));
      expect(agreement, contains(r'never snapshot-and-`??=`-cache reactive state'));
      expect(
        agreement,
        contains(r'No public synchronous accessor over `StateNotifier` state'),
      );
      expect(agreement, contains(r'observe it in `build`'));
      expect(agreement, contains('Config = VALUES in the tree; impls = DI'));
      expect(agreement, contains('Guards LOUD or GONE'));
      // The doctrine rides the AGREEMENT, so it renders under ## Working agreement.
      expect(
        buildAgentBrief(bead('tg-1'), _workspace()).render(),
        contains('## Working agreement'),
      );
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

    test('the brief carries the COMMIT POLICY (pow-8dx): conventional-commit '
        'subjects, the bead as a git TRAILER, never a foreign reference in the '
        'subject or the body', () {
      final brief = buildAgentBrief(bead('tg-1'), _workspace()).render();
      expect(brief, contains('CONVENTIONAL COMMITS v1.0.0'));
      expect(brief, contains('`<type>[(scope)][!]: <description>`'));
      expect(brief, contains('NEVER put the bead id (`tg-1`)'));
      expect(brief, contains('Refs: tg-1'));
      expect(brief, contains('BREAKING CHANGE: <what breaks>'));
      // The worked example is itself compliant (it is what the agent copies).
      expect(
        lintConventionalSubject(
          'feat(landing): infer the pr title from the branch diff',
        ),
        isEmpty,
      );
    });

    test('a station\'s trailer token flows into the brief', () {
      final brief = buildAgentBrief(
        bead('tg-1'),
        _workspace(),
        trailerToken: 'Bead',
      ).render();
      expect(brief, contains('Bead: tg-1'));
      expect(brief, isNot(contains('Refs: tg-1')));
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

    test('returns tokens/cost/turns/duration/model when the harness wrote an '
        'envelope', () async {
      final dir = Directory.systemTemp.createTempSync('agent-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      writeUsage(
        dir.path,
        '{"duration_ms": 900, "num_turns": 4, "total_cost_usd": 0.03, '
        '"usage": {"input_tokens": 12, "output_tokens": 34}, '
        '"modelUsage": {"claude-opus-4-8": {"outputTokens": 34}}}',
      );
      final c = resultCtx(dir.path);
      final out = await const AgentCapability().result(c.context, c.args);
      expect(out, {
        'tokensIn': '12',
        'tokensOut': '34',
        'costUsd': '0.03',
        'numTurns': '4',
        'harnessDurationMs': '900',
        'model': 'claude-opus-4-8',
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

  group(
    'AgentCapability materializes the station_overlay into .claude/ at provision '
    "(pow-kzx — ADR-0001's skill-DELIVERY leg)",
    () {
      late Directory worktree;

      setUp(() {
        worktree = Directory.systemTemp.createTempSync('agent-overlay-');
      });

      tearDown(() {
        if (worktree.existsSync()) worktree.deleteSync(recursive: true);
      });

      ({FakeTreeContext context, StepArgs args}) ctxAt(String workspaceDir) => (
        context: FakeTreeContext(
          values: {
            Bead: bead('tg-1'),
            Workspace: testWorkspace(
              'tg-1',
              workspaceDir: workspaceDir,
              branch: 'grid/tg-1',
            ),
          },
        ),
        args: stepArgs('tg-1/agent'),
      );

      File discoverSkill(Directory root) =>
          File(p.join(root.path, '.claude', 'skills', 'discover', 'SKILL.md'));

      test(
        'the REAL vended discover skill lands at .claude/skills/discover/ FULLY '
        'RENDERED — every {{hole}} bound, so the agent gets a runnable skill, '
        'not literal template text',
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(
            devRoot: '/dev/root',
            overlaySourceRef: 'testref',
          );
          cap.spawn(c.context, c.args);

          final installed = discoverSkill(worktree);
          expect(installed.existsSync(), isTrue);
          final body = installed.readAsStringSync();
          expect(body, startsWith('---\n'));
          // The default binding: kDefaultOverlayRunner + the registered root.
          expect(body, contains('space search --json'));
          expect(body, contains('/dev/root'));
          expect(body, isNot(contains('{{')));
        },
      );

      test(
        'the BRIEF names the installed skill, so a print-mode claude -p can '
        '/invoke it (print mode selects no skill on its own — ADR-0001)',
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(
            devRoot: '/dev/root',
            overlaySourceRef: 'testref',
          );
          final cfg = cap.spawn(c.context, c.args);
          // The rendered brief rides as the FINAL positional of the sh-wrapped
          // claude invocation (FT-2 — `agent_harness.dart`'s claudeArgs end with
          // `brief.render()`).
          expect(cfg.args.last, contains('`/discover`'));
          expect(cfg.args.last, contains('.claude/skills/'));
          // The OPERATOR skills ride the same overlay into the worktree, but
          // the brief must never OFFER them: harvest-review pushes + opens PRs,
          // which this very agreement forbids.
          expect(cfg.args.last, isNot(contains('`/harvest-review`')));
          expect(cfg.args.last, isNot(contains('`/station-operations`')));
        },
      );

      test(
        'the materialized asset dir is git-EXCLUDED by a SELF-IGNORING '
        '.gitignore — land commits with `git add -A`, so without this every '
        "bead's PR would carry the vended skills",
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(
            devRoot: '/dev/root',
            overlaySourceRef: 'testref',
          );
          cap.spawn(c.context, c.args);

          final ignore = File(
            p.join(
              worktree.path,
              '.claude',
              'skills',
              'discover',
              '.gitignore',
            ),
          );
          expect(ignore.existsSync(), isTrue);
          // A bare `*` matches every file in the dir INCLUDING this file, so the
          // exclusion is not residue either.
          expect(ignore.readAsStringSync(), endsWith('*\n'));
        },
      );

      test(
        'the exclusion is SCOPED to the asset dir — no blanket .claude/.gitignore '
        "is written, so ADR-0000 A5's residue gate still sees everything else in "
        "the worktree (including the agent's own .claude/ files)",
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(
            devRoot: '/dev/root',
            overlaySourceRef: 'testref',
          );
          cap.spawn(c.context, c.args);

          expect(
            File(p.join(worktree.path, '.claude', '.gitignore')).existsSync(),
            isFalse,
            reason:
                'a shared .claude/.gitignore could collide with one the repo '
                'itself tracks, and would over-hide',
          );
          expect(
            File(
              p.join(worktree.path, '.claude', 'skills', '.gitignore'),
            ).existsSync(),
            isFalse,
            reason:
                'never ignore the whole skills/ dir — a repo-owned skill and '
                "the agent's own work must stay visible",
          );
        },
      );

      test(
        'NON-DESTRUCTIVE: a pre-existing .claude/skills/discover/SKILL.md '
        'survives provision byte-unchanged',
        () {
          final existing = discoverSkill(worktree)..createSync(recursive: true);
          existing.writeAsStringSync('OPERATOR-AUTHORED — do not touch');

          final c = ctxAt(worktree.path);
          const cap = AgentCapability(
            devRoot: '/dev/root',
            overlaySourceRef: 'testref',
          );
          cap.spawn(c.context, c.args);

          expect(
            existing.readAsStringSync(),
            'OPERATOR-AUTHORED — do not touch',
          );
        },
      );

      test("a station's overlayArgs override the wire's default binding", () {
        final c = ctxAt(worktree.path);
        const cap = AgentCapability(
          devRoot: '/dev/root',
          overlaySourceRef: 'testref',
          overlayArgs: {'runner': 'grid', 'gridHome': '/grid/home'},
        );
        cap.spawn(c.context, c.args);

        final body = discoverSkill(worktree).readAsStringSync();
        expect(body, contains('grid search --json'));
        expect(body, contains('/grid/home'));
        expect(body, isNot(contains('space search --json')));
      });

      test(
        'an injected overlayRoot materializes a FIXTURE instead of the real tree '
        '(the offline test-isolation seam)',
        () {
          final fixture = Directory.systemTemp.createTempSync(
            'overlay-fixture-',
          );
          addTearDown(() {
            if (fixture.existsSync()) fixture.deleteSync(recursive: true);
          });
          File(
            p.join(
              fixture.path,
              '.claude',
              'skills',
              'fixture-skill',
              'SKILL.md',
            ),
          )
            ..createSync(recursive: true)
            ..writeAsStringSync('---\nname: fixture-skill\n---\nfixture body\n');

          final c = ctxAt(worktree.path);
          final cap = AgentCapability(
            devRoot: '/dev/root',
            overlayRoot: fixture.path,
            overlaySourceRef: 'testref',
          );
          final cfg = cap.spawn(c.context, c.args);

          expect(
            File(
              p.join(
                worktree.path,
                '.claude',
                'skills',
                'fixture-skill',
                'SKILL.md',
              ),
            ).readAsStringSync(),
            contains('fixture body'),
          );
          expect(discoverSkill(worktree).existsSync(), isFalse);
          expect(cfg.args.last, contains('`/fixture-skill`'));
        },
      );

      test(
        'an asset whose holes are UNBOUND is never installed and never fails the '
        'spawn — and the brief does not name it',
        () {
          final fixture = Directory.systemTemp.createTempSync(
            'overlay-unbound-',
          );
          addTearDown(() {
            if (fixture.existsSync()) fixture.deleteSync(recursive: true);
          });
          File(
            p.join(fixture.path, '.claude', 'skills', 'half-bound', 'SKILL.md'),
          )
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '---\nname: half-bound\n---\ncall {{nobodyBindsThis}}\n',
            );

          final c = ctxAt(worktree.path);
          final cap = AgentCapability(
            devRoot: '/dev/root',
            overlayRoot: fixture.path,
            overlaySourceRef: 'testref',
          );
          late final RuntimeConfig cfg;
          expect(() => cfg = cap.spawn(c.context, c.args), returnsNormally);

          expect(
            File(
              p.join(
                worktree.path,
                '.claude',
                'skills',
                'half-bound',
                'SKILL.md',
              ),
            ).existsSync(),
            isFalse,
          );
          expect(cfg.args.last, isNot(contains('`/half-bound`')));
        },
      );

      test(
        'a spawn that installs NO skills carries no skills paragraph — the brief '
        'only names what is actually there',
        () {
          final empty = Directory.systemTemp.createTempSync('overlay-empty-');
          addTearDown(() {
            if (empty.existsSync()) empty.deleteSync(recursive: true);
          });

          final c = ctxAt(worktree.path);
          final cap = AgentCapability(
            devRoot: '/dev/root',
            overlayRoot: empty.path,
            overlaySourceRef: 'testref',
          );
          final cfg = cap.spawn(c.context, c.args);

          expect(cfg.args.last, isNot(contains('VENDED skills')));
        },
      );
    },
  );
}
