/// The vended-asset OVERLAY WRITER — non-destructive materialization of an
/// already-RESOLVED asset set (ADR-0001's "missing leg": a vended skill is inert
/// until it is INSTALLED where the agent runs).
///
/// **It writes a RESOLUTION, never a walk.** The file set is
/// [GridAssetResolution.artifacts] — the one pure selector evaluation over the
/// station-generated registry (`asset_resolution.dart`,
/// `power_station#one-asset-resolution-defines-tree-and-writers`). Each resolved
/// artifact already carries its EXACT source file and its root-relative target,
/// so this lib enumerates no source tree, maps no path, and cannot select a
/// different set than the tree mounted. An undeclared file sitting next to a
/// vended one is not an asset and is never installed.
///
/// **One resolution, two consumers, two ROOTS.** The SAME resolution serves both
/// legs ADR-0001 names: a per-bead WORKTREE root (this package's own provision
/// wire — `AgentCapability`, `code_capabilities.dart`) and an operator STATION
/// repo root (the `assets install` Command). They differ only in root and in
/// [OverlayMaterializer.materializeSync]'s `subtrees` SCOPE: the worktree leg
/// takes [kWorktreeOverlaySubtrees] — the per-harness SKILL trees,
/// `.claude/skills` and `.agents/skills` — because a loose
/// `.claude/settings.json` is repo-owned territory a per-asset-dir `.gitignore`
/// cannot fence (`power_station#the-worktree-overlay-scope-widens-to-every-skill-tree`,
/// A23(6)). Every path in scope sits inside an `<id>/` asset dir, so the fence
/// still covers all of it.
///
/// Its rules, per file:
///
/// - **Rendered, never half-bound.** Each file is substituted against the
///   resolution's render arguments. One left carrying an unbound `{{hole}}` is
///   REFUSED — reported, never written. A literal `{{runner}}` in an installed
///   skill is a silent packaging bug (the tree-level counterpart of
///   [PackagedAssetLoader.renderSkill]'s LOUD guard, ADR-0000 A12); refusing is
///   loud in the returned report and safe at a provision hook, which must not
///   fail a bead's agent over one unconfigured operator arg.
/// - **Never clobber what we did not generate.** A target file with NO provenance
///   stamp is hand-authored: BLOCKED, reported, never overwritten.
/// - **Idempotent, and drift-correcting.** A stamped target whose BODY matches
///   source is UNCHANGED (left byte-for-byte alone — a stale ref alone is not
///   drift, so a re-install never churns the tree); one whose body DRIFTED is
///   regenerated (UPDATED).
/// - **Stale, never swept.** A STAMPED target this tooling generated that the
///   current resolution no longer selects is reported [OverlayFileStale] — named,
///   and left exactly where it is. Reporting is loud; deleting an operator's
///   committed file because a selector changed is not this lib's call.
/// - **Sync core, async wrapper.** [OverlayMaterializer.materializeSync] is the
///   implementation; [OverlayMaterializer.materialize] delegates for a caller
///   that wants a `Future` (a Flutter UI, the `assets install` Command). The sync
///   entry point exists because the provision wire CANNOT await:
///   `ProcessCapability.spawn` returns a `RuntimeConfig` directly (ADR-0000 A1).
///
/// Keeping a materialized overlay OUT of git is deliberately NOT this lib's job:
/// only the worktree leg has a commit to protect, and the operator's install is
/// meant to be committed. The wire owns that (`_excludeOverlayFromGit`), reading
/// [OverlayMaterializeReport.writtenAssetDirsUnder].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'asset_loader.dart';
import 'asset_resolution.dart';
import 'overlay_provenance.dart';

/// Where Claude Code discovers a skill inside a repo root
/// (`<root>/.claude/skills/<id>/SKILL.md`) — the harness's layout named ONCE,
/// for the callers that must scope to it (the worktree wire) or read skill ids
/// back out of it.
const String kClaudeSkillsSubtree = '.claude/skills';

/// Where Codex discovers a skill inside a repo root
/// (`<root>/.agents/skills/<id>/SKILL.md`, scanned from cwd up to the repo
/// root). Copilot CLI reads this tree AND `.claude/skills`, so the two legs
/// below already serve it — there is no third rendering.
const String kAgentsSkillsSubtree = '.agents/skills';

/// Subtrees materialized into an agent worktree — one per harness SKILL tree,
/// and nothing else: each is a set of `<id>/` asset dirs, which is what keeps
/// the per-asset-dir git fence able to cover every path the leg writes.
///
/// Landing consumes this same list, so a new worktree subtree is rendered and
/// restored by changing this manifest once.
const List<String> kWorktreeOverlaySubtrees = [
  kClaudeSkillsSubtree,
  kAgentsSkillsSubtree,
];

