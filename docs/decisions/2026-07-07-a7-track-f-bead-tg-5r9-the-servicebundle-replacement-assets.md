---
status: accepted
date: 2026-07-07
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a7-track-f-bead-tg-5r9-the-servicebundle-replacement-assets
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A7"
---
## A7 (2026-07-07) — Track F (bead `tg-5r9`): the ServiceBundle-replacement assets PROVIDE the existing concrete `ServiceBundle` per substation; `sourceControlFor(bead)` is realized as the positional `sourceControlOf(TreeContext)`; `HarnessProvider`/`CircuitProvider` naming; git machinery injected as asset params

**Decision:** Track F ("assets replace ServiceBundle") is built in `packages/grid_assets/lib/src/assets/composition_assets.dart` as four `SingleChildStatelessSeed` composition assets + one resolver, WITHOUT deleting `ServiceBundle`/`serviceBundleMapFor` (that deletion is the fossil track, Track H, and lives in grid_engine — off this worktree's scope). Specific autonomous choices, none named verbatim by the ratified v3 doc:
(1) **The assets provide the EXISTING concrete `ServiceBundle`** into the tree (`GitGridAssets` → `InheritedSeed<ServiceBundle>(ServiceBundle(sourceControl: GitSourceControl(...)))`), one per substation, rather than introducing a new power_station-local carrier type. The opinion-free engine (grid_engine `session_scope.dart`/`allocation.dart`/`capability_host.dart` + the power_station capabilities) resolves source control via `getInheritedSeedOfExactType<ServiceBundle>()` TODAY; providing that same type is what lets the runner-built `Map<String,ServiceBundle>` + `sourceControlsByRoot` map be dropped with zero engine change. The provided bundle carries an EMPTY `sourceControlsByRoot`, so `ServiceBundle.sourceControlFor(anyRootName)` collapses to the substation's ONE source control — the v3 "no string-keyed bundle map," expressed without touching the still-present engine type.
(2) **`sourceControlFor(bead)` is realized as `sourceControlOf(TreeContext)`** — a genesis-idiomatic positional resolver (`SubstationScope.of`/`GridRoot.of` family). The bead's identity enters through its TREE POSITION (a work bead is mounted under its owning substation's scope, so the nearest ambient `ServiceBundle` IS its substation's), never a bead-keyed/root-name lookup — a bead-argument function would re-import the very selector shape v3 kills.
(3) **`GitHubGridAssets` enriches the git asset via a new `GitSourceControl.withPrOpener` seam** (it reads the ambient `ServiceBundle` GitGridAssets provided from ABOVE in the `Nest` and re-provides the source control with the PR opener added → `canLand` true), rather than the git asset reading an ambient PrOpener. Forced by `Nest` fold order: `[GitGridAssets, GitHubGridAssets]` makes GitGridAssets the ANCESTOR, so the land-enrichment must happen at the inner GitHub node.
(4) **`HarnessProvider` and `CircuitProvider`** are named to match the ratified v3 §2 sketch (`HarnessProvider(/* parameters */)` at station scope) and §3/Q8 ("Circuit provider / circuit scope"); the source-control assets keep the sketch's exact `GitGridAssets`/`GitHubGridAssets`.
(5) **The git-execution machinery (`StationGitService` provisioner / `GitOps` / `PrOpener`) is injected as asset constructor params** (the runner passes the station's shared instances; both-null is the offline/dry-run build → provision + land no-op), rather than a separate station-scoped git-machinery asset. The task's enumerated station-scoped asset is HARNESS provision; params match the sketch's `GitGridAssets(/* parameters */)`, and `RootCheckout` is built from the ambient `SubstationScope`'s ONE root + name (a live `registerRootCheckout` probes `defaultBranch`; an offline asset authors it, defaulting `main`).
(6) **`CircuitProvider` provides `InheritedSeed<CircuitResolver>`** to ESTABLISH the Q8 shape; the kernel's `SessionResolver` seam is a station-level kernel PARAMETER today, so binding a mounted resolver into it is deferred to Track G (the runners) — noted in the type's doc, not wired here. gc's `Order` (trigger→formula, the when-axis) is compat vocabulary only; the grid when-axis stays future + clockless (event-driven, no tick).
(7) **`grid_assets` gains a `grid_sdk` dependency** (`pubspec.yaml` `grid_sdk: any` + the machine-local override) — the substation-scoped assets read `SubstationScope.of(context)` from grid_sdk's Track-B composition layer.

**Why:** the engine reads/deletes are grid_engine's (a sibling repo, the fossil track — out of this worktree's scope, matching the bead's "the ServiceBundle/serviceBundleMapFor DELETION itself belongs to the fossil track; this track builds the replacement"). Building the replacement so it FEEDS the unchanged engine (provide `ServiceBundle`, empty the root map) is what makes the later engine-side simplification a clean swap rather than a flag day. The naming/param/seam choices reuse established power_station-local idioms (the `is`-detected `withPrOpener` mirrors A5's `TreeVerifiableSourceControl`; injected offline seams mirror every capability here) and the ratified v3 vocabulary, minimising net-new invented surface. Kernel-side consumption of the mounted circuit resolver is genuinely a Track-G (runner) concern and was flagged rather than half-wired.
**Affects (if promoted):** power_station code (built this bead): `packages/grid_assets/lib/src/assets/composition_assets.dart` (the four assets + `sourceControlOf`), `packages/grid_assets/lib/src/code/code_capabilities.dart` (`GitSourceControl.withPrOpener`), `packages/grid_assets/lib/grid_assets.dart` (export + library doc), `packages/grid_assets/pubspec.yaml` (`grid_sdk` dep), `packages/grid_assets/test/track_f_composition_assets_test.dart`. the_grid: Track G's runner should mount these assets under grid_sdk's `Substation`/`Station` in place of `composeStation`'s `services:`/`wrapRoot:` seams, and bind `CircuitProvider`'s mounted resolver into the kernel `SessionResolver`; Track H then deletes `ServiceBundle`/`serviceBundleMapFor`/`sourceControlsByRoot` and re-sources the engine's source-control resolution off whatever these assets provide.
**Status:** pending.

