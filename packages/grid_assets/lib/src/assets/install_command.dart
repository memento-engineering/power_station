/// The OPERATOR-side install Command — `<cli> install`.
///
/// THIN by rule (the layering redline, ADR-0001: a Command is "a thin adapter
/// over UI-drivable lib logic"): argv, sinks, and the delegate it was handed.
/// Every decision — which overlays are in scope, which target, what gets
/// written, what gets printed, the exit code — is [resolveStationOverlayRoots]
/// / [OverlayInstallService] / [renderInstallReport], so a Flutter app drives
/// the same install.
///
/// The OPERATOR half of the delivery leg: the SAME `station_overlay` the
/// provision wire expands into a per-bead worktree (A23) expands here into the
/// operator's own `.claude/` — the human at the grid home gets the skills the
/// station's agents get. It shows a DIFF and commits NOTHING: the operator
/// reviews and commits. It never overwrites a file it did not write.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import '../code/code_capabilities.dart' show kDefaultOverlayRunner;
import 'overlay_install.dart';

/// `install` — expand every in-scope `station_overlay` into the operator's
/// `.claude/`, show the diff, commit nothing, overwrite nothing.
///
/// A station composes it with ITS resident-station context:
/// `runner.addCommand(InstallCommand(delegate: () => MyDelegate(...)))` — the
/// [delegate] factory is invoked per run, its tree is mounted OFFLINE to
/// resolve the grid home ([mountedGridHomeOf]), and the delegate is disposed
/// after the run (this command owns the instance it asked for).
class InstallCommand extends Command<int> {
  /// Creates the command over the composing station's [delegate] factory, the
  /// install [service], and the overlay-root [roots] resolver (injectable for
  /// tests; defaults to the non-prescriptive `extension_discovery` walk).
  /// [out]/[err] default to the real stdout/stderr; tests capture them.
  InstallCommand({
    required sdk.GridDelegate Function() delegate,
    OverlayInstallService service = const OverlayInstallService(),
    Future<List<String>> Function(String gridHome)? roots,
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _service = service,
       _roots = roots ?? _discoverRoots,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'diff',
        defaultsTo: true,
        help:
            'Show a NEW-FILE diff of everything installed (the default) — the '
            'operator reviews it and commits. --no-diff prints only what was '
            'added and ignores pre-existing files.',
      )
      ..addOption(
        'target',
        help: "The .claude/ dir to expand into (default: the grid home's own).",
      )
      ..addOption(
        'grid-home',
        help:
            'The grid home (default: the RawAssetGrid root the '
            'resident-station context authors).',
      );
  }

  static Future<List<String>> _discoverRoots(String gridHome) =>
      resolveStationOverlayRoots(gridHome: gridHome);

  final sdk.GridDelegate Function() _delegate;
  final OverlayInstallService _service;
  final Future<List<String>> Function(String) _roots;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'install';

  @override
  final String description =
      'Expand every in-scope asset pack\'s vended station_overlay (skills + '
      'agents) into the operator\'s .claude/ — non-destructive (a file that '
      'already exists is never overwritten), diff-first, and it commits '
      'NOTHING.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final delegate = _delegate();
    try {
      final gridHome = args.option('grid-home') ?? mountedGridHomeOf(delegate);
      if (gridHome == null) {
        _err.writeln(
          'install: the resident-station context authors no grid root — pass '
          '--grid-home <dir>',
        );
        return 1;
      }
      final overlayRoots = await _roots(gridHome);
      if (overlayRoots.isEmpty) {
        _err.writeln(
          'install: no package in $gridHome vends an '
          'extension/station_overlay — nothing to install',
        );
        return 1;
      }
      final report = await _service.install(
        overlayRoots: overlayRoots,
        targetRoot: args.option('target') ?? operatorClaudeDir(gridHome),
        args: {
          // The composing station's OWN verb — the vended skills' `{{runner}}`
          // calls ride it (the ADR-0001 coupling), never a hardcoded name.
          'runner': runner?.executableName ?? kDefaultOverlayRunner,
          'gridHome': gridHome,
        },
      );
      _out.write(renderInstallReport(report, diff: args.flag('diff')));
      return report.exitCode;
    } on StateError catch (error) {
      // The lib's LOUD refusals — no package config, or a malformed vended
      // overlay. Reported, never a half-installed tree.
      _err.writeln('install: ${error.message}');
      return 1;
    } finally {
      delegate.dispose();
    }
  }
}