/// The harness target heads a materialized asset can land under — the whole
/// territory the STALE scan reads when a caller scopes to nothing.
const List<String> kOverlayTargetHeads = [kClaudeTargetHead, kAgentsTargetHead];

/// The executable name the vended overlay's skills render `{{runner}}` against
/// (the skill's own `<runner> search --json` call — the coupled skill+command
/// pattern, ADR-0001). The first-party station composing this pack is
/// `space_station`, whose binary is `space`; any station with another verb
/// overrides it. Homed here because it is an OVERLAY binding, and the
/// materializer names it in every provenance stamp.
const String kDefaultOverlayRunner = 'space';

/// Any `{{key}}` hole left in a rendered file — an installed asset has none.
final RegExp _templateHole = RegExp(r'\{\{[^}]*\}\}');

/// How a path reads in a `--check` report — the CLOSED classification vocabulary
/// `assets install --check` prints and exits on.
enum OverlayCheckClassification {
  /// Generated here and identical to source.
  inSync('IN SYNC'),

  /// Generated here and DRIFTED from source (or refused for an unbound hole,
  /// which is the same operator answer: the installed tree does not match what
  /// the source would produce).
  drifted('DRIFTED'),

  /// Present but NOT generated by this tooling — hand-authored, or a symlink.
  handEdited('HAND-EDITED'),

  /// Selected by the resolution and absent from the target.
  missing('MISSING'),

  /// Generated here once, and no longer selected by the resolution.
  stale('STALE');

  const OverlayCheckClassification(this.label);

  /// The exact label the report prints.
  final String label;
}

/// What became of ONE file — sealed, so a caller (the `assets install` renderer,
/// the provision wire) faces every case with an exhaustive `switch`.
sealed class OverlayFileOutcome {
  /// Creates the outcome for the file at [relativePath].
  const OverlayFileOutcome(this.relativePath);

  /// The file's path relative to the TARGET root (e.g.
  /// `.claude/skills/discover/SKILL.md`) — the resolution's own target path.
  final String relativePath;

  /// How this outcome reads in a `--check` report.
  OverlayCheckClassification get checkClassification => switch (this) {
    OverlayFileWritten() => OverlayCheckClassification.missing,
    OverlayFileUpdated() ||
    OverlayFileRefused() => OverlayCheckClassification.drifted,
    OverlayFileUnchanged() => OverlayCheckClassification.inSync,
    OverlayFileBlocked() => OverlayCheckClassification.handEdited,
    OverlayFileStale() => OverlayCheckClassification.stale,
  };
}

/// [relativePath] did not exist at the target: this call WROTE it (or, in a
/// `dryRun`, found it MISSING).
class OverlayFileWritten extends OverlayFileOutcome {
  /// Creates the written outcome.
  const OverlayFileWritten(
    super.relativePath, {
    required this.sourceRoot,
    required this.contents,
  });

  /// The vending package root it came from.
  final String sourceRoot;

  /// The final, STAMPED bytes — what is on disk, or (in a `dryRun`) what would
  /// be. Carried so a renderer diffs the exact file without re-reading it, and
  /// says the same thing in both modes.
  final String contents;
}

/// [relativePath] was GENERATED by this tooling (it carries the provenance
/// stamp) and its body DRIFTED from source: this call regenerated it (or, in a
/// `dryRun`, reported the drift). Only the BODY decides — a stale source ref in
/// an otherwise-identical file is not drift.
class OverlayFileUpdated extends OverlayFileOutcome {
  /// Creates the updated outcome.
  const OverlayFileUpdated(
    super.relativePath, {
    required this.sourceRoot,
    required this.contents,
  });

  /// The vending package root it came from.
  final String sourceRoot;

  /// The final, STAMPED bytes — see [OverlayFileWritten.contents].
  final String contents;
}

/// [relativePath] is already generated AND identical to source — nothing was
/// written. A re-install is idempotent: the file is left byte-for-byte alone.
class OverlayFileUnchanged extends OverlayFileOutcome {
  /// Creates the unchanged outcome.
  const OverlayFileUnchanged(super.relativePath);
}

/// [relativePath] exists at the target but was NOT generated by this tooling —
/// a hand-authored file (no provenance stamp) or a SYMLINK. NEVER clobbered,
/// always reported, and non-zero at the CLI (guards LOUD or GONE: the named
/// invariants are "this tooling never overwrites a file it did not generate" and
/// "it writes nothing outside the target root").
class OverlayFileBlocked extends OverlayFileOutcome {
  /// Creates the blocked outcome. [symlink] ⇒ the target path is a link.
  const OverlayFileBlocked(super.relativePath, {this.symlink = false});

