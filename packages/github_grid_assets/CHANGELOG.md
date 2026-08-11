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
