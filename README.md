# power_station

First-party grid asset packs for [the_grid](https://github.com/memento-engineering/the_grid) —
each pack exports **domain components + CLI components** (the CLI-SDK model):

| Pack | Domain |
|---|---|
| `packages/grid_assets` | the `code` asset (agent/verify/land + the `code` circuit + the git `SourceControl`) and the `compute` asset (bounded dispatch over a federation lease) |
| `packages/dart_grid_assets` | the DART domain (the typed `grid.dart` envelope + pub dev-time linkage + the exported `DartCommand`) |

The butane `burn` asset (`butane_grid_assets`) moved to its system's repo —
`butane_flutter/packages/butane_grid_assets` (grid assets live with their
system; the ADR-0011 placement split).

Extracted from `the_grid@17ea50a90d39791e8bad7a16c28a93711b44abf2` at the repo split.

## Dev linkage

The the_grid framework packages are declared `any` and resolved via a
machine-local `pubspec_overrides.yaml` at this root (gitignored) — path deps
into the sibling `../the_grid` checkout during dev, hosted/git refs at
stabilization. The dart domain's `grid dart link` generates it; see
the_grid `docs/SCRATCH-pub-capability-and-repo-split.md`. `genesis_tree`
stays hosted (`^0.1.3`).

```sh
dart pub get          # workspace root (needs the sibling checkout + overrides)
dart run melos run test
dart run melos run analyze
```
