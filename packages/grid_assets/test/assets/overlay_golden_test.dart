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
import 'package:yaml/yaml.dart';

/// Every path the wire is allowed to write under a worktree — the vended
/// skills' `SKILL.md` plus the self-ignoring `.gitignore` that keeps each out of
/// the bead's PR. Nothing else: no `settings.json`, no `agents/`.
const List<String> kWorktreeOverlayGolden = [
  '.claude/skills/asset-author/.gitignore',
  '.claude/skills/asset-author/SKILL.md',
  '.claude/skills/discover/.gitignore',
  '.claude/skills/discover/SKILL.md',
  '.claude/skills/gate-medicine/.gitignore',
  '.claude/skills/gate-medicine/SKILL.md',
  '.claude/skills/harvest-review/.gitignore',
  '.claude/skills/harvest-review/SKILL.md',
  '.claude/skills/intake-refinement/.gitignore',
  '.claude/skills/intake-refinement/SKILL.md',
  '.claude/skills/release/.gitignore',
  '.claude/skills/release/SKILL.md',
  '.claude/skills/station-operations/.gitignore',
  '.claude/skills/station-operations/SKILL.md',
];

void main() {
  late Directory worktree;

  setUp(
    () => worktree = Directory.systemTemp.createTempSync('overlay-golden-'),
  );
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
  List<String> materializedPaths() =>
      Directory(p.join(worktree.path, '.claude'))
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: worktree.path))
          .toList()
        ..sort();

  test('the provision wire emits EXACTLY the golden set — no settings.json, no '
      'agents/, nothing outside .claude/skills/', () {
    const cap = AgentCapability(devRoot: '/dev/root');
    final c = ctx();

    cap.spawn(c.context, c.args);

    expect(materializedPaths(), kWorktreeOverlayGolden);
  });

  test('every materialized SKILL.md is frontmatter-led and fully bound — no '
      'template residue ever reaches the agent', () {
    const cap = AgentCapability(devRoot: '/dev/root');
    final c = ctx();

    cap.spawn(c.context, c.args);

    for (final rel in kWorktreeOverlayGolden.where((r) => r.endsWith('.md'))) {
      final body = File(p.join(worktree.path, rel)).readAsStringSync();
      expect(body, startsWith('---\n'), reason: '$rel opens its frontmatter');
      expect(body, isNot(contains('{{')), reason: '$rel has no residue');
    }
  });

  test(
    'a STAMPED SKILL.md still parses as agentskills frontmatter — the harness '
    'discovers a skill by yaml-parsing the `---` block, so a stamp that broke '
    'it would silently un-discover every vended skill',
    () {
      const cap = AgentCapability(devRoot: '/dev/root');
      final c = ctx();

      cap.spawn(c.context, c.args);

      for (final rel in kWorktreeOverlayGolden.where(
        (r) => r.endsWith('.md'),
      )) {
        final body = File(p.join(worktree.path, rel)).readAsStringSync();
        expect(hasProvenance(body), isTrue, reason: '$rel is stamped');

        final fenceEnd = body.indexOf('\n---', 3);
        expect(fenceEnd, greaterThan(0), reason: '$rel closes its frontmatter');
        final frontmatter = loadYaml(body.substring(4, fenceEnd)) as YamlMap;
        expect(
          frontmatter['name'],
          p.basename(p.dirname(rel)),
          reason: '$rel still names itself through the stamp',
        );
        expect(frontmatter['description'], isNotEmpty);
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

      for (final rel in kWorktreeOverlayGolden.where(
        (r) => r.endsWith('.gitignore'),
      )) {
        expect(
          File(p.join(worktree.path, rel)).readAsStringSync(),
          endsWith('*\n'),
          reason: '$rel ignores its whole asset dir, including itself',
        );
      }
    },
  );
}
