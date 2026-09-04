/// The OPERATOR-side vended-asset Commands — `<cli> assets install`.
///
/// THIN by rule (the layering redline, ADR-0001: a Command is "a thin adapter
/// over UI-drivable lib logic"): argv, sinks, and the delegate it was handed.
/// Every decision — WHICH assets are in scope, which root, what gets written,
/// what gets printed, the exit code — is [resolveGridAssets] /
/// [OverlayInstallService] / [renderInstallReport], so a Flutter app drives the
/// same install.
///
/// The OPERATOR half of the delivery leg: the SAME resolution the provision wire
/// materializes into a per-bead worktree is written here onto the operator's own
/// repo ROOT — the human at the grid home gets the assets the station's agents
/// get, plus the ones only a seat needs (the governor agent-def, the harness
/// settings). It shows a DIFF and commits NOTHING: the operator reviews and
/// commits. It never overwrites a file it did not generate, and it never deletes
/// one it no longer selects.
///
/// The station composes its GENERATED registry in
/// (`registry: GeneratedGridAssetRegistrant.registry`), so this Command names no
/// pack and discovers none: `power_station#station-registries-use-resolved-package-closures`
/// owns membership, and `power_station#one-asset-resolution-defines-tree-and-writers`
/// owns selection.
library;

import 'dart:io';

import 'package:args/args.dart' show ArgResults;
import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'asset_resolution.dart';
import 'overlay_install.dart';
import 'overlay_materializer.dart' show kDefaultOverlayRunner;
import 'overlay_provenance.dart' show resolveOverlaySourceRefSync;

/// Creates the fact observer for [roots] over [registry] — the injectable
/// OBSERVATION seam (impls are DI); the default is the real filesystem one.
typedef SubstationFactsRepositoryFactory =
    SubstationFactsRepository Function({
      required Map<SubstationKey, String> roots,
      required sdk.GridAssetRegistry registry,
    });

SubstationFactsRepository _fileFactsRepository({
  required Map<SubstationKey, String> roots,
  required sdk.GridAssetRegistry registry,
}) => FileSystemSubstationFactsRepository(roots: roots, registry: registry);

/// The substation identity the operator install resolves under: the grid home
/// itself, which is the one root this Command observes.
const SubstationKey kGridHomeSubstation = SubstationKey('grid-home');

