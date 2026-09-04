/// The vended-skill views callers used to read off hand-maintained const lists.
///
/// Both DERIVE from the generated [GridAssetsPack], so a skill declared in the
/// `grid:` block is in these views by construction and no second id list can
/// drift from it. The audience doctrine those lists carried lives, verbatim, on
/// the block's `audience` field in `pubspec.yaml`.
library;

import 'package:grid_sdk/grid_sdk.dart';

import 'grid_asset_pack.dart';

/// The skill ids this package vends, sorted.
///
/// `OverlayMaterializer` does not read this (it installs whatever files exist
/// under the overlay); it is the by-id render surface's index, and the
/// structural harness fence's — both overlay legs vend exactly this id set
/// (`power_station#a-harness-may-carry-its-own-instructions`).
List<String> get vendedSkillIds => _skillIds((_) => true);

/// The vended skills whose AUDIENCE is the OPERATOR — the human at the grid
/// home, whose `.claude/` the `install` Command fills.
///
/// A DENY-list, not an allow-list: the provision wire installs them into a
/// per-bead worktree like any other overlay file (one tree, two consumers) but
/// NEVER names them in a build agent's brief. Only a DECLARED operator
/// audience (`audience: human` in the `grid:` block) withholds a skill
/// (`power_station#a24-bead-pow-a74-the-operator-install-leg-discovers-its-over`).
List<String> get operatorSkillIds =>
    _skillIds((asset) => asset.audience == AssetAudience.human);

List<String> _skillIds(bool Function(GridAssetDefinition asset) where) =>
    <String>[
      for (final asset in GridAssetsPack.assets)
        if (asset.assetKey.kind == AssetKind.skill && where(asset))
          asset.assetKey.id,
    ]..sort();
