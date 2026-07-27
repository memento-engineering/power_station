/// The Packaged-AI-Assets loader (M5 "The Circuit" Track D / D-9).
///
/// Loads the committee's rubric prose + critic prompt template from the on-disk
/// `extension/` assets authored in the Dart/Flutter "Packaged AI Assets" format
/// (per flutter.dev/go/packaged-ai-assets — the `package:extension_discovery`
/// `extension/mcp/config.yaml` shape). The active prompt path is composed in Dart
/// (`CriticCapability.buildCriticPrompt`) using [loadRubric] as its rubric
/// source; [renderCriticPrompt] is the standalone, format-faithful renderer of
/// the `prompts/critic.md` template (the portable mirror).
///
/// The vended SKILLS (`extension/station_overlay/claude/skills/<id>/SKILL.md`,
/// bead `pow-88p`) ride the same loader: the agentic halves of the coupled
/// skill+command pairs (ADR-0001 — the skill CALLS the vended deterministic
/// Command, e.g. `discover` calls `search --json`). Each SKILL.md is
/// mustache-templated on its manifest-declared args (`runner`, `gridHome`);
/// [renderSkill] renders ONE skill by id and fails LOUD on any unbound hole.
/// The ROOT-RELATIVE `station_overlay` FORMAT — a tree that MIRRORS its target
/// repo root — and the path-preserving expansion of it ship next door in
/// `overlay_materializer.dart`: this loader stays the by-id render surface,
/// `OverlayMaterializer` is the whole-tree install. Two callers ride the latter
/// — the operator install Command (`assets install`, onto a station repo root)
/// and this package's OWN provision-time wire (`AgentCapability`,
/// `code_capabilities.dart`, onto a per-bead worktree root).
///
/// Asset resolution resolves the package's own `extension/` dir via the package
/// config (`Isolate.resolvePackageUriSync` — cwd-independent, the live-arm path),
/// falling back to a cwd walk-up (works from the repo root or the package dir,
/// like the structural fence's walk) where no package config is present. This is
/// the follow-up flagged when only the cwd walk existed: the assets ship inside
/// the package, so a runner whose cwd is a foreign checkout (the post-split
/// `space_station` runner) still finds them.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;

import 'overlay_manifest.dart';

/// The skill ids this package vends
/// (`extension/station_overlay/skills/<id>/SKILL.md`) — the agentic halves of
/// the coupled skill+command pairs (ADR-0001). `OverlayMaterializer` does not
/// read this constant (it installs whatever files exist under the overlay); it
/// is the by-id render surface's own index, and the skill-manifest test's.
const List<String> kVendedSkills = [
  'discover',
  'gate-medicine',
  'harvest-review',
  'intake-refinement',
  'release',
  'station-operations',
];

/// The vended skills whose AUDIENCE is the OPERATOR — the human at the grid
/// home, whose `.claude/` the `install` Command fills. The provision wire
/// installs them into a per-bead worktree like any other overlay file (one
/// tree, two consumers), but NEVER names them in a build agent's brief
/// (`buildAgentBrief`). The mirror of each skill's `audience:` in
/// `extension/mcp/config.yaml`, fenced by test.
///
/// The split is load-bearing, not cosmetic. These four drive the STATION (boot
/// it, land its work, clear its gates) — and `harvest-review` teaches "push and
/// open a PR with receipts", which the very brief that would offer it FORBIDS
/// ("Do NOT push and do NOT open a pull request"). Offering a build agent a
/// skill that contradicts its working agreement is a live hazard.
///
/// A DENY-list, not an allow-list of agent skills: the wire materializes
/// whatever overlay it is handed, so a skill this package does not vend (a
/// third-party asset pack's, an injected fixture's) is a skill whose pack meant
/// it for its agents. Naming it is what makes it invocable — dropping it
/// silently is the failure this doctrine forbids. Only a DECLARED operator
/// audience withholds a skill.
const List<String> kOperatorSkills = [
  'gate-medicine',
  'harvest-review',
  'intake-refinement',
  'release',
  'station-operations',
];

/// Loads grid_assets' bundled rubric/prompt assets from `extension/`.
class PackagedAssetLoader {
  /// Creates a loader. [root] explicitly points at the `extension/` dir (tests
  /// inject it); absent ⇒ the dir is discovered via the package config (with a
  /// cwd walk-up fallback — see [_resolveRoot]).
  PackagedAssetLoader({String? root}) : _explicitRoot = root;

  final String? _explicitRoot;

  /// The resolved `extension/` directory (discovered once, lazily).
  late final String _root = _explicitRoot ?? _resolveRoot();

  /// The resolved `extension/` directory this loader reads from — exposed so a
  /// sibling caller that must build a path relative to it (the station_overlay
  /// materialization wire, bead `pow-kzx`) reuses this ONE resolution
  /// (package-config first, cwd walk-up fallback) instead of re-deriving it.
  /// Throws (via [_resolveRoot]) when no `extension/` can be located at all —
  /// the same fail-loud packaging-bug posture every other read here holds.
  String get root => _root;

  /// The prose bands for [rubricId] (`extension/rubrics/<id>.md`). Throws an
  /// [ArgumentError] for an unknown rubric (fail-loud — a missing rubric is a
  /// packaging bug, never a silent empty prompt).
  String loadRubric(String rubricId) {
    final file = File(p.join(_root, 'rubrics', '$rubricId.md'));
    if (!file.existsSync()) {
      throw ArgumentError('unknown rubric "$rubricId" (no ${file.path})');
    }
    return file.readAsStringSync().trim();
  }

  /// The mustache-templated prompt body for [promptId] (`extension/prompts/<id>.md`).
  String loadPromptTemplate(String promptId) {
    final file = File(p.join(_root, 'prompts', '$promptId.md'));
    if (!file.existsSync()) {
      throw ArgumentError('unknown prompt "$promptId" (no ${file.path})');
    }
    return file.readAsStringSync();
  }

  /// Renders the `critic` prompt template for [rubricId] + [bead] — substitutes
  /// `{{rubric}}`, `{{rubricText}}` (the loaded rubric bands), and `{{bead}}` (the
  /// full work bead). The format-faithful mirror of `buildCriticPrompt`.
  String renderCriticPrompt(String rubricId, Bead bead) =>
      _mustache(loadPromptTemplate('critic'), {
        'rubric': rubricId,
        'rubricText': loadRubric(rubricId),
        'bead': beadBlock(bead),
      });

  /// Renders the `spec-critic` prompt template for [rubricId] + [bead] — the
  /// spec-readiness committee's portable mirror (of `buildSpecCriticPrompt`,
  /// bead `pow-6ao`); same three substitutions as [renderCriticPrompt].
  String renderSpecCriticPrompt(String rubricId, Bead bead) =>
      _mustache(loadPromptTemplate('spec-critic'), {
        'rubric': rubricId,
        'rubricText': loadRubric(rubricId),
        'bead': beadBlock(bead),
      });

  /// Renders the `readiness` prompt template for [rubricId] + [bead] — the
  /// spec-readiness INTAKE lens's portable mirror (of
  /// `ReadinessCriticCapability.buildReadinessPrompt`, bead `pow-q7n`); same
  /// three substitutions as [renderCriticPrompt]. Its own template, not
  /// `spec-critic`'s: the lens grades the BEAD, where the spec critics grade a
  /// SPEC and the code critics a DIFF — three prompt SHAPES, three mirrors.
  String renderReadinessPrompt(String rubricId, Bead bead) =>
      _mustache(loadPromptTemplate('readiness'), {
        'rubric': rubricId,
        'rubricText': loadRubric(rubricId),
        'bead': beadBlock(bead),
      });

  /// Renders the `discovery` prompt template for [lens] + [bead] — the discovery
  /// circuit's portable mirror (of `DiscoveryLensCapability.buildLensPrompt`).
  /// It takes a LENS BRIEF, not a rubric: an explorer gathers and cites, it does
  /// not grade, so there are no bands to load.
  String renderDiscoveryPrompt(String lens, String lensBrief, Bead bead) =>
      _mustache(loadPromptTemplate('discovery'), {
        'lens': lens,
        'lensBrief': lensBrief,
        'bead': beadBlock(bead),
      });

  /// The mustache-templated SKILL.md body for [skillId]
  /// (`extension/station_overlay/claude/skills/<skillId>/SKILL.md` — the
  /// ROOT-RELATIVE vended-asset overlay format: the tree mirrors the target repo
  /// root, so it already carries the harness's own `.claude/skills/` layout).
  /// Throws an [ArgumentError] for an unknown skill (fail-loud — a missing skill
  /// is a packaging bug, never a silent empty install).
  String loadSkillTemplate(String skillId) {
    final file = File(
      p.join(_root, 'station_overlay', 'claude', 'skills', skillId, 'SKILL.md'),
    );
    if (!file.existsSync()) {
      throw ArgumentError('unknown skill "$skillId" (no ${file.path})');
    }
    return file.readAsStringSync();
  }

  /// This package's overlay source plus manifest-declared mappings.
  StationOverlaySource loadStationOverlaySource() =>
      loadStationOverlaySourceFromPaths(
        overlayRoot: p.join(_root, 'station_overlay'),
        manifestPath: p.join(_root, 'mcp', 'config.yaml'),
      );

  /// Renders the SKILL.md for [skillId], substituting every `{{key}}` from
  /// [args] (the manifest's declared skill args — e.g. `runner`, `gridHome`
  /// for `discover`). The composing station's delivery leg calls this at
  /// materialization time.
  ///
  /// Throws a [StateError] when any `{{…}}` hole survives substitution — an
  /// installed skill has NO unbound template holes (a leftover `{{runner}}`
  /// would read as a literal in the seat's skill, a silent packaging bug).
  String renderSkill(String skillId, {required Map<String, String> args}) {
    final rendered = _mustache(loadSkillTemplate(skillId), args);
    final residue = RegExp(r'\{\{[^}]*\}\}').allMatches(rendered);
    if (residue.isNotEmpty) {
      final holes = {for (final m in residue) m.group(0)!};
      throw StateError(
        'renderSkill("$skillId"): unbound template hole(s) '
        '${holes.join(', ')} — bind every declared arg '
        '(got: ${args.keys.join(', ')})',
      );
    }
    return rendered;
  }

  /// A `RubricSource` tear-off bound to this loader (wire into `CriticCapability`).
  String Function(String) get rubricSource => loadRubric;

  /// Substitutes every `{{key}}` in [template] from [vars] (a tiny, dependency-
  /// free mustache for flat string args — the only templating D-9 needs now).
  static String _mustache(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
    return out;
  }

  /// Renders the full work [bead] into a prompt block (title/task/design/
  /// acceptance/notes) — the `{{bead}}` substitution.
  static String beadBlock(Bead bead) {
    final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
    final b = StringBuffer()..writeln('`${bead.id}` — $title');
    void section(String heading, String body) {
      if (body.trim().isEmpty) return;
      b
        ..writeln()
        ..writeln('### $heading')
        ..writeln(body.trim());
    }

    section('Task', bead.description);
    section('Design', bead.design);
    section('Acceptance criteria', bead.acceptanceCriteria);
    section('Notes', bead.notes);
    return b.toString().trimRight();
  }

  /// Locates this package's `extension/` dir, trying resolution strategies in
  /// order and failing loud with every probe attempted (a missing `extension/`
  /// is a packaging bug, never a silent empty prompt):
  ///
  ///   1. the package config (`Isolate.resolvePackageUriSync`) — cwd-independent,
  ///      so a runner whose cwd is a foreign checkout still finds the assets;
  ///   2. a cwd walk-up — the fallback for contexts with no package config
  ///      (e.g. an AOT/compiled process), robust whether the process runs from
  ///      the repo root or the package dir.
  static String _resolveRoot() {
    final probes = <String>[];
    final viaPackageConfig = _discoverRootViaPackageConfig(probes);
    if (viaPackageConfig != null) return viaPackageConfig;
    final viaCwd = _discoverRootViaCwd(probes);
    if (viaCwd != null) return viaCwd;
    throw StateError(
      'could not locate packages/grid_assets/extension — probed:\n'
      '${probes.map((probe) => '  - $probe').join('\n')}',
    );
  }

  /// Resolves `extension/` from the package config: resolves a `package:` URI
  /// into this package's `lib/`, walks up to the package root (the dir whose
  /// `pubspec.yaml` is named `grid_assets`), then into `extension/`. Returns null
  /// (recording the failed probe in [probes]) when there is no package config or
  /// the resolved package holds no `extension/rubrics`.
  static String? _discoverRootViaPackageConfig(List<String> probes) {
    Uri? libUri;
    try {
      libUri = Isolate.resolvePackageUriSync(
        Uri.parse('package:grid_assets/src/assets/asset_loader.dart'),
      );
    } on Object catch (error) {
      probes.add('package config: resolvePackageUriSync threw ($error)');
      return null;
    }
    if (libUri == null || !libUri.isScheme('file')) {
      probes.add(
        'package config: package:grid_assets did not resolve to a '
        'file URI (no package config?)',
      );
      return null;
    }
    var dir = Directory.fromUri(libUri).parent;
    for (var i = 0; i < 8; i++) {
      if (_isGridAssetsPackageRoot(dir)) {
        final probe = Directory(p.join(dir.path, 'extension'));
        if (_hasRubrics(probe)) return probe.path;
        probes.add(
          'package config: ${probe.path} has no rubrics/ '
          '(package root ${dir.path})',
        );
        return null;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    probes.add(
      'package config: no grid_assets pubspec.yaml above '
      '${libUri.toFilePath()}',
    );
    return null;
  }

  /// Walks up from the cwd to locate this package's `extension/` dir — robust
  /// whether the process runs from the repo root or the package dir (mirrors the
  /// structural fence's `_libSrc` walk). Returns null (recording the failed probe
  /// in [probes]) when the walk reaches the filesystem root without a hit.
  static String? _discoverRootViaCwd(List<String> probes) {
    final candidates = <String>[
      'extension',
      p.join('packages', 'grid_assets', 'extension'),
    ];
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      for (final rel in candidates) {
        final probe = Directory(p.join(dir.path, rel));
        if (_hasRubrics(probe)) return probe.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    probes.add(
      'cwd walk-up from ${Directory.current.path} '
      '(probing extension/, packages/grid_assets/extension/)',
    );
    return null;
  }

  /// Whether [dir] is grid_assets' package root — has a `pubspec.yaml` declaring
  /// `name: grid_assets`. A line scan (not a yaml parse) keeps lib code free of a
  /// yaml dependency; the top-level `name:` field is unambiguous at column 0.
  static bool _isGridAssetsPackageRoot(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    return pubspec.readAsLinesSync().any(
      (line) => RegExp(r'^name:\s*grid_assets\s*$').hasMatch(line),
    );
  }

  /// Whether [extensionDir] is a usable assets root — it exists and holds the
  /// `rubrics/` subtree (the load-bearing marker both resolution paths gate on).
  static bool _hasRubrics(Directory extensionDir) =>
      extensionDir.existsSync() &&
      Directory(p.join(extensionDir.path, 'rubrics')).existsSync();
}
