// Target MAPPING is a property of the DECLARATION now, not of a walk: a
// `claude` leg declared under `extension/station_overlay/claude/…` lands at
// `.claude/…`, an `agents` leg at `.agents/…`, and a leg with no repository
// target (`mcp`, `station`) lands nowhere. The writer translates nothing — it
// writes `ResolvedGridAssetArtifact.relativePath`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_resolution_fixture.dart';

void main() {
  late Directory temp;
  late Directory target;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('overlay_mapping_');
    target = Directory(p.join(temp.path, 'target'))..createSync();
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('each delivery leg maps to its own harness head, and a leg with no '
      'repository target maps nowhere', () {
    final fixture = TestAssetResolutionFixture(
      root: temp,
      assets: <GridAssetDefinition>[
        fixtureSkill('x'),
        fixtureSettings('harness'),
        fixtureRubric('graded'),
      ],
      bodies: const <String, String>{
        'extension/station_overlay/claude/settings.json':
            '{\n  "on": true\n}\n',
      },
    );

    const OverlayMaterializer().materializeSync(
      resolution: fixture.resolution(),
      targetRoot: target.path,
      sourceRef: 'test',
    );

    expect(
      File(
        p.join(target.path, '.claude', 'skills', 'x', 'SKILL.md'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(target.path, '.agents', 'skills', 'x', 'SKILL.md'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(target.path, '.claude', 'settings.json')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(target.path, 'extension')).existsSync(),
      isFalse,
      reason: 'the mcp leg has no repository target at all',
    );
  });

  test('a scoped resolution narrows the written set to the named subtree', () {
    final fixture = TestAssetResolutionFixture(
      root: temp,
      assets: <GridAssetDefinition>[fixtureSkill('x')],
    );

    final report = const OverlayMaterializer().materializeSync(
      resolution: fixture.resolution(),
      targetRoot: target.path,
      sourceRef: 'test',
      subtrees: const [kAgentsSkillsSubtree],
    );

    expect(
      report.written.single.relativePath,
      p.join('.agents', 'skills', 'x', 'SKILL.md'),
    );
    expect(
      File(
        p.join(target.path, '.claude', 'skills', 'x', 'SKILL.md'),
      ).existsSync(),
      isFalse,
    );
  });
}
