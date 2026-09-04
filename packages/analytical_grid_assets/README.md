# analytical_grid_assets

The reusable station-health and effectiveness reporting pack for a `the_grid`
station. It presents `grid_engine`'s `SessionLedgerMetricsProjection` per
substation and merges the set from the engine's component totals — false-F
rate, weighted cache-hit rate, cost per landed delivery, rework rounds, and
the grade distribution by lane — with day and harness/model splits, and vends
the `station metrics` Commands and view models over that merge.

Compose it in a station runner the way every other `*_grid_assets` pack is
composed: the pack vends the Command; the station supplies the roster.
Requires `grid_engine ^0.3.0-rc.14` (the component totals) and
`grid_assets ^0.6.0-rc.12`.
