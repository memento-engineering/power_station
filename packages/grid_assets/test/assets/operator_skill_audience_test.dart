// The build brief's operator deny-list is STATION-WIDE, not package-local
// (`power_station#station-operator-audiences-derive-from-the-resolved-registry`).
//
// A station's registry is a resolved package CLOSURE: it composes packs
// grid_assets has never heard of. A24's rule — "only a DECLARED operator
// audience withholds a skill" — has to hold for every one of them, or the
// one-tree-two-consumers guard protects only grid_assets's own skills while a
// downstream pack's `audience: human` skill is installed AND offered.
//
// This rides the REAL provision-to-brief path: `AgentCapability.spawn` →
// `resolveGridAssets` → `OverlayMaterializer` → `buildAgentBrief`. The
// assertions prove BOTH skills were installed before reading the brief, so a
// pass can never come from the downstream skill simply never arriving; and the
// test filters no audience itself.
//
// Offline — a temp two-pack fixture, no live registry and no real process.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_resolution_fixture.dart';

/// A DOWNSTREAM pack — a second package in the same station closure, the shape
/// a real station composes (lunar_grid_assets beside grid_assets).
const String _downstreamPackage = 'downstream_assets';

void main() {
  group('the operator deny-list spans the whole station registry', () {
    late Directory root;
    late Directory worktree;
    late TestAssetResolutionFixture fixture;

    setUp(() {
      root = Directory.systemTemp.createTempSync('operator-audience-');
      worktree = Directory(p.join(root.path, 'worktree'))
        ..createSync(recursive: true);
      fixture = TestAssetResolutionFixture(
        root: root,
        assets: <sdk.GridAssetDefinition>[fixtureSkill('fixture-agent')],
        extraPacks: <String, List<sdk.GridAssetDefinition>>{
          _downstreamPackage: <sdk.GridAssetDefinition>[
            fixtureSkill(
              'downstream-operator',
              package: _downstreamPackage,
              audience: sdk.AssetAudience.human,
            ),
            fixtureSkill('downstream-agent', package: _downstreamPackage),
          ],
        },
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    File installedSkill(String id) =>
        File(p.join(worktree.path, '.claude', 'skills', id, 'SKILL.md'));

    /// The production spawn, over the two-pack registry the fixture composed.
    RuntimeConfig spawn() =>
        AgentCapability(
          assetRegistry: fixture.registry,
          overlaySourceRef: 'testref',
        ).spawn(
          FakeTreeContext(
            values: <Type, Object>{
              Bead: bead('tg-1'),
              Workspace: testWorkspace(
                'tg-1',
                workspaceDir: worktree.path,
                branch: 'grid/tg-1',
              ),
              SubstationFactsSnapshot: fixture.snapshot,
              sdk.SubstationScope: sdk.SubstationScope(
                name: kFixtureSubstation.name,
                root: fixture.substationRoot,
                prefix: 'fx',
              ),
            },
          ),
          stepArgs('tg-1/agent'),
        );

    test("a DOWNSTREAM pack's human-audience skill is INSTALLED into the "
        'worktree and still never named in the brief — the same force as a '
        'declaration in grid_assets itself', () {
      final config = spawn();

      // Non-vacuity: the deny-list can only be doing work if the downstream
      // skill actually reached the worktree.
      for (final id in const [
        'fixture-agent',
        'downstream-agent',
        'downstream-operator',
      ]) {
        expect(
          installedSkill(id).existsSync(),
          isTrue,
          reason: 'the production materializer installed /$id',
        );
      }

      final brief = config.args.last;
      expect(brief, contains('`/fixture-agent`'));
      // A DENY-list, not an allow-list: an UNDECLARED downstream skill stays
      // offerable, so the fix withholds by declaration and not by package.
      expect(brief, contains('`/downstream-agent`'));
      expect(brief, isNot(contains('`/downstream-operator`')));
    });
  });
}
