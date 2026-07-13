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
///   in this same call. That one skip-if-exists rule is what gives "union by
///   tree position" its precedence: roots expand IN THE GIVEN ORDER, so the
///   first root to offer a path wins.
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
///   `pow-a74`'s Command). The sync entry point exists because the provision
///   wire CANNOT await: `ProcessCapability.spawn` returns a `RuntimeConfig`
///   directly — the same constraint `DartLinkService.applySync` was added for
///   (ADR-0000 A1).
///
/// Keeping a materialized overlay OUT of git is deliberately NOT this lib's job:
/// the operator's own `~/.claude` is not a repo, and only the worktree leg has a
/// commit to protect. The wire owns that (`_excludeOverlayFromGit`), reading
/// [OverlayMaterializeReport.writtenEntryDirs].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'asset_loader.dart';

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
  /// was REFUSED is absent: it was not installed, so a brief must never name
  /// it. The harness discovers a skill by its `SKILL.md`, so that file — not
  /// merely the dir — is the test. The provision wire uses this to tell the
  /// agent what it may `/invoke`.
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
  /// every file under `<root>/skills/<name>/**` then `<root>/agents/<name>/**`
  /// is rendered against [args] and mirrored to
  /// `<targetRoot>/<kind>/<relative path>`, UNLESS a file already exists there
  /// (skipped, never overwritten) or the render leaves an unbound `{{hole}}`
  /// (refused, never written). An overlay root with neither subdir, or an empty
  /// [overlayRoots], contributes nothing and is not an error.
  ///
  /// THROWS a [StateError] when a source file sits LOOSE directly under a kind
  /// dir (`skills/stray.md`) instead of inside its own asset dir
  /// (`skills/<name>/stray.md`) — a malformed vended tree is a packaging bug,
  /// and silently installing it would leave the caller unable to name the asset
  /// it just installed (or to exclude it from git).
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
              'malformed overlay: "$kind/$relativeToKind" (in $overlayRoot) '
              'sits directly under the kind dir — every asset lives in its own '
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

  /// The async counterpart of [materializeSync] — for a caller that CAN await
  /// (a Flutter UI, `pow-a74`'s CLI Command). Every underlying op is synchronous
  /// `dart:io`, so this only shapes the call as a `Future`; see
  /// [materializeSync] for the whole behavior contract.
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
