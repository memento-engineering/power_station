## 0.6.0-rc.5

- New `declared-tests-present` code-review lane: confidently-declared test paths in the design are compared against the pinned diff; omitted files hard-block the round (#131).
- `CompletionContract.artifactDurability` adopted for every critic: recovery lives in the probe (the tg-291 stdout salvage recovers and persists canonically), `result()`'s unreachable envelope/fail-closed tiers are deleted, and the artifactless SiblingView cache fallback is removed — the join waits on durable artifacts, never a cached completion (#132).

## 0.6.0-rc.4

- Critic verdict artifacts are strict-decoded (non-object root, off-ladder/blank grade, blank rationale/nodePath, non-integer round all refuse); a present-but-malformed verdict fails the lane loudly (`AllocationFailed`, reason-prefixed) instead of silently grading F; unknown read exceptions fail the same way. Repair rides `criticRepairInstruction` on engine-supervised restarts (#128).
- Bundle derivations converted to `ServiceBundle.derive` — new bundle fields compile-error instead of silently dropping (#126).

## 0.6.0-rc.3

- `DeliveryMethod` seam additions backing the grade-gated landing postures (#121).

## 0.6.0-rc.2

- `MountEligibilityAssets` — the composable mount gate (pow-50l, #114). A
  station that mounts this seed admits a work bead only when it carries a
  driveable type, a `validation_plan`, and the `grid.approved` label. Without
  it the gate is INERT and every ready bead mounts, which is what 0.6.0-rc.1
  shipped: the class exists on `main` but is absent from the published
  0.6.0-rc.1 archive, so consumers resolving from pub could not compose the
  gate at all (pow-w83). This release is that fix — the version moves so the
  archive and the source stop disagreeing at the same number. It stays an
  `-rc` because grid_assets still depends on pre-release grid_engine /
  grid_runtime / grid_sdk / beads_dart / grid_exploration, and pub requires a
  package depending on a pre-release to publish as one.
- The git composition collaborators are watched from the tree rather than
  passed as constructor params (#113), matching the seat-facing const-services
  direction.
- Terminology: the human approval gate is "approve/approval" throughout
  (#118).
- Tests: the invariant-2/3 acceptance suites assert chokepoint creates by
  SHAPE rather than by a hard total, so they hold under both published-dep and
  path-override resolution (the_grid tg-zlfu adds a `mount-attempt` write).

## 0.6.0-rc.1

- Breaking: the GitHub implementations are REMOVED from this package and now
  live in `github_grid_assets` (pow-2ua, power_station #109). Six exports are
  gone: `GitHubAppPrOpener`, `GitHubPrDelivery`, `GitHubGridAssets`,
  `GitHubReconciler`/`GitHubReconcilerRuntime`, `GitHubReconcilerCursor`/
  `GitHubCursorStore`/`FileGitHubCursorStore`, and `NormalizedGitHubEvent`.
  Migration: depend on `github_grid_assets ^0.1.0-rc.2` and import them from
  `package:github_grid_assets/github_grid_assets.dart`. The abstractions they
  implement stay here — `DeliveryMethod`, `DeliverRouteCapability`,
  `SourceControl`, `PrComposition` and every `*Capability` are unchanged.
- Breaking: this package no longer depends on `github_grid_assets`. The
  dependency direction is inverted per the org rule: `grid_assets` holds the
  generic assets and the abstractions other asset packages implement, domain
  implementations live in their own domain package, and the edge runs
  implementation -> abstraction. Anything that reached a GitHub symbol
  transitively through this package must now depend on `github_grid_assets`
  directly.
- The MINOR moves rather than the patch specifically so `^0.5.0-rc.1`
  resolvers do not silently inherit the removals.

## 0.5.0-rc.1

- Breaking: adopts the_grid's 0.2.0-rc.1 prerelease wave — `beads_dart
  ^0.2.0-rc.1`, `grid_runtime ^0.2.0-rc.1`, `grid_engine ^0.3.0-rc.1`,
  `grid_sdk ^0.3.0-rc.1`. Published as a prerelease because pub requires a
  package depending on a prerelease to be one itself.
- Breaking: `BdExportBeadSource` no longer shells `bd export --all`, which is
  refused in proxied-server mode and whose API was deleted upstream. It now
  issues ONE all-status `bd query --all --json` per store. The contract is
  unchanged — one spawn per store, a read-only probe that never mutates, and
  closed beads are still included.

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
