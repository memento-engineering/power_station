/// The OPERATOR leg of overlay delivery — the UI-drivable lib under the
/// `assets install` Command.
///
/// Two pieces now, both CLI-free and git-free (the third — roster DISCOVERY —
/// is gone: no runtime package-extension walk decides what installs;
/// [resolveGridAssets] over the station-generated registry does,
/// `power_station#one-asset-resolution-defines-tree-and-writers`, which updates
/// A24's discovery mechanism while keeping its explicit-command, offline,
/// commits-nothing posture):
///
/// - [OverlayInstallService] — writes ONE [GridAssetResolution] onto a repo ROOT
///   through [OverlayMaterializer]. The exact same value the substation tree
///   mounted and the worktree wire materializes, so the operator's checkout and
///   an agent's worktree cannot hold different asset sets.
/// - [renderInstallReport] — the DIFF the operator reviews, and the five-way
///   `--check` classification ([OverlayCheckClassification]) it reports drift as.
///
/// **Committed, not gitignored.** The installed assets are meant to be COMMITTED
/// — the operator seat IS the station's manual, so a fresh clone must hold it
/// without a build step. Three guards make that safe rather than drift-prone:
/// the materializer never clobbers a file it did not generate
/// ([OverlayFileBlocked]), it reports a generated file the resolution no longer
/// selects ([OverlayFileStale]) instead of sweeping it, and `--check`
/// ([OverlayInstallService.install]'s `check`) FAILS when the installed tree has
/// drifted from source. This leg still COMMITS NOTHING and writes no git
/// artifact — the operator reads the diff and commits.
library;

import 'dart:convert';

import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'asset_resolution.dart';
import 'mounted_tree.dart';
import 'overlay_materializer.dart';

/// The grid home the composing station AUTHORED — the ambient [sdk.GridRoot] of
/// [delegate]'s tree, resolved BY TREE POSITION in one offline mount (the A11
/// idiom; `RawAssetGrid(root:)` provides it). Null when the delegate authors no
/// `RawAssetGrid` — the Command refuses LOUD on that.
String? mountedGridHomeOf(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) =>
    mountedValueOf<sdk.GridRoot>(delegate, configuration: configuration)?.path;

/// One install's outcome — the [OverlayMaterializeReport] (the sealed per-file
/// outcomes, consumed with an exhaustive `switch` by whoever needs the cases)
/// plus the CONTENTS of every file this run wrote or updated, so
/// [renderInstallReport] is a pure function of the report and a Flutter UI
/// renders the same diff.
class OverlayInstallReport {
  /// Creates the report.
  const OverlayInstallReport({
    required this.targetRoot,
    required this.resolution,
    required this.materialized,
    required this.writtenContents,
  });

  /// The repo ROOT the assets expanded onto (the resolution's target paths land
  /// under it: `.claude/…`, `.agents/…`).
  final String targetRoot;

  /// The ONE resolution this install wrote — the same value the tree mounts.
  final GridAssetResolution resolution;

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

  /// The generated files this resolution no longer selects — reported, never
  /// repaired or deleted.
  List<OverlayFileStale> get stale => materialized.stale;

  /// The skill ids present under `.claude/skills/` after this run.
  List<String> get installedSkillIds =>
      materialized.installedSkillIdsUnder(kClaudeSkillsSubtree);

  /// The process exit code.
  ///
  /// INSTALL: 0 when every selected file is installed or already current; 1 on
  /// any REFUSED (a half-bound asset — a packaging or config bug), BLOCKED (a
  /// hand-authored file shadowing a vended one) or STALE (a generated file the
  /// resolution dropped — the operator decides whether it goes). All three are
  /// LOUD by doctrine, and none of them is repaired here.
  ///
  /// CHECK (`dryRun`): 0 ONLY when the installed tree EQUALS the resolution — so
  /// a MISSING file (never installed) and a DRIFTED one fail too. This is the
  /// no-drift enforcement that lets the overlay be COMMITTED rather than
  /// gitignored.
  int get exitCode {
    if (refused.isNotEmpty || blocked.isNotEmpty || stale.isNotEmpty) return 1;
    if (dryRun && (written.isNotEmpty || updated.isNotEmpty)) return 1;
    return 0;
  }
}

