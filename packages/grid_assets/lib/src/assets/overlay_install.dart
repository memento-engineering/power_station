/// The OPERATOR leg of overlay delivery — the UI-drivable lib under the
/// `install` Command.
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
/// - [OverlayInstallService] — expands those roots onto the operator's
///   `.claude/` through [OverlayMaterializer] (a file the target already has is
///   NEVER overwritten) and reads back what it wrote, so the renderer is PURE.
/// - [renderInstallReport] — the DIFF the operator reviews.
///
/// This leg COMMITS NOTHING and writes no git artifact. That is the ONE place
/// it departs from the provision wire, which self-ignores what it materialized
/// (A23(6)) because `land` commits the worktree with `git add -A`: the
/// operator's overlay is meant to be COMMITTED — by the operator, after reading
/// the diff — so hiding it from git would defeat the point.
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

/// The operator's `.claude/` dir under [gridHome] — the default install target
/// (the grid home is where the operator runs their agent).
String operatorClaudeDir(String gridHome) => p.join(gridHome, '.claude');

/// The grid home the composing station AUTHORED — the ambient [sdk.GridRoot] of
/// [delegate]'s tree, resolved BY TREE POSITION in one offline mount (the A11
/// idiom; `RawAssetGrid(root:)` provides it). Null when the delegate authors no
/// `RawAssetGrid` — the Command refuses LOUD on that.
String? mountedGridHomeOf(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) => mountedValueOf<sdk.GridRoot>(
  delegate,
  configuration: configuration,
)?.path;

/// The ORDERED `station_overlay` roots in scope for [gridHome] — every package
/// in the grid home's package config that ships BOTH the asset manifest
/// (`extension/mcp/config.yaml`) and an `extension/station_overlay/` dir,
/// sorted by package name (deterministic). Roots union in that order: the FIRST
/// to offer a path wins, per [OverlayMaterializer]'s skip-if-exists rule — and
/// a file the operator already has beats every root.
///
/// Reads the package config EXPLICITLY
/// (`<gridHome>/.dart_tool/package_config.json`) rather than the running
/// isolate's: a composing station ships as an AOT binary, which cannot find its
/// own package config, and the assets to install are the OPERATOR's project's,
/// not the binary's. `useCache: false` keeps this command's writes confined to
/// its target `.claude/` tree — it leaves no `.dart_tool/extension_discovery/`
/// artifact in the operator's checkout.
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
/// plus the CONTENTS of every file this run wrote, so [renderInstallReport] is
/// a pure function of the report and a Flutter UI renders the same diff.
class OverlayInstallReport {
  /// Creates the report.
  const OverlayInstallReport({
    required this.targetRoot,
    required this.overlayRoots,
    required this.materialized,
    required this.writtenContents,
  });

  /// The operator `.claude/` dir the overlay expanded onto.
  final String targetRoot;

  /// The overlay roots expanded, in precedence order.
  final List<String> overlayRoots;

  /// What [OverlayMaterializer] did, file by file.
  final OverlayMaterializeReport materialized;

  /// `relativePath` → the contents this run wrote there (the diff body).
  final Map<String, String> writtenContents;

  /// The files this run wrote.
  List<OverlayFileWritten> get written => materialized.written;

  /// The files left untouched because the target already had them.
  List<OverlayFileSkipped> get skipped => materialized.skipped;

  /// The files REFUSED for unbound holes — installed nowhere.
  List<OverlayFileRefused> get refused => materialized.refused;

  /// The skill ids PRESENT at the target after this run.
  List<String> get installedSkillIds => materialized.installedSkillIds;

  /// The process exit code: 0 when every in-scope file is either installed or
  /// already present (a skip is not a failure — a re-install is idempotent);
  /// 1 when ANY file was REFUSED, because a half-bound asset is a packaging or
  /// config bug the operator must see (LOUD, per doctrine).
  int get exitCode => refused.isEmpty ? 0 : 1;
}

/// Expands the in-scope overlays onto the operator's `.claude/` — the
/// UI-drivable half of `<cli> install` (a Flutter app calls exactly this).
class OverlayInstallService {
  /// Creates the service over the [materializer] (injectable for tests).
  const OverlayInstallService({
    OverlayMaterializer materializer = const OverlayMaterializer(),
  }) : _materializer = materializer;

  final OverlayMaterializer _materializer;

  /// Expands [overlayRoots] (in precedence order) onto [targetRoot], rendering
  /// every file against [args], and reads back what it wrote.
  ///
  /// NON-DESTRUCTIVE, mirroring `DartLinkService`'s never-overwrite posture
  /// (ADR-0000 A1): a file the target already has is SKIPPED — this domain
  /// never overwrites or deletes what it did not write. Writes NOTHING outside
  /// [targetRoot], and nothing at all beyond the expanded files: the operator
  /// reviews the diff and commits.
  Future<OverlayInstallReport> install({
    required List<String> overlayRoots,
    required String targetRoot,
    Map<String, String> args = const {},
  }) async {
    final materialized = await _materializer.materialize(
      overlayRoots: overlayRoots,
      targetRoot: targetRoot,
      args: args,
    );
    return OverlayInstallReport(
      targetRoot: targetRoot,
      overlayRoots: overlayRoots,
      materialized: materialized,
      writtenContents: {
        for (final file in materialized.written)
          file.relativePath: File(
            p.join(targetRoot, file.relativePath),
          ).readAsStringSync(),
      },
    );
  }
}

/// Renders [report] for the operator — PURE (no IO), so the CLI and a UI print
/// the same thing.
///
/// With [diff] (the default) every written file is shown as a NEW-FILE unified
/// diff (`--- /dev/null` / `+++ <path>` / `+`-prefixed body) — everything this
/// leg installs is new, because it never overwrites — and the pre-existing
/// files are NAMED as skipped, so "why didn't my update land" has an answer on
/// stdout. Nothing here commits anything; the closing line says so.
///
/// With [diff] false (`--no-diff`) the diff bodies AND the pre-existing files
/// are omitted: the output reports only what this run ADDED. A REFUSAL prints
/// either way (LOUD).
String renderInstallReport(OverlayInstallReport report, {bool diff = true}) {
  final b = StringBuffer();
  for (final file in report.written) {
    final path = p.join(report.targetRoot, file.relativePath);
    if (!diff) {
      b.writeln('installed $path');
      continue;
    }
    b
      ..writeln('--- /dev/null')
      ..writeln('+++ $path');
    final contents = report.writtenContents[file.relativePath] ?? '';
    for (final line in const LineSplitter().convert(contents)) {
      b.writeln('+$line');
    }
    b.writeln();
  }
  if (diff) {
    for (final file in report.skipped) {
      b.writeln(
        'skipped (already present — never overwritten): '
        '${p.join(report.targetRoot, file.relativePath)}',
      );
    }
  }
  for (final file in report.refused) {
    b.writeln('REFUSED ${file.relativePath}: ${file.reason}');
  }
  b
    ..writeln(
      'install: ${report.written.length} written, ${report.skipped.length} '
      'skipped, ${report.refused.length} refused — ${report.targetRoot} '
      '<- ${report.overlayRoots.length} overlay root(s)',
    )
    ..writeln(
      'install: NOTHING was committed — review the diff, then commit what you '
      'keep.',
    );
  return b.toString();
}
