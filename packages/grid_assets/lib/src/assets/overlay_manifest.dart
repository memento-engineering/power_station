library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Default publish-safe source directory to harness target directory mappings.
///
/// A head exists only where some harness READS the mapped target inside a repo:
/// `.claude` (Claude Code), `.agents` (Codex skills, also read by Copilot CLI),
/// `.github` (Copilot's repo-level instructions), `.codex` (Codex config).
/// A repo-level `.copilot/` is read by nothing — Copilot CLI reads `.github/`,
/// `.claude/` and `.agents/` in the repo and `$HOME/.copilot/` outside it — so
/// no `copilot` head is vended. A pack that wants one declares it in its own
/// `station_overlay.mappings`.
const Map<String, String> kDefaultStationOverlayMappings = {
  'claude': '.claude',
  'agents': '.agents',
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
      final target = _safeRelativePath('${entry.value}', label: 'target');
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

String _safeRelativePath(String value, {required String label}) {
  final normalized = p.normalize(value);
  if (value.isEmpty ||
      p.isAbsolute(value) ||
      normalized == '.' ||
      normalized == '..' ||
      p.split(normalized).contains('..')) {
    throw FormatException(
      'overlay mapping $label "$value" must be a safe relative path',
    );
  }
  return normalized;
}
