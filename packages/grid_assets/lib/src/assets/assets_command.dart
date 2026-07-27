/// The OPERATOR-side vended-asset Commands — `<cli> assets install`.
///
/// THIN by rule (the layering redline, ADR-0001: a Command is "a thin adapter
/// over UI-drivable lib logic"): argv, sinks, and the delegate it was handed.
/// Every decision — which overlays are in scope, which root, what gets written,
/// what gets printed, the exit code — is [resolveStationOverlayRoots] /
/// [OverlayInstallService] / [renderInstallReport], so a Flutter app drives the
/// same install.
///
/// The OPERATOR half of the delivery leg: the SAME `station_overlay` the
/// provision wire expands into a per-bead worktree expands here onto the
/// operator's own repo ROOT — the human at the grid home gets the assets the
/// station's agents get, plus the ones only a seat needs (the governor agent-def,
/// the harness settings). It shows a DIFF and commits NOTHING: the operator
/// reviews and commits. It never overwrites a file it did not generate.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'overlay_install.dart';
import 'overlay_manifest.dart';
import 'overlay_materializer.dart' show kDefaultOverlayRunner;
import 'overlay_provenance.dart' show resolveOverlaySourceRefSync;

/// `assets` — the vended-AI-ASSET domain umbrella (the subcommands carry the
/// verbs).
///
/// A station composes it with ITS resident-station context:
/// `runner.addCommand(AssetsCommand(delegate: () => MyDelegate(...)))` — the
/// deterministic half of the coupled skill+command pattern (ADR-0001). NEVER
/// folded into `<cli> up`: no automagic-on-boot, the same reason auto-reload was
/// rejected. Installing the operator's own manual is an explicit act.
class AssetsCommand extends Command<int> {
  /// Creates the umbrella with its subcommands.
  ///
  /// When [runnerInvocation] is supplied, the installed assets render it into
  /// `{{runner}}`. Omission uses the enclosing runner's executable name.
  AssetsCommand({
    required sdk.GridDelegate Function() delegate,
    OverlayInstallService service = const OverlayInstallService(),
    String? runnerInvocation,
    Future<List<StationOverlaySource>> Function(String gridHome)? roots,
    String Function(String overlayRoot)? sourceRef,
    StringSink? out,
    StringSink? err,
  }) {
    addSubcommand(
      AssetsInstallCommand(
        delegate: delegate,
        service: service,
        runnerInvocation: runnerInvocation,
        roots: roots,
        sourceRef: sourceRef,
        out: out,
        err: err,
      ),
    );
  }

  @override
  final String name = 'assets';

  @override
  final String description =
      "The vended AI ASSETS domain: install the asset packs' station_overlay "
      'onto a repo root (skills, agent defs, harness settings).';
}

/// `assets install` — overlay every in-scope `station_overlay` onto a repo ROOT,
/// PATH-PRESERVING (the overlay's own layout IS the target's), stamping each file
/// with the grid_assets source ref it was generated from. Shows a diff, commits
/// NOTHING, and never clobbers a file it did not generate.
///
/// `--check` writes nothing and exits non-zero when the installed tree has
/// DRIFTED from source (or is missing files) — the enforcement that lets the
/// overlay be COMMITTED rather than gitignored, so a fresh clone of the operator
/// seat holds its own manual with no build step.
class AssetsInstallCommand extends Command<int> {
  /// Creates the command over the composing station's [delegate] factory, the
  /// install [service], the overlay-root [roots] resolver and the [sourceRef]
  /// resolver (both injectable; the defaults are the non-prescriptive
  /// `extension_discovery` walk and the overlay checkout's short sha).
  ///
  /// When [runnerInvocation] is supplied, the installed assets render it into
  /// `{{runner}}`. Omission uses the enclosing runner's executable name.
  /// [out]/[err] default to the real stdout/stderr; tests capture them.
  AssetsInstallCommand({
    required sdk.GridDelegate Function() delegate,
    OverlayInstallService service = const OverlayInstallService(),
    String? runnerInvocation,
    Future<List<StationOverlaySource>> Function(String gridHome)? roots,
    String Function(String overlayRoot)? sourceRef,
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _service = service,
       _runnerInvocation = runnerInvocation,
       _roots = roots ?? _discoverRoots,
       _sourceRef = sourceRef ?? resolveOverlaySourceRefSync,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Write NOTHING: report per-file drift between the installed tree '
            'and the vended source, and exit non-zero if any file is missing, '
            'drifted, or blocked.',
      )
      ..addFlag(
        'diff',
        defaultsTo: true,
        help:
            'Show a NEW-FILE diff of everything installed (the default) — the '
            'operator reviews it and commits.',
      )
      ..addOption(
        'root',
        help:
            'The repo ROOT to overlay onto, path-preserving (default: the grid '
            "home the resident-station context authors). The overlay's own "
            'tree decides where each asset lands under it.',
      )
      ..addOption(
        'source-ref',
        help:
            'The grid_assets ref each provenance header records (default: the '
            "short commit sha of the overlay's own checkout).",
      )
      ..addOption(
        'grid-home',
        help:
            'An ABSOLUTE grid-home override (default: the RawAssetGrid root '
            'the resident-station context authors by mounted tree position).',
      );
  }

