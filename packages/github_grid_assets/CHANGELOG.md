## 0.1.0-rc.6

- `GitHubReconcilerBindingAssets`: provides each live seat a durable `GitHubCursorStore` and SELF-only deferred-intake `GitHubEventSink`, completing the ambient seams required by `GitHubReconcilerAssets` to construct its polling runtime (#139).

## 0.1.0-rc.5

- `GitHubAppClientAssets`: per-seat GitHub App client construction with per-app key resolution — the key path comes from the env var each seat's `privateKeyVar` names (inert when unset, loud on a bad path or mode), replacing the single fixed `GC_GITHUB_APP_KEY_PATH` (#134).
- Committee fakes adopt the `declared-tests-present` lane; floors `grid_assets ^0.6.0-rc.5` (#133).

## 0.1.0-rc.4

- The seat's ServiceBundle derivation uses `ServiceBundle.derive` — field drops are now compile errors (#126).

## 0.1.0-rc.3

- Landing postures as sibling `DeliveryMethod`s: `GitHubDeliveryPolicy` values select `GitHubPrDelivery` (default), `GitHubAutoMergeDelivery` (native auto-merge only when validation rc == 0 and every committee grade is B or better), or `GitHubDirectMergeDelivery` (protected-aware); refused enables fall back loudly with named flares (#121).
- CI-feedback path: `GitHubGridAssets` observes `GitHubReconcilerRuntime`/`CiFeedbackProjection` from the tree; a failed `CheckConcluded` routes exactly one fenced `grid/rework` through the chokepoint, with the ratified attempt budget and cap gate (#122).
- `GitHubReconcilerAssets`: the provider that constructs a live `GitHubReconcilerRuntime` from a `GitHubReconcilerConfig` value and mounts it for the seat; config-absent and dry/offline compositions construct nothing (#123).

## 0.1.0-rc.2

- Requires `grid_assets ^0.6.0-rc.1`. This is the load-bearing change: 0.1.0-rc.1
  could resolve alongside `grid_assets 0.5.0-rc.1`, which still exported
  `GitHubPrDelivery`, so a hosted resolve saw the same symbol from two packages
  and failed to compile ("'GitHubPrDelivery' is imported from both ..."). Local
  path overrides masked it; only a no-override resolve hit it. The tightened
  constraint makes that pairing unrepresentable.

# Changelog

## 0.1.0-rc.1

- Initial release: GitHub App identity and authenticated REST transport.
- Home of the org's GitHub grid-asset implementations: `GitHubAppPrOpener`,
  `GitHubPrDelivery`, the `GitHubGridAssets` seed, and the reconciler/cursor
  surface, relocated out of `grid_assets` by pow-2ua (power_station #109).
  `grid_assets` holds the generic assets and the abstractions; the dependency
  runs implementation -> abstraction, so this package depends on `grid_assets`
  and never the reverse.
- Published as a pre-release because it depends on pre-release siblings
  (`grid_assets ^0.5.0-rc.1`, `grid_engine ^0.3.0-rc.3`, `grid_runtime`).
