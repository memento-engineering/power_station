// The CODEX leg of the vended overlay:
// `extension/station_overlay/agents/skills/<id>/SKILL.md`, mapped to
// `.agents/skills/<id>/SKILL.md` at install by the `agents -> .agents` head
// already in `kDefaultStationOverlayMappings`.
//
// The agents leg is an INDEPENDENT instruction source for the codex-style
// harnesses the station arms. It started life as a copy of the claude leg and
// MAY diverge from it: a harness may carry its own instructions (Nico,
// 2026-09-03), so a difference between the two legs is a harness-specific
// instruction, not drift. Identical content is permitted, never required —
// nothing here reads a SKILL.md's bytes.
//
// What this file DOES pin is STRUCTURE, which is harness-independent: both
// legs vend the same skill IDS (a skill present for one harness and absent
// for the other is a vending gap, not an instruction difference), the leg
// carries SKILL.md files and nothing else, and no copilot leg exists.
//
// Offline only — reads the bundled `extension/` files.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `extension/` dir by walking up from the cwd — the
/// same walk `skill_assets_test.dart` uses, so the two never disagree on cwd.
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/extension from '
    '${Directory.current.path}',
  );
}

void main() {
  final overlay = p.join(_extensionDir(), 'station_overlay');
  final claudeSkills = p.join(overlay, 'claude', 'skills');
  final agentsSkills = p.join(overlay, 'agents', 'skills');

  List<String> skillIdsIn(String dir) =>
      Directory(dir)
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toList()
        ..sort();

  test('the agents leg vends EXACTLY the claude leg skill ids', () {
    expect(skillIdsIn(agentsSkills), kVendedSkills);
    expect(skillIdsIn(agentsSkills), skillIdsIn(claudeSkills));
  });

  test('the agents leg carries SKILL.md files and nothing else — no operator '
      'seat asset, no loose file', () {
    final files =
        Directory(p.join(overlay, 'agents'))
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.relative(f.path, from: overlay))
            .toList()
          ..sort();
    expect(files, [
      for (final id in kVendedSkills)
        p.join('agents', 'skills', id, 'SKILL.md'),
    ]);
  });

  test('no copilot leg is authored and no AGENTS.md is vended — Copilot CLI '
      'reads the claude and agents trees directly, and a loose root file is '
      'the one shape the per-asset-dir fence cannot cover', () {
    expect(Directory(p.join(overlay, 'copilot')).existsSync(), isFalse);
    expect(File(p.join(overlay, 'AGENTS.md')).existsSync(), isFalse);
    expect(kDefaultStationOverlayMappings.containsKey('copilot'), isFalse);
  });
}
