// The ROOT-FILE agents leg fixture: the one declared artifact whose target is
// the repository ROOT itself rather than a harness head.
//
// It lives in its own support file on purpose. The pre-existing declarations and
// fixture bodies must keep proving the exact paths and bytes they always proved,
// so the new leg is composed ALONGSIDE them by the suites that want it and is
// invisible to the ones that do not.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';

import 'asset_resolution_fixture.dart';

/// The declared source path of [fixtureAgentsInstructions]'s one artifact.
///
/// An `agents` delivery leg, exactly like a `.agents/skills/…` leg — what tells
/// the two apart is the SOURCE HEAD it is declared under, since the SDK's
/// delivery enum names both agents surfaces with one case.
const String kFixtureAgentsRootSourcePath =
    '$kStationOverlaySourceHead/$kAgentsRootMappingKey/'
    '$kAgentsRootRelativePath';

/// The ROOT instruction artifact: the `agents`-target leg that installs as the
/// repository-root [kAgentsRootRelativePath] a codex-style seat actually reads.
GridAssetDefinition fixtureAgentsInstructions({
  String id = 'instructions',
  AssetSelector selector = const AlwaysApplies(),
  String package = kFixturePackage,
}) => GridAssetDefinition(
  assetKey: AssetKey(package: package, kind: AssetKind.resource, id: id),
  description: 'the $id fixture root instructions',
  audience: AssetAudience.agent,
  selector: selector,
  artifacts: const <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.agents,
      path: kFixtureAgentsRootSourcePath,
    ),
  ],
);

/// A plain-Markdown root instruction body — deliberately NOT frontmatter-led:
/// the root file is repository INSTRUCTION prose, not a skill, so it carries no
/// YAML block for a stamp to hide in.
String fixtureAgentsInstructionsBody([String body = 'the org doctrine']) =>
    '# Fixture doctrine\n\n$body\n';

/// The `bodies` entry a [TestAssetResolutionFixture] needs for the root leg —
/// the fixture's default body is a frontmatter-led SKILL.md, which the root file
/// never is.
Map<String, String> fixtureAgentsInstructionsBodies([
  String body = 'the org doctrine',
]) => <String, String>{
  kFixtureAgentsRootSourcePath: fixtureAgentsInstructionsBody(body),
};

/// An `agents_root` artifact declared at a path the leg does not vend — the one
/// shape the resolution must refuse loudly, since the repository root is not a
/// tree an overlay pours into.
GridAssetDefinition fixtureAgentsRootTree() => const GridAssetDefinition(
  assetKey: AssetKey(
    package: kFixturePackage,
    kind: AssetKind.resource,
    id: 'poured',
  ),
  description: 'declared under the root-file head, but not the root file',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.agents,
      path: '$kStationOverlaySourceHead/$kAgentsRootMappingKey/notes/NOTE.md',
    ),
  ],
);
