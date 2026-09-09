## 0.1.0-rc.16

- Changed: the `grid_assets` floor is `^0.6.0-rc.16` — the intake store tests reference `kFilingApprovalRevisionPrefix`, first exported there; the release scrub gate analyzes the package at its declared floors and caught the rc.13 floor.
- Added: the station keeps watching an OUTBOUND issue after it opens one. A seat declares `GitHubIssueWatch(originatingBeadId:, owner:, repository:, issueNumber:)` values on `GitHubReconcilerConfig.issueWatches`, and the reconciler observes each watched issue's resource and its Link-paginated timeline, emitting `NormalizedGitHubEvent.issueCommented` and `NormalizedGitHubEvent.watchedIssueStateChanged` (pow-1rn.8).
- Added: TWO read lanes, split by what a GitHub App can actually reach. A watch naming the seat's own repository rides the existing `GitHubAppClient` and its installation token. Every other repository is FOREIGN — an App cannot be installed on a third party's, for reading or writing — and rides the new GET-only `GitHubReadClient` over the same `GitHubHttpTransport` seam, token-less by default (`Authorization` omitted entirely) with an optional personal token named by `GitHubReconcilerConfig.foreignReadTokenVariable`. Writing to a foreign repository stays out of scope and human-authored.
- Added: the foreign lane has its OWN rate budget — a separate `GitHubPollCoordinator` keyed `foreign/issue-watch`, spaced by `GitHubReconcilerConfig.foreignMinimumSpacing` and clamped up to a 65-second floor whenever no token is configured, which keeps a four-request reserve inside GitHub's 60-per-hour unauthenticated allowance. An installed-repository start neither waits on that budget nor spends it.
- Added: the watch covers every terminal and near-terminal state, not just comments — closed as completed, closed as not planned, reopened, lock changes, transferred, deleted, converted to a discussion, and unreadable (private or 404). Closed, reopened, locked and unreadable watches keep polling; transferred, deleted and converted stop.
- Added: `GitHubReconcilerCursor.issueWatches` — per-coordinate issue identity, comment/timeline marks, state, reason, lock and update time, plus two conditional tags in the EXISTING `etags` map, written and evicted with their record. ADDITIVE at cursor `version: 1`: absence decodes empty, so a live seat upgrades in place; a present-but-wrong shape throws. Watch observations ride the existing pending queue with per-leg acknowledgement.
- Added: `GitHubIssueWatchProjection`, registered as the durable `issue-watch` delivery leg beside `ci-feedback`. It asks the EXISTING `GitHubSelfTrust` about the issue's AUTHOR — the only identity with an answer — and reopens the ORIGINATING bead with a deterministic note and `github.watch.*` metadata. It never approves anything: an external maintainer's reply lands the bead OPEN and unstamped, and the same update removes all three approval-stamp keys. `GitHubReconcilerBindingAssets` shares one trust and one `bd` store between both projections.
- Added: `githubRestHeaders` and `githubFailureCause` — one home each for the REST header contract and for the type-led, 300-character-bounded cause every GitHub failure escalates with; `GitHubAppPrOpener` now renders through the shared formatter unchanged.
- Changed: `GitHubPollCoordinator.schedule` is generic and returns its request's result, so a single scheduled GET can ride a budget. `GitHubReconcilerRuntimeFactory` and `createGitHubReconcilerRuntime` take a nullable `foreignClient`.
- Compatibility: every new configuration value is optional and defaults to the feature-off value. An empty `issueWatches` constructs no foreign transport, reads no environment variable and makes no watch request, so `SpaceDelegate.substations` and `LunarDelegate.substations` need no edit.

## 0.1.0-rc.15

- Added: the station reacts to a red workflow run that is not a station pull request. A seat declares `WorkflowRunIntakeRule`s on `GitHubReconcilerConfig.workflowRuns` (workflow path + events + branches + conclusions + priority + validation plan + approve); the reconciler gains a `/actions/runs?status=completed` leg that emits `NormalizedGitHubEvent.workflowRunConcluded` — with each failed job and its first failed step — for matching runs only, and intake files the failure as an OPEN `bug` carrying the run metadata, its validation plan and one falsifiable acceptance checkbox. An empty rule list is the default and makes the leg spend no request at all (pow-1rn.7).
- Added: `GitHubSelfTrust` admits the seat's OWN `github-workflow` `OWNER/REPOSITORY` identity as `TrustLevel.self` beside the human login; every other repository — a fork's run above all — stays external, and the poll leg drops a foreign `head_repository` before it costs a jobs request.
- Added: a rule with `approve: true` self-approves its SELF-authority filing by CALLING `grid_assets`' `ApproveService` as `github-workflow`. The four-row filing preflight is unchanged and is still the only route to the `grid.approved_*` stamp; a refused preflight leaves the bead OPEN, unstamped, with the failing rows in its notes. See `power_station#own-workflow-failures-are-self-approved`.
- Added: `GitHubReconcilerCursor.workflow_runs_since` — ADDITIVE at cursor `version: 1`, so a cursor already on disk still loads.

