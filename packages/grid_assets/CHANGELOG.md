## 0.6.0-rc.16

- Fixed: the shelled decision lookup accepts the decisions index envelope `spec: 2` beside `spec: 1` (`_acceptedDecisionIndexSpecs`); against decisions_grid_assets 0.2.1 every explore-decision surface FAILED on rc.13–rc.15 and the round held at `discovery-route` (pow-rokz, #231).
- Fixed: approval receipts are complete and bound to the filing basis — `ApprovalStamp.tryParse` requires a nonblank `grid.approved_by`, a UTC `grid.approved_at`, and a recognized `grid.approved_rev` (a legacy raw git sha, or the `filing:v1:sha256:` digest the approve verb now writes over the bead's filing contract); a lone `grid.approved_at` no longer mounts, and mount eligibility re-checks the fresh bead against the stamped revision (pow-9rah, #232).

## 0.6.0-rc.15

- Fixed: the discovery gather carries the WORK BEAD's own citation fields (`boundedBeadFields`) WHOLE — `kMaxDiscoverySnippetChars` bounds FOREIGN evidence (prior-art hits, anchor contents, decision entries, history) so it cannot flood a lens, and it never clips the brief the lens is judging. A description past 4 KB arrived at every lens truncated, and the prior-art lens correctly refused to judge a clipped brief — holding the bead's own discovery round. `boundDiscoveryEvidence` gains `truncateSnippet` (default `true`, so every foreign caller is unchanged); digests, evidence ids and the `EvidenceState` meanings are untouched (pow-xfm0).
- Fixed: the discovery gather no longer treats a record clipped at its OWN bound (`kMaxDiscoverySnippetChars`, `kMaxHistoryCommits`) or a clipped anchor/symbol extraction (`kMaxAnchors`) as a deterministic gap — every mature surface exceeds those bounds, and the override held every round at `discovery-route` while the lenses reported zero gaps. A clip is rendered as context the lens narrates; only `failed` overrides a lens, and only the lens's own insufficient-evidence outcome holds the round on a clip. `gatherHistory` records `unavailable` over an empty resolved path list instead of logging the whole repository (pow-gcx9, #225).

## 0.6.0-rc.14

- Added: the `grid:` block accepts an optional `teaches:` sequence per skill asset (the deterministic commands its prose teaches), parsed by `parseGridBlock`, emitted by the registrant generator only when non-empty, and authored for the baseline skill/command pairs; unclaimed packs generate byte-identical output. Floors `grid_sdk ^0.3.0-rc.15` for `GridAssetDefinition.teaches` (pow-prw4, #228).
- Fixed: the discovery gather's roster decision lookup qualifies surfaces from the SESSION's substation (`metadata['rig']` is a session-bead field no work bead carries), never shells a `<repo>`-prefixed surface (recorded `unavailable` instead), and runs the station's verb from the composing grid home (`overlayArgs['gridHome'] ?? devRoot`) rather than the work worktree — every explore-decision lens held its round on rc.12/rc.13 (pow-974y, #226). Stations pass `'gridHome'` beside `'runner'` in `buildCodeRegistry(overlayArgs:)`.
- Fixed: `--state-root` on the filing verbs takes the GRID HOME its help names — the resolver appends `.grid` when the root holds one, accepts a state store unchanged, and refuses a root holding neither child loudly; an unconsulted cross-store edge is reported as UNCHECKED, never as missing (pow-ixag, #227).
- Fixed: the code-validation gating lane preserves the validation failure output the way land/revalidate does — the shared captured-output leaf recognizes `[E]` beside `Error:` / `Failed to load`, and the full log lands in `.grid/critique/code-validation.log` (#224).

## 0.6.0-rc.13

- Breaking: asset availability is resolved ONCE — `resolveGridAssets` over a repository-observed `SubstationFactsSnapshot` defines the tree's selected definitions and BOTH overlay writers (`assets install`, `OverlayMaterializer`) and the landing pre-rebase guard consume that same resolution; `--check` reports drift. Un-migrated stations without facts keep the pre-resolution path (pow-4peu, #216). Migration: compose a station's assets through `resolveGridAssets`/`GridAssetRegistry` — a writer must never build a second catalog; `github_grid_assets ^0.1.0-rc.13` carries the matching `SubstationSeed`.
- Breaking: `operatorSkillIds` is a FUNCTION over the station-resolved `GridAssetRegistry` (`operatorSkillIds(registry)`), not a getter over this package's own pack — a downstream pack's `audience: human` declaration is now withheld from a build agent's brief (pow-vtts, #218). Migration: pass the resolved registry; `vendedSkillIds` is unchanged.
- Added: `prime --hook-json` (echoes `bd prime` and injects an operator seat's newest handoff on SessionStart sources startup/clear/compact — never resume) and `seat <name>` (the harness-neutral operator-seat launcher composed over `AgentEnvironment`); five nullable seat declarations on `AgentEnvironment` (`drivenArgs`, `roleAsset`, `roleArgs`, `memoryDirArgs`, `primeMode`) — the driven-only flag moved from `args` to `drivenArgs`, one-turn argv byte-identical. The vended station overlay's SessionStart hook is now `{{runner}} prime --hook-json`; a station adopting this rc MUST compose `PrimeCommand`/`SeatCommand` into its runner (pow-lv6t, #220; space_station space-31x).
- Added: SHADOW stage-specific committee selection — `CommitteeSelectionPolicy` (eight deterministic rules over the round-stamped discovery evidence / pinned diff, a closed classifier allowlist, `fullFallback` on a non-result), `CommitteeSelectionCapability` as a dependency of NOTHING, `CommitteeShadowRouteCapability` wrapping every route, typed JSON receipts with lane input digests and counterfactual totals; the full committees stay authoritative. Depends on `grid_trajectory ^0.2.0-rc.4` for its report vocabulary (`GateDisposition`, `LaneReport`, `UsageSample`) — value types only (pow-1nl.1.1, #222).
- Added: usage cost is DERIVED from a declared per-model price table (`ModelPriceTable`, `kUsageModelPrices`, keyed by the ladder's model ids) when a harness reports tokens but no `total_cost_usd` (codex), stamped `UsageCostSource.derived` vs `reported`; an unknown model keeps its tokens, reports null cost and flares (pow-zetn, #221).
- Fixed: the land/revalidate reason leads with the Dart front-end's `Error:` / `Failed to load` lines (deduplicated) before the tail and writes the full output to `.grid/critique/revalidate.log` (pow-gvfx, #217).

## 0.6.0-rc.12

- Breaking: the vended asset surface is DECLARED in the package's own `pubspec.yaml` `grid:` block and CODEGEN'd into a typed Dart registrant (`GeneratedGridAssetRegistrant`); the hand-maintained `kVendedSkills`/`kOperatorSkills` mirrors are retired and `extension/mcp/config.yaml` is generated from the same block (pow-u6hj, #205). Migration: a downstream pack that listed its assets in the const mirrors declares them in its `grid:` block and runs the generator (`dart run tool/generate_grid_assets.dart`); nothing else changes for stations that only compose the vended packs.
- Breaking (floor): `grid_engine ^0.3.0-rc.15` — critic verdict failures ride the typed `CapabilityFailure` seam (`CapabilityFailureKind.invalidResult`), `CriticCapability` declares its own `SupervisionPolicy` (retry its lane only, never grade F, gate on exhaustion), and the six `Failed.nonResult` call sites are gone (pow-dzc, #214).
- Added: the station Dart registrant is generated from the resolved package closure — every dependency's `grid:` block is unioned once (pow-bafc, #212).
- Added: discovery evidence is gathered ONCE into a bounded, round-stamped `DiscoveryDossier` with provenance and explicit truncation, and each inference lane receives a capability-specific projection; the decision-index gather runs through the composed decisions command or the station's runner, and an ABSENT tool is `unavailable`, never a gap (pow-ri9c, #208).
- Added: `parseSpecContract` — the typed record grammar for specs (AC-n ids, labeled steps, exact `AC-n -> command -> expected` validation mappings) measured in SHADOW by `spec_contract_shadow.dart`; the five live presence checks remain the A/F gate (pow-5ufz, #207).
- Added: `format-clean`, a deterministic code-review step before the critics that gates unformatted Dart naming the files (pow-jicn, #209).
- Added: PR-description inference receives a bounded (16 KiB) deterministic change manifest — commit subjects, diffstat, change shape, bead identity, receipts — instead of the raw diff (pow-c7lb, #203).
- Fixed: the decision-alignment brief renders the roster lookup from the STATION's runner (`overlayArgs['runner']`) and the rubric uses the `{{runner}}` hole — no more hardcoded `space decisions index` (pow-q7ty, #213).
- Floors tightened to `dart_grid_assets ^0.1.2`.

## 0.6.0-rc.11

- Fixed: `SpecifyCapability` is harness-neutral — it routes the spec seat
  through its `AgentSessionAdapter` (a shared `_resolveRun` feeds both `spawn`
  and a new `createSession`), and the ACP bridge now reports its child's real
  exit status and a bounded stderr tail instead of a bare "output closed".
  `landReasonTail`, `kRevalidateReasonTailChars` and `planOutputWithoutPubAdvice`
  move verbatim from the landing circuit to a zero-import
  `src/agent/captured_output.dart` leaf (same names, same behaviour, newly
  exported from the barrel) beside the new `capturedOutputReason` assembler;
  `usageEnvelopeJson`/`writeUsageEnvelope` render FT-2 telemetry a channel
  harness has no wrapper to produce, and `AgentSessionAdapter.launch` gains an
  optional `usageOut` to carry the path across the seam (pow-39tl, #197).
- Changed: the vended `governor` agent overlay states the seat's COST posture —
  ranked under throughput, with the model/effort calls it implies — pinned by
  `governor_posture_test.dart` (pow-8dwh, #198).
- Added: the `/handoff` ritual vends as an operator-audience skill on BOTH
  overlay legs (`station_overlay/claude/skills/handoff/` and
  `station_overlay/agents/skills/handoff/`), with the MCP `config.yaml` entry
  and the `asset_loader` wiring that carries it (pow-pry0, #199).
- Fixed: scaffold restore MERGES directories instead of clobbering them, and a
  failed provision UNWINDS what it created rather than leaving a half-cut
  worktree behind — the shape that wedged fresh worktrees on a scaffold
  collision (pow-gnrm, #200).
- Fixed: the discovery circuit fences lens reports on ROUND. Every lens prompt
  stamps `round` beside `nodePath` and one shared fence reads both on every read
  path, the round-stamp parser is promoted out of `committee.dart` as the shared
  `stampedRound`, `AnchorsCapability`'s blanket `.grid/discovery` wipe becomes a
  round-aware `sweepStaleDiscovery`, and the route join classifies an
  artifact-less lane (decided-with-no-artifact vs. merely LATE) instead of
  dropping it (pow-3yo, #202).

## 0.6.0-rc.10

- Fixed: `AgentSession.onRuntimeEvent` handles `RuntimeEvent.sessionOrphaned`.
  The arm is an OBSERVATION, not a state change: it flares
  `agent.sessionOrphaned` (`sessionId`, `pgid`, `memberCount`) on the injected
  `ExplorationTransport` and returns, so the session stays live and supervised
  and the `Exited`/`Died` after the provider's bounded grace is still the
  terminal. `AgentSession` gains an optional `transport` parameter, wired in
  `AgentCapability.createSession` from the ambient `ServiceBundle.transport`;
  absent means no flares, never a failure. The switch stays exhaustive with no
  default arm, so the next lifecycle variant is caught the same way.
- Fixed: this pack's three `ProcessGroupController` fakes implement the
  `groupMembers(pgid)` member the same upstream change added, so the package
  analyzes and tests clean again.
- Breaking (floor): `grid_runtime` is floored at `^0.2.0-rc.10`. A single source
  cannot be exhaustive over `RuntimeEvent` under both rc.9 (no `SessionOrphaned`)
  and rc.10 (with it), so this pack now requires the candidate that carries the
  variant and ships with that wave.

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
