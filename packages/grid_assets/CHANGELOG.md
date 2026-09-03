## 0.6.0-rc.9

- Added: the typed-seat arming MECHANISM is vended — `AgentArming` (the pure
  per-seat VALUE), `TypedEnvironmentProvider` (the ONE seed both the station rung
  and the per-substation rung mount) and `SeatEnvironments` (the
  offline projection of all four resolutions at a point in the tree) now ship
  from `lib/src/agent/seat_environments.dart`, beside the seat vocabulary they
  wrap. `AgentArming` is the typed-seat shape: four typed seats and no
  role rung. A composing station keeps its own named environments and ladders:
  mechanism is vended, posture is not.

## 0.6.0-rc.8

- Fixed: the `filing` verb reads the grid home's cross-store link beads. It
  gains `--state-root <path>` with the same injected default `approve` carries,
  and both verbs now register and resolve it through one seam
  (`lib/src/filing/state_root_option.dart`: `kStateRootOption`,
  `kStateRootHelp`, `noStateRoot`, `addStateRootOption`, `resolveStateRoot`) —
  a blocker wired by an open link bead used to pass `approve` and fail
  `filing`. The named-blocker parser also tightened: a blocker is DECLARED by a
  segment that OPENS with `Blocked by` / `Blocked on` / `Depends on` (a
  mid-sentence mention declares nothing), and a `<prefix>-<tail>` token is a
  bead id only when its prefix is known or its tail carries a digit, so
  `cross-store` is no longer reported as a missing blocker.
- Breaking: approval IS the `grid.approved_*` stamp. `mountEligibilityFindings`
  no longer reads the `grid.approved` LABEL — its clause is now
  `if (!isApprovalStamped(bead))`, refusing with
  `approval: not approved - run the approve verb` — the `kApprovedLabel`
  constant is deleted, and the `approve` verb writes only the three stamp keys
  (`grid.approved_by`, `grid.approved_at`, `grid.approved_rev`) in its one
  `bd update`, with no `--add-label`. A bead carried four encodings of "not
  yet" and the label and the stamp were the same act written twice; a label any
  writer could add mounted work ahead of its blockers, while a hand-added one
  silently never mounted at all.
  Migration: every open bead holding ONLY the `grid.approved` label stops
  mounting — re-approve it with `<runner> approve --actor <name> <bead-id>`,
  which stamps it. Beads already stamped by the verb keep mounting untouched;
  the now-inert label needs no removal. `ApprovalStamp`, the three key
  constants and `isApprovalStamped` are unchanged and still exported, and the
  filing preflight is untouched. The vended station overlay teaches the stamp
  rule.

## 0.6.0-rc.7

- Breaking: the role map is retired — `AgentRole`, `roleEnvironments`,
  `modelForRole`, `stationModelFor`, `tierFor` and `defaultModelFor` are gone;
  `resolveAgentConfig` maps role to tier and model environments are selected by
  value through typed seats (`seat_environments.dart`) (#161, #168, #170).
  Migration: author the agent posture as typed seat environments instead of a
  role map; see `lib/src/agent/seat_environments.dart`.
- Breaking: author-owned spec-review verdicts route to the human gate
  (pow-hxme, #164), and committee metadata changes route through docs review (#162).
- Live environment availability is published to the arming surface (pow-n6n.3, #165).
- The decisions register: design decisions are recorded as slug entries under
  `docs/decisions/` and the lens excludes `views/` (#169).
- The approve verb stamps `grid.approved_by/at/rev` beside the label, and the
  overlay skills teach approval through the verb (pow-5ch, #163).
- Declared-tests base-gates bare prose test mentions (#158).
- Requires `grid_runtime ^0.2.0-rc.8` and `beads_dart ^0.2.0-rc.5`
  (the wave-2 the_grid train).

## 0.6.0-rc.6

- Breaking: a `grid.approved` label without a `grid.approved_at` stamp no
  longer mounts. The new `approve` verb (`ApproveCommand`) gates its atomic
  receipt write on filing completeness — sentence-scoped blockers and
  state-store links included — and records the approver, the UTC instant and
  the repository revision, so mount eligibility can tell a verb-issued receipt
  from a bare label (pow-kps, #159). Migration: re-stamp every open
  `grid.approved` bead with the `approve` verb; a bare label is refused at the
  gate. The governor already ran this org-wide on 2026-09-02.
- The bead filing contract is enforced by a read-only filing service and
  `FilingCommand`, which reject mechanically incomplete author-side filings;
  `discover` calls the command, and the defer and mount-eligibility boundaries
  are unchanged (#148).
- ACP-backed agent sessions: Copilot and Codex drive through one long-lived ACP
  adapter carrying structured progress, completion, usage, steering,
  permissions and model selection, with hermetic protocol-conformance coverage
  and an opt-in live worktree proof (#153).
- Channel-backed agent sessions: harness-specific session adapters, bead-routed
  fenced steering and environment opt-in wiring; agent briefs, structured
  results and usage travel the long-lived channel while every builtin stays on
  the one-turn path (#147).
- The `architect` agent role gives specification agents an independent
  environment role, with a build fallback so existing build-environment
  armings keep working (#154).
- Copilot one-shot telemetry: the Copilot environment declares silent JSON
  output and keyed resume, and projects premium-request consumption plus
  session duration through the generic usage report path (#145).
- Critic verdict rounds are authored at the capability boundary: a canonical
  verdict must be proven to belong to the current critic incarnation before it
  replaces a model-authored round, the model value is preserved for
  diagnostics, and an unresolved durability probe flares (pow-uok, #157).
- Critic verdict artifacts are written through same-directory atomic
  replacement, and respec ledgers are fenced by their owning session root, so a
  concurrent or stale artifact cannot poison a live join (#140).
- `specify` completion is gated on a fresh exact-id readback through the owned
  bd client, failing closed when authored acceptance or design is absent or
  unreadable (#149).
- Mount eligibility preloads the owning store's bead snapshot and rechecks a
  tentative refusal against the fresh bead, so first-refusal clauses derive
  from current fields; eligible snapshots stay synchronous (#152).
- Declared tests: extraction is narrowed to authored declarations and ignores
  run commands, quotation contexts and unchanged/restore statements (#150);
  bare `Test:` run references are split from authored declarations and consult
  the pinned base only as the fallback set (#155); package-relative
  declarations resolve against repo-relative pinned-diff paths by path suffix
  (#138).
- Readiness, specify, spec review and discovery prompts search both local
  decision homes (`docs/adr` and `docs/decisions`) through one missing-safe
  command set, and packaged assets accept legacy clauses as well as decision
  slugs in a citation (#146).
- The vended skills teach the enforced approval-label transition in place of
  defer staging, with pinned source rendering and operator installation (#151).
- Tests: the specify environment assertion names the `architect` environment
  rather than a bare codex argv (#156).

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
