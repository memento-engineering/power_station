// The GOLDEN set the provision wire materializes into a per-bead WORKTREE.
//
// Written BEFORE the root-relative overlay restructure and unchanged after it:
// the overlay's TREE moves, the emitted set does NOT. This is the regression
// gate on the LIVE path — the running station provisions every bead's worktree
// through `AgentCapability.spawn`, so a change here breaks live agent setup.
//
// The worktree leg is SCOPED to `.claude/skills`: a loose `.claude/settings.json`
// is repo-owned territory a per-asset-dir `.gitignore` cannot fence (A23(6) —
// power_station and lenny TRACK `.claude/settings.json`), so the operator-seat
// assets are the operator's seat's, never a bead's worktree's.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every path the wire is allowed to write under a worktree — the 5 vended
/// skills' `SKILL.md` plus the self-ignoring `.gitignore` that keeps each out of
/// the bead's PR. Nothing else: no `settings.json`, no `agents/`.
const List<String> kWorktreeOverlayGolden = [
  '.claude/skills/discover/.gitignore',
  '.claude/skills/discover/SKILL.md',
  '.claude/skills/gate-medicine/.gitignore',
  '.claude/skills/gate-medicine/SKILL.md',
  '.claude/skills/harvest-review/.gitignore',
  '.claude/skills/harvest-review/SKILL.md',
  '.claude/skills/intake-grooming/.gitignore',
  '.claude/skills/intake-grooming/SKILL.md',
  '.claude/skills/station-operations/.gitignore',
  '.claude/skills/station-operations/SKILL.md',
];

void main() {
  late Directory worktree;

  setUp(() => worktree = Directory.systemTemp.createTempSync('overlay-golden-'));
  tearDown(() {
    if (worktree.existsSync()) worktree.deleteSync(recursive: true);
  });

  ({FakeTreeContext context, StepArgs args}) ctx() => (
    context: FakeTreeContext(
      values: {
        Bead: bead('tg-1'),
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: worktree.path,
          branch: 'grid/tg-1',
        ),
      },
    ),
    args: stepArgs('tg-1/agent'),
  );

  /// Every file the spawn left under the worktree, worktree-relative + sorted.
  List<String> materializedPaths() => Directory(p.join(worktree.path, '.claude'))
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.relative(f.path, from: worktree.path))
      .toList()
    ..sort();

  test(
    'the provision wire emits EXACTLY the golden set — no settings.json, no '
    'agents/, nothing outside .claude/skills/',
    () {
      const cap = AgentCapability(devRoot: '/dev/root');
      final c = ctx();

      cap.spawn(c.context, c.args);

      expect(materializedPaths(), kWorktreeOverlayGolden);
    },
  );

  test(
    'every materialized SKILL.md is frontmatter-led and fully bound — no '
    'template residue ever reaches the agent',
    () {
      const cap = AgentCapability(devRoot: '/dev/root');
      final c = ctx();

      cap.spawn(c.context, c.args);

      for (final rel in kWorktreeOverlayGolden.where((r) => r.endsWith('.md'))) {
        final body = File(p.join(worktree.path, rel)).readAsStringSync();
        expect(body, startsWith('---\n'), reason: '$rel opens its frontmatter');
        expect(body, isNot(contains('{{')), reason: '$rel has no residue');
      }
    },
  );

  test(
    "each written asset dir self-ignores, so land's `git add -A` cannot carry "
    "the vended overlay into the bead's PR (A23(6))",
    () {
      const cap = AgentCapability(devRoot: '/dev/root');
      final c = ctx();

      cap.spawn(c.context, c.args);

      for (final rel
          in kWorktreeOverlayGolden.where((r) => r.endsWith('.gitignore'))) {
        expect(
          File(p.join(worktree.path, rel)).readAsStringSync(),
          endsWith('*\n'),
          reason: '$rel ignores its whole asset dir, including itself',
        );
      }
    },
  );
}
