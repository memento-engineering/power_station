// The GOLDEN set the provision wire materializes into a per-bead WORKTREE.
//
// Written BEFORE the root-relative overlay restructure and unchanged after it:
// the overlay's TREE moves, the emitted set does NOT. This is the regression
// gate on the LIVE path — the running station provisions every bead's worktree
// through `AgentCapability.spawn`, so a change here breaks live agent setup.
//
// The worktree leg is SCOPED to the per-harness SKILL trees (`.claude/skills` +
// `.agents/skills`): a loose `.claude/settings.json`
// is repo-owned territory a per-asset-dir `.gitignore` cannot fence (A23(6) —
// power_station and lenny TRACK `.claude/settings.json`), so the operator-seat
// assets are the operator's seat's, never a bead's worktree's.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_engine/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/asset_resolution_fixture.dart';

/// Every path the wire is allowed to write under a worktree — each vended
/// skill's `SKILL.md`, in EVERY harness skill tree the station arms, plus the
/// self-ignoring `.gitignore` that keeps each out of the bead's PR. Nothing
/// else: no `settings.json`, no `agents/` agent-defs, no loose root file.
const List<String> kWorktreeOverlayGolden = [
  '.agents/skills/asset-author/.gitignore',
  '.agents/skills/asset-author/SKILL.md',
  '.agents/skills/discover/.gitignore',
  '.agents/skills/discover/SKILL.md',
  '.agents/skills/gate-medicine/.gitignore',
  '.agents/skills/gate-medicine/SKILL.md',
  '.agents/skills/handoff/.gitignore',
  '.agents/skills/handoff/SKILL.md',
  '.agents/skills/harvest-review/.gitignore',
  '.agents/skills/harvest-review/SKILL.md',
  '.agents/skills/intake-refinement/.gitignore',
  '.agents/skills/intake-refinement/SKILL.md',
  '.agents/skills/release/.gitignore',
  '.agents/skills/release/SKILL.md',
  '.agents/skills/station-operations/.gitignore',
  '.agents/skills/station-operations/SKILL.md',
  '.claude/skills/asset-author/.gitignore',
  '.claude/skills/asset-author/SKILL.md',
  '.claude/skills/discover/.gitignore',
  '.claude/skills/discover/SKILL.md',
  '.claude/skills/gate-medicine/.gitignore',
  '.claude/skills/gate-medicine/SKILL.md',
  '.claude/skills/handoff/.gitignore',
  '.claude/skills/handoff/SKILL.md',
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
        // The one resolution's inputs: the substation this worktree belongs to
        // and the facts observed at its root.
        ...liveAssetContextValues(),
      },
    ),
    args: stepArgs('tg-1/agent'),
  );

  /// The provision wire as the station composes it: the GENERATED registry,
  /// resolved against the ambient facts above.
  AgentCapability capability() => AgentCapability(
    devRoot: '/dev/root',
    assetRegistry: GeneratedGridAssetRegistrant.registry,
  );

  /// Every file the spawn left under the worktree, worktree-relative + sorted.
  /// The walk starts at the ROOT, not at one subtree: a loose file at the root
  /// (an `AGENTS.md`, a `settings.json`) is exactly the shape the per-asset-dir
  /// fence cannot cover, so the equality below is what refuses one.
  List<String> materializedPaths() =>
      worktree
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: worktree.path))
          .toList()
        ..sort();

  test('the provision wire emits EXACTLY the golden set into a BUILD WORKTREE '
      '— both harness skill trees, no settings.json, no agent-defs, and no '
      'loose file anywhere at the root', () {
    final cap = capability();
    final c = ctx();

    cap.spawn(c.context, c.args);

    expect(materializedPaths(), kWorktreeOverlayGolden);
  });

  test('every materialized SKILL.md is frontmatter-led and fully bound — no '
      'template residue ever reaches the agent', () {
    final cap = capability();
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
      final cap = capability();
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
      final cap = capability();
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

  ProcessResult git(List<String> args) =>
      Process.runSync('git', args, workingDirectory: worktree.path);

  test('in a REAL git repo the provision leaves NOTHING for `git add -A` to '
      'stage: every written path is check-ignore clean and the tracked tree is '
      'untouched (A23(6), now across BOTH skill trees)', () {
    expect(git(const ['init', '--initial-branch=main']).exitCode, 0);
    File(p.join(worktree.path, 'README.md')).writeAsStringSync('# seed\n');
    expect(git(const ['add', 'README.md']).exitCode, 0);
    expect(
      git(const [
        '-c',
        'user.email=gate@example.com',
        '-c',
        'user.name=gate',
        'commit',
        '-m',
        'seed',
      ]).exitCode,
      0,
    );

    final cap = capability();
    final c = ctx();

    cap.spawn(c.context, c.args);

    for (final rel in kWorktreeOverlayGolden) {
      expect(
        git(['check-ignore', '-q', rel]).exitCode,
        0,
        reason: '$rel must be git-excluded',
      );
    }
    expect(
      (git(const ['status', '--porcelain']).stdout as String).trim(),
      isEmpty,
      reason: "the bead's PR carries none of the vended overlay",
    );
  });

  test('a HAND-AUTHORED file at a vended path under .agents/skills is BLOCKED, '
      'never clobbered, and its dir gets no fence — `.agents/` is repo-owned '
      'territory (`bd init` tracks `.agents/skills/beads/`), and never '
      'clobbering it is what makes the widened scope safe', () {
    const handAuthored = '---\nname: discover\n---\nthe repo own copy\n';
    final target =
        File(p.join(worktree.path, '.agents', 'skills', 'discover', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync(handAuthored);

    final cap = capability();
    final c = ctx();

    cap.spawn(c.context, c.args);

    expect(target.readAsStringSync(), handAuthored);
    expect(
      File(
        p.join(worktree.path, '.agents', 'skills', 'discover', '.gitignore'),
      ).existsSync(),
      isFalse,
      reason: 'the fence covers only asset dirs this call actually wrote into',
    );
    expect(
      File(
        p.join(worktree.path, '.claude', 'skills', 'discover', 'SKILL.md'),
      ).existsSync(),
      isTrue,
      reason: 'the claude leg still installs — one blocked path fails nothing',
    );
  });
}