  /// Whether the target path is a SYMLINK (rather than an unstamped file).
  final bool symlink;

  /// Why it was blocked, and how the operator clears it (the renderer prints
  /// this).
  String get reason => symlink
      ? 'is a SYMLINK — never generated by this tooling, and writing through it '
            'would mutate a file OUTSIDE the target root; remove the link to '
            'let the vended file install'
      : 'exists WITHOUT a provenance header — hand-authored, never clobbered; '
            'delete it to let the vended file install';
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

  /// Why it was refused.
  String get reason =>
      'unbound template hole(s) ${holes.join(', ')} — not installed '
      '(bound args: ${boundArgs.isEmpty ? 'none' : boundArgs.join(', ')})';
}

/// [relativePath] carries this tooling's provenance stamp but the CURRENT
/// resolution does not select it — an asset that was withdrawn, excluded, or
/// whose selector stopped holding.
///
/// Reported, never repaired: the file is left byte-for-byte alone in BOTH modes.
/// A generated file the operator committed is theirs to delete.
class OverlayFileStale extends OverlayFileOutcome {
  /// Creates the stale outcome.
  const OverlayFileStale(super.relativePath);

  /// Why it is reported, and what the operator does about it.
  String get reason =>
      'generated here but absent from the selected resolution; left untouched';
}

/// One materialization's result: an outcome per file, in resolution order, then
/// the stale paths (sorted) the same scope turned up at the target.
class OverlayMaterializeReport {
  /// Creates the report. [dryRun] ⇒ nothing was written; every outcome is what
  /// WOULD happen (the `--check` mode).
  const OverlayMaterializeReport({required this.files, required this.dryRun});

  /// Every file outcome, in processing order.
  final List<OverlayFileOutcome> files;

  /// Whether this was a PLAN (`--check`) rather than a write.
  final bool dryRun;

  /// The files this call wrote (or, dry, would create).
  List<OverlayFileWritten> get written =>
      files.whereType<OverlayFileWritten>().toList();

  /// The generated files whose body drifted from source.
  List<OverlayFileUpdated> get updated =>
      files.whereType<OverlayFileUpdated>().toList();

  /// The generated files already identical to source.
  List<OverlayFileUnchanged> get unchanged =>
      files.whereType<OverlayFileUnchanged>().toList();

  /// The hand-authored files this call refused to clobber.
  List<OverlayFileBlocked> get blocked =>
      files.whereType<OverlayFileBlocked>().toList();

  /// The files refused for unbound holes — installed NOWHERE.
  List<OverlayFileRefused> get refused =>
      files.whereType<OverlayFileRefused>().toList();

  /// The generated files the resolution no longer selects — reported, untouched.
  List<OverlayFileStale> get stale =>
      files.whereType<OverlayFileStale>().toList();

  /// The ASSET DIRS under [subtree] this call wrote or updated at least one file
  /// into — the unit the provision wire excludes from git (its per-asset-dir
  /// self-ignoring `.gitignore`, A23(6)). An asset dir is ONE level below
  /// [subtree] (`.claude/skills/discover`).
  ///
  /// A STALE, BLOCKED or REFUSED path contributes nothing: this call wrote none
  /// of them, so fencing their dirs would ignore territory it does not own.
  ///
  /// THROWS a [StateError] when a written file sits LOOSE directly under
  /// [subtree] with no asset dir: the caller asked for the dirs it must fence,
  /// and a loose file cannot be fenced per-asset-dir without ignoring repo-owned
  /// territory — A23(6)'s own reason for rejecting a shared `.claude/.gitignore`.
  /// This is A23(7)'s LOUD malformed-tree guard, RE-HOMED from the walk (where
  /// the path-preserving format now legitimately carries loose files like
  /// `.claude/settings.json`) to the one caller whose invariant it protects.
  List<String> writtenAssetDirsUnder(String subtree) {
    final dirs = <String>{};
    for (final file in files) {
      final wrote = switch (file) {
        OverlayFileWritten() || OverlayFileUpdated() => true,
        OverlayFileUnchanged() ||
        OverlayFileBlocked() ||
        OverlayFileRefused() ||
        OverlayFileStale() => false,
      };
      if (!wrote) continue;
      final within = _within(file.relativePath, subtree);
      if (within == null) continue;
      final segments = p.split(within);
      if (segments.length < 2) {
        throw StateError(
          'malformed overlay: "${file.relativePath}" sits directly under '
          '"$subtree" with no asset dir — the wire cannot git-fence a loose '
          'file there without ignoring repo-owned territory (A23(6))',
        );
      }
      dirs.add(p.join(subtree, segments.first));
    }
    return dirs.toList()..sort();
  }