  static Future<List<StationOverlaySource>> _discoverRoots(String gridHome) =>
      resolveStationOverlaySources(gridHome: gridHome);

  final sdk.GridDelegate Function() _delegate;
  final OverlayInstallService _service;
  final String? _runnerInvocation;
  final Future<List<StationOverlaySource>> Function(String) _roots;
  final String Function(String) _sourceRef;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'install';

  @override
  final String description =
      "Overlay every in-scope asset pack's vended station_overlay onto a repo "
      'root — path-preserving, provenance-stamped, and it commits NOTHING. '
      '--check reports drift instead of writing.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final delegate = _delegate();
    try {
      final flag = args.option('grid-home')?.trim();
      String? unresolvedHome;
      if (flag == null || flag.isEmpty) {
        try {
          unresolvedHome = mountedGridHomeOf(delegate);
        } on ArgumentError catch (error) {
          final authored = error.invalidValue;
          if (authored is! String || p.isAbsolute(authored)) rethrow;
          _refuseRelativeGridHome(authored);
        }
      } else {
        unresolvedHome = flag;
      }
      if (unresolvedHome == null) {
        _err.writeln(
          'assets install: the resident-station context authors no grid root — '
          'pass --grid-home <dir> or --root <dir>',
        );
        return 1;
      }
      if (!p.isAbsolute(unresolvedHome)) {
        _refuseRelativeGridHome(unresolvedHome);
      }
      final gridHome = p.normalize(unresolvedHome);
      final overlaySources = await _roots(gridHome);
      if (overlaySources.isEmpty) {
        _err.writeln(
          'assets install: no package in $gridHome vends an '
          'extension/station_overlay — nothing to install',
        );
        return 1;
      }
      final report = await _service.install(
        overlaySources: overlaySources,
        targetRoot: args.option('root') ?? gridHome,
        sourceRef:
            args.option('source-ref') ?? _sourceRef(overlaySources.first.root),
        check: args.flag('check'),
        args: {
          // A JIT station supplies its launchable invocation; compiled stations
          // keep the enclosing runner's executable name and unattached fallback.
          'runner':
              _runnerInvocation ??
              runner?.executableName ??
              kDefaultOverlayRunner,
          'gridHome': gridHome,
        },
      );
      _out.write(renderInstallReport(report, diff: args.flag('diff')));
      return report.exitCode;
    } on StateError catch (error) {
      // The libs' LOUD refusals — no package config, or an unstampable vended
      // file. Reported, never a half-installed tree.
      _err.writeln('assets install: ${error.message}');
      return 1;
    } finally {
      delegate.dispose();
    }
  }

  Never _refuseRelativeGridHome(String gridHome) {
    usageException(
      'assets install: --grid-home must be an ABSOLUTE path (got '
      '"$gridHome") — the install RENDERS the grid home into every asset it '
      'stamps, and the coded roster resolves its relative seats against it; '
      'a cwd-relative home would be baked into the committed manual.',
    );
  }
}
