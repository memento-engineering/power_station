---
status: accepted
date: 2026-09-21
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: github-poll-coordination-is-station-owned
  surfaces:
    - "packages/github_grid_assets/lib/src/assets/github_reconciler_assets.dart"
    - "packages/github_grid_assets/lib/src/github/github_reconciler_runtime.dart"
    - "packages/github_grid_assets/test/github_reconciler_assets_test.dart"
    - "packages/github_grid_assets/test/github/github_reconciler_runtime_test.dart"
    - "packages/github_grid_assets/test/assets/substation_seed_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-eup0
  legacy-id: null
---

# The GitHub poll quota is STATION-owned: one coordinator, mounted above the repository fan-out, partitioned by installation id

## Context and Problem Statement

`GitHubPollCoordinator` has always been written as a shared budget. Its maps
are keyed by an opaque quota identity, its doc comment says so, and its whole
reason for existing is that two repositories on one GitHub App installation
spend ONE 5000-per-hour allowance between them.

The production factory did not give it one. `createGitHubReconcilerRuntime`
constructed `GitHubPollCoordinator(minimumSpacing: config.minimumSpacing)`
inline, per runtime — so every repository got its own coordinator, every
coordinator held a map with exactly one live key, and the serialization and
start-spacing those maps implement could never apply across the repositories
that actually share the quota. Two production-created runtimes for one
installation admitted both requests at once; the station spent its allowance at
N times the rate the design says it does, and the only thing that reported that
was GitHub's 403.

The defect was invisible to the suite because every coordinator test injected a
coordinator it had built and shared itself. Those tests prove the coordinator
serializes. They prove nothing about who hands it to whom, which is where the
budget was lost.

Two shapes were then genuinely open. Both are correct about the maps; they
differ about who OWNS the instance and where it is mounted.

## Considered Options

* **A station-level coordinator keyed by installation.** One
  `GitHubPollCoordinator` mounted once above the station's repository fan-out;
  the existing installation-id key partitions serialization and spacing inside
  it.
* **An installation-scoped provider subtree.** A rung per installation, so each
  installation's repositories mount under their own coordinator and the key
  becomes redundant.
* **A process-global singleton.** Rejected outright, and not a real option: it
  is untestable in a suite that mounts many stations in one process, it
  survives station disposal, and it puts the budget somewhere no tree owns.

The installation-scoped subtree was rejected: it makes the composing station
author a rung per installation and re-author it whenever a seat's installation
changes, it gives the tree two facts to keep in step (the subtree's identity
and the config's `installationId`) where there is now one, and it buys nothing
— the coordinator's maps already partition by key, so the second partition is
the same partition twice.

## Decision Outcome

**Nico selected the station-level coordinator keyed by installation.** One
coordinator is owned at station scope and injected into every repository
reconciler runtime; the installation id partitions serialization and
start-spacing inside it.

1. **`GitHubPollCoordinatorAssets` is the ownership rung.** It wraps its child
   in `Provider<GitHubPollCoordinator>(create: ...)`, so the TREE creates and
   owns the instance, exactly once per station mount. Its
   `GitHubPollCoordinatorFactory` seam exists so a test can hand it a
   controllable clock and delay; it must construct a FRESH instance per call,
   because a pre-built one passed through `create:` would falsely assign
   ownership to the tree.
2. **A composing station mounts it ONCE, above its repository fan-out.** Not
   inside `SubstationSeed`: that seed is per repository, and a coordinator
   mounted there would reproduce the defect this entry retires.
3. **The runtime factory takes the coordinator; it never builds one.**
   `GitHubReconcilerRuntimeFactory` and `createGitHubReconcilerRuntime` both
   take a required `coordinator`, and `GitHubReconcilerAssets` resolves it with
   the SUBSCRIBING build verb (`context.watch`, ADR-0008 D3) and includes its
   identity in the runtime's replacement inputs — a replaced coordinator is a
   replaced runtime, detached before the successor attaches.
4. **A live repository with no station coordinator REFUSES, loudly.** The seat
   detaches whatever it had, then throws a `StateError` naming
   `GitHubPollCoordinatorAssets`. A quiet per-seat fallback is the defect: it
   looks like it works and spends the quota N times over.
5. **No process-global value and no second scheduler.** The coordinator spaces
   STARTS — a transport rate — and decides nothing about when reconciliation
   happens. That stays the station tick's, through
   `GitHubReconciliationQuery`.
6. **The foreign lane keeps its OWN coordinator.** The token-less/personal-token
   issue-watch lane is constructed per seat under `kForeignIssueWatchRateKey`,
   against a 60-per-hour allowance that an installation poll must never be able
   to spend. No installation credential and no installation spacing state
   crosses that boundary, in either direction.
7. **Conflicting spacing requests resolve by ADJACENT-PAIR MAXIMUM.** Sharing
   one coordinator means two repositories can now ask one key for different
   minimum spacings. `schedule` takes the spacing as a per-cycle request,
   remembers what the last start under a key asked for, and waits
   `max(previousRequest, nextRequest)` between them — in either ordering. After
   the stricter repository leaves the pair, only the one boundary from its last
   start stays strict; later lower/lower pairs use the lower interval.

**Why the maximum and not the minimum, the constructor value, or a refusal.**
The minimum lets the loosest seat spend the strictest seat's reserve, which is
the defect in a smaller costume. Pinning the constructor value makes
`GitHubReconcilerConfig.minimumSpacing` — a per-repository VALUE the composing
station already authors — silently inert. Refusing a mismatch would make a
station unable to run a hot repository beside a conservative one under one
installation, which is an ordinary thing to want. The maximum honours the
strictest request that is actually adjacent to a start, costs at most one
boundary of over-spacing when the strict seat goes away, and needs no new
configuration to express.