/// Writes one resolved asset set onto a repo ROOT — the UI-drivable half of
/// `<cli> assets install` (a Flutter app calls exactly this).
class OverlayInstallService {
  /// Creates the service over the [materializer] (injectable for tests).
  const OverlayInstallService({
    OverlayMaterializer materializer = const OverlayMaterializer(),
  }) : _materializer = materializer;

  final OverlayMaterializer _materializer;

  /// Writes [resolution]'s selected artifacts onto [targetRoot], rendering each
  /// against the resolution's own arguments and stamping it with [sourceRef].
  ///
  /// [check] plans WITHOUT writing (the drift mode): the report says what WOULD
  /// change, and [OverlayInstallReport.exitCode] is non-zero unless the tree
  /// already equals the resolution.
  ///
  /// This lib NEVER overwrites a file it did not generate ([OverlayFileBlocked]),
  /// never deletes one it no longer selects ([OverlayFileStale]), writes nothing
  /// outside [targetRoot], and commits NOTHING: the operator reviews the diff and
  /// commits.
  Future<OverlayInstallReport> install({
    required GridAssetResolution resolution,
    required String targetRoot,
    required String sourceRef,
    bool check = false,
  }) async {
    final materialized = await _materializer.materialize(
      resolution: resolution,
      targetRoot: targetRoot,
      sourceRef: sourceRef,
      dryRun: check,
    );
    return OverlayInstallReport(
      targetRoot: targetRoot,
      resolution: resolution,
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
/// (`report.dryRun`) prints each path under its
/// [OverlayCheckClassification] label — `IN SYNC`, `DRIFTED`, `HAND-EDITED`,
/// `MISSING`, `STALE` — because it wrote nothing, so no line may claim it
/// installed anything. A BLOCKED, REFUSED or STALE file prints either way
/// (LOUD).
String renderInstallReport(OverlayInstallReport report, {bool diff = true}) {
  final b = StringBuffer();
  for (final file in report.materialized.files) {
    final path = p.join(report.targetRoot, file.relativePath);
    if (report.dryRun) {
      b.writeln('${file.checkClassification.label} $path');
      switch (file) {
        case OverlayFileWritten() || OverlayFileUpdated():
          if (diff) {
            _writeDiff(b, path, report.writtenContents[file.relativePath]);
          }
        case OverlayFileBlocked():
          b.writeln('BLOCKED $path: ${file.reason}');
        case OverlayFileRefused():
          b.writeln('REFUSED ${file.relativePath}: ${file.reason}');
        case OverlayFileStale():
          b.writeln('STALE $path: ${file.reason}');
        case OverlayFileUnchanged():
          break;
      }
      continue;
    }
    switch (file) {
      case OverlayFileWritten():
        b.writeln('installed $path');
        if (diff) {
          _writeDiff(b, path, report.writtenContents[file.relativePath]);
        }
      case OverlayFileUpdated():
        b.writeln('updated $path');
        if (diff) {
          _writeDiff(b, path, report.writtenContents[file.relativePath]);
        }
      case OverlayFileUnchanged():
        if (diff) b.writeln('current $path');
      case OverlayFileBlocked():
        b.writeln('BLOCKED $path: ${file.reason}');
      case OverlayFileRefused():
        b.writeln('REFUSED ${file.relativePath}: ${file.reason}');
      case OverlayFileStale():
        b.writeln('STALE $path: ${file.reason}');
    }
  }
  b
    ..writeln(
      'assets install${report.dryRun ? ' --check' : ''}: '
      '${report.written.length} ${report.dryRun ? 'missing' : 'installed'}, '
      '${report.updated.length} ${report.dryRun ? 'drifted' : 'updated'}, '
      '${report.unchanged.length} current, ${report.blocked.length} blocked, '
      '${report.refused.length} refused, ${report.stale.length} stale — '
      '${report.targetRoot} <- ${report.resolution.artifacts.length} selected '
      'artifact(s)',
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
