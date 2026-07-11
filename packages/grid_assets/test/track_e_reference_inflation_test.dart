// Track E — reference inflation: briefs resolve from the ACTIVATION, never a
// bead-stamped path (bead `tg-m2q`; the Q3′ invariant of v3 —
// `the_grid/docs/GRID-SDK-BUILD-ORDER.md` Track E: *beads carry references,
// never resolved paths*).
//
// The 0(b) audit (`the_grid/docs/SCRATCH-station-config-model.md` §8, landed
// PR#30) found the brief path ALREADY structurally clean: no brief/prompt
// builder anywhere reads a resolved filesystem path off a bead. There are
// exactly four brief builders org-wide, all in this package —
// `buildAgentBrief` (code_capabilities.dart), `CriticCapability.
// buildCriticPrompt` (committee.dart), and the spec stage's pair (bead
// `pow-6ao`, specify.dart): `buildSpecifyBrief` +
// `SpecCriticCapability.buildSpecCriticPrompt` — and every path that
// reaches a spawned agent (the process cwd AND any path interpolated into the
// brief text) comes from the ambient `Workspace` seed, never a bead field.
//
// This file is the REGRESSION FENCE that pins that invariant so a future edit
// cannot silently re-inflate a bead stamp back into a brief or a spawn cwd:
//
//   1. `AgentBrief` declares NO path-typed field (task/workingAgreement/context
//      only) — a structural fence over the type (§8.1: "AgentBrief carries no
//      path-typed field").
//   2. Both brief builders, fed a bead whose metadata is POISONED with resolved
//      paths (`grid.root`/`worktree`/`branch` — the §8.2/§8.4 stamps), leak NONE
//      of them into the brief text; the only paths that surface are the ambient
//      `Workspace`'s.
//   3. Every harness `spawnFor` — and the full `AgentCapability.spawn` path —
//      roots `workDir` at `workspace.workspaceDir`, independent of the bead: the
//      spawn cwd is the activation's, never a stamp.
//   4. Bead reads in brief-building stay CONTENT / REFERENCE (title/description/
//      design/acceptance/notes + the `rig` NAME) — never a path.
//
// EXPLICITLY out of scope (per the bead + §8.4): the `grid.dart` devPath surface
// (a pending operator decision — pub-link paths, NOT a brief/cwd) and the
// `grid.root` SELECTOR machinery (dies in Track H, not here). This file asserts
// neither surfaces in a brief; it does not touch or move either.
//
// Pure-Dart, offline: no live claude/git/network; no filesystem writes (the one
// full-spawn test aims at a non-existent synthetic workspace dir, so
// `AgentCapability`'s `grid.dart` link probe no-ops — same posture as
// `GitSourceControl.provisionWorkspace`'s offline branch).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The sentinel prefix stamped onto EVERY poisoned bead path. A resolved path
/// on a bead is the exact Q3′ regression shape — `grid.root` abused as a path,
/// or the write-only `worktree`/`branch` session stamps (§8.4) misread. NONE of
/// these may reach a brief or a spawn cwd; a single `contains(_poison)` catches
/// any of them.
const String _poison = 'POISON';

/// A work bead whose metadata is POISONED with resolved paths, alongside a
/// legitimate `rig` NAME reference and the five content fields. Q3′: none of the
/// poison paths may surface in a brief or a cwd; the `rig` name + content MUST.
Bead _poisonedBead() => bead('tg-m2q').copyWith(
  title: 'Wire the federation bus',
  description: 'Connect The Studio to The Dashboard.',
  design: 'A lossy inter-station gossip bus.',
  acceptanceCriteria: 'A peer heartbeat surfaces within 1s.',
  notes: 'Coexistence-safe; do not touch gc.',
  metadata: const {
    'rig': 'tgdog', // a NAME reference — MUST surface (allowed, §8.5).
    // Resolved-path POISON — MUST NOT surface in any brief or cwd:
    'grid.root': '$_poison/grid-root-from-bead',
    'worktree': '$_poison/worktree-from-bead',
    'branch': '$_poison-branch-from-bead',
  },
);

/// The ambient activation — the ONLY legitimate source of paths in a brief.
/// Distinct, recognizable values so a leak is unambiguous.
Workspace _activation() => testWorkspace(
  'tg-m2q',
  workspaceDir: '/real/activation/worktree/tg-m2q',
  branch: 'grid/tg-m2q',
  baseBranch: 'main',
);

/// Locates `grid_assets/lib/<relative>` walking up from the test's working dir
/// (robust whether the suite runs from the repo root or the package dir) —
/// mirrors `structural_test.dart`'s `_libDir` locator.
File _libFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final base in ['lib', p.join('packages', 'grid_assets', 'lib')]) {
      final probe = File(p.join(dir.path, base, relative));
      if (probe.existsSync()) return probe;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate grid_assets/lib/$relative from ${Directory.current.path}');
}