## 0.1.0-rc.14

- Fixed: the CI feedback leg no longer runs `bd export --all`, which every proxied-server store refuses; one head-of-line `CheckConcluded` observation wedged a seat's GitHub poll forever and the failure never reached the station log (5 of 8 lunar seats were dark from 2026-09-03). `CiFeedbackProjection` composes one typed `BdCliService.listScope` session read, ignores-with-a-flare zero, many, or id-less matching sessions, gains a `CiFeedbackReporter` seam bound onto the binding-provided value, and the reconciler subscribes to the station transport above the substation git bundle; a source fence keeps `bd export` out of `lib/` (pow-2xmo, #261).
- Fixed: approval receipts bind to the filing basis (#232).

## 0.1.0-rc.13

- Changed: `SubstationSeed` builds through grid_assets' single availability resolution — the seat mounts the selected generated definition Seeds from the resolved `SubstationFactsSnapshot`, and every seat keeps building without facts (the pre-resolution path) instead of failing closed (pow-4peu, #216).
- Floors tightened to `grid_assets ^0.6.0-rc.13`.

## 0.1.0-rc.12

- Fixed: `deliver` REUSES an open pull request for the branch (one GET, PATCH when the title/body changed, `step.delivered` with `reused: true`) instead of racing a create into HTTP 422 and stranding a reworked round `held` (pow-r4eo, #211).
- Floors tightened to `grid_assets ^0.6.0-rc.12`.

## 0.1.0-rc.11

- Fixed: the App transport encodes its body as UTF-8 at the SINK
  (`ioRequest.add(utf8.encode(body))`) and sends
  `Content-Type: application/json; charset=utf-8`. An `IOSink` falls back to
  iso-8859-1 when the content type carries no charset, and latin1 THROWS on the
  first code unit above U+00FF — so a single em dash in a PR body killed
  delivery before the request was ever sent. Encoding at the sink covers every
  caller, the `/pulls` POST and the installation-token exchange alike.
- Fixed: a THROWN PR-open error escalates type-first — generic advice leads and
  the cause trails as `Cause (<runtimeType>): …`, capped at 300 CHARACTERS
  (never a first-line cap: `safeToString` escapes newlines, so a serialized
  request renders as one multi-kilobyte line). Delivery passes the reason
  through `landReasonTail`, which keeps the TAIL, so the type and message now
  survive the cut instead of whatever an SDK error had embedded (pow-b14a,
  #201).
- Changed: the `grid_assets` floor is `^0.6.0-rc.11` — the in-set coherence
  floor for this wave.

## 0.1.0-rc.10

- Adopts the the_grid wave 2 and grid_assets 0.6.0-rc.10: floors `grid_assets ^0.6.0-rc.10`, `grid_cli ^0.5.0-rc.12`, `grid_engine ^0.3.0-rc.12`, `grid_runtime ^0.2.0-rc.10`, `grid_sdk ^0.3.0-rc.10` (power_station#195). No API change.

## 0.1.0-rc.9

- Added: `SubstationSeed`, the COMPOSED per-seat stack, plus its
  `SubstationAppIdentity` delivery identity and the `MountedSubstationSeed`
  offline projection. A downstream station now composes a full GitHub-delivering
  seat from `the_grid` + `power_station` alone: the seed mounts the seat's
  `TypedEnvironmentProvider` rung, the mounted projection, `grid_assets`'
  `GitGridAssets`, the live-arm reconciler binding, `GitHubReconcilerAssets`,
  `GitHubGridAssets` and `MountEligibilityAssets`, and wraps the App client and
  PR opener on a live poll arm. `SubstationAppIdentity.installationId` is an
  `int`, so a malformed installation id fails where the seat is authored rather
  than during mount; the pre-existing `GitHubAppConfig` is untouched.
- Changed: the `grid_assets` floor is `^0.6.0-rc.9` — the seed consumes the
  arming mechanism vended there.

## 0.1.0-rc.8

- Breaking: `GitHubSelfTrust.fromEnvironment` takes an injected
  `EnvironmentReader`; nothing under `lib/` reads `Platform.environment`
  ambiently any more, and the App-key asset tests are hermetic against an
  operator's exported `GRID_GITHUB_APP_KEY_*` variables (pow-vw38, #184).
- Breaking: the reconciler poll reads every `Link` page before advancing, and
  `since` moves only to the last examined update. Issue-shaped pull rows fetch
  the full pull resource; `GitHubReconcilerCursor` caches `pullHeads` beside
  their conditional tags (`intake/pull/<nodeId>`) and evicts the two together.
  `nextGitHubPageUri` is the one home for the `Link` parse (pow-40a4, #182).
- Added: a durable pending/delivered outbox on the cursor document. An
  observation is persisted pending before its sink runs, acknowledged per
  delivery leg (`addObserver`/`removeObserver`, `kSinkDeliveryLeg`), and
  replayed as a step of the next poll after a restart, so an event between a
  fetch and a crash is delivered exactly once. The document stays version 1
  (pow-oe97, #183).
- Changed: GitHub intake bead writes (correlate, create, update) ride
  `BdCliService`, inheriting the shared compatibility and runner behaviour;
  requires `dart_grid_assets` at the rc that ships `create(defer:, externalRef:,
  setMetadata:)` and `listScope` (pow-0nvg, #174).
- Changed: the decision lane's lookup rides the composing station's roster-mode
  `decisions index --surface`, so a decision in a sibling register is reachable
  (#178).
- Breaking: `GitHubIntakeStore.upsertDeferred` is renamed `upsert`, and admitted
  GitHub intake beads are filed OPEN — the `9999-12-31` parking date is dropped
  (pow-5wo). The store writes no approval marker of any kind; absence of the
  approve verb's `grid.approved_*` stamp is the pending state
  (`power_station#github-intake-files-open-and-unstamped`).

## 0.1.0-rc.7

- Breaking: the reconciler tolerates pull rows and flare polling failures
  (pow-2s1, #143) — the polling loop no longer throws on a failed poll.
- Closed intake rows are filtered from reconciliation (#144).
- Model environments route through typed seats (pow-n6n.2, #168).
- Requires `grid_cli ^0.5.0-rc.10` (the rc.8/rc.9 cap is lifted now that the
  hosted chain resolves) and `grid_assets ^0.6.0-rc.7`.

## 0.1.0-rc.6

- `GitHubReconcilerBindingAssets`: provides each live seat a durable `GitHubCursorStore` and SELF-only deferred-intake `GitHubEventSink`, completing the ambient seams required by `GitHubReconcilerAssets` to construct its polling runtime (#139).

## 0.1.0-rc.5

- `GitHubAppClientAssets`: per-seat GitHub App client construction with per-app key resolution — the key path comes from the env var each seat's `privateKeyVar` names (inert when unset, loud on a bad path or mode), replacing the single fixed `GC_GITHUB_APP_KEY_PATH` (#134).
- Committee fakes adopt the `declared-tests-present` lane; floors `grid_assets ^0.6.0-rc.5` (#133).

## 0.1.0-rc.4

- The seat's ServiceBundle derivation uses `ServiceBundle.derive` — field drops are now compile errors (#126).

## 0.1.0-rc.3

- Landing postures as sibling `DeliveryMethod`s: `GitHubDeliveryPolicy` values select `GitHubPrDelivery` (default), `GitHubAutoMergeDelivery` (native auto-merge only when validation rc == 0 and every committee grade is B or better), or `GitHubDirectMergeDelivery` (protected-aware); refused enables fall back loudly with named flares (#121).
- CI-feedback path: `GitHubGridAssets` observes `GitHubReconcilerRuntime`/`CiFeedbackProjection` from the tree; a failed `CheckConcluded` routes exactly one fenced `grid/rework` through the chokepoint, with the ratified attempt budget and cap gate (#122).
- `GitHubReconcilerAssets`: the provider that constructs a live `GitHubReconcilerRuntime` from a `GitHubReconcilerConfig` value and mounts it for the seat; config-absent and dry/offline compositions construct nothing (#123).

## 0.1.0-rc.2

- Requires `grid_assets ^0.6.0-rc.1`. This is the load-bearing change: 0.1.0-rc.1
  could resolve alongside `grid_assets 0.5.0-rc.1`, which still exported
  `GitHubPrDelivery`, so a hosted resolve saw the same symbol from two packages
  and failed to compile ("'GitHubPrDelivery' is imported from both ..."). Local
  path overrides masked it; only a no-override resolve hit it. The tightened
  constraint makes that pairing unrepresentable.

# Changelog

## 0.1.0-rc.1

- Initial release: GitHub App identity and authenticated REST transport.
- Home of the org's GitHub grid-asset implementations: `GitHubAppPrOpener`,
  `GitHubPrDelivery`, the `GitHubGridAssets` seed, and the reconciler/cursor
  surface, relocated out of `grid_assets` by pow-2ua (power_station #109).
  `grid_assets` holds the generic assets and the abstractions; the dependency
  runs implementation -> abstraction, so this package depends on `grid_assets`
  and never the reverse.
- Published as a pre-release because it depends on pre-release siblings
  (`grid_assets ^0.5.0-rc.1`, `grid_engine ^0.3.0-rc.3`, `grid_runtime`).
