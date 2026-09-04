---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-grid-block-is-the-single-asset-authority
  surfaces:
    - "packages/grid_assets/pubspec.yaml"
    - "packages/grid_assets/lib/src/assets/grid_block.dart"
    - "packages/grid_assets/lib/src/assets/grid_asset_pack.dart"
    - "packages/grid_assets/lib/src/assets/vended_assets.dart"
    - "packages/grid_assets/extension/mcp/config.yaml"
    - "packages/grid_assets/tool/generate_grid_assets.dart"
  obsoletes: []
  updates:
    - a24-bead-pow-a74-the-operator-install-leg-discovers-its-over
    - a-harness-may-carry-its-own-instructions
    - the-handoff-ritual-vends-as-an-operator-audience-skill
  obsoleted-by: null
  updated-by: []
  bead: pow-836a
  legacy-id: null
---

# The `grid:` block is the single authored asset authority

## Context and Problem Statement

The vended asset surface was declared in four places that drifted
independently: `kVendedSkills` and `kOperatorSkills` (const id lists in
`asset_loader.dart`), the hand-written `skills:` section of
`extension/mcp/config.yaml`, and the shape of the
`extension/station_overlay/**/skills/` tree itself. Nothing typed existed for a
station to compose. `the_grid#grid-block-packages-publish-dart-asset-definitions`
settled which packages participate — "A package that carries a top-level
`grid:` block participates in the compiled registry and therefore publishes
generated Dart definitions" — leaving power_station to author the block and
generate from it.

## Decision Outcome

The `grid:` block in `packages/grid_assets/pubspec.yaml` is the SOLE authored
declaration. `tool/generate_grid_assets.dart` renders BOTH
`lib/src/assets/grid_asset_pack.dart` and `extension/mcp/config.yaml` from ONE
parse, in memory, and writes them only after the complete block validates —
so the Dart declaration and the MCP mirror change together or not at all.
`extension/mcp/config.yaml` is now GENERATED OUTPUT; its hand-written
commentary is retired and edits go to the block.

The selector vocabulary is closed over six tokens and maps onto `grid_sdk`'s
sealed `AssetSelector` union: `unknown` (an omitted `selector`) and `any` both
emit `AlwaysApplies()`, `dart-package:<name>` emits `RequiresPackage`,
`decision-register` emits `RequiresPath('docs/decisions')`, and `station` emits
`RequiresPath('.grid')`. `never` is grammar-valid and REFUSED at emit: that
union carries no unsatisfiable variant, and this pack must consume the neutral
contract rather than define a Power-local registry type. The refusal names the
asset, the field, and the absent variant; it becomes an emission the day
`grid_sdk` gains one.

`kVendedSkills` and `kOperatorSkills` are deleted. `vendedSkillIds` and
`operatorSkillIds` derive from `GridAssetsPack.assets`, and the audience
doctrine those constants documented is preserved verbatim on the block's
`audience` field.

This UPDATES three entries on their MECHANISM only; every doctrinal clause
stands. `a24-…` keeps its deny-list ruling — "Only a DECLARED operator audience
withholds a skill" — with `audience: human` in the block as that declaration.
`a-harness-may-carry-its-own-instructions` keeps "both legs vend exactly the
`kVendedSkills` id set"; the set is now `vendedSkillIds`.
`the-handoff-ritual-vends-as-an-operator-audience-skill` keeps handoff's
operator audience; it now "joins" the deny-list by declaring
`audience: human`.

### Consequences

* Good, because a skill can no longer be vended in the overlay tree, missing
  from the manifest, and absent from an id list at the same time — one block
  produces all three views.
* Good, because a station composes a typed `GridAssetPackDefinition` rather
  than re-deriving the surface from a file scan.
* Bad, because `extension/mcp/config.yaml`'s hand-written commentary is lost;
  the prose that was load-bearing (the audience doctrine) moved verbatim into
  the block and is fenced by test, and the rest was decoration.
* Bad, because a `selector: never` declaration cannot ship until `grid_sdk`
  gains an unsatisfiable variant. Accepted: no asset needs one today, and a
  loud refusal beats a Power-local type the station could not read.
