// Target MAPPING is a property of the DECLARATION now, not of a walk: a
// `claude` leg declared under `extension/station_overlay/claude/…` lands at
// `.claude/…`, an `agents` leg at `.agents/…`, an `agents` leg declared under
// `extension/station_overlay/agents_root/` lands at the repository ROOT, and a
// leg with no repository target (`mcp`, `station`) lands nowhere. The writer
// translates nothing — it writes `ResolvedGridAssetArtifact.relativePath`.
//
// The root leg is why the mapping KEY, not the delivery enum, is the routing
// authority: `AssetDeliveryTarget.agents` names BOTH agents surfaces with one
// case, so only the declared source head can tell `AGENTS.md` from
// `.agents/skills/…`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/agents_root_fixture.dart';
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

  test('the agents root mapping leg resolves AGENTS.md to the repository '
      'root', () {
    final fixture = TestAssetResolutionFixture(
      root: temp,
      assets: <GridAssetDefinition>[
        fixtureSkill('x'),
        fixtureAgentsInstructions(),
      ],
      bodies: fixtureAgentsInstructionsBodies(),
    );

    final resolution = fixture.resolution();

    expect(
      resolution.relativePaths,
      [
        p.join(kClaudeTargetHead, 'skills', 'x', 'SKILL.md'),
        p.join(kAgentsTargetHead, 'skills', 'x', 'SKILL.md'),
        kAgentsRootRelativePath,
      ],
      reason: 'the root leg maps to a LOOSE root file, under no harness head',
    );
    final root = resolution.artifacts.last;
    expect(root.artifact.target, AssetDeliveryTarget.agents);
    expect(root.sourcePath, p.join(fixture.packageRoot, root.artifact.path));
  });

  test('the root leg is a THIRD destination, not a re-route: both harness-head '
      'legs keep their exact targets beside it', () {
    final withRoot = TestAssetResolutionFixture(
      root: Directory(p.join(temp.path, 'with'))..createSync(),
      assets: <GridAssetDefinition>[
        fixtureSkill('x'),
        fixtureAgentsInstructions(),
      ],
      bodies: fixtureAgentsInstructionsBodies(),
    ).resolution();
    final without = TestAssetResolutionFixture(
      root: Directory(p.join(temp.path, 'without'))..createSync(),
      assets: <GridAssetDefinition>[fixtureSkill('x')],
    ).resolution();

    expect(
      withRoot.relativePaths.where((path) => path != kAgentsRootRelativePath),
      without.relativePaths,
    );
  });

  test('an agents_root artifact that is NOT the vended root file refuses '
      'loudly — the repository root is not a tree to pour into', () {
    final fixture = TestAssetResolutionFixture(
      root: temp,
      assets: <GridAssetDefinition>[fixtureAgentsRootTree()],
      bodies: const <String, String>{
        'extension/station_overlay/agents_root/notes/NOTE.md': '# note\n',
      },
    );

    expect(
      fixture.resolution,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains(kAgentsRootMappingKey),
            contains(kAgentsRootRelativePath),
            contains('notes/NOTE.md'),
          ),
        ),
      ),
    );
  });
}
