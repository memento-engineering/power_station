## Implementation Plan

Every command below runs from the worktree root
`/Users/nico/development/engineering.memento/power_station/.grid/worktrees/power_station/pow-kzx`.
`dart pub get` has already resolved (the pub-workspace `package_config.json` is at the worktree
root's `.dart_tool/`); `cd packages/grid_assets && dart analyze` returns `No issues found!` on the
current base (`1d5a165`) before any step — re-run it after each step that touches `lib/`.

**This is the round-3 rebuild on the CURRENT base.** Round 1 was built on `56b80f6` and gated on a
land rebase conflict; `#31`/`#32` have since landed and they moved the very lines this plan edits.
All line numbers, signatures, and amendment numbers below were re-read from the live tree at
`1d5a165`. Three specific things the pre-`#32` draft of this plan got wrong, now corrected — do not
re-introduce them:

- The ADR-0000 register's last entry is **A21** (`pow-96y`, the discovery circuit, added by `#32`),
  so this bead's amendment is **A22**. (The register regresses as well as grows — `56b80f6` deleted
  a mis-filed A21 — so the number was re-derived by `grep -n '^## A[0-9]' docs/adr/ADR-0000-ai-decision-register.md`, never assumed.)
- `buildAgentBrief` now takes a named `trailerToken` (bead `pow-8dx`/A18):
  `AgentBrief buildAgentBrief(Bead bead, Workspace workspace, {String trailerToken = kDefaultTrailerToken})`,
  and `AgentCapability.spawn` passes `trailerToken: composition.trailerToken`. The new `skills:`
  param is ADDED ALONGSIDE it — the plan never rewrites that signature away.
- A THIRD `AgentCapability` spawn site now exists (`test/agent/role_model_ladder_test.dart:73`,
  bead `pow-edp`). It mounts `workspaceDir: '/w/tg-1'`, which does not exist, so
  `_linkWorkspace`'s existing `Directory(...).existsSync()` guard early-returns and the new wire is
  inert there (verified — see `## Touches`).

Three further defects, verified against the live tree, that the plan's DESIGN exists to prevent:

1. **A verbatim copy installs a BROKEN skill.** The discover SKILL.md is mustache-templated: it
   carries `{{runner}}` (lines 31, 68) and `{{gridHome}}` (lines 58, 105). Copying it file-for-file
   into `.claude/skills/` hands the agent a skill whose commands are literal `{{runner}}` text — the
   silent packaging bug ADR-0000 A12 put the LOUD unbound-hole guard on `renderSkill` to prevent. So
   `OverlayMaterializer` RENDERS each file against caller-supplied args and REFUSES (never writes) a
   file left with an unbound hole.
2. **The materialized overlay would be committed into every PR.** `LandCapability` →
   `GitSourceControl.commitAll` → `GitOps.commitAll` runs `git add -A`
   (verified live at `the_grid/packages/grid_runtime/lib/src/git/git_ops.dart:312`), so an untracked
   `<worktree>/.claude/skills/**` lands in the bead's commit and its PR, in whatever repo the bead
   belongs to.
3. **One shared `<worktree>/.claude/.gitignore` would NOT fix (2) — it has a leak hole**, because
   `.claude/` is repo-owned territory in the very repos the grid provisions worktrees from. Verified
   live: `git ls-files '.claude/*'` shows **the_grid TRACKS `.claude/skills/grid-porting/SKILL.md` +
   `.claude/skills/predictable-flutter/SKILL.md`**, and power_station and lenny each track
   `.claude/settings.json`. A non-destructive "skip if it exists" would then silently skip writing
   the exclusion the day such a repo adds its own `.claude/.gitignore`, and the whole vended tree
   would ride every PR — the exact failure the step exists to prevent. **This plan instead writes a
   SELF-IGNORING `.gitignore` (a single `*`) INSIDE EACH materialized asset dir**
   (`<worktree>/.claude/skills/discover/.gitignore`). `*` matches every file in that dir INCLUDING
   the `.gitignore` itself, so the whole vended asset is invisible to git, and the mechanism cannot
   collide with — or be defeated by — any repo-owned `.claude/.gitignore`.

The exclusion design was re-verified empirically in a scratch repo reproducing the_grid's real
shape (`.claude/skills/**` + `.claude/settings.json` TRACKED). With the per-asset-dir `.gitignore`
in place: `git status --porcelain` is EMPTY and `git add -A` stages nothing, while a modified
tracked `.claude/skills/grid-porting/SKILL.md` (` M`), a new untracked `.claude/notes.md` (`??`),
and a new untracked source file (`??`) all stay fully visible — so ADR-0000 A5's post-commit residue
gate keeps detecting genuine uncommitted work exactly as it does today (see `## ADR Alignment`).

### Step 1 — Relocate the discover skill under `station_overlay/`, point the loader at it, expose the resolved root

Move the file (content unchanged — a pure relocation):

```sh
mkdir -p packages/grid_assets/extension/station_overlay/skills
git mv packages/grid_assets/extension/skills/discover \
       packages/grid_assets/extension/station_overlay/skills/discover
rmdir packages/grid_assets/extension/skills 2>/dev/null || true
```

In `packages/grid_assets/lib/src/assets/asset_loader.dart`, replace the library-doc paragraph
(lines 11–17, `/// The vended SKILLS (…)` through `/// and fails LOUD on any unbound hole.`) with:

```dart
/// The vended SKILLS (`extension/station_overlay/skills/<id>/SKILL.md`, bead
/// `pow-88p`) ride the same loader: the agentic halves of the coupled
/// skill+command pairs (ADR-0001 — the skill CALLS the vended deterministic
/// Command, e.g. `discover` calls `search --json`). Each SKILL.md is
/// mustache-templated on its manifest-declared args (`runner`, `gridHome`);
/// [renderSkill] renders ONE skill by id and fails LOUD on any unbound hole.
/// The `station_overlay/{skills,agents}` FORMAT and the non-destructive
/// TREE-level expansion of it onto a target `.claude/` dir ship next door in
/// `overlay_materializer.dart` (bead `pow-kzx`, the delivery leg): this loader
/// stays the by-id render surface, [OverlayMaterializer] is the whole-tree
/// install. Two callers ride the latter — the operator install Command
/// (`pow-a74`) and this package's OWN provision-time wire
/// (`AgentCapability._linkWorkspace`, `code_capabilities.dart`, ADR-0000 A1).
```

Replace the `kVendedSkills` doc (lines 34–36) with:

```dart
/// The skill ids this package vends
/// (`extension/station_overlay/skills/<id>/SKILL.md`) — the agentic halves of
/// the coupled skill+command pairs (ADR-0001). [OverlayMaterializer] does not
/// read this constant (it installs whatever files exist under the overlay);
/// it is the by-id render surface's own index, and the skill-manifest test's.
const List<String> kVendedSkills = ['discover'];
```

Replace `loadSkillTemplate`'s doc + body (lines 121–131) with:

```dart
  /// The mustache-templated SKILL.md body for [skillId]
  /// (`extension/station_overlay/skills/<skillId>/SKILL.md` — the vended-asset
  /// overlay format, bead `pow-kzx`). Throws an [ArgumentError] for an unknown
  /// skill (fail-loud — a missing skill is a packaging bug, never a silent
  /// empty install).
  String loadSkillTemplate(String skillId) {
    final file = File(
      p.join(_root, 'station_overlay', 'skills', skillId, 'SKILL.md'),
    );
    if (!file.existsSync()) {
      throw ArgumentError('unknown skill "$skillId" (no ${file.path})');
    }
    return file.readAsStringSync();
  }
```

Add a public getter immediately after the `late final String _root = …` field (line 49):

```dart
  /// The resolved `extension/` directory this loader reads from — exposed so a
  /// sibling caller that must build a path relative to it (the station_overlay
  /// materialization wire, bead `pow-kzx`) reuses this ONE resolution
  /// (package-config first, cwd walk-up fallback) instead of re-deriving it.
  /// Throws (via [_resolveRoot]) when no `extension/` can be located at all —
  /// the same fail-loud packaging-bug posture every other read here holds.
  String get root => _root;
```

Finally, fix the one other doc reference to the old home. In
`packages/grid_assets/lib/src/code/discovery.dart` line 66, the phrase
`(`extension/skills/discover/`)` becomes:

```dart
/// (`extension/station_overlay/skills/discover/`). The skill is the human front
```

Test: `cd packages/grid_assets && dart test test/assets/skill_assets_test.dart` → FAILS on the
manifest-path assertion until Step 3 lands (expected: the loader now reads the new path, the
manifest still declares the old one). `dart analyze` → `No issues found!`. Do not stop here.
Commit: `refactor(grid_assets): re-home the discover skill under extension/station_overlay/skills + expose PackagedAssetLoader.root`

### Step 2 — Point the skills manifest at the new path

In `packages/grid_assets/extension/mcp/config.yaml`, replace the comment block above `skills:`
(lines 121–129, the paragraph beginning `# Skills — front-of-house agentic assets…`) with:

```yaml
# Skills — front-of-house agentic assets in the agentskills SKILL.md format
# (the same community shape lenny's leonard_cli assets ship). The upstream
# proposal defines only resources/prompts; this section is this manifest's
# forward extension of it, reusing the prompts' arg-declaration shape. Each
# skill dir under extension/station_overlay/skills/<id>/ holds a mustache-
# templated SKILL.md. Two legs install the rendered tree (bead `pow-kzx`'s
# OverlayMaterializer — non-destructive, and it REFUSES to write a file whose
# holes are unbound): this package's own provision-time wire
# (AgentCapability._linkWorkspace -> a per-bead worktree's .claude/skills/) and
# the operator install Command (`pow-a74` -> the operator's own .claude/). The
# coupled skill+command pattern (ADR-0001): the skill CALLS the vended
# deterministic Command instead of re-deriving the operation by inference.
```

And change the `discover` entry's path (line 137):

```yaml
    path: station_overlay/skills/discover/SKILL.md
```

Commit: `chore(grid_assets): point the skills manifest at station_overlay/skills`

### Step 3 — Update the skill-manifest test's path assertion

In `packages/grid_assets/test/assets/skill_assets_test.dart`, replace line 3 of the header comment
(`// \`extension/skills/<id>/SKILL.md\` and rendered by [PackagedAssetLoader].`) with:

```dart
// `extension/station_overlay/skills/<id>/SKILL.md` and rendered by
// [PackagedAssetLoader].
```

and replace the manifest-path assertion (line 187, currently
`expect(discover['path'], 'skills/discover/SKILL.md');`) with:

```dart
      expect(discover['path'], 'station_overlay/skills/discover/SKILL.md');
```

Test: `cd packages/grid_assets && dart test test/assets/skill_assets_test.dart` →
`All tests passed!` (loader path and manifest path now agree).
Commit: `test(grid_assets): assert the station_overlay skills path in the manifest`

### Step 4 — Add the `OverlayMaterializer` lib

Create `packages/grid_assets/lib/src/assets/overlay_materializer.dart`:

```dart
/// The vended-asset OVERLAY format + its non-destructive materialization LIB
/// (bead `pow-kzx` — ADR-0001's "missing leg": a vended skill is inert until it
/// is INSTALLED where the agent runs).
///
/// **The format.** A package that vends agentic assets ships them under
/// `extension/station_overlay/{skills,agents}/<name>/…`. The ASSET DIR —
/// `<kind>/<name>/` — is the format's unit: everything inside one is installed
/// onto the target `.claude/` tree file-for-file, and the format imposes nothing
/// on an asset's internal shape beyond living in its own dir under its kind. A
/// file sitting LOOSE directly under a kind dir has no asset dir, so it THROWS
/// (see [OverlayMaterializer.materializeSync]).
///
/// **One tree, two consumers.** The SAME overlay serves both legs ADR-0001
/// names: a per-bead WORKTREE's `.claude/` (this package's own provision wire —
/// `AgentCapability._linkWorkspace`, `code_capabilities.dart`, ADR-0000 A1) and
/// the OPERATOR's `.claude/` (bead `pow-a74`'s `space install` Command). There
/// is no separate worktree-only format.
///
/// **The lib.** [OverlayMaterializer] is the CLI-FREE, git-free, UI-drivable
/// substrate both legs ride. It takes the ALREADY-RESOLVED, ORDERED overlay
/// roots — deciding WHICH packages are in scope (walking the composing station's
/// `GridDelegate`, the way `mountedRosterOf` does for search) is the CALLER's
/// job; this lib mounts no tree — and expands their `skills/`+`agents/` subtrees
/// onto one target dir. Four rules:
///
/// - **Non-destructive** (mirrors `DartLinkService`'s never-overwrite posture):
///   a target file that already exists is SKIPPED — whether it pre-existed
///   (operator-authored, or a previous run) or an EARLIER overlay root wrote it
///   in this same call. That one skip-if-exists rule is what gives "union by tree
///   position" its precedence: roots expand IN THE GIVEN ORDER, so the first root
///   to offer a path wins.
/// - **Rendered, never half-bound.** Each file's contents is substituted against
///   [OverlayMaterializer.materializeSync]'s `args` (the manifest-declared skill
///   args — `runner`, `gridHome`). A file left carrying an unbound `{{hole}}` is
///   REFUSED — reported, never written. A literal `{{runner}}` in an installed
///   skill is a silent packaging bug (the tree-level counterpart of
///   [PackagedAssetLoader.renderSkill]'s LOUD guard, ADR-0000 A12); refusing is
///   loud in the returned report and safe at a provision hook, which must not
///   fail a bead's agent over one unconfigured operator arg.
/// - **The format is enforced LOUD.** A malformed overlay (a file with no asset
///   dir) THROWS rather than half-installing — a first-party packaging bug, the
///   same fail-closed posture A1 gives a breaking `grid.dart` envelope.
/// - **Sync core, async wrapper.** [OverlayMaterializer.materializeSync] is the
///   implementation (plain `dart:io`); [OverlayMaterializer.materialize]
///   delegates to it for a caller that wants a `Future` (a Flutter UI,
///   `pow-a74`'s Command). The sync entry point exists because the provision wire
///   CANNOT await: `ProcessCapability.spawn` returns a `RuntimeConfig` directly —
///   the same constraint `DartLinkService.applySync` was added for (ADR-0000 A1).
///
/// Keeping a materialized overlay OUT of git is deliberately NOT this lib's job:
/// the operator's own `~/.claude` is not a repo, and only the worktree leg has a
/// commit to protect. The wire owns that (`_excludeOverlayFromGit`), reading
/// [OverlayMaterializeReport.writtenEntryDirs].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The overlay kinds a `station_overlay` root carries, walked in this fixed
/// order (deterministic output).
const List<String> kOverlayKinds = ['skills', 'agents'];

/// Any `{{key}}` hole left in a rendered file — an installed asset has none.
final RegExp _templateHole = RegExp(r'\{\{[^}]*\}\}');

/// What became of ONE file in a materialization call — sealed, so a caller (a
/// `space install` diff renderer, the provision wire) faces every case with an
/// exhaustive `switch`.
sealed class OverlayFileOutcome {
  /// Creates the outcome for the file at [relativePath].
  const OverlayFileOutcome(this.relativePath);

  /// The file's path relative to the target root, kind-prefixed (e.g.
  /// `skills/discover/SKILL.md`).
  final String relativePath;

  /// The `<kind>/<name>` ASSET DIR this file belongs to — the format's unit
  /// (e.g. `skills/discover`). Always well-formed: the materializer throws on a
  /// file that has no asset dir, so every outcome has one.
  String get entryDir => p.joinAll(p.split(relativePath).take(2).toList());
}

/// [relativePath] was written from [sourceRoot] — the target had no file there.
class OverlayFileWritten extends OverlayFileOutcome {
  /// Creates the written outcome.
  const OverlayFileWritten(super.relativePath, {required this.sourceRoot});

  /// The overlay root it came from (an element of the call's `overlayRoots`).
  final String sourceRoot;
}

/// [relativePath] already existed at the target and was left alone (never
/// overwritten): operator-authored, a previous run, or an earlier overlay root
/// in the same call. The asset IS present at the target — just not this call's.
class OverlayFileSkipped extends OverlayFileOutcome {
  /// Creates the skipped outcome.
  const OverlayFileSkipped(super.relativePath);
}

/// [relativePath] was NOT installed: after substitution it still carried
/// [holes], and a half-bound asset reads as literal text to an agent.
class OverlayFileRefused extends OverlayFileOutcome {
  /// Creates the refusal, naming the surviving [holes] and the [boundArgs].
  const OverlayFileRefused(
    super.relativePath, {
    required this.holes,
    required this.boundArgs,
  });

  /// The unbound holes that survived substitution (e.g. `{{gridHome}}`).
  final List<String> holes;

  /// The arg names the caller DID bind (diagnostics).
  final List<String> boundArgs;

  /// Why it was refused (human-readable; the `space install` renderer prints
  /// this).
  String get reason =>
      'unbound template hole(s) ${holes.join(', ')} — not installed '
      '(bound args: ${boundArgs.isEmpty ? 'none' : boundArgs.join(', ')})';
}

/// One materialization's result: an outcome per file, in processing order
/// (overlay-root order, then [kOverlayKinds] order, then sorted path).
class OverlayMaterializeReport {
  /// Creates the report.
  const OverlayMaterializeReport({required this.files});

  /// Every file outcome, in processing order.
  final List<OverlayFileOutcome> files;

  /// The files this call wrote.
  List<OverlayFileWritten> get written => [
    for (final f in files)
      if (f is OverlayFileWritten) f,
  ];

  /// The files left untouched because the target already had them.
  List<OverlayFileSkipped> get skipped => [
    for (final f in files)
      if (f is OverlayFileSkipped) f,
  ];

  /// The files refused for unbound holes — installed NOWHERE.
  List<OverlayFileRefused> get refused => [
    for (final f in files)
      if (f is OverlayFileRefused) f,
  ];

  /// The `<kind>/<name>` asset dirs this call WROTE at least one file into —
  /// the unit a caller excludes from git (the provision wire's
  /// `_excludeOverlayFromGit`). An asset dir whose every file was SKIPPED is
  /// absent: this call put nothing new there, so there is nothing new to
  /// exclude.
  List<String> get writtenEntryDirs =>
      {for (final f in written) f.entryDir}.toList()..sort();

  /// The skill ids PRESENT at the target after this call — a `skills/<id>/`
  /// asset whose `SKILL.md` this call WROTE, or which was ALREADY there (an
  /// operator's own copy is still an installed skill). A skill whose SKILL.md
  /// was REFUSED is absent: it was not installed, so a brief must never name it.
  /// The harness discovers a skill by its `SKILL.md`, so that file — not merely
  /// the dir — is the test. The provision wire uses this to tell the agent what
  /// it may `/invoke`.
  List<String> get installedSkillIds {
    final ids = <String>{};
    for (final f in files) {
      if (f is OverlayFileRefused) continue;
      final segments = p.split(f.relativePath);
      if (segments.length == 3 &&
          segments.first == 'skills' &&
          segments.last == 'SKILL.md') {
        ids.add(segments[1]);
      }
    }
    return ids.toList()..sort();
  }
}

/// Expands `station_overlay`-shaped source roots onto a target `.claude/`-shaped
/// dir — stateless, and safe to construct anywhere (a CLI Command, a Flutter
/// interactor, a synchronous engine Capability hook). This class has NO CLI and
/// NO git dependency.
class OverlayMaterializer {
  /// Creates the materializer.
  const OverlayMaterializer();

  /// The synchronous core. Expands [overlayRoots] (already resolved and ORDERED
  /// by the caller — earlier roots win a same-path conflict) onto [targetRoot]:
  /// every file under `<root>/skills/<name>/**` then `<root>/agents/<name>/**` is
  /// rendered against [args] and mirrored to `<targetRoot>/<kind>/<relative
  /// path>`, UNLESS a file already exists there (skipped, never overwritten) or
  /// the render leaves an unbound `{{hole}}` (refused, never written). An overlay
  /// root with neither subdir, or an empty [overlayRoots], contributes nothing
  /// and is not an error.
  ///
  /// THROWS a [StateError] when a source file sits LOOSE directly under a kind
  /// dir (`skills/stray.md`) instead of inside its own asset dir
  /// (`skills/<name>/stray.md`) — a malformed vended tree is a packaging bug, and
  /// silently installing it would leave the caller unable to name the asset it
  /// just installed (or to exclude it from git).
  OverlayMaterializeReport materializeSync({
    required List<String> overlayRoots,
    required String targetRoot,
    Map<String, String> args = const {},
  }) {
    final files = <OverlayFileOutcome>[];
    for (final overlayRoot in overlayRoots) {
      for (final kind in kOverlayKinds) {
        final kindDir = Directory(p.join(overlayRoot, kind));
        if (!kindDir.existsSync()) continue;
        final sources =
            kindDir.listSync(recursive: true).whereType<File>().toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final source in sources) {
          final relativeToKind = p.relative(source.path, from: kindDir.path);
          if (p.split(relativeToKind).length < 2) {
            throw StateError(
              'malformed overlay: "$kind/$relativeToKind" (in $overlayRoot) sits '
              'directly under the kind dir — every asset lives in its own '
              '"$kind/<name>/" dir (the station_overlay format, bead `pow-kzx`)',
            );
          }
          final relativePath = p.join(kind, relativeToKind);
          final target = File(p.join(targetRoot, relativePath));
          if (target.existsSync()) {
            files.add(OverlayFileSkipped(relativePath));
            continue;
          }
          final rendered = _render(source.readAsStringSync(), args);
          final residue = _templateHole.allMatches(rendered);
          if (residue.isNotEmpty) {
            files.add(
              OverlayFileRefused(
                relativePath,
                holes: ({for (final m in residue) m.group(0)!}.toList()..sort()),
                boundArgs: args.keys.toList()..sort(),
              ),
            );
            continue;
          }
          target.parent.createSync(recursive: true);
          target.writeAsStringSync(rendered);
          files.add(OverlayFileWritten(relativePath, sourceRoot: overlayRoot));
        }
      }
    }
    return OverlayMaterializeReport(files: files);
  }

  /// The async counterpart of [materializeSync] — for a caller that CAN await (a
  /// Flutter UI, `pow-a74`'s CLI Command). Every underlying op is synchronous
  /// `dart:io`, so this only shapes the call as a `Future`; see [materializeSync]
  /// for the whole behavior contract.
  Future<OverlayMaterializeReport> materialize({
    required List<String> overlayRoots,
    required String targetRoot,
    Map<String, String> args = const {},
  }) async => materializeSync(
    overlayRoots: overlayRoots,
    targetRoot: targetRoot,
    args: args,
  );

  /// Substitutes every `{{key}}` from [args] — the same dependency-free flat
  /// mustache `PackagedAssetLoader` renders skills with.
  static String _render(String contents, Map<String, String> args) {
    var out = contents;
    args.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
    return out;
  }
}
```

Test: `cd packages/grid_assets && dart analyze` → `No issues found!` (Step 6 adds the suite).
Commit: `feat(grid_assets): add OverlayMaterializer — non-destructive, rendering, sync-core station_overlay expansion`

### Step 5 — Export it + update the package library doc

In `packages/grid_assets/lib/grid_assets.dart`, replace the "VENDED SKILLS" paragraph
(lines 51–57) with:

```dart
/// The VENDED SKILLS (bead `pow-88p`, `extension/station_overlay/skills/`) are
/// those agentic halves: `discover` is the grid home's HITL front door — it
/// dispatches on arg shape (topic research / bead advisory / bead directed),
/// researches via the vended `search` Command, and on the human's yes files an
/// ephemeral staged bead and hands to `specify`. [kVendedSkills] enumerates
/// them; [PackagedAssetLoader.renderSkill] renders one by id.
///
/// The DELIVERY leg (bead `pow-kzx`) is [OverlayMaterializer]: the CLI-free,
/// non-destructive lib that expands a `station_overlay/{skills,agents}` tree
/// onto a target `.claude/` dir, rendering each file and REFUSING to install
/// one whose holes are unbound. Both consumers ride it — this package's OWN
/// provision-time wire ([AgentCapability], which materializes the overlay into
/// every per-bead worktree so a station-spawned `claude -p` can `/invoke` a
/// vended skill) and the operator install Command (`pow-a74`).
```

Add the export in alphabetical position among the `src/assets/…` exports (immediately after the
`export 'src/assets/composition_assets.dart';` line):

```dart
export 'src/assets/overlay_materializer.dart';
```

Test: `cd packages/grid_assets && dart analyze` → `No issues found!`
Commit: `feat(grid_assets): export OverlayMaterializer`

### Step 6 — The `OverlayMaterializer` test suite

Create `packages/grid_assets/test/assets/overlay_materializer_test.dart`:

```dart
// The vended-asset OVERLAY materialization lib (bead `pow-kzx` — ADR-0001's
// missing delivery leg): [OverlayMaterializer] expands `station_overlay`-shaped
// roots onto a target `.claude/`-shaped dir — non-destructively, rendering each
// file, refusing a half-bound one, throwing on a malformed tree, unioning by tree
// position (the ORDER the roots are given in). The WIRE half (the provision hook
// that drives this into a live worktree, and the git exclusion it writes there)
// is covered in `track_h_code_extension_test.dart`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `extension/` dir with the same cwd walk the other
/// asset suites use, so the live-tree test never disagrees with the loader.
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/extension from '
    '${Directory.current.path}',
  );
}

/// Writes [contents] at [segments] under [root] (creating parents).
File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grid-overlay-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('OverlayMaterializer — fresh expand', () {
    test(
      'mirrors skills/ and agents/ onto the target, kind-prefixed, including a '
      'nested multi-file asset dir',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'foo skill');
        _write(overlay, [
          'skills',
          'foo',
          'references',
          'notes.md',
        ], 'foo notes');
        _write(overlay, ['agents', 'bar', 'AGENT.md'], 'bar agent');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target,
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
          'foo skill',
        );
        expect(
          File(
            p.join(target, 'skills', 'foo', 'references', 'notes.md'),
          ).readAsStringSync(),
          'foo notes',
        );
        expect(
          File(p.join(target, 'agents', 'bar', 'AGENT.md')).readAsStringSync(),
          'bar agent',
        );
        expect(
          report.written.map((f) => f.relativePath),
          unorderedEquals([
            p.join('skills', 'foo', 'SKILL.md'),
            p.join('skills', 'foo', 'references', 'notes.md'),
            p.join('agents', 'bar', 'AGENT.md'),
          ]),
        );
        expect(report.skipped, isEmpty);
        expect(report.refused, isEmpty);
        expect(report.installedSkillIds, ['foo']);
        expect(
          report.writtenEntryDirs,
          unorderedEquals([p.join('agents', 'bar'), p.join('skills', 'foo')]),
        );
      },
    );

    test(
      'an overlay root with neither skills/ nor agents/ contributes nothing (an '
      'empty overlay is not an error)',
      () async {
        final overlay = Directory(p.join(temp.path, 'empty'))
          ..createSync(recursive: true);
        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: p.join(temp.path, 'target'),
        );
        expect(report.files, isEmpty);
      },
    );

    test('an empty overlayRoots list contributes nothing (not an error)', () async {
      final report = await const OverlayMaterializer().materialize(
        overlayRoots: const [],
        targetRoot: p.join(temp.path, 'target'),
      );
      expect(report.files, isEmpty);
    });

    test(
      'materializeSync — the entry point the provision wire rides, since '
      'ProcessCapability.spawn cannot await — mirrors materialize',
      () {
        final overlay = Directory(p.join(temp.path, 'sync'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'sync body');
        final target = p.join(temp.path, 'target-sync');

        final report = const OverlayMaterializer().materializeSync(
          overlayRoots: [overlay.path],
          targetRoot: target,
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
          'sync body',
        );
        expect(
          report.written.single.relativePath,
          p.join('skills', 'foo', 'SKILL.md'),
        );
        expect(report.skipped, isEmpty);
        expect(report.refused, isEmpty);
      },
    );
  });

  group('OverlayMaterializer — non-destructive (skip-existing)', () {
    test(
      "a pre-existing target file is NEVER overwritten — the operator's bytes "
      'survive (positive control: the overlay offers DIFFERENT bytes at the same '
      'path)',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'vended body');
        final target = Directory(p.join(temp.path, 'target'));
        final existing = _write(target, [
          'skills',
          'foo',
          'SKILL.md',
        ], 'OPERATOR — keep me');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
        );

        expect(existing.readAsStringSync(), 'OPERATOR — keep me');
        expect(report.written, isEmpty);
        expect(
          report.skipped.single.relativePath,
          p.join('skills', 'foo', 'SKILL.md'),
        );
        // Present at the target — an operator's own copy is still installed…
        expect(report.installedSkillIds, ['foo']);
        // …but this call wrote nothing, so there is nothing new to git-exclude.
        expect(report.writtenEntryDirs, isEmpty);
      },
    );
  });

  group('OverlayMaterializer — render + refuse', () {
    test('declared args are substituted into every copied file', () async {
      final overlay = Directory(p.join(temp.path, 'overlay'));
      _write(overlay, [
        'skills',
        'foo',
        'SKILL.md',
      ], 'run {{runner}} search in {{gridHome}}');
      final target = p.join(temp.path, 'target');

      await const OverlayMaterializer().materialize(
        overlayRoots: [overlay.path],
        targetRoot: target,
        args: const {'runner': 'space', 'gridHome': '/grid/home'},
      );

      expect(
        File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
        'run space search in /grid/home',
      );
    });

    test(
      'a file left with an UNBOUND hole is REFUSED — never written (a half-bound '
      'skill would read as literal text to the agent)',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, [
          'skills',
          'foo',
          'SKILL.md',
        ], 'run {{runner}} in {{gridHome}}');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target,
          args: const {'runner': 'space'},
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).existsSync(),
          isFalse,
          reason: 'a half-bound asset is installed NOWHERE',
        );
        expect(report.written, isEmpty);
        final refused = report.refused.single;
        expect(refused.relativePath, p.join('skills', 'foo', 'SKILL.md'));
        expect(refused.holes, ['{{gridHome}}']);
        expect(refused.reason, contains('{{gridHome}}'));
        expect(
          report.installedSkillIds,
          isEmpty,
          reason: 'a refused skill must never be named to an agent',
        );
      },
    );
  });

  group('OverlayMaterializer — the format is enforced LOUD', () {
    test(
      'a file loose directly under a kind dir (no asset dir) THROWS — a malformed '
      'vended tree is a packaging bug, never a silent half-install',
      () {
        final overlay = Directory(p.join(temp.path, 'malformed'));
        _write(overlay, ['skills', 'stray.md'], 'no asset dir');

        expect(
          () => const OverlayMaterializer().materializeSync(
            overlayRoots: [overlay.path],
            targetRoot: p.join(temp.path, 'target'),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('stray.md'), contains('malformed overlay')),
            ),
          ),
        );
      },
    );
  });

  group('OverlayMaterializer — union by tree position', () {
    test('two roots with distinct skills both land — a true union', () async {
      final a = Directory(p.join(temp.path, 'a'));
      _write(a, ['skills', 'alpha', 'SKILL.md'], 'alpha');
      final b = Directory(p.join(temp.path, 'b'));
      _write(b, ['skills', 'beta', 'SKILL.md'], 'beta');
      final target = p.join(temp.path, 'target');

      final report = await const OverlayMaterializer().materialize(
        overlayRoots: [a.path, b.path],
        targetRoot: target,
      );

      expect(
        File(p.join(target, 'skills', 'alpha', 'SKILL.md')).readAsStringSync(),
        'alpha',
      );
      expect(
        File(p.join(target, 'skills', 'beta', 'SKILL.md')).readAsStringSync(),
        'beta',
      );
      expect(report.written, hasLength(2));
      expect(report.installedSkillIds, ['alpha', 'beta']);
    });

    test(
      'two roots offering the SAME path — the EARLIER tree position wins (the same '
      'skip-existing mechanism as the non-destructive case)',
      () async {
        final a = Directory(p.join(temp.path, 'a'));
        _write(a, ['skills', 'discover', 'SKILL.md'], 'root A wins');
        final b = Directory(p.join(temp.path, 'b'));
        _write(b, ['skills', 'discover', 'SKILL.md'], 'root B loses');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [a.path, b.path],
          targetRoot: target,
        );

        expect(
          File(
            p.join(target, 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          'root A wins',
        );
        expect(report.written.single.sourceRoot, a.path);
        expect(report.skipped, hasLength(1));
      },
    );
  });

  group('OverlayMaterializer — the live grid_assets station_overlay', () {
    test(
      'the REAL extension/station_overlay round-trips the vended discover skill: a '
      'non-empty, frontmatter-led SKILL.md with no {{ residue',
      () async {
        final overlayRoot = p.join(_extensionDir(), 'station_overlay');
        final target = p.join(temp.path, 'live');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlayRoot],
          targetRoot: target,
          args: const {'runner': 'space', 'gridHome': '/grid/home'},
        );

        final installed = File(p.join(target, 'skills', 'discover', 'SKILL.md'));
        expect(installed.existsSync(), isTrue);
        final body = installed.readAsStringSync();
        expect(body, startsWith('---\n'));
        expect(body, contains('space search --json'));
        expect(body, contains('/grid/home'));
        expect(body, isNot(contains('{{')));
        expect(report.installedSkillIds, contains('discover'));
        expect(report.refused, isEmpty);
      },
    );

    test(
      'the source has NO CLI and NO git dependency (UI-drivable — pow-a74 is the '
      'only CLI seam, and the wire owns git exclusion)',
      () {
        final packageRoot = p.dirname(_extensionDir());
        final source = File(
          p.join(
            packageRoot,
            'lib',
            'src',
            'assets',
            'overlay_materializer.dart',
          ),
        ).readAsStringSync();
        expect(source, isNot(contains('package:args')));
        expect(source, isNot(contains('CommandRunner')));
        expect(source, isNot(contains('GitRunner')));
      },
    );
  });
}
```

Test: `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` →
`All tests passed!`
Commit: `test(grid_assets): cover OverlayMaterializer — expand, skip-existing, render/refuse, format guard, union, live round-trip`

### Step 7 — WIRE: materialize the overlay into the worktree at provision (`AgentCapability._linkWorkspace`, ADR-0000 A1)

This is the leg round 1 of this bead's spec wrongly deferred as cross-store. ADR-0000 A1 already
names `AgentCapability._linkWorkspace`
(`packages/grid_assets/lib/src/code/code_capabilities.dart`) as the sanctioned IN-STORE provision
hook — the only point called after `GitSourceControl.provisionWorkspace` that legitimately reads the
ambient `Bead`+`Workspace`. This step extends that SAME guarded hook.

In `packages/grid_assets/lib/src/code/code_capabilities.dart`:

**(a) Two new imports.** `package:path/path.dart` joins the `package:` block (after
`import 'package:grid_runtime/grid_runtime.dart';`, line 22), and the sibling lib joins the relative
block (after `import '../assets/asset_loader.dart';`, line 27):

```dart
import 'package:path/path.dart' as p;
```
```dart
import '../assets/overlay_materializer.dart';
```

**(b) Free the `p` prefix inside `buildAgentBrief`.** That function declares a local
`final p = StringBuffer()` (line 260) which would SHADOW the new import prefix inside that one
function. The shadowing is legal Dart and analyzes clean, and `buildAgentBrief` makes no path call —
but leaving a prefix un-usable inside the one function this step also edits is a footgun. Rename the
local to `task` throughout `buildAgentBrief`'s body: the declaration (line 260), the two `p` writes
inside the nested `section(…)` closure (lines 270–273), and the `task:` argument of the final
`AgentBrief(...)` (line 350) — which becomes `AgentBrief(task: task.toString(), workingAgreement: agreement.toString())`.

**(c) The default runner binding**, as a top-level const immediately above `AgentCapability`
(before its doc comment at line 103):

```dart
/// The executable name the vended overlay's skills render `{{runner}}` against
/// (the skill's own `<runner> search --json` call — the coupled skill+command
/// pattern, ADR-0001). The first-party station composing this pack is
/// `space_station`, whose binary is `space`; any station with another verb
/// overrides it — `buildCodeRegistry(overlayArgs: {'runner': '<verb>'})`.
const String kDefaultOverlayRunner = 'space';
```

**(d) `AgentCapability`'s constructor + fields** (lines 135–142) become — the existing `devRoot` /
`linkService` params UNCHANGED, three new ones all defaulted:

```dart
  const AgentCapability({
    String? devRoot,
    DartLinkService linkService = const DartLinkService(),
    OverlayMaterializer materializer = const OverlayMaterializer(),
    String? overlayRoot,
    Map<String, String> overlayArgs = const {},
  }) : _devRoot = devRoot,
       _linkService = linkService,
       _materializer = materializer,
       _overlayRoot = overlayRoot,
       _overlayArgs = overlayArgs;

  final String? _devRoot;
  final DartLinkService _linkService;
  final OverlayMaterializer _materializer;

  /// The `station_overlay` dir [_linkWorkspace] expands into every provisioned
  /// worktree's `.claude/` (bead `pow-kzx`); null ⇒ this package's OWN vended
  /// overlay (`<PackagedAssetLoader.root>/station_overlay`). Tests inject a
  /// fixture so the wire is provable without the live tree.
  final String? _overlayRoot;

  /// The station's overrides for the overlay's template args — merged OVER the
  /// wire's own binding (`runner`/`gridHome`), so a station with a different
  /// runner verb or a real grid home wins.
  final Map<String, String> _overlayArgs;
```

Append to that constructor's existing doc comment (after "… [linkService] is injectable for
tests."):

```dart
  /// [materializer]/[overlayRoot]/[overlayArgs] are the station_overlay delivery
  /// seam (bead `pow-kzx`): the vended skills materialized into the per-bead
  /// worktree at provision, so the spawned `claude -p` can `/invoke` them.
```

**(e) `spawn` captures what provision installed and passes it to the brief.** Replace the bare call
`_linkWorkspace(bead, workspace);` (line 154) with:

```dart
    final skills = _linkWorkspace(bead, workspace);
```

and extend the existing `buildAgentBrief` call (lines 176–180) — KEEPING its `trailerToken`
argument, which bead `pow-8dx` added:

```dart
      brief: buildAgentBrief(
        bead,
        workspace,
        trailerToken: composition.trailerToken,
        skills: skills,
      ),
```

**(f) `_linkWorkspace` returns the installed skill ids** (lines 201–215) — same guard, same
fail-closed pub-link block, plus the overlay:

```dart
  List<String> _linkWorkspace(Bead bead, Workspace workspace) {
    if (!Directory(workspace.workspaceDir).existsSync()) return const [];
    final outcome = _linkService.applySync(
      metadata: bead.metadata,
      context: PubLinkContext.worktree,
      workspaceDir: workspace.workspaceDir,
      devRoot: _devRoot,
    );
    if (outcome is LinkRefused) {
      throw StateError(
        'AgentCapability: grid.dart pub linkage refused (fail-closed): '
        '${outcome.reason}',
      );
    }
    return _materializeStationOverlay(workspace);
  }

  /// Expands the vended `station_overlay` into `<workspaceDir>/.claude/` and
  /// returns the skill ids now installed there (bead `pow-kzx` — ADR-0001's
  /// delivery leg: `claude --dangerously-skip-permissions -p` is NON-bare, so it
  /// discovers `.claude/skills/`, and print mode invokes a skill only when the
  /// brief names it explicitly — hence the returned ids ride [buildAgentBrief]).
  ///
  /// Same synchronous constraint as the pub-link write above, and the same
  /// non-destructive posture ([OverlayMaterializer] never overwrites a file it
  /// did not write, and REFUSES to install one whose holes are unbound rather
  /// than shipping literal `{{runner}}` text to an agent). A missing overlay dir
  /// contributes nothing rather than erroring — the empty-overlay case, not a
  /// violated invariant.
  List<String> _materializeStationOverlay(Workspace workspace) {
    final overlayRoot =
        _overlayRoot ?? p.join(PackagedAssetLoader().root, 'station_overlay');
    if (!Directory(overlayRoot).existsSync()) return const [];
    final claudeDir = p.join(workspace.workspaceDir, '.claude');
    final report = _materializer.materializeSync(
      overlayRoots: [overlayRoot],
      targetRoot: claudeDir,
      args: {
        'runner': kDefaultOverlayRunner,
        // The station's registered root checkout is the closest thing this
        // capability holds to a grid home; a station that knows its real one
        // overrides it (`buildCodeRegistry(overlayArgs:)`). Never null — an
        // unbound hole would REFUSE the skill instead of installing it.
        'gridHome': _devRoot ?? workspace.workspaceDir,
        ..._overlayArgs,
      },
    );
    _excludeOverlayFromGit(claudeDir, report.writtenEntryDirs);
    return report.installedSkillIds;
  }

  /// Keeps what we just materialized OUT of the bead's commit: `LandCapability`
  /// commits with `git add -A` ([GitOps.commitAll]), so an untracked
  /// `.claude/skills/**` would ride every bead's PR into whatever repo the bead
  /// belongs to. Writes a SELF-IGNORING `.gitignore` — a single `*` — INSIDE each
  /// asset dir this call wrote into: `*` matches every file in that dir INCLUDING
  /// the `.gitignore` itself, so the whole vended asset is invisible to git
  /// (`git status --porcelain` stays EMPTY there and `git add -A` stages none of
  /// it), and the exclusion file is not residue either.
  ///
  /// SCOPED to the asset dirs, never a blanket `.claude/` ignore, and never a
  /// shared `.claude/.gitignore`: `.claude/` is repo-owned territory in the very
  /// repos the grid provisions worktrees from (the_grid TRACKS
  /// `.claude/skills/grid-porting/`; power_station and lenny track
  /// `.claude/settings.json`), so a shared file could be one the repo already
  /// owns. Per-asset-dir files cannot collide with it. Because a git ignore
  /// cannot hide TRACKED files, and because nothing outside the materialized
  /// asset dirs is ignored, `land`'s post-commit residue gate
  /// ([TreeVerifiableSourceControl.uncommittedResidue] → `GitOps.
  /// hasUncommittedWork` → plain `git status --porcelain`, ADR-0000 A5) still
  /// detects every other change in the worktree — including new files the coding
  /// agent itself writes under `.claude/`.
  void _excludeOverlayFromGit(String claudeDir, List<String> writtenEntryDirs) {
    for (final entryDir in writtenEntryDirs) {
      final ignore = File(p.join(claudeDir, entryDir, '.gitignore'));
      if (ignore.existsSync()) continue;
      ignore.writeAsStringSync(
        '# Per-worktree AGENT CONTEXT materialized at provision by the vended\n'
        '# station_overlay (grid_assets, bead `pow-kzx`) — never repo content.\n'
        '# `*` ignores this whole asset dir INCLUDING this file, so land\'s\n'
        '# `git add -A` cannot carry it into the bead\'s PR.\n'
        '*\n',
      );
    }
  }
```

**(g) The brief NAMES the installed skills** (print mode has no autonomous skill selection — the
station must name them, ADR-0001). `buildAgentBrief`'s signature (lines 253–257) gains ONE named,
defaulted param alongside the existing `trailerToken`:

```dart
AgentBrief buildAgentBrief(
  Bead bead,
  Workspace workspace, {
  String trailerToken = kDefaultTrailerToken,
  List<String> skills = const [],
}) {
```

and, immediately before the closing `return AgentBrief(...)` (line 350), append to the agreement
(whose last existing entry is the `..write('- Guards LOUD or GONE: …')`):

```dart
  if (skills.isNotEmpty) {
    agreement
      ..writeln()
      ..writeln()
      ..writeln(
        "The station materialized these VENDED skills into this worktree's "
        '`.claude/skills/` at provision (bead `pow-kzx`) — invoke one '
        'EXPLICITLY by name when the task calls for it (print mode selects no '
        'skill on its own, ADR-0001). They are per-worktree agent context, not '
        'repo content — already git-excluded, never commit them:',
      )
      ..write(skills.map((id) => '- `/$id`').join('\n'));
  }
```

**(h) Thread the station's overrides through `buildCodeRegistry`** (its param list, lines 857–867).
Add one defaulted param:

```dart
  Map<String, String> overlayArgs = const {},
```

and pass it at the `'agent'` registration (line 908):

```dart
      'agent': AgentCapability(devRoot: devRoot, overlayArgs: overlayArgs),
```

Test: `cd packages/grid_assets && dart analyze` → `No issues found!`
Commit: `feat(grid_assets): wire the station_overlay into AgentCapability provision — per-worktree skill delivery`

### Step 8 — WIRE test suite (extend `track_h_code_extension_test.dart`)

`packages/grid_assets/test/track_h_code_extension_test.dart` already imports `dart:io`,
`package:grid_assets/grid_assets.dart`, `package:grid_engine/grid_engine.dart`,
`package:grid_runtime/grid_runtime.dart`, `package:path/path.dart as p`, `package:test/test.dart`,
and `support/asset_fakes.dart` (which re-exports `FakeTreeContext`/`bead`/`testWorkspace`/`stepArgs`
from `package:grid_engine/testing.dart`) — no new imports. Append a new group before the final
closing `}` of `main()` (line 670):

```dart
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
        'RENDERED — every {{hole}} bound, so the agent gets a runnable skill, not '
        'literal template text',
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(devRoot: '/dev/root');
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
          const cap = AgentCapability(devRoot: '/dev/root');
          final cfg = cap.spawn(c.context, c.args);
          // The rendered brief rides as the FINAL positional of the sh-wrapped
          // claude invocation (FT-2 — `agent_harness.dart`'s claudeArgs end with
          // `brief.render()`).
          expect(cfg.args.last, contains('`/discover`'));
          expect(cfg.args.last, contains('.claude/skills/'));
        },
      );

      test(
        'the materialized asset dir is git-EXCLUDED by a SELF-IGNORING .gitignore '
        "— land commits with `git add -A`, so without this every bead's PR would "
        'carry the vended skills',
        () {
          final c = ctxAt(worktree.path);
          const cap = AgentCapability(devRoot: '/dev/root');
          cap.spawn(c.context, c.args);

          final ignore = File(
            p.join(worktree.path, '.claude', 'skills', 'discover', '.gitignore'),
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
          const cap = AgentCapability(devRoot: '/dev/root');
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
        'NON-DESTRUCTIVE: a pre-existing .claude/skills/discover/SKILL.md survives '
        'provision byte-unchanged',
        () {
          final existing = discoverSkill(worktree)..createSync(recursive: true);
          existing.writeAsStringSync('OPERATOR-AUTHORED — do not touch');

          final c = ctxAt(worktree.path);
          const cap = AgentCapability(devRoot: '/dev/root');
          cap.spawn(c.context, c.args);

          expect(existing.readAsStringSync(), 'OPERATOR-AUTHORED — do not touch');
        },
      );

      test("a station's overlayArgs override the wire's default binding", () {
        final c = ctxAt(worktree.path);
        const cap = AgentCapability(
          devRoot: '/dev/root',
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
          final fixture = Directory.systemTemp.createTempSync('overlay-fixture-');
          addTearDown(() {
            if (fixture.existsSync()) fixture.deleteSync(recursive: true);
          });
          File(p.join(fixture.path, 'skills', 'fixture-skill', 'SKILL.md'))
            ..createSync(recursive: true)
            ..writeAsStringSync('fixture body');

          final c = ctxAt(worktree.path);
          final cap = AgentCapability(
            devRoot: '/dev/root',
            overlayRoot: fixture.path,
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
            'fixture body',
          );
          expect(discoverSkill(worktree).existsSync(), isFalse);
          expect(cfg.args.last, contains('`/fixture-skill`'));
        },
      );

      test(
        'an asset whose holes are UNBOUND is never installed and never fails the '
        'spawn — and the brief does not name it',
        () {
          final fixture = Directory.systemTemp.createTempSync('overlay-unbound-');
          addTearDown(() {
            if (fixture.existsSync()) fixture.deleteSync(recursive: true);
          });
          File(p.join(fixture.path, 'skills', 'half-bound', 'SKILL.md'))
            ..createSync(recursive: true)
            ..writeAsStringSync('call {{nobodyBindsThis}}');

          final c = ctxAt(worktree.path);
          final cap = AgentCapability(
            devRoot: '/dev/root',
            overlayRoot: fixture.path,
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
          );
          final cfg = cap.spawn(c.context, c.args);

          expect(cfg.args.last, isNot(contains('VENDED skills')));
        },
      );
    },
  );
```

Test: `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` →
`All tests passed!`
Commit: `test(grid_assets): cover the provision-time station_overlay wire — rendered install, brief invocation, scoped git-exclusion, non-destructive`

### Step 9 — Full suite, then record the autonomous calls in ADR-0000 as A22

```sh
cd packages/grid_assets && dart analyze && dart test
```
→ `No issues found!` then `All tests passed!`.

Then append to `docs/adr/ADR-0000-ai-decision-register.md`, AFTER its current last entry — which is
**A21** (`pow-96y`, the discovery circuit; re-confirm with
`grep -n '^## A[0-9]' docs/adr/ADR-0000-ai-decision-register.md | tail -1` before writing, since the
register both grows and regresses) — in the file's existing entry format:

```markdown
## A22 (2026-07-13) — bead `pow-kzx`: the station_overlay delivery lib RENDERS and REFUSES rather than raw-copying; its core is SYNCHRONOUS; the provision wire binds `runner`/`gridHome` in-store, names the installed skills in the brief, and git-EXCLUDES what it materialized with a per-asset-dir self-ignoring `.gitignore`

**Decision:** the vended-asset overlay format (`extension/station_overlay/{skills,agents}/<name>/…`, Nico's placement) ships its install lib as `packages/grid_assets/lib/src/assets/overlay_materializer.dart` and is wired at the ADR-0000 A1 hook (`AgentCapability._linkWorkspace`, `code_capabilities.dart`). Seven autonomous calls:
(1) **The lib RENDERS each file against caller-supplied `args` and REFUSES (reports, never writes) a file left with an unbound `{{hole}}`** — it is not a raw file copier. The vended `discover` SKILL.md is mustache-templated (`{{runner}}`, `{{gridHome}}`); a verbatim copy would install a skill whose commands are literal `{{runner}}` text — the exact silent packaging bug A12 put the LOUD guard on `renderSkill` to stop. Refusal (an `OverlayFileRefused` outcome in the returned sealed report) is the tree-level form of that guard: loud in the report, and safe at a provision hook, which must not fail a bead's agent over one unconfigured operator arg.
(2) **`overlayRoots` is a caller-supplied ORDERED `List<String>`; the lib resolves no roster itself** (no `GridDelegate` mount, unlike `mountedRosterOf`). "Union by tree position" describes the composed behavior once a caller has built that ordered list — building a second roster-walker here would duplicate A11's.
(3) **The core is SYNCHRONOUS (`materializeSync`), with `materialize` a thin async delegate.** The wire runs inside `ProcessCapability.spawn`, which returns a `RuntimeConfig` directly and cannot await — literally A1's own `applySync` rationale, reapplied.
(4) **The wire binds the overlay's args IN-STORE** — `runner` from a new `kDefaultOverlayRunner` const (`'space'`, the first-party station's verb) and `gridHome` from the capability's registered root checkout (`devRoot`), with `buildCodeRegistry(overlayArgs:)` / `AgentCapability(overlayArgs:)` overriding both. Neither value is derivable from the capability's ambient tree (`SubstationConfig` carries no root path; the grid home is `space up --grid-home`, a station-level config), and an unbound binding would refuse the skill — so an in-store default is what makes the wire actually deliver a working skill today, with no cross-store change. A station that knows its real grid home passes it.
(5) **The brief NAMES the installed skills** (`buildAgentBrief(…, skills:)` appends `` `/discover` `` to the working agreement, alongside the `trailerToken` commit policy A18 added). ADR-0001's own resolution says print mode supports only explicit `/skill-name` invocation "because the station composes each stage's brief and names the skill" — installing the file without naming it would satisfy the letter of the bead and none of its intent.
(6) **The wire git-excludes what it materialized with a SELF-IGNORING `.gitignore` (a single `*`) written INSIDE EACH materialized asset dir** — NOT one shared `<worktree>/.claude/.gitignore`. `LandCapability` → `GitOps.commitAll` runs `git add -A` (`git_ops.dart:312`), so an untracked `.claude/skills/**` would otherwise ride every bead's PR into genesis/the_grid/power_station alike. A shared `.claude/.gitignore` was rejected because `.claude/` is REPO-OWNED territory in the very repos the grid cuts worktrees from (`git ls-files '.claude/*'`: the_grid tracks `.claude/skills/grid-porting/` + `.claude/skills/predictable-flutter/`; power_station and lenny track `.claude/settings.json`) — a non-destructive "skip if it exists" would then silently LEAK the whole vended tree into every PR, and an overwrite/append would edit a tracked repo file from a provision hook. A per-asset-dir `*` cannot collide with a repo-owned file, ignores itself (so it is not residue), and is scoped to exactly what was installed. Verified empirically against the_grid's real shape (tracked `.claude/skills/**` + `.claude/settings.json`): `git status --porcelain` stays EMPTY, `git add -A` stages nothing, and a modified tracked `.claude/skills/**` file plus a new untracked `.claude/notes.md` both stay VISIBLE — so A5's residue gate is preserved (see (6a)).
(6a) **That exclusion is deliberately compatible with A5, not a hole in it.** A5's post-commit gate reads `GitOps.hasUncommittedWork` → plain `git status --porcelain` (no `--ignored`, `git_ops.dart:185`), so an ignored file reads clear — which is the intent: the vended overlay is not the agent's work, and A5 exists to catch land committing a SUBSET of the *reviewed tree*. Because a git ignore cannot hide TRACKED files, and because the ignore is scoped to the materialized asset dirs (never a blanket `.claude/`), A5 still gates on genuine residue anywhere else in the worktree, including new `.claude/` files the coding agent itself writes.
(7) **The per-file outcome is a hand-rolled `sealed class`** (`OverlayFileWritten`/`OverlayFileSkipped`/`OverlayFileRefused`), matching this package's own idiom for this shape (`LinkOutcome`, `StoreSearchOutcome`) rather than adding `freezed` — no file in `grid_assets` uses it today. The FORMAT itself is guarded LOUD: a file with no `<kind>/<name>/` asset dir THROWS (a first-party packaging bug — A1's fail-closed posture for a breaking envelope), which is also what lets the wire safely derive the asset dirs it must exclude.
**Why:** (1)/(5)/(6) are correctness, not polish: without them the leg installs a broken skill, an agent never invokes it, and every PR the grid opens carries stray vended files. (2)/(3)/(7) reuse the nearest proven idiom in this package (A11's restraint, A1's sync constraint, the existing sealed-outcome shape). (4) is the one genuine judgement call — a hardcoded default runner verb — taken because the alternative (defer the binding to the composing station) reproduces exactly the cross-store deferral this bead was re-specced to fix.
**Affects (if promoted):** `packages/grid_assets/lib/src/assets/overlay_materializer.dart` (new), `…/lib/src/assets/asset_loader.dart` (`PackagedAssetLoader.root`, the skill path), `…/lib/src/code/code_capabilities.dart` (`kDefaultOverlayRunner`; `AgentCapability`'s `materializer`/`overlayRoot`/`overlayArgs`; `_linkWorkspace` returns the installed skill ids; `_materializeStationOverlay`/`_excludeOverlayFromGit`; `buildAgentBrief(skills:)`; `buildCodeRegistry(overlayArgs:)`), `…/lib/src/code/discovery.dart` (doc path), `lib/grid_assets.dart`, `extension/station_overlay/skills/discover/SKILL.md` (relocated), `extension/mcp/config.yaml`, `test/assets/skill_assets_test.dart`, new `test/assets/overlay_materializer_test.dart`, `test/track_h_code_extension_test.dart`. `pow-a74` consumes the same lib as its thin CLI adapter and owns the OPERATOR leg's roster resolution (its target, `~/.claude`, is not a repo, so it needs none of (6)).
**Status:** pending.
```

Commit: `docs(grid_assets): record the overlay-delivery decisions as ADR-0000 A22`

## Touches

- `packages/grid_assets/extension/skills/discover/SKILL.md` — DELETED (relocated, content unchanged).
- `packages/grid_assets/extension/station_overlay/skills/discover/SKILL.md` — NEW (the `station_overlay/{skills,agents}` format's first occupant).
- `packages/grid_assets/extension/mcp/config.yaml` — MODIFIED: the `skills:` comment block (lines 121–129) + `discover.path` (line 137) → `station_overlay/skills/discover/SKILL.md`.
- `packages/grid_assets/lib/src/assets/asset_loader.dart` — MODIFIED: library doc (lines 11–17), `kVendedSkills` doc (34–36), `loadSkillTemplate` path + doc (121–131). NEW public symbol `lib/src/assets/asset_loader.dart:PackagedAssetLoader.root` (getter). No breaking signature change.
- `packages/grid_assets/lib/src/assets/overlay_materializer.dart` — NEW. Public symbols: `lib/src/assets/overlay_materializer.dart:kOverlayKinds`, `:OverlayFileOutcome` (sealed; `relativePath`/`entryDir`), `:OverlayFileWritten` (`sourceRoot`), `:OverlayFileSkipped`, `:OverlayFileRefused` (`holes`/`boundArgs`/`reason`), `:OverlayMaterializeReport` (`files`/`written`/`skipped`/`refused`/`writtenEntryDirs`/`installedSkillIds`), `:OverlayMaterializer` (`materializeSync({overlayRoots, targetRoot, args})`, `materialize({overlayRoots, targetRoot, args})`).
- `packages/grid_assets/lib/grid_assets.dart` — MODIFIED: `export 'src/assets/overlay_materializer.dart';` + the library-doc delivery paragraph (lines 51–57).
- `packages/grid_assets/lib/src/code/code_capabilities.dart` — MODIFIED: two new imports (`package:path/path.dart as p`, `../assets/overlay_materializer.dart`); NEW public symbol `lib/src/code/code_capabilities.dart:kDefaultOverlayRunner`; `AgentCapability` gains `materializer`/`overlayRoot`/`overlayArgs` ctor params (all defaulted — every existing call site stays valid); `_linkWorkspace` now returns the installed skill ids and calls the new private `_materializeStationOverlay` + `_excludeOverlayFromGit`; `buildAgentBrief` gains an optional `skills:` named param ALONGSIDE the existing `trailerToken:` (positional signature unchanged) and renames its private local `p` → `task`; `buildCodeRegistry` gains `overlayArgs`.
- `packages/grid_assets/lib/src/code/discovery.dart` — MODIFIED: one doc-comment path (line 66) → `extension/station_overlay/skills/discover/`.
- `packages/grid_assets/test/assets/skill_assets_test.dart` — MODIFIED: header comment (line 3) + the manifest `path` assertion (line 187).
- `packages/grid_assets/test/assets/overlay_materializer_test.dart` — NEW.
- `packages/grid_assets/test/track_h_code_extension_test.dart` — MODIFIED: one new group appended before `main()`'s closing brace (line 670); existing groups untouched; no new imports.
- `docs/adr/ADR-0000-ai-decision-register.md` — MODIFIED: appended `A22`.

Re-validated against the live tree at the CURRENT base (`1d5a165` — round 3's reset; `#31`/`#32` have landed and moved these files, so every line number and signature above was re-read, not carried over). Every touched/added symbol was grepped for callers:
`AgentCapability(` — 13 hits: 11 test construction sites (8 in `track_h_code_extension_test.dart` at lines 153/275/521/536/545/599/611/637/666, 1 in `track_e_reference_inflation_test.dart:360`, and **1 NEW since the last spec round — `test/agent/role_model_ladder_test.dart:73`**, added by bead `pow-edp`), the ctor itself (`code_capabilities.dart:135`), and 1 production site (`buildCodeRegistry`, `code_capabilities.dart:908`). All pass zero or one existing named arg, so the three new all-defaulted params leave every one valid.
Only ONE existing group spawns against a REAL directory: `track_h`'s tg-ucz pub-linkage group (lines 549–669), whose four tests mount a temp worktree. They now ALSO materialize the real overlay there; their assertions read `pubspec_overrides.yaml` only, and their temp dirs are torn down, so none breaks. Its breaking-envelope test (line 642) still passes: `_linkWorkspace` throws on `LinkRefused` BEFORE `_materializeStationOverlay` is reached, so a refused envelope still writes nothing at all.
Every OTHER spawn site mounts a Workspace at a path that does NOT exist — `/w/tg-1` (`_capCtx` in `track_h`, and `role_model_ladder_test`'s `_ctx`) and `/real/activation/worktree/tg-m2q` (`track_e`) — so `_linkWorkspace`'s existing `Directory(...).existsSync()` guard early-returns exactly as today and no overlay is written; `role_model_ladder_test`'s `--model` assertions and `track_e`'s poison-leak fence are both unaffected (the brief's new lines name skill ids, never a bead field, and appear only when a skill was actually installed).
`buildAgentBrief(` — 8 hits: the production call (`code_capabilities.dart:176`), the definition (253), and 6 test calls (`track_h` 191/215/228/236/248/264, `track_e` 155/286) — all passing 2 positionals; the new `skills:` is named + defaulted, so all stay valid, and the `trailerToken:` param `pow-8dx` added is PRESERVED, not replaced.
`buildCodeRegistry(` — called across the acceptance/kernel suites and (live, cross-store) at `space_station/lib/src/up_command.dart` as `buildCodeRegistry()`; the new `overlayArgs` is defaulted, so no cross-store change is required or triggered.
`loadSkillTemplate`/`renderSkill`/`kVendedSkills` and every `extension/skills` path string — referenced ONLY by `asset_loader.dart`, `extension/mcp/config.yaml`, `test/assets/skill_assets_test.dart`, `lib/grid_assets.dart`'s doc, and `lib/src/code/discovery.dart:66`'s doc (all five edited here; verified by `grep -rn "extension/skills\|skills/discover\|loadSkillTemplate\|renderSkill\|kVendedSkills"` over `packages/` + `docs/`). `structural_test.dart`'s lib-wide grep only asserts the literal `claude` appears somewhere in lib (unaffected); `track_d_assets_test.dart` enumerates no skills path.
`PackagedAssetLoader(` — every call site passes no args or `root:`; the new `root` getter is purely additive.
The ADR amendment number was re-derived from the live register (`grep -n '^## A[0-9]'`): its last entry is **A21** (`pow-96y`, added by `#32`), so this bead's is **A22** — NOT the A14 a pre-`#32` draft of this spec assumed.
Sibling check: `bd dep list pow-kzx` → "pow-kzx has no dependencies" (no parent, no siblings). `pow-a74` DEPENDS ON this bead (not a dep of it) and owns the operator `space install` Command, its multi-package roster resolution, and migrating space_station's operator skills into overlays — none of which this plan touches.

## ADR Alignment

`ls docs/adr/` in this worktree lists only `ADR-0000-ai-decision-register.md`;
`grep -li "overlay\|skill\|materializ\|non-destructive\|provision\|deliver" docs/adr/*.md` hits only
that file (via A1/A5/A11/A12), and the warranted second sweep
`grep -li "git\|commit\|land\|residue" docs/adr/*.md` (warranted because this plan's own design
engineers around `GitOps.commitAll`/`git add -A`) hits it via A5. ADR-0001
(`ADR-0001-packaged-ai-asset-skill-command-coupling.md`) is an **untracked draft in the main
checkout**, so it exists in no per-bead worktree — it must be read from
`/Users/nico/development/engineering.memento/power_station/docs/adr/ADR-0001-packaged-ai-asset-skill-command-coupling.md`
(re-confirmed present and unchanged this round). Both documents were read in full.

- **ADR-0001 (DRAFT, main checkout) — the direct governing doc.** Its "missing leg" clause is what
  this whole bead resolves: *"delivery = **materialize the vended `SKILL.md` into the worktree's
  `.claude/skills/` at provision (+ the operator's dir at setup) and have the brief invoke it** — not
  MCP or injection… `extension/` still needs a `skills/` home added; the skill body then calls its
  vended Command via Bash. Full detail on `pow-kzx`."* Its adjacent sentence records why the brief
  must name the skill: *"Print mode supports only **explicit `/skill-name`** invocation (no
  autonomous selection) — fine here, because the station composes each stage's brief and names the
  skill."* This plan delivers all three clauses: **at provision** (Step 7's wire at the A1 hook),
  **have the brief invoke it** (Step 7g — the brief names `/discover`), and **the skill body calls
  its vended Command** (which only holds if `{{runner}}` is BOUND — hence Step 4's render+refuse
  contract). The operator's dir stays `pow-a74`, per the same clause.
- **ADR-0000 A1 (`tg-ucz`) — the wire's placement, quoted:** *"the grid.dart envelope decode+apply …
  happens inside `AgentCapability.spawn` … immediately after the ambient `Bead`/`Workspace` are read
  and guarded on `Directory(workspace.workspaceDir).existsSync()`"*, because it is *"the only point
  that is (a) called AFTER `GitSourceControl.provisionWorkspace` in the same `startOrAdopt` flow, and
  (b) already reads the ambient `Bead`+`Workspace` legitimately"*, and *"`spawn()` returns
  `RuntimeConfig` directly (not a `Future`), forcing the sync `applySync` path"*. Step 7 extends that
  SAME guarded hook rather than adding a circuit step, and Step 4's `materializeSync` exists for
  exactly the reason A1 gives for `applySync`. This is why the wiring is IN-STORE, not a cross-store
  deferral (the round-1 error this bead was re-specced to fix). A1 is also the precedent for WRITING
  into a provisioned worktree from this hook at all (it already writes `pubspec_overrides.yaml`
  there) and for the fail-closed throw on a first-party packaging bug.
- **ADR-0000 A5 (`tg-bns`) — the residue gate this plan's git-exclusion must not defeat.** A5
  established `LandCapability`'s post-`commitAll` check: *"`GitSourceControl` implements it by
  delegating to `GitOps.hasUncommittedWork` (the SAME three-gate `git status --porcelain` probe the
  worktree-reap logic already trusts) — no new git call"*, gating with *"land committed a SUBSET of
  the reviewed tree"* on any residue. Step 7f manipulates precisely the signal that probe inspects,
  so it is specified **with** A5 in hand, not around it:
  - **The probe is `git status --porcelain` with no `--ignored`** (verified live at
    `the_grid/packages/grid_runtime/lib/src/git/git_ops.dart:181–194`, and `GitSourceControl.uncommittedResidue`
    calls it with the default EMPTY `excluding`), so an ignored file reads clear. That is the intent,
    not an evasion: the vended overlay is station-provided agent context, never the agent's work, and
    A5 exists to catch `land` committing a SUBSET of *the reviewed tree*.
  - **The ignore is SCOPED to the asset dirs the wire actually wrote** (`.claude/skills/discover/.gitignore`,
    a bare `*`), and is emphatically **not** a blanket `.claude/` ignore and **not** a shared
    `.claude/.gitignore`. Because a git ignore cannot hide TRACKED files, and because nothing outside
    those asset dirs is ignored, A5's residue detection is preserved for the ENTIRE rest of the
    worktree — including new files the coding agent itself writes under `.claude/` (which a blanket
    ignore would have silently swallowed, re-creating exactly the "committed a subset" class of
    incident A5 was written to end).
  - **Verified empirically this round**, in a scratch repo reproducing the_grid's real shape (tracked
    `.claude/skills/**` + `.claude/settings.json`): with the per-asset-dir ignore in place
    `git status --porcelain` is EMPTY and `git add -A` stages nothing, while a modified tracked
    `.claude/skills/grid-porting/SKILL.md` (` M`), a new untracked `.claude/notes.md` (`??`), and a
    new untracked source file (`??`) all remain visible to the very probe A5 gates on.
- **ADR-0000 A12 (`pow-88p`) — the skill's own render contract:** it vends `discover` as *"one
  mustache-templated SKILL.md (`{{runner}}`/`{{gridHome}}`)"* with *"a LOUD unbound-hole render
  guard"*. A raw copy at delivery would defeat that guard by installing the unrendered template;
  Step 4's REFUSE outcome is the same guard at tree level, and Step 1 relocates A12's
  `extension/skills/` home to `station_overlay/skills/` per this bead's format. (A12 itself
  anticipates this: *"`pow-kzx` (delivery) consumes `kVendedSkills` + `renderSkill(runner:, gridHome:)`"* —
  this plan binds those same two args, at tree level.)
- **ADR-0000 A11 (`pow-ovh`) — two reused shapes:** its per-item sealed outcome (`StoreSearchOutcome`)
  is mirrored by `OverlayFileOutcome`, and its restraint (`mountedRosterOf` walks a `GridDelegate`
  only where a caller actually holds one) is why `OverlayMaterializer` takes ordered roots instead of
  mounting a tree from inside a capability's `spawn`, which holds no delegate.
- **ADR-0000 A18 (`pow-8dx`) — the brief contract this plan EXTENDS rather than overwrites.** A18 put
  the commit policy into the working agreement and demoted the bead id to a git TRAILER, adding
  `buildAgentBrief`'s `trailerToken` param. Step 7g adds `skills:` ALONGSIDE it and appends to the
  same agreement buffer; the acceptance keeps a regression check that the trailer policy and
  `track_e`'s poison-leak fence still hold.
- **ADR-0008 D-H (the genesis_tree doctrine, this repo's `CLAUDE.md`)** does not bind the new lib:
  `OverlayMaterializer` is a stateless `dart:io` service with no `InheritedSeed`/`build`/`dependOn*`
  surface — it mirrors `DartLinkService`, which is D-H-exempt for the same reason. `AgentCapability`
  reads its ambient values at the non-binding `spawn` edge via `getInheritedSeedOfExactType` (the
  correct EFFECT verb, ADR-0008 D3) — unchanged by this plan. On **guards LOUD or GONE**: both new
  guards are loud — the unbound-hole guard refuses the file and records it in the sealed report (and
  the brief then never names the skill), and the malformed-format guard THROWS. The
  missing-`station_overlay`-dir and missing-worktree paths are not guards but the established
  not-wired no-op this file already documents (`LandCapability` no-ops without a `SourceControl`), so
  no silent guard is added.

## Validation Plan

- [ ] WIRE — rendered install (every `{{hole}}` bound; `space search --json`, the bound grid home, no `{{`) → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — the brief names `/discover` so print-mode `claude -p` can invoke it → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — a self-ignoring `.gitignore` (`*`) is written inside `.claude/skills/discover/` → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — the exclusion is SCOPED: no `.claude/.gitignore` and no `.claude/skills/.gitignore` is written, so ADR-0000 A5's residue gate still sees the rest of the worktree → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — a pre-existing `.claude/skills/discover/SKILL.md` survives byte-unchanged → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — `overlayArgs` override renders `grid search --json` instead of the default → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — an unbound fixture asset is not installed, does not throw, is not named in the brief → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart` → `All tests passed!`
- [ ] WIRE — the brief's existing contract is intact (bead sections + the `pow-8dx` trailer policy; no skills paragraph when nothing was installed) → `cd packages/grid_assets && dart test test/track_h_code_extension_test.dart test/track_e_reference_inflation_test.dart` → `All tests passed!`
- [ ] FORMAT — `extension/station_overlay/skills/discover/SKILL.md` resolves through both the loader and the manifest → `cd packages/grid_assets && dart test test/assets/skill_assets_test.dart` → `All tests passed!`
- [ ] LIB — fresh expand mirrors `skills/`+`agents/`, nested files included, kind-prefixed → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — non-destructive positive control (existing target bytes unchanged, reported skipped) → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — render substitutes declared args; an unbound hole is REFUSED, no file is written, and `installedSkillIds` omits it → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — union by tree position (distinct paths union; same path → earlier root wins) → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — the format is enforced LOUD: a file loose under a kind dir throws a `StateError` naming it → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — edge cases (no `skills/`+`agents/` dirs; empty `overlayRoots`) yield an empty report, no throw → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — `materializeSync` mirrors `materialize` for identical input → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — the real `extension/station_overlay` round-trips a frontmatter-led, residue-free discover SKILL.md → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] LIB — no CLI and no git dependency (`package:args` / `CommandRunner` / `GitRunner` absent from the source) → `cd packages/grid_assets && dart test test/assets/overlay_materializer_test.dart` → `All tests passed!`
- [ ] No regression across the package → `cd packages/grid_assets && dart test` → `All tests passed!`, 0 failures
- [ ] Static analysis clean → `cd packages/grid_assets && dart analyze` → `No issues found!`