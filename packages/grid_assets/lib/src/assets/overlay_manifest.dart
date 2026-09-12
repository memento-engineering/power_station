library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The vended-tree prefix EVERY station-overlay artifact is declared under.
///
/// One mapping KEY names the source directory directly below this prefix, and
/// [kDefaultStationOverlayMappings] names the TARGET that directory installs
/// to — so this ONE table, never a second one beside the resolver, is what
/// routes a declared artifact to its installed path.
const String kStationOverlaySourceHead = 'extension/station_overlay';

/// The mapping key of the Claude Code leg.
const String kClaudeMappingKey = 'claude';

/// The mapping key of the harness-neutral agents TREE leg.
const String kAgentsMappingKey = 'agents';

/// The mapping key of the harness-neutral agents ROOT-FILE leg — the only leg
/// whose target is the repository ROOT itself rather than a harness head.
///
/// It is a SEPARATE key because the SDK's `AssetDeliveryTarget.agents` names
/// BOTH agents surfaces at once (`AGENTS.md` AND `.agents/…`) while a repository
/// installs them at two different places: the delivery enum cannot tell them
/// apart, so the DECLARED SOURCE DIR does.
const String kAgentsRootMappingKey = 'agents_root';

/// Where Claude Code reads a repo's assets — the head every [kClaudeMappingKey]
/// leg materializes under.
const String kClaudeTargetHead = '.claude';

/// Where the harness-neutral agents layout reads a repo's assets — the head
/// every [kAgentsMappingKey] leg materializes under.
const String kAgentsTargetHead = '.agents';

/// The target of the [kAgentsRootMappingKey] leg: the repository ROOT.
///
/// Still a target DIRECTORY, exactly like every other mapping value — no
/// mapping value ever alternates between file and directory semantics. What the
/// leg may vend INSIDE it is [kAgentsRootRelativePath] and nothing else.
const String kAgentsRootTargetHead = '.';

/// The ONE root-relative file the [kAgentsRootMappingKey] leg vends — the file a
/// codex-style seat actually reads at a repository root, and the reason the leg
/// exists at all: `.agents/` carries skills, and no `.agents/` path is read as
/// repository INSTRUCTION.
const String kAgentsRootRelativePath = 'AGENTS.md';

/// Default publish-safe source directory to harness target directory mappings.
///
/// A head exists only where some harness READS the mapped target inside a repo:
/// `.claude` (Claude Code), `.agents` (Codex skills, also read by Copilot CLI),
/// `.` — the repository root — for the one root-relative instruction file a
/// codex-style seat reads ([kAgentsRootRelativePath]), `.github` (Copilot's
/// repo-level instructions), `.codex` (Codex config).
/// A repo-level `.copilot/` is read by nothing — Copilot CLI reads `.github/`,
/// `.claude/` and `.agents/` in the repo and `$HOME/.copilot/` outside it — so
/// no `copilot` head is vended. A pack that wants one declares it in its own
/// `station_overlay.mappings`.
const Map<String, String> kDefaultStationOverlayMappings = {
  kClaudeMappingKey: kClaudeTargetHead,
  kAgentsMappingKey: kAgentsTargetHead,
  kAgentsRootMappingKey: kAgentsRootTargetHead,
  'github': '.github',
  'codex': '.codex',
};

/// One ordered overlay root and the path mappings declared by its own pack.
class StationOverlaySource {
  const StationOverlaySource({required this.root, required this.mappings});

  final String root;
  final Map<String, String> mappings;
}

/// Reads `station_overlay.mappings` from [manifestPath] over the defaults.
StationOverlaySource loadStationOverlaySourceFromPaths({
  required String overlayRoot,
  required String manifestPath,
}) {
  final yaml = loadYaml(File(manifestPath).readAsStringSync());
  final stationOverlay = yaml is YamlMap ? yaml['station_overlay'] : null;
  if (stationOverlay != null && stationOverlay is! YamlMap) {
    throw const FormatException('station_overlay must be a map');
  }
  final configured = stationOverlay is YamlMap
      ? stationOverlay['mappings']
      : null;
  if (configured != null && configured is! YamlMap) {
    throw const FormatException('station_overlay.mappings must be a map');
  }
  final mappings = <String, String>{...kDefaultStationOverlayMappings};
  if (configured is YamlMap) {
    for (final entry in configured.entries) {
      final source = _safeRelativeSegment('${entry.key}', label: 'source');
      final target = _safeRelativePath(
        '${entry.value}',
        label: 'target',
        source: source,
      );
      mappings[source] = target;
    }
  }
  return StationOverlaySource(
    root: overlayRoot,
    mappings: Map.unmodifiable(mappings),
  );
}

String _safeRelativeSegment(String value, {required String label}) {
  final normalized = p.normalize(value);
  if (value.isEmpty ||
      p.isAbsolute(value) ||
      normalized == '.' ||
      normalized == '..' ||
      p.split(normalized).length != 1) {
    throw FormatException(
      'overlay mapping $label "$value" must be one segment',
    );
  }
  return normalized;
}

/// [value] as a safe relative target for the mapping key [source].
///
/// `.` — the repository ROOT — is a legal target for exactly ONE key,
/// [kAgentsRootMappingKey], whose whole purpose is the loose root file
/// [kAgentsRootRelativePath]. On any other key it would collapse a harness head
/// onto the root and pour that head's whole tree over an operator's repo, so it
/// throws there exactly as an absolute or parent-traversing value does.
String _safeRelativePath(
  String value, {
  required String label,
  required String source,
}) {
  final normalized = p.normalize(value);
  final rootIsLegal = source == kAgentsRootMappingKey;
  if (value.isEmpty ||
      p.isAbsolute(value) ||
      (normalized == '.' && !rootIsLegal) ||
      normalized == '..' ||
      p.split(normalized).contains('..')) {
    throw FormatException(
      'overlay mapping $label "$value" must be a safe relative path',
    );
  }
  return normalized;
}
