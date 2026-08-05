## 0.5.0-rc.1

- Breaking: adopts the_grid's 0.2.0-rc.1 prerelease wave — `beads_dart
  ^0.2.0-rc.1`, `grid_runtime ^0.2.0-rc.1`, `grid_engine ^0.3.0-rc.1`,
  `grid_sdk ^0.3.0-rc.1`. Published as a prerelease because pub requires a
  package depending on a prerelease to be one itself.
- Breaking: `BdExportBeadSource` no longer shells `bd export --all`, which is
  refused in proxied-server mode and whose API was deleted upstream. It now
  issues ONE all-status `bd query --all --json` per store. The contract is
  unchanged — one spawn per store, a pure read (A37), closed beads included.

## 0.4.0

- Breaking: rides the 0.2.0 substrate wave — grid_engine/grid_sdk ^0.2.0,
  genesis_tree ^0.2.0 (foundation diagnostics; ext.leonard.* namespace).

## 0.3.1

- `CodeCircuitResolver` accepts an optional pre-classification `overrideFor` policy: a non-null override roots that circuit without cursor classification; the null path is byte-for-byte unchanged. Enables subclass stations to route selected beads (e.g. burn orders) to non-code circuits.

# Changelog

## 0.3.0

- **Breaking:** overlay assets now ship from VISIBLE source directories
  (`extension/station_overlay/claude/`, `agents/`, `github/`, …) mapped to
  dot-targets (`.claude/`, `.agents/`, `.github/`, …) at install time —
  `dart pub publish` strips hidden directories, so 0.1.0/0.2.0 tarballs shipped
  HOLLOW (no operator files at all). Default mappings cover
  claude/agents/github/copilot/codex; the overlay manifest can declare its own.
  Migration for `OverlayInstallService.install` overriders: the
  `overlayRoots: List<String>` required parameter is now optional and superseded
  by `overlaySources: List<StationOverlaySource>`; root providers return
  `List<StationOverlaySource>` instead of `List<String>`.

## 0.2.0

- **Breaking:** `SearchCommand` and `AssetsCommand` now OWN the `--grid-home`
  flag, its absolute-path guard, and normalization; the delegate factory seam
  changed from a zero-arg closure to `GridDelegate Function(String gridHome)`.
  Migration: drop your own `--grid-home` option registration and resolve/guard
  block, pass `gridHomeDefault`, and curry the factory with the
  command-resolved home — `delegate: (gridHome) => MyDelegate(gridRoot: gridHome)`.
  The `AssetsCommand` install leg treats the flag as an explicit OVERRIDE only:
  when absent the default remains mount-then-read-ambient `GridRoot` via
  `mountedGridHomeOf`.
- Added `runnerInvocation` as a first-class parameter on `AssetsCommand` and
  `OverlayInstallService`, so a JIT-launched station renders the `{{runner}}`
  template hole without subclassing. Omitted, behaviour is unchanged
  (`runner.executableName` remains the default).
- Added `buildComputeServeCommand()` / `buildComputeLeaseCommand()` — the
  compute asset now vends its own fully-wired `ServeCommand` / `LeaseCommand`
  instead of every station copying the assembly block. The `--allow` list stays
  a caller-supplied parameter (station security policy).
- Generalized `codedRosterOf` off the station-specific factory typedef, with
  dispose-on-throw fenced.
- Fixed: spec verdict rounds are sourced from circuit params.

## 0.1.0

- Initial release: the_grid's opinion assets — the agent/verify/land Capability impls, the code circuit, and the git SourceControl.
# 0.2.1

- Store station overlay assets in publish-visible source directories and map
  them to harness dot-directories at install time.
- Allow asset manifests to override the default station overlay mappings.
- Warn during install and release dry-run when hidden overlay source
  directories would be omitted by `dart pub publish`.