/// `assets` — the vended-AI-ASSET domain umbrella (the subcommands carry the
/// verbs).
///
/// A station composes it with ITS resident-station context and ITS generated
/// registry:
/// `runner.addCommand(AssetsCommand(delegate: () => MyDelegate(...), registry:
/// GeneratedGridAssetRegistrant.registry))` — the deterministic half of the
/// coupled skill+command pattern (ADR-0001). NEVER folded into `<cli> up`: no
/// automagic-on-boot, the same reason auto-reload was rejected. Installing the
/// operator's own manual is an explicit act.
class AssetsCommand extends Command<int> {
  /// Creates the umbrella with its subcommands.
  ///
  /// When [runnerInvocation] is supplied, the installed assets render it into
  /// `{{runner}}`. Omission uses the enclosing runner's executable name.
  AssetsCommand({
    required sdk.GridDelegate Function() delegate,
    required sdk.GridAssetRegistry registry,
    GridAssetRosterOverride? rosterOverride,
    SubstationFactsRepositoryFactory factsRepository = _fileFactsRepository,
    OverlayInstallService service = const OverlayInstallService(),
    String? runnerInvocation,
    String Function(String packageRoot)? sourceRef,
    StringSink? out,
    StringSink? err,
  }) {
    addSubcommand(
      AssetsInstallCommand(
        delegate: delegate,
        registry: registry,
        rosterOverride: rosterOverride,
        factsRepository: factsRepository,
        service: service,
        runnerInvocation: runnerInvocation,
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
      'The vended AI ASSETS domain: install the station registry\'s selected '
      'assets onto a repo root (skills, agent defs, harness settings).';
}

/// `assets install` — write every asset the station's registry SELECTS for this
/// grid home onto a repo ROOT, stamping each file with the grid_assets source
/// ref it was generated from. Shows a diff, commits NOTHING, never clobbers a
/// file it did not generate, and never deletes a stale one.
///
/// `--check` writes nothing and exits non-zero when the installed tree has
/// DRIFTED from the resolution (or is missing files, or holds hand-edited or
/// stale ones) — the enforcement that lets the assets be COMMITTED rather than
/// gitignored, so a fresh clone of the operator seat holds its own manual with
/// no build step.
class AssetsInstallCommand extends Command<int> {
  /// Creates the command over the composing station's [delegate] factory, its
  /// generated [registry], the install [service], the fact-observation
  /// [factsRepository] seam and the [sourceRef] resolver (both injectable; the
  /// defaults are the real filesystem observer and the vending package
  /// checkout's short sha).
  ///
  /// [rosterOverride] carries the station's explicit include/exclude exceptions
  /// to what the selectors decide. When [runnerInvocation] is supplied, the
  /// installed assets render it into `{{runner}}`; omission uses the enclosing
  /// runner's executable name. [out]/[err] default to the real stdout/stderr;
  /// tests capture them.
  AssetsInstallCommand({
    required sdk.GridDelegate Function() delegate,
    required sdk.GridAssetRegistry registry,
    GridAssetRosterOverride? rosterOverride,
    SubstationFactsRepositoryFactory factsRepository = _fileFactsRepository,
    OverlayInstallService service = const OverlayInstallService(),
    String? runnerInvocation,
    String Function(String packageRoot)? sourceRef,
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _registry = registry,
       _rosterOverride = rosterOverride,
       _factsRepository = factsRepository,
       _service = service,
       _runnerInvocation = runnerInvocation,
       _sourceRef = sourceRef ?? resolveOverlaySourceRefSync,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Write NOTHING: report per-file drift between the installed tree '
            'and the selected resolution as IN SYNC, DRIFTED, HAND-EDITED, '
            'MISSING or STALE, and exit non-zero unless every path is in sync.',
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
            'The repo ROOT to write onto (default: the grid home the '
            'resident-station context authors). Each selected artifact lands at '
            'its declared root-relative path under it.',
      )
      ..addOption(
        'source-ref',
        help:
            'The grid_assets ref each provenance header records (default: the '
            "short commit sha of the vending package's own checkout).",
      )
      ..addOption(
        'grid-home',
        help:
            'An ABSOLUTE grid-home override (default: the RawAssetGrid root '
            'the resident-station context authors by mounted tree position).',
      );
  }

  final sdk.GridDelegate Function() _delegate;
  final sdk.GridAssetRegistry _registry;
  final GridAssetRosterOverride? _rosterOverride;
  final SubstationFactsRepositoryFactory _factsRepository;
  final OverlayInstallService _service;
  final String? _runnerInvocation;
  final String Function(String) _sourceRef;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'install';

  @override
  final String description =
      'Write every asset the station registry selects for this grid home onto '
      'a repo root — provenance-stamped, and it commits NOTHING. --check '
      'reports drift instead of writing.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final delegate = _delegate();
    SubstationFactsRepository? repository;
    try {
      final gridHome = _resolveGridHome(delegate, args);
      if (gridHome == null) return 1;
      final targetRoot = p.normalize(
        p.absolute(args.option('root') ?? gridHome),
      );
      // The roots are OBSERVED here, outside any build, and the repository is
      // this Command's to own and dispose.
      repository = _factsRepository(
        roots: <SubstationKey, String>{kGridHomeSubstation: targetRoot},
        registry: _registry,
      );
      repository.refresh();
      final resolution = resolveGridAssets(
        registry: _registry,
        snapshot: repository.current,
        substation: kGridHomeSubstation,
        rosterOverride: _rosterOverride,
        renderArguments: <String, String>{
          // A JIT station supplies its launchable invocation; compiled stations
          // keep the enclosing runner's executable name and unattached fallback.
          'runner':
              _runnerInvocation ??
              runner?.executableName ??
              kDefaultOverlayRunner,
          'gridHome': gridHome,
        },
      );
      if (resolution.artifacts.isEmpty) {
        _err.writeln(
          'assets install: the station registry selects no installable asset '
          'for $gridHome — nothing to install',
        );
        return 1;
      }
      final report = await _service.install(
        resolution: resolution,
        targetRoot: targetRoot,
        sourceRef:
            args.option('source-ref') ??
            _sourceRef(resolution.artifacts.first.packageRoot),
        check: args.flag('check'),
      );
      _out.write(renderInstallReport(report, diff: args.flag('diff')));
      return report.exitCode;
    } on StateError catch (error) {
      // The libs' LOUD refusals — a substation whose facts are missing, a
      // selected artifact whose source is absent, an unstampable vended file.
      // Reported, never a half-installed tree.
      _err.writeln('assets install: ${error.message}');
      return 1;
    } finally {
      repository?.dispose();
      delegate.dispose();
    }
  }

  /// The ABSOLUTE, normalized grid home — the `--grid-home` override, else the
  /// root the resident-station context authors by mounted tree position. Null
  /// (after writing the refusal) when the context authors none.
  String? _resolveGridHome(sdk.GridDelegate delegate, ArgResults args) {
    final flag = args.option('grid-home')?.trim();
    String? unresolved;
    if (flag == null || flag.isEmpty) {
      try {
        unresolved = mountedGridHomeOf(delegate);
      } on ArgumentError catch (error) {
        final authored = error.invalidValue;
        if (authored is! String || p.isAbsolute(authored)) rethrow;
        _refuseRelativeGridHome(authored);
      }
    } else {
      unresolved = flag;
    }
    if (unresolved == null) {
      _err.writeln(
        'assets install: the resident-station context authors no grid root — '
        'pass --grid-home <dir> or --root <dir>',
      );
      return null;
    }
    if (!p.isAbsolute(unresolved)) _refuseRelativeGridHome(unresolved);
    return p.normalize(unresolved);
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
