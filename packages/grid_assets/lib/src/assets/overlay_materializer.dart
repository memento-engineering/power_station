/// The vended-asset OVERLAY format + its non-destructive materialization LIB
/// (ADR-0001's "missing leg": a vended skill is inert until it is INSTALLED
/// where the agent runs).
///
/// **The format is a PATH-PRESERVING OVERLAY onto a target ROOT.** A package
/// that vends agentic assets ships them under `extension/station_overlay/`, a
/// directory tree whose internal layout MIRRORS THE TARGET. A file at
/// `station_overlay/<rel>` lands at `<targetRoot>/<rel>` — so the vended tree
/// already carries the harness's own layout
/// (`station_overlay/.claude/skills/discover/SKILL.md`). There is NO kind
/// mapping and no install-target translation in this lib: the overlay AUTHOR
/// decides where an asset lands by where it sits in the tree.
///
/// **One tree, two consumers, two ROOTS.** The SAME overlay serves both legs
/// ADR-0001 names: a per-bead WORKTREE root (this package's own provision wire —
/// `AgentCapability`, `code_capabilities.dart`) and an operator STATION repo
/// root (the `assets install` Command). One root-parametric materializer, two
/// callers. They differ only in root and in [OverlayMaterializer.materializeSync]'s
/// `subtrees` SCOPE: the worktree leg takes [kClaudeSkillsSubtree] alone, because
/// a loose `.claude/settings.json` is repo-owned territory a per-asset-dir
/// `.gitignore` cannot fence (ADR-0000 A23(6)).
///
/// **The lib.** [OverlayMaterializer] is the CLI-FREE, git-free, UI-drivable
/// substrate both legs ride. It takes the ALREADY-RESOLVED, ORDERED overlay
/// roots — deciding WHICH packages are in scope is the CALLER's job; this lib
/// mounts no tree. Its rules, per file:
///
/// - **Rendered, never half-bound.** Each file is substituted against `args`. One
///   left carrying an unbound `{{hole}}` is REFUSED — reported, never written. A
///   literal `{{runner}}` in an installed skill is a silent packaging bug (the
///   tree-level counterpart of [PackagedAssetLoader.renderSkill]'s LOUD guard,
///   ADR-0000 A12); refusing is loud in the returned report and safe at a
///   provision hook, which must not fail a bead's agent over one unconfigured
///   operator arg.
/// - **Never clobber what we did not generate.** A target file with NO provenance
///   stamp is hand-authored: BLOCKED, reported, never overwritten.
/// - **Idempotent, and drift-correcting.** A stamped target whose BODY matches
///   source is UNCHANGED (left byte-for-byte alone — a stale ref alone is not
///   drift, so a re-install never churns the tree); one whose body DRIFTED is
///   regenerated (UPDATED).
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
import 'overlay_provenance.dart';

/// Where Claude Code discovers a skill inside a repo root
/// (`<root>/.claude/skills/<id>/SKILL.md`). The overlay MIRRORS the target, so
/// the vended tree carries the same path — this constant names the harness's
/// layout ONCE, for the callers that must scope to it (the worktree wire) or
/// read skill ids back out of it.
const String kClaudeSkillsSubtree = '.claude/skills';

/// The executable name the vended overlay's skills render `{{runner}}` against
/// (the skill's own `<runner> search --json` call — the coupled skill+command
/// pattern, ADR-0001). The first-party station composing this pack is
/// `space_station`, whose binary is `space`; any station with another verb
/// overrides it. Homed here because it is an OVERLAY binding, and the
/// materializer names it in every provenance stamp.
const String kDefaultOverlayRunner = 'space';

/// Any `{{key}}` hole left in a rendered file — an installed asset has none.
final RegExp _templateHole = RegExp(r'\{\{[^}]*\}\}');

/// What became of ONE file — sealed, so a caller (the `assets install` renderer,
/// the provision wire) faces every case with an exhaustive `switch`.
sealed class OverlayFileOutcome {
  /// Creates the outcome for the file at [relativePath].
  const OverlayFileOutcome(this.relativePath);

  /// The file's path relative to BOTH roots — the overlay is path-preserving, so
  /// `<overlayRoot>/<relativePath>` mirrors to `<targetRoot>/<relativePath>`
  /// (e.g. `.claude/skills/discover/SKILL.md`).
  final String relativePath;
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

  /// The overlay root it came from.
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

  /// The overlay root it came from.
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

/// [relativePath] exists at the target WITHOUT a provenance stamp — a
/// hand-authored file. NEVER clobbered, always reported, and non-zero at the
/// CLI (guards LOUD or GONE: the named invariant is "this tooling never
/// overwrites a file it did not generate").
class OverlayFileBlocked extends OverlayFileOutcome {
  /// Creates the blocked outcome.
  const OverlayFileBlocked(super.relativePath);

  /// Why it was blocked (the renderer prints this).
  String get reason =>
      'exists WITHOUT a provenance header — hand-authored, never clobbered; '
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

/// One materialization's result: an outcome per file, in processing order
/// (overlay-root order, then subtree order, then sorted path).
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

