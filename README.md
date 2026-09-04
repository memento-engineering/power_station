# power_station

First-party grid asset packs for [the_grid](https://github.com/memento-engineering/the_grid) —
each pack exports **domain components + CLI components** (the CLI-SDK model):

| Pack | Domain |
|---|---|
| `packages/grid_assets` | the `code` asset (agent/verify/land + the `code` circuit + the git `SourceControl`) and the `compute` asset (bounded dispatch over a federation lease) |
| `packages/dart_grid_assets` | the DART domain (the typed `grid.dart` envelope + pub dev-time linkage + the exported `DartCommand`) |
| `packages/federated_grid_assets` | the federation surface (station server + cross-station asset leasing) |
| `packages/zero_conf_grid_assets` | zero-conf station discovery (mDNS advertisement/browse) |
| `packages/analytical_grid_assets` | the ANALYTICAL domain (station health and effectiveness REPORTING over the session-ledger metrics projection: split token distributions + the exported `MetricsCommand`) |

The butane `burn` asset (`butane_grid_assets`) moved to its system's repo —
`butane_flutter/packages/butane_grid_assets` (grid assets live with their
system; the ADR-0011 placement split).

Extracted from `the_grid@17ea50a90d39791e8bad7a16c28a93711b44abf2` at the repo split.

## Dev linkage

The the_grid framework packages are declared `any` and resolved via a
machine-local `pubspec_overrides.yaml` at this root (gitignored) — path deps
into the sibling `../the_grid` checkout during dev, hosted/git refs at
stabilization. The dart domain's `grid dart link` generates it; see
the_grid `docs/DESIGN-pub-capability-and-repo-split.md`. `genesis_tree`
stays hosted (`^0.1.3`).

```sh
dart pub get          # workspace root (needs the sibling checkout + overrides)
dart run melos run test
dart run melos run analyze
```

## Sibling repositories

power_station is one repo of the
[memento-engineering](https://github.com/memento-engineering) org, and its docs
reference siblings by name: [`the_grid`](https://github.com/memento-engineering/the_grid)
(the engine these asset packs plug into),
[`lenny`](https://github.com/memento-engineering/lenny) (the debugging harness),
`space_station` (the org's grid instance — public release to follow), and
**houston** (not a repo: the id prefix of the station's state store). **Gas City**
(`gc`) is the predecessor system the_grid reimplements — not ours; see the
original project at [docs.gascityhall.com](https://docs.gascityhall.com).

## License

MIT — see [LICENSE](LICENSE).
