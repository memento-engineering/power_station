/// The OPERATOR leg of overlay delivery — the UI-drivable lib under the
/// `assets install` Command.
///
/// The delivery leg built the tree-level expansion ([OverlayMaterializer]) and
/// left this leg's ROSTER RESOLUTION here (ADR-0000 A23). Three pieces, all
/// CLI-free and git-free:
///
/// - [resolveStationOverlayRoots] — WHICH overlays are in scope, discovered
///   NON-PRESCRIPTIVELY: `package:extension_discovery` over the grid home's
///   package config names every package that ships the Packaged-AI-Asset
///   manifest (`extension/mcp/config.yaml`); one that ALSO ships an
///   `extension/station_overlay/` contributes it. No pack is named here — a
///   new asset pack in the station's pubspec is in scope the moment it is.
/// - [OverlayInstallService] — expands those roots onto a repo ROOT through
///   [OverlayMaterializer], PATH-PRESERVING (the overlay's own tree decides
///   where each asset lands under the root — there is no mapping here).
/// - [renderInstallReport] — the DIFF the operator reviews.
///
/// **Committed, not gitignored.** The installed assets are meant to be COMMITTED
/// — the operator seat IS the station's manual, so a fresh clone must hold it
/// without a build step. Two guards make that safe rather than drift-prone: the
/// materializer never clobbers a file it did not generate
/// ([OverlayFileBlocked]), and `--check` ([OverlayInstallService.install]'s
/// `check`) FAILS when the installed tree has drifted from source. This leg
/// still COMMITS NOTHING and writes no git artifact — the operator reads the
/// diff and commits.
library;

import 'dart:convert';
import 'dart:io';

import 'package:extension_discovery/extension_discovery.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'mounted_tree.dart';
import 'overlay_materializer.dart';

/// The Packaged-AI-Asset manifest's target-package name: a package vends assets
/// by shipping `extension/<kAssetManifestTarget>/config.yaml` — the
/// `extension/mcp/config.yaml` shape [PackagedAssetLoader] reads and
/// `package:extension_discovery` detects.
const String kAssetManifestTarget = 'mcp';

/// The grid home the composing station AUTHORED — the ambient [sdk.GridRoot] of
/// [delegate]'s tree, resolved BY TREE POSITION in one offline mount (the A11
/// idiom; `RawAssetGrid(root:)` provides it). Null when the delegate authors no
/// `RawAssetGrid` — the Command refuses LOUD on that.
String? mountedGridHomeOf(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) =>
    mountedValueOf<sdk.GridRoot>(delegate, configuration: configuration)?.path;

/// The ORDERED `station_overlay` roots in scope for [gridHome] — every package
/// in the grid home's package config that ships BOTH the asset manifest
/// (`extension/mcp/config.yaml`) and an `extension/station_overlay/` dir,
/// sorted by package name (deterministic). Roots union in that order: the FIRST
/// to offer a path wins.
///
/// Reads the package config EXPLICITLY
/// (`<gridHome>/.dart_tool/package_config.json`) rather than the running
/// isolate's: a composing station ships as an AOT binary, which cannot find its
/// own package config, and the assets to install are the OPERATOR's project's,
/// not the binary's. `useCache: false` keeps this command's writes confined to
/// its target tree — it leaves no `.dart_tool/extension_discovery/` artifact in
/// the operator's checkout.
///
/// THROWS a [StateError] naming the probed path when the grid home has no
/// package config (LOUD: an operator who has not run `dart pub get` is told,
/// never handed a silent empty install).
Future<List<String>> resolveStationOverlayRoots({
  required String gridHome,
}) async {
  final packageConfig = File(
    p.join(gridHome, '.dart_tool', 'package_config.json'),
  );
  if (!packageConfig.existsSync()) {
    throw StateError(
      'no package config at ${packageConfig.path} — run `dart pub get` in the '
      'grid home so its vended asset packs can be discovered',
    );
  }
  final extensions = await findExtensions(
    kAssetManifestTarget,
    packageConfig: packageConfig.uri,
    useCache: false,
  );
  final ordered = [...extensions]
    ..sort((a, b) => a.package.compareTo(b.package));
  final roots = <String>[];
  for (final extension in ordered) {
    final overlay = Directory(
      p.join(extension.rootUri.toFilePath(), 'extension', 'station_overlay'),
    );
    if (overlay.existsSync()) roots.add(overlay.path);
  }
  return roots;
}

/// One install's outcome — the [OverlayMaterializeReport] (the sealed per-file
/// outcomes, consumed with an exhaustive `switch` by whoever needs the cases)
/// plus the CONTENTS of every file this run wrote or updated, so
/// [renderInstallReport] is a pure function of the report and a Flutter UI
/// renders the same diff.
class OverlayInstallReport {
  /// Creates the report.
  const OverlayInstallReport({
    required this.targetRoot,
    required this.overlayRoots,
    required this.materialized,
    required this.writtenContents,
  });

  /// The repo ROOT the overlay expanded onto (path-preserving: the overlay's own
  /// `.claude/…` lands under it).
  final String targetRoot;

  /// The overlay roots expanded, in precedence order.
  final List<String> overlayRoots;

  /// What [OverlayMaterializer] did (or, in `--check`, would do), file by file.
  final OverlayMaterializeReport materialized;

  /// `relativePath` → the final bytes for each file this run wrote/updated (or,
  /// dry, would). The diff body — identical in both modes, because the
  /// materializer carries it rather than the disk.
  final Map<String, String> writtenContents;

  /// Whether this was a `--check` PLAN — nothing was written.
  bool get dryRun => materialized.dryRun;

