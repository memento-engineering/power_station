# Changelog

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