  /// The skill ids PRESENT under [subtree] after this call — a
  /// `<subtree>/<id>/SKILL.md` this call wrote, updated, or found already
  /// generated and current.
  ///
  /// A REFUSED, BLOCKED or STALE skill is ABSENT: it is not installed FROM THE
  /// VENDED SOURCE by this call, so a brief that promises "the station
  /// materialized these VENDED skills" must never name it. (A blocked path holds
  /// a hand-authored file whose body this tooling neither wrote nor vetted, and
  /// a stale one is no longer selected at all — naming either would be a claim
  /// we cannot make.) The harness discovers a skill by its `SKILL.md`, so that
  /// file — not merely the dir — is the test.
  List<String> installedSkillIdsUnder(String subtree) {
    final ids = <String>{};
    for (final file in files) {
      final installed = switch (file) {
        OverlayFileWritten() ||
        OverlayFileUpdated() ||
        OverlayFileUnchanged() => true,
        OverlayFileBlocked() ||
        OverlayFileRefused() ||
        OverlayFileStale() => false,
      };
      if (!installed) continue;
      final within = _within(file.relativePath, subtree);
      if (within == null) continue;
      final segments = p.split(within);
      if (segments.length == 2 && segments.last == 'SKILL.md') {
        ids.add(segments.first);
      }
    }
    return ids.toList()..sort();
  }

  /// [relativePath] with [subtree] stripped, or null when it is not under it.
  static String? _within(String relativePath, String subtree) {
    final prefix = '${p.normalize(subtree)}${p.separator}';
    final normalized = p.normalize(relativePath);
    if (!normalized.startsWith(prefix)) return null;
    return normalized.substring(prefix.length);
  }
}

/// Writes a [GridAssetResolution] onto a target ROOT — stateless, and safe to
/// construct anywhere (a CLI Command, a Flutter interactor, a synchronous engine
/// Capability hook). This class has NO CLI and NO git dependency.
class OverlayMaterializer {
  /// Creates the materializer.
  const OverlayMaterializer();

  /// The synchronous core. Writes exactly [resolution]'s selected artifacts
  /// (scoped by [subtrees]) onto [targetRoot], rendering each against
  /// [GridAssetResolution.renderArguments] and STAMPING it with [sourceRef].
  ///
  /// [subtrees] scopes to those root-relative prefixes (e.g.
  /// `['.claude/skills']`); empty ⇒ every selected artifact. The worktree wire
  /// scopes; the operator install does not.
  ///
  /// [dryRun] plans WITHOUT writing — every outcome is what WOULD happen (the
  /// `--check` drift mode).
  ///
  /// Per file: an unbound `{{hole}}` is REFUSED (never written); an absent target
  /// is WRITTEN; a stamped target whose body matches is UNCHANGED (byte-for-byte
  /// untouched); one whose body drifted is UPDATED; and a target with NO stamp is
  /// BLOCKED, never clobbered. Every STAMPED file the same scope holds at the
  /// target that the resolution does NOT select is reported STALE and left alone.
  ///
  /// THROWS a [StateError] when a selected artifact's SOURCE is missing (the
  /// resolution named a file the vending package does not ship — a packaging
  /// bug, fail-closed rather than a silently shrunken install), or (via
  /// [stampProvenance]) on a vended file type that cannot carry a stamp.
  OverlayMaterializeReport materializeSync({
    required GridAssetResolution resolution,
    required String targetRoot,
    required String sourceRef,
    List<String> subtrees = const [],
    bool dryRun = false,
  }) {
    final files = <OverlayFileOutcome>[];
    final selected = resolution.artifactsUnder(subtrees);
    final args = resolution.renderArguments;
    final runner = args['runner'] ?? kDefaultOverlayRunner;
    for (final resolved in selected) {
      final source = File(resolved.sourcePath);
      if (!source.existsSync()) {
        throw StateError(
          'selected artifact source is missing: ${resolved.sourcePath}',
        );
      }
      final relativePath = resolved.relativePath;
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
      final target = File(p.join(targetRoot, relativePath));
      // A SYMLINK — at the file OR at any ancestor dir — is never something
      // this tooling generated (it only ever writes regular files), and
      // writing THROUGH one would mutate a file outside the target root,
      // breaking this lib's "writes nothing outside targetRoot" promise. It
      // is also exactly how an operator seat hand-wires its assets today
      // (`.claude/skills/x -> ../../extension/skills/x` — a symlinked DIR,
      // so the file under it is not itself a link), and a DANGLING link
      // would crash the write outright. Blocked, never followed.
      if (_escapesTargetRoot(targetRoot, relativePath)) {
        files.add(OverlayFileBlocked(relativePath, symlink: true));
        continue;
      }
      final existing = target.existsSync() ? target.readAsStringSync() : null;
      if (existing != null && !hasProvenance(existing)) {
        files.add(OverlayFileBlocked(relativePath));
        continue;
      }
      if (existing != null && stripProvenance(existing) == rendered) {
        files.add(OverlayFileUnchanged(relativePath));
        continue;
      }
      final stamped = stampProvenance(
        rendered,
        relativePath: relativePath,
        sourceRef: sourceRef,
        runner: runner,
      );
      if (!dryRun) {
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(stamped);
      }
      files.add(
        existing == null
            ? OverlayFileWritten(
                relativePath,
                sourceRoot: resolved.packageRoot,
                contents: stamped,
              )
            : OverlayFileUpdated(
                relativePath,
                sourceRoot: resolved.packageRoot,
                contents: stamped,
              ),
      );
    }
    files.addAll(
      _staleOutcomes(
        targetRoot: targetRoot,
        selectedPaths: selected
            .map((artifact) => p.normalize(artifact.relativePath))
            .toSet(),
        subtrees: subtrees,
      ),
    );
    return OverlayMaterializeReport(
      files: List<OverlayFileOutcome>.unmodifiable(files),
      dryRun: dryRun,
    );
  }