  /// The files this run created (or, dry, found MISSING).
  List<OverlayFileWritten> get written => materialized.written;

  /// The generated files whose body DRIFTED from source.
  List<OverlayFileUpdated> get updated => materialized.updated;

  /// The generated files already identical to source.
  List<OverlayFileUnchanged> get unchanged => materialized.unchanged;

  /// The hand-authored files this run refused to clobber.
  List<OverlayFileBlocked> get blocked => materialized.blocked;

  /// The files REFUSED for unbound holes — installed nowhere.
  List<OverlayFileRefused> get refused => materialized.refused;

  /// The skill ids present under `.claude/skills/` after this run.
  List<String> get installedSkillIds =>
      materialized.installedSkillIdsUnder(kClaudeSkillsSubtree);

  /// The process exit code.
  ///
  /// INSTALL: 0 when every in-scope file is installed or already current; 1 on
  /// any REFUSED (a half-bound asset — a packaging or config bug) or BLOCKED (a
  /// hand-authored file shadowing a vended one — the operator must resolve it).
  /// Both are LOUD by doctrine.
  ///
  /// CHECK (`dryRun`): 0 ONLY when the installed tree EQUALS source — so a
  /// MISSING file (never installed) and a DRIFTED one fail too. This is the
  /// no-drift enforcement that lets the overlay be COMMITTED rather than
  /// gitignored.
  int get exitCode {
    if (refused.isNotEmpty || blocked.isNotEmpty) return 1;
    if (dryRun && (written.isNotEmpty || updated.isNotEmpty)) return 1;
    return 0;
  }
}

/// Expands the in-scope overlays onto a repo ROOT — the UI-drivable half of
/// `<cli> assets install` (a Flutter app calls exactly this).
class OverlayInstallService {
  /// Creates the service over the [materializer] (injectable for tests).
  const OverlayInstallService({
    OverlayMaterializer materializer = const OverlayMaterializer(),
  }) : _materializer = materializer;

  final OverlayMaterializer _materializer;

  /// Expands [overlayRoots] (in precedence order) onto [targetRoot], rendering
  /// each file against [args] and stamping it with [sourceRef].
  ///
  /// [check] plans WITHOUT writing (the drift mode): the report says what WOULD
  /// change, and [OverlayInstallReport.exitCode] is non-zero unless the tree
  /// already equals source.
  ///
  /// This lib NEVER overwrites a file it did not generate ([OverlayFileBlocked]),
  /// writes nothing outside [targetRoot], and commits NOTHING: the operator
  /// reviews the diff and commits.
  Future<OverlayInstallReport> install({
    required List<String> overlayRoots,
    required String targetRoot,
    required String sourceRef,
    Map<String, String> args = const {},
    bool check = false,
  }) async {
    final materialized = await _materializer.materialize(
      overlayRoots: overlayRoots,
      targetRoot: targetRoot,
      sourceRef: sourceRef,
      args: args,
      dryRun: check,
    );
    return OverlayInstallReport(
      targetRoot: targetRoot,
      overlayRoots: overlayRoots,
      materialized: materialized,
      writtenContents: {
        for (final file in materialized.written)
          file.relativePath: file.contents,
        for (final file in materialized.updated)
          file.relativePath: file.contents,
      },
    );
  }
}

/// Renders [report] for the operator — PURE (no IO), so the CLI and a UI print
/// the same thing.
///
/// With [diff] (the default) every created/updated file is shown as a NEW-FILE
/// unified diff and every current file is NAMED. A `--check` run
/// (`report.dryRun`) prints the same lines in the CONDITIONAL — `MISSING`,
/// `DRIFTED` — because it wrote nothing. A BLOCKED or REFUSED file prints either
/// way (LOUD).
String renderInstallReport(OverlayInstallReport report, {bool diff = true}) {
  final b = StringBuffer();
  for (final file in report.materialized.files) {
    final path = p.join(report.targetRoot, file.relativePath);
    switch (file) {
      case OverlayFileWritten():
        b.writeln(report.dryRun ? 'MISSING $path' : 'installed $path');
        if (diff) {
          _writeDiff(b, path, report.writtenContents[file.relativePath]);
        }
      case OverlayFileUpdated():
        b.writeln(report.dryRun ? 'DRIFTED $path' : 'updated $path');
        if (diff) {
          _writeDiff(b, path, report.writtenContents[file.relativePath]);
        }
      case OverlayFileUnchanged():
        if (diff) b.writeln('current $path');
      case OverlayFileBlocked():
        b.writeln('BLOCKED $path: ${file.reason}');
      case OverlayFileRefused():
        b.writeln('REFUSED ${file.relativePath}: ${file.reason}');
    }
  }
  b
    ..writeln(
      'assets install${report.dryRun ? ' --check' : ''}: '
      '${report.written.length} ${report.dryRun ? 'missing' : 'installed'}, '
      '${report.updated.length} ${report.dryRun ? 'drifted' : 'updated'}, '
      '${report.unchanged.length} current, ${report.blocked.length} blocked, '
      '${report.refused.length} refused — ${report.targetRoot} '
      '<- ${report.overlayRoots.length} overlay root(s)',
    )
    ..writeln(
      report.dryRun
          ? 'assets install: NOTHING was written — this was a --check.'
          : 'assets install: NOTHING was committed — review the diff, then '
                'commit what you keep.',
    );
  return b.toString();
}

/// Appends a NEW-FILE unified diff of [contents] at [path].
void _writeDiff(StringBuffer b, String path, String? contents) {
  b
    ..writeln('--- /dev/null')
    ..writeln('+++ $path');
  for (final line in const LineSplitter().convert(contents ?? '')) {
    b.writeln('+$line');
  }
  b.writeln();
}
