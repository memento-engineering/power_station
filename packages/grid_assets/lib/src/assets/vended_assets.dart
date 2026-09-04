/// The vended-skill views callers used to read off hand-maintained const lists.
///
/// Both DERIVE from a generated value, so a skill declared in a `grid:` block is
/// in these views by construction and no second id list can drift from it — but
/// they derive from DIFFERENT ones, because they answer different questions.
/// [vendedSkillIds] asks "what does THIS package vend"; [operatorSkillIds] asks
/// "what may a build agent's brief never offer AT THIS STATION", and only the
/// station's composed registry knows that. The audience doctrine those lists
/// carried lives, verbatim, on the block's `audience` field in `pubspec.yaml`.
library;

import 'package:grid_sdk/grid_sdk.dart';

import 'grid_asset_pack.dart';

/// The skill ids this package vends, sorted.
///
/// `OverlayMaterializer` does not read this (it installs whatever the one
/// resolution selected); it is the by-id render surface's index, and the
/// structural harness fence's — both overlay legs vend exactly this id set
/// (`power_station#a-harness-may-carry-its-own-instructions`).
List<String> get vendedSkillIds =>
    _skillIds(GridAssetsPack.assets, (_) => true);

/// The skills [registry] declares for the OPERATOR — the human at the grid
/// home, whose `.claude/` the `install` Command fills — sorted.
///
/// A DENY-list, not an allow-list: the provision wire installs them into a
/// per-bead worktree like any other overlay file (one tree, two consumers) but
/// NEVER names them in a build agent's brief. Only a DECLARED operator
/// audience (`audience: human` in the `grid:` block) withholds a skill
/// (`power_station#a24-bead-pow-a74-the-operator-install-leg-discovers-its-over`).
///
/// [registry] is the STATION's generated closure, never this package's own
/// pack: a station composes packs grid_assets has never heard of, and a
/// declaration in one of them has exactly the force of a declaration here
/// (`power_station#station-operator-audiences-derive-from-the-resolved-registry`).
/// Reading `GridAssetsPack.assets` instead would silently offer every
/// downstream operator skill to a build agent.
List<String> operatorSkillIds(GridAssetRegistry registry) => _skillIds(
  registry.assets,
  (asset) => asset.audience == AssetAudience.human,
);

List<String> _skillIds(
  Iterable<GridAssetDefinition> assets,
  bool Function(GridAssetDefinition asset) where,
) => <String>[
  for (final asset in assets)
    if (asset.assetKey.kind == AssetKind.skill && where(asset))
      asset.assetKey.id,
]..sort();
