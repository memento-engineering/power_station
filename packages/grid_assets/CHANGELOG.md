## Unreleased

- Added: `runRecall` takes an optional `workingDirectory` — the root its durable recall corpus path resolves against, defaulting to the process working directory, so the vended `tool/search_recall.dart` invocation is unchanged. A caller that owns a corpus elsewhere (the pack's own recall suite, which exercises record mode against a disposable copy) now names that root instead of assigning `Directory.current`. That property is process-global while `dart test` runs test files in concurrent isolates of ONE process, so the three suites that moved it raced the eleven that read package-local source by a relative path: a read scheduled inside another file's window threw `PathNotFoundException` or resolved a different tree, nondeterministically and never in isolation. The suite now anchors every package-local path on one cwd-independent package root and assigns the process working directory nowhere.

## 0.6.1

- Fixed: the asset generator formats a generated registry at the CONSUMING PACKAGE's own Dart language version — the inclusive floor of its `environment.sdk` — instead of `--language-version=latest`, so ONE committed `lib/src/assets/grid_asset_pack.dart` is current AND format-clean under every SDK a consumer runs. Under `latest` the rendered bytes were a function of whichever SDK happened to run the generator: an unchanged commit that was current on Dart 3.12 reported `STALE lib/src/assets/grid_asset_pack.dart` on 3.13, and no single committed file could satisfy both. The SDK `dart format` executable stays the formatter, and a pubspec whose `environment.sdk` is missing, malformed, or carries no inclusive floor is now refused LOUD before either output is rendered, compared, or written (pow-10fv; extends pow-5ifa, which put the SDK formatter executable in place; the duplicate tg-txbs was misfiled against the_grid and is closed).

## 0.6.0

- PROMOTED from 0.6.0-rc.26. This is the stable release of the 0.6.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.6.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.6.0-rc.26

- Changed: the refiner and governor agent definitions no longer present PUBLISHING as an action the seat does not take. Both now carry the org ruling: publishing a PRERELEASE is ordinary agent work with no per-release ask, candidates included, while the human owns the PROMOTION — `beta` to `rc`, and `rc` to a non-prerelease version. `dev` to `beta` stays agent work on its machine-checkable condition. Every other gate in those lists is unchanged: merging to main, the first live arm, persistence and credential changes (org-6si, pow-2cnz).
- Added: the `release` skill gains the RUNG LADDER it had no vocabulary for — `dev`/`beta`/`rc` as a per-package property distinct from the semver move, the `--rung` and `--promotion-intent` flags the vended verb takes, `--change rc` as the compatibility spelling of `--change breaking --rung rc`, and the rule that a breaking change enters at `dev` rather than being forced onto a candidate. Its trigger now admits an agent-initiated prerelease rather than only "when the human says release".
- Added: the release skill records a MEASURED limit on the stale-rc demote — `0.6.0-beta.1` sorts BELOW `0.6.0-rc.25` and pub resolves the highest, so a demote on a package with higher candidates publishes a version nothing selects.
- Changed: the station-throughput decision's human-gate enumeration is NARROWED where the agent definitions inherited their wording. It read "anything outward-facing beyond a branch push and PR", which swept in prerelease publishing — neither irreversible nor a human act, since pub excludes prereleases from stable caret ranges. It now names promoting a release instead, carrying an `updated-by` edge to the two org entries. No new decision minted.

## 0.6.0-rc.25

- Added: `{{bootRunner}}` — the RESIDENT-BOOT invocation hole, independent of `{{runner}}` and DEFAULTING to it. A station has two runtimes and the overlay could name only one, so a station whose runner is on PATH could not spell its seat verbs with the global name without also re-spelling its resident boot — which needs the JIT run form, because that is what carries `--enable-vm-service` and therefore hot reload, the `reload` verb and the leonard attach. `station-operations` declares the hole on both targets and uses it at its five boot sites; `seat`, `down` and `status` stay on the verb hole, none of them needing a VM service. Purely additive: a station naming only one runtime renders byte-identically (lunar_station-cu7, #288).
- Fixed: the overlay template substitution existed TWICE — the materializer's `_render` and the loader's `_mustache` — so a default bound in one was refused as an unbound hole by the other. Both now share the public `renderOverlayTemplate`, which is public because the two-runtime contract is worth asserting directly (#288).
- Changed: the build-agent working agreement makes a command, skill or other vended asset DONE only when a real runner or install path REACHES it, and requires the acceptance criteria to prove that reachable surface. A verb could previously ship in an asset, be named by a vended skill, and pass a green plan while no runner composed the command — so the installed skill taught a first step that could not run (pow-yt8n, #283).
- Changed: handoff board state and rulings carry bead TITLES next to ids, so a handoff read on a phone needs no store lookup; both overlay legs updated identically (Nico 2026-09-10, #282).
- Changed: floors `dart_grid_assets` at `^0.2.0-dev.1`, the rung-split release service (#284).

## 0.6.0-rc.24

- Added: the specify capability stamps `spec.author = specify` on the spec it authors through `writeSpecifyAuthoredSpec` (the grid_runtime rc.19 chokepoint), so a rework re-authors specify text while preserving hand-written and governor-restored `design` / `acceptance_criteria` (pow-m8v5, #279; closes the loop opened by the_grid#390).
- Added: `park` and `unpark` filing verbs that reclaim a stalled session slot in one command, composed over the engine `voidRetireMetadata` and liveness seams with a marker-based park predicate (pow-6fqs, #280).
- Added: `seat succession`, the safe handoff-consumption verb (pow-s2sk, #276).
- Fixed: the asset generator normalizes generated Dart with the SDK `dart format` executable instead of the consuming workspace resolved `dart_style`, so `--check` and `dart format --set-exit-if-changed` agree (pow-5ifa, #277).
- Changed: floors `grid_runtime` at `^0.2.0-rc.19` and `grid_sdk` at `^0.3.0-rc.22`.

## 0.6.0-rc.23

- Fixed: a decision-surface record is TRUNCATED only when its entry SET was clipped at `kMaxDecisionEntriesPerSurface` or a named entry failed to resolve; a decision doc over `kMaxDiscoverySnippetChars` keeps its own truncated state on the entry body and no longer fails the whole surface. With rc.22's register-wide resolution, 49 of 125 the_grid and 48 of 87 power_station decision docs are over the bound, so every spec round on those registers held at discovery with no narrow exit (lunar epoch 60: tg-nidl r3) (pow-jidn, #270).

## 0.6.0-rc.22

- Fixed: explicit decision citations resolve REGISTER-WIDE, never per surface. On rc.21 a real accepted decision cited from a surface that does not declare it read as `absent` and failed the surface, so every bead citing a sibling-surface decision held at discovery with no exit (lunar epoch 56: tg-nidl, lenny-dgp); a record indexed elsewhere in the gathered register now resolves and is annotated `namedElsewhere` (pow-9xkj, #263).
- Fixed: adopted worktrees fast-forward their base to the root checkout's default branch on re-adoption, best-effort with a receipt, so a surviving worktree no longer pins the base its first mint cut (pow-1g7, #260).
- Test: `acp_session_adapter_test` compiles the ACP probe fixture once per suite and bounds its waits by wall clock instead of fixed iteration counts; four different tests had failed across a lane, a merge-queue run and a PR check on 2026-09-08 under load (pow-qw6e, #266).

## 0.6.0-rc.21

- Fixed: the discovery decision-surface lookup selects bead-named records FIRST and raises `kMaxDecisionEntriesPerSurface` from 12 to 96, so a bead citing decisions on an 81-entry surface no longer holds at discovery on a clipped index; more than 96 named records is a FAILED surface, not a silent clip. Explicit references are only canonical `register#slug` tokens under a register the gathered index contains, or `ADR-nnnn` ids; a bare legacy `A<n>` token never fails a surface (it only orders), and a canonical-shaped token under an unknown register is prose. `DecisionIndexSource` gains the requesting `Bead` as a third positional argument (pow-mrg8, #257).
- Added: the interactive `refiner` role definition and its seat assets, vended with the baseline pack (pow-7nmo, #254).
- Added: design round classification and verification — the spec round records whether a design is a verify or an infer round and the committee reads it (#251); the verify inference wiring is pinned by test (#253).
- Fixed: `FormatCleanCapability` classifies a dirty-format verdict as `work`, never `infra` (#250).
- Fixed: the agent capability reports a provider capacity refusal as a typed non-result instead of an end turn (#248).
- Test: token-keyed `WorkBead` persistence is asserted (#249).

## 0.6.0-rc.20

- Fixed: `FormatCleanCapability` reports a `DartFormatDirty` verdict as `CapabilityFailureKind.work` and declares a `supervisionPolicy` that spends ONE deterministic attempt on it before parking at a gate whose reason names the would-change files. A formatter that ran and refused is substantive work, not an environment refusal: on lunar epoch 51 the untyped non-result was classed `infra`, counted five silent harness exits, flared `harness.throttled` and hid the offending file under the flare's `underlying` field (pow-7jvc). An undecidable probe — missing or unreadable pinned scope, a formatter that would not launch — stays a non-result on the circuit's own budget.
- Fixed: `MountEligibilityAssets` expires a cached fresh-read failure after `kMountEligibilityReadRetryBackoff` (30 s, doubling per consecutive failure of the same bead, capped at 5 min; a seed value with an injected clock) and re-arms the read on the next evaluation, and flares bd's own `BdTimeoutException` through `kMountEligibilityReadTimeoutFlare`; on lunar epoch 43, 280 of 500 refusals were boot-burst read failures cached until the bead was edited (pow-l73v, #246).
- Fixed: the discovery lens freshness fence carries the session id, so a re-minted session sweeps the PRIOR session's lens reports and waits for its own instead of joining a stale verdict; a missing `SessionHandle` fails fast (pow-l2r5, #245).
- Added: `HarnessProvider` mounts `InheritedSeed<SiteBinding>` above the availability seed and runs `EnvironmentRegistry.validate` as the ONE boot-eager gate, whose site-binding tail now covers only the environments an arming reaches plus custom entries — a bare station with builtin `pi` unbound still boots, an armed environment with a missing endpoint refuses with `SiteBindingError` (pow-2eg, #244).
- Added: the committee selector's Ok payload and the shadow route's Advance payload persist the selection run and receipt (17 and 34 reserved keys; the six pre-existing keys byte-identical) (pow-1nl.1.3, #242).
- Fixed: decision lookups render as `cd '<grid home>' && <verb>` so critic lanes and the architect can run the roster-mode decisions index from a worktree (pow-96ei, #243).
- Floors `beads_dart` to `^0.2.0-rc.10`, `grid_engine` to `^0.3.0-rc.20`, `grid_runtime` to `^0.2.0-rc.13` and `grid_sdk` to `^0.3.0-rc.16`.
- Tests: the PDR §7 (e) spawn-in-flight probe admits its bead through `StationAdmissionAuthority` before mounting the `SessionScope` directly, and answers grid_engine rc.20's mount-attempt read and record before the gated session create — the exported `GatedCreateBdRunner` still answers `bd list` with an object, which rc.20's mint prelude cannot parse.

## 0.6.0-rc.19

- Fixed: the mount gate no longer compares a bound approval stamp's revision against a fresh filing evaluation. rc.18 (pow-9rah) bound `grid.approved_rev` over the bead's design, acceptance criteria and notes and refused a mismatch as `approval: stale`; the station's own specify step writes design and acceptance on every first round and rework appends notes, so every bead approved on rc.18 un-approved itself at its own spec write and the engine's content gate disposed the running round (lunar epoch 43, 2026-09-05: four of four fresh rounds, only legacy raw-sha stamps survived). `mountEligibilityFindings` still requires a COMPLETE stamp of either form and still accepts `evaluatedApprovalRevision`, which is recorded but not enforced; the approve verb keeps writing the bound revision for the audit trail. Re-instating a comparison over a basis the station does not itself rewrite is pow-lr8n (governor patch, precedent pow-gcx9).

## 0.6.0-rc.18

- Fixed: the explore-decision lane renders a decision entry's body ONCE however many roster-qualified surfaces cite it — the first surface carries the body, every later surface cites the entry by identity as "also governs this surface". The roster-mode decisions index answers every surface of a repo with the same entries, so a bead touching 12 power_station surfaces carried 12 copies of each (550 KB for 12 distinct bodies on pow-ed1c) and the cheap lens died `prompt_too_long`, holding the round on a failed lane. Per-surface lookup records and the evidence-id profile (rc.17, pow-bvui) are unchanged (pow-alwh, #239).

## 0.6.0-rc.17

- Fixed: `DiscoveryAnchors.fromJson` no longer refuses the gather the deterministic gather itself writes — the colliding-profile guard counted a decision ENTRY once per roster-qualified surface while `evidenceIds` collapsed the same body cited under several lookups, so on rc.16 (the first release whose decision lookups resolve) every discovery round with decision entries decoded to an empty gather and held at `discovery-route` on `gather:round -1 / gather:workBeadId ``. Decision entry ids are counted distinct; a duplicated lookup id or a body id reused by a foreign record still refuses (pow-bvui, #237).
- Fixed: `MountEligibilityAssets` bounds its fresh read — `kMountEligibilityReadDeadline` (60s) wraps the `bd.query` in `_readFresh`, a timeout is routed through the existing failure cache as a refused decision naming the bead, store root and deadline, and is flared by name (`kMountEligibilityReadTimeoutFlare`) so the operator can see WHICH store's read hangs; genesis and decisions beads sat at `fresh mount-eligibility read pending` forever across nine lunar boots (pow-7i3k, #236).
- Fixed: the work bead's OWN citation fields (description, design, acceptance, notes) are carried WHOLE into the gather — `boundDiscoveryEvidence` gains `truncateSnippet` (default true; only `BeadFieldEvidence` opts out), so a description over `kMaxDiscoverySnippetChars` no longer holds its own discovery round as TRUNCATED; foreign evidence keeps the bound (pow-xfm0, #235).

## 0.6.0-rc.16

- Fixed: the shelled decision lookup accepts the decisions index envelope `spec: 2` beside `spec: 1` (`_acceptedDecisionIndexSpecs`); against decisions_grid_assets 0.2.1 every explore-decision surface FAILED on rc.13–rc.15 and the round held at `discovery-route` (pow-rokz, #231).
- Fixed: approval receipts are complete and bound to the filing basis — `ApprovalStamp.tryParse` requires a nonblank `grid.approved_by`, a UTC `grid.approved_at`, and a recognized `grid.approved_rev` (a legacy raw git sha, or the `filing:v1:sha256:` digest the approve verb now writes over the bead's filing contract); a lone `grid.approved_at` no longer mounts, and mount eligibility re-checks the fresh bead against the stamped revision (pow-9rah, #232).

## 0.6.0-rc.15

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