/// The source text of the `AgentBrief` class body — sliced from its declaration
/// to the next top-level declaration — for the structural field fence.
String _agentBriefClassBody() {
  final src = _libFile(p.join('src', 'agent', 'agent_harness.dart'))
      .readAsStringSync();
  final start = src.indexOf('class AgentBrief {');
  expect(start, greaterThanOrEqualTo(0),
      reason: 'AgentBrief moved/renamed — update this Q3′ fence');
  final end = src.indexOf(RegExp(r'\n(abstract |class |mixin |enum )'), start + 1);
  return src.substring(start, end == -1 ? src.length : end);
}

void main() {
  group('Track E (tg-m2q) — briefs inflate references, never bead-stamped paths', () {
    // ---------------------------------------------------------------------
    // 1. AgentBrief carries NO path-typed field (structural fence).
    // ---------------------------------------------------------------------
    group('AgentBrief declares no path-typed field (§8.1)', () {
      test('its fields are content/policy only — none denotes a filesystem path',
          () {
        final body = _agentBriefClassBody();
        // Every `final <Type> <name>` field, initialized or not (the type token
        // excludes untyped locals like render()'s `final b = ...`).
        final fields = RegExp(r'^\s*final\s+.+?\s+(\w+)\s*(?:=|;)', multiLine: true)
            .allMatches(body)
            .map((m) => m.group(1)!)
            .toList();
        // The known content/policy fields are present (the full set today —
        // task + the working agreement + labeled context blocks).
        expect(fields, containsAll(<String>['task', 'workingAgreement', 'context']),
            reason: 'the brief carries rendered CONTENT + policy, nothing else');
        // No field NAME denotes a path. A path-typed field is the Q3′
        // regression: it would let a bead stamp ride the brief instead of
        // resolving from the Workspace activation. (Dart can't type "path", so
        // the field name is the enforceable proxy.)
        const pathish = {
          'workdir', 'workspacedir', 'root', 'worktree', 'cwd', 'repo',
          'reporoot', 'path', 'dir', 'directory', 'home', 'basedir', 'checkout',
        };
        for (final f in fields) {
          expect(pathish.contains(f.toLowerCase()), isFalse,
              reason: 'AgentBrief.$f looks path-typed — paths must resolve from '
                  'the Workspace activation (Q3′), never ride the brief');
        }
      });
    });

    // ---------------------------------------------------------------------
    // 2. buildAgentBrief — the coding-agent brief resolves from the activation.
    // ---------------------------------------------------------------------
    group('buildAgentBrief resolves paths from the activation, never the bead', () {
      final brief = buildAgentBrief(_poisonedBead(), _activation());
      final rendered = brief.render();

      test('the only paths in the brief are the ambient Workspace\'s', () {
        expect(rendered, contains('/real/activation/worktree/tg-m2q'));
        expect(rendered, contains('grid/tg-m2q'));
      });

      test('no bead-stamped path leaks into the brief (Q3′)', () {
        expect(rendered, isNot(contains(_poison)),
            reason: 'a resolved path on the bead (grid.root/worktree/branch) '
                'must never reach the brief — briefs inflate from the activation');
      });

      test('the working agreement interpolates the Workspace, not the bead', () {
        // The one path interpolated into brief text is the working agreement's
        // ${workspace.workspaceDir} + ${workspace.branch} (§8.1) — seed, not bead.
        expect(brief.workingAgreement, contains('/real/activation/worktree/tg-m2q'));
        expect(brief.workingAgreement, contains('grid/tg-m2q'));
        expect(brief.workingAgreement, isNot(contains(_poison)));
      });

      test('the bead `rig` NAME surfaces — a REFERENCE, not a path (§8.5)', () {
        expect(rendered, contains('substation `tgdog`'));
      });

      test('the bead CONTENT flows through (title/description/design/'
          'acceptance/notes)', () {
        expect(rendered, contains('Wire the federation bus'));
        expect(rendered, contains('Connect The Studio to The Dashboard.'));
        expect(rendered, contains('A lossy inter-station gossip bus.'));
        expect(rendered, contains('A peer heartbeat surfaces within 1s.'));
        expect(rendered, contains('Coexistence-safe; do not touch gc.'));
      });
    });

    // ---------------------------------------------------------------------
    // 3. buildCriticPrompt — the critic brief's only path is the verdict
    //    path, derived from the WORKSPACE dir passed in by the activation
    //    (absolute + cwd-invariant since tg-r66). It must still leak no
    //    bead-stamped path.
    // ---------------------------------------------------------------------
    group('buildCriticPrompt reads no path off the bead (the critic brief)', () {
      const workspaceDir = '/activations/tg-m2q';
      final prompt = const CriticCapability().buildCriticPrompt(
        _poisonedBead(),
        'spec-adherence',
        'tg-m2q/review/spec-adherence',
        workspaceDir,
      );

      test('no bead-stamped path leaks into the critic prompt (Q3′)', () {
        expect(prompt, isNot(contains(_poison)));
      });

      test('its verdict path derives from the activation workspace, '
          'never the bead (§8.1, tg-r66)', () {
        expect(
          prompt,
          contains('$workspaceDir/.grid/critique/spec-adherence.json'),
        );
      });

      test('the bead CONTENT flows through (reference-only reads, §8.5)', () {
        expect(prompt, contains('Wire the federation bus'));
        expect(prompt, contains('Connect The Studio to The Dashboard.'));
        expect(prompt, contains('A lossy inter-station gossip bus.'));
      });
    });

    // ---------------------------------------------------------------------
    // 3b. The spec stage's brief builders (bead `pow-6ao`) hold the same
    //     fence: buildSpecifyBrief + buildSpecCriticPrompt inflate from the
    //     activation, never a bead stamp.
    // ---------------------------------------------------------------------
    group('the spec-stage builders read no path off the bead (pow-6ao)', () {
      test('buildSpecifyBrief: no bead-stamped path; the Workspace\'s paths + '
          'the bead CONTENT flow through', () {
        final brief = buildSpecifyBrief(_poisonedBead(), _activation());
        final rendered = brief.render();
        expect(rendered, isNot(contains(_poison)));
        expect(rendered, contains('/real/activation/worktree/tg-m2q'));
        expect(rendered, contains('grid/tg-m2q'));
        expect(rendered, contains('Wire the federation bus'));
        expect(rendered, contains('substation `tgdog`'));
      });

      test('buildSpecCriticPrompt: no bead-stamped path; its verdict path '
          'derives from the activation workspace', () {
        const workspaceDir = '/activations/tg-m2q';
        final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
          _poisonedBead(),
          'coherence',
          'tg-m2q/spec_review/coherence',
          workspaceDir,
        );
        expect(prompt, isNot(contains(_poison)));
        expect(
          prompt,
          contains('$workspaceDir/.grid/critique/coherence.json'),
        );
        expect(prompt, contains('Wire the federation bus'));
      });
    });

    // ---------------------------------------------------------------------
    // 4. Every harness roots workDir at the activation, never the bead.
    // ---------------------------------------------------------------------
    group('every harness roots workDir at the activation, never the bead', () {
      final brief = buildAgentBrief(_poisonedBead(), _activation());
      final ws = _activation();

      // (harness impl, a legal config for it). `pi` reaches only endpoint
      // targets, so it gets an OpenAI-compatible one; the rest are managed.
      final cases = <String, ({AgentHarness harness, AgentConfig config})>{
        'claude': (harness: const ClaudeHarness(), config: const AgentConfig()),
        'copilot': (
          harness: const CopilotHarness(),
          config: const AgentConfig(harness: 'copilot'),
        ),
        'pi': (
          harness: const PiHarness(),
          config: AgentConfig(
            harness: 'pi',
            target: OpenAiCompatible(Uri.parse('http://127.0.0.1:8080')),
          ),
        ),
        'opencode': (
          harness: const OpencodeHarness(),
          config: const AgentConfig(harness: 'opencode'),
        ),
      };

      for (final entry in cases.entries) {
        test('${entry.key}: workDir == workspace.workspaceDir; no bead path in '
            'the invocation', () {
          final cfg = entry.value.harness.spawnFor(
            config: entry.value.config,
            brief: brief,
            workspace: ws,
          );
          expect(cfg.workDir, ws.workspaceDir);
          expect(cfg.workDir, '/real/activation/worktree/tg-m2q');
          // The rendered brief rides in the argv; no bead-stamped path there.
          expect(cfg.args.join('\n'), isNot(contains(_poison)));
        });
      }

      test('claude usage-capture wrapper keeps workDir at the activation (FT-2)',
          () {
        final cfg = const ClaudeHarness().spawnFor(
          config: const AgentConfig(),
          brief: brief,
          workspace: ws,
          usageOut: usageReportPath('tg-m2q/agent'),
        );
        // The sh-wrapped invocation (FT-2) still cwds at the activation.
        expect(cfg.command, 'sh');
        expect(cfg.workDir, ws.workspaceDir);
        expect(cfg.args.join('\n'), isNot(contains(_poison)));
      });

      test('the standard registry wires exactly the four harnesses this fence '
          'covers', () {
        expect(buildAgentHarnessRegistry().ids.toSet(),
            {'claude', 'copilot', 'pi', 'opencode'});
      });
    });

    // ---------------------------------------------------------------------
    // 5. The FULL AgentCapability.spawn path — the cwd is the activation's,
    //    end to end (not just the isolated builder).
    // ---------------------------------------------------------------------
    group('AgentCapability.spawn roots the cwd at the activation, end to end', () {
      test('spawns claude in workspace.workspaceDir; no bead path in the config',
          () {
        final ctx = FakeTreeContext(
          values: {
            Bead: _poisonedBead(),
            Workspace: _activation(),
            ServiceBundle: const ServiceBundle(),
          },
        );
        final cfg = const AgentCapability().spawn(ctx, stepArgs('tg-m2q/agent'));
        expect(cfg.workDir, '/real/activation/worktree/tg-m2q');
        expect(cfg.args.join('\n'), isNot(contains(_poison)));
      });
    });
  });
}
