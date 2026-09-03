---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: github-app-assets-flake-is-real-io-below-the-fake-read
  surfaces:
    - "packages/github_grid_assets/test/github_app_client_assets_test.dart"
    - "packages/github_grid_assets/test/environment_fence_test.dart"
    - "packages/github_grid_assets/lib/src/intake/github_self_trust.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-vw38
  legacy-id: null
---

# The github_grid_assets asset-test flake is REAL filesystem IO below the `_FakeRead` seam, not an ambient-environment coupling

## Context and Problem Statement

`packages/github_grid_assets/test/github_app_client_assets_test.dart` failed
intermittently on the operator's box and stayed green on CI, and the reported
cause was a coupling to the exported `GRID_GITHUB_APP_KEY_*` variables. That is
falsified. No file in this repository reads those names; the pack's whole `lib/`
touched `Platform.environment` in only two places, neither on the asset's path
(`lib/src/credentials.dart`'s `platformEnvironment()`, which the test never uses
because it injects its own `EnvironmentReader`, and
`lib/src/intake/github_self_trust.dart`, which reads only `GITHUB_USER`); and
the same file failed 2 of 5 with both variables UNSET. The `env -u` A/B that
motivated the report was a coincidence of build-cache warmth, not causation.

The real defect is that `_FakeRead.call` awaited `File(path).readAsString()` — a
real OS completion below a seam named "fake" — while the file's private `_settle`
waited by pumping the event queue exactly three times. When the read had not
landed, the asset's client was still null and the assertions read the pre-load
tree.

## Decision Outcome

A FAKE performs no IO. `_FakeRead` serves the fixture PEMs from a map read
synchronously at library load, and every wait in the file goes through the pack
family's shared bounded `settle` (`test/support/asset_fakes.dart`), targeted at
the observable it awaits. Both fakes record the paths they were asked for, and a
path the test never staged throws rather than returning a sentinel.

The hermeticity hardening the report asked for is kept on its own merits rather
than as the cure: `GitHubSelfTrust.fromEnvironment` takes the same injectable
`EnvironmentReader` the credential loader has — a BREAKING signature change,
with its only three call sites in this pack's own tests — leaving
`lib/src/credentials.dart` as the ONE sanctioned process-environment read, and
`test/environment_fence_test.dart` fails loudly on any new one.

This is the same failure class as
`power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`,
which remains in force unamended. A28 ruled that "real filesystem IO in a
production write path is legitimate; what was wrong is the harness's model of
what a WAIT is". That legitimacy does not reach a TEST DOUBLE: there the IO sat
below a fake `BdRunner` in a production write path and only the wait was fixed;
here the IO is in the double itself, so the IO is removed as well as the wait
repaired.

### Consequences

* Good, because the pack is green under any ambient environment and any cache
  warmth, so a `github_grid_assets` bead no longer needs a governor hand-harvest.
* Good, because the fence turns a silent regression — a new
  `?? Platform.environment` fallback — into a failing test.
* Bad, because the fixture PEMs are now read eagerly at library load even for
  the cases that never resolve a key: a few microseconds paid by every run of
  the file.

### Confirmation

`cd packages/github_grid_assets && dart test` is green with
`GRID_GITHUB_APP_KEY_MEMENTO` and `GRID_GITHUB_APP_KEY_NICHOLAS` exported, over
20 consecutive runs of the file and the whole pack; `dart analyze` is clean. The
fence was proven loud by appending a `Platform.environment` read to
`lib/src/http_transport.dart` and observing the failure, then reverting.

**Status:** pending.
