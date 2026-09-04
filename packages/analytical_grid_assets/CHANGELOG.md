# Changelog

## 0.1.0-rc.1

- Initial candidate: the reusable station-health/effectiveness reporting pack — `StationMetricsBuilder` merges `SessionLedgerMetricsProjection` per store from the engine's component totals (false-F rate, weighted cache-hit rate, cost per landed delivery, rework rounds, grade distribution by lane), with day and harness/model splits, and the `station metrics` Commands/view models over it (pow-fv4, #210). Requires `grid_engine ^0.3.0-rc.14`.