  /// The ASSET DIRS under [subtree] this call wrote or updated at least one file
  /// into — the unit the provision wire excludes from git (its per-asset-dir
  /// self-ignoring `.gitignore`, A23(6)). An asset dir is ONE level below
  /// [subtree] (`.claude/skills/discover`).
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
      if (file is! OverlayFileWritten && file is! OverlayFileUpdated) continue;
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
  /// A REFUSED or BLOCKED skill is ABSENT: it is not installed FROM THE VENDED
  /// SOURCE, so a brief that promises "the station materialized these VENDED
  /// skills" must never name it. (A blocked path holds a hand-authored file
  /// whose body this tooling neither wrote nor vetted — naming it would be a
  /// claim we cannot make.) The harness discovers a skill by its `SKILL.md`, so
  /// that file — not merely the dir — is the test.
  List<String> installedSkillIdsUnder(String subtree) {
    final ids = <String>{};
    for (final file in files) {
      if (file is OverlayFileRefused || file is OverlayFileBlocked) continue;
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

/// Expands `station_overlay`-shaped source roots onto a target ROOT,
/// PATH-PRESERVING — stateless, and safe to construct anywhere (a CLI Command, a
/// Flutter interactor, a synchronous engine Capability hook). This class has NO
/// CLI and NO git dependency.
class OverlayMaterializer {
  /// Creates the materializer.
  const OverlayMaterializer();

  /// The synchronous core. Mirrors every file under [overlayRoots] (ORDERED by
  /// the caller — the FIRST root to offer a path wins) onto [targetRoot],
  /// rendering it against [args] and STAMPING it with [sourceRef].
  ///
  /// [subtrees] scopes the expansion to those overlay-relative prefixes (e.g.
  /// `['.claude/skills']`); empty ⇒ the WHOLE overlay. The worktree wire scopes;
  /// the operator install does not.
  ///
  /// [dryRun] plans WITHOUT writing — every outcome is what WOULD happen (the
  /// `--check` drift mode).
  ///
  /// Per file: an unbound `{{hole}}` is REFUSED (never written); an absent target
  /// is WRITTEN; a stamped target whose body matches is UNCHANGED (byte-for-byte
  /// untouched); one whose body drifted is UPDATED; and a target with NO stamp is
  /// BLOCKED, never clobbered. A missing overlay root or subtree contributes
  /// nothing and is not an error.
  ///
  /// THROWS a [StateError] (via [stampProvenance]) on a vended file type that
  /// cannot carry a provenance stamp — a packaging bug, fail-closed.
  OverlayMaterializeReport materializeSync({
    required List<String> overlayRoots,
    required String targetRoot,
    required String sourceRef,
    List<String> subtrees = const [],
    Map<String, String> args = const {},
    bool dryRun = false,
  }) {
    final files = <OverlayFileOutcome>[];
    final seen = <String>{};
    final runner = args['runner'] ?? kDefaultOverlayRunner;
    for (final overlayRoot in overlayRoots) {
      for (final scope in subtrees.isEmpty ? const [''] : subtrees) {
        final dir = scope.isEmpty
            ? Directory(overlayRoot)
            : Directory(p.join(overlayRoot, scope));
        if (!dir.existsSync()) continue;
        final sources = dir.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final source in sources) {
          final relativePath = p.relative(source.path, from: overlayRoot);
          // Union by tree position: an earlier root already decided this path.
          if (!seen.add(relativePath)) continue;
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
          final existing = target.existsSync()
              ? target.readAsStringSync()
              : null;
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
                    sourceRoot: overlayRoot,
                    contents: stamped,
                  )
                : OverlayFileUpdated(
                    relativePath,
                    sourceRoot: overlayRoot,
                    contents: stamped,
                  ),
          );
        }
      }
    }
    return OverlayMaterializeReport(files: files, dryRun: dryRun);
  }

  /// The async counterpart of [materializeSync] — for a caller that CAN await (a
  /// Flutter UI, the `assets install` Command). Every underlying op is
  /// synchronous `dart:io`, so this only shapes the call as a `Future`; see
  /// [materializeSync] for the whole behavior contract.
  Future<OverlayMaterializeReport> materialize({
    required List<String> overlayRoots,
    required String targetRoot,
    required String sourceRef,
    List<String> subtrees = const [],
    Map<String, String> args = const {},
    bool dryRun = false,
  }) async => materializeSync(
    overlayRoots: overlayRoots,
    targetRoot: targetRoot,
    sourceRef: sourceRef,
    subtrees: subtrees,
    args: args,
    dryRun: dryRun,
  );

  /// Substitutes every `{{key}}` from [args] — the same dependency-free flat
  /// mustache `PackagedAssetLoader` renders skills with.
  static String _render(String contents, Map<String, String> args) {
    var out = contents;
    args.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
    return out;
  }
}
