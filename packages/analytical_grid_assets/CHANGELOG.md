# Changelog

## 0.1.0

- PROMOTED from 0.1.0-rc.1. This is the stable release of the 0.1.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.1.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.1.0-rc.1

- Initial candidate: the reusable station-health/effectiveness reporting pack — `StationMetricsBuilder` merges `SessionLedgerMetricsProjection` per store from the engine's component totals (false-F rate, weighted cache-hit rate, cost per landed delivery, rework rounds, grade distribution by lane), with day and harness/model splits, and the `station metrics` Commands/view models over it (pow-fv4, #210). Requires `grid_engine ^0.3.0-rc.14`.