  /// The async counterpart of [materializeSync] — for a caller that CAN await (a
  /// Flutter UI, the `assets install` Command). Every underlying op is
  /// synchronous `dart:io`, so this only shapes the call as a `Future`; see
  /// [materializeSync] for the whole behavior contract.
  Future<OverlayMaterializeReport> materialize({
    required GridAssetResolution resolution,
    required String targetRoot,
    required String sourceRef,
    List<String> subtrees = const [],
    bool dryRun = false,
  }) async => materializeSync(
    resolution: resolution,
    targetRoot: targetRoot,
    sourceRef: sourceRef,
    subtrees: subtrees,
    dryRun: dryRun,
  );

  /// The STAMPED files under this call's scope at [targetRoot] that
  /// [selectedPaths] does not name — reported, never deleted, in either mode.
  ///
  /// Reads only the scoped heads (the worktree leg's skill trees, or
  /// [kOverlayTargetHeads] for an unscoped install), so it can never wander into
  /// the rest of the operator's repo. An UNSTAMPED file it meets is somebody
  /// else's and is not reported at all — this lib speaks only about files it
  /// generated.
  List<OverlayFileStale> _staleOutcomes({
    required String targetRoot,
    required Set<String> selectedPaths,
    required List<String> subtrees,
  }) {
    final roots = subtrees.isEmpty ? kOverlayTargetHeads : subtrees;
    final stale = <OverlayFileStale>[];
    final seen = <String>{};
    for (final relativeRoot in roots) {
      final root = Directory(p.join(targetRoot, relativeRoot));
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.normalize(p.relative(entity.path, from: targetRoot));
        if (selectedPaths.contains(relative)) continue;
        if (!seen.add(relative)) continue;
        if (hasProvenance(entity.readAsStringSync())) {
          stale.add(OverlayFileStale(relative));
        }
      }
    }
    return stale
      ..sort((left, right) => left.relativePath.compareTo(right.relativePath));
  }

  /// Whether writing `<targetRoot>/<relativePath>` would land OUTSIDE
  /// [targetRoot] by following a symlink — the file itself being a link, or any
  /// EXISTING ancestor dir under the root being one.
  ///
  /// Guards the named invariant "this lib writes nothing outside the target
  /// root". A dangling link counts: `File.existsSync()` is false through one, so
  /// an unguarded write would follow it and throw instead of reporting.
  static bool _escapesTargetRoot(String targetRoot, String relativePath) {
    if (FileSystemEntity.isLinkSync(p.join(targetRoot, relativePath))) {
      return true;
    }
    var dir = targetRoot;
    for (final segment in p.split(p.dirname(relativePath))) {
      if (segment == '.' || segment.isEmpty) continue;
      dir = p.join(dir, segment);
      if (FileSystemEntity.isLinkSync(dir)) return true;
    }
    return false;
  }

  /// Substitutes every `{{key}}` from [args] — the same dependency-free flat
  /// mustache `PackagedAssetLoader` renders skills with.
  static String _render(String contents, Map<String, String> args) {
    var out = contents;
    args.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
    return out;
  }
}
