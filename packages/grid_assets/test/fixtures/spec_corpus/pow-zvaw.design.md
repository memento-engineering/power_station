## Implementation Plan

### Step 1 — Adopt the wave in every pubspec that names it

Three pack pubspecs name the the_grid train. Rewrite the floors in place
(`dart_grid_assets` and `zero_conf_grid_assets` name none of these packages —
leave both alone; `grid_trajectory` is named by no pack pubspec here and enters
the resolve transitively through `grid_sdk`, so there is nothing to pin for it).

In `packages/grid_assets/pubspec.yaml`:

```yaml
  beads_dart: ^0.2.0-rc.7
  grid_engine: ^0.3.0-rc.11
  grid_runtime: ^0.2.0-rc.9
  grid_sdk: ^0.3.0-rc.9
```

In `packages/federated_grid_assets/pubspec.yaml`:

```yaml
  grid_engine: ^0.3.0-rc.11
```

In `packages/github_grid_assets/pubspec.yaml` — same four floors, plus
`grid_cli`. The nine-line comment above `grid_cli` describes a pub.dev breakage
(grid_cli 0.5.0-rc.9 importing a `DevModeHost` that grid_exploration 0.3.0-rc.3
never exported) that the rc.10/rc.11 republish cleared; replace the whole
comment block with the two lines below so the pubspec stops asserting a stale
fact:

```yaml
  beads_dart: ^0.2.0-rc.7
  # Floored with the rest of the wave (the_grid #284/#286): grid_cli 0.5.0-rc.11
  # is the republished train the engine/sdk rc.11/rc.9 pair belongs to.
  grid_cli: ^0.5.0-rc.11
  grid_diagnostics_contract: ^0.2.0
  grid_engine: ^0.3.0-rc.11
  grid_runtime: ^0.2.0-rc.9
  grid_sdk: ^0.3.0-rc.9
```

Then resolve from the workspace root:

```sh
dart pub upgrade
```

`pubspec.lock` is untracked here (`git ls-files | grep pubspec.lock` is empty —
the root pubspec documents the machine-local `pubspec_overrides.yaml` linkage),
so there is no lock to commit.

Test: `dart pub upgrade && grep -n 'grid_engine\|grid_sdk\|grid_runtime\|beads_dart\|grid_cli' packages/*/pubspec.yaml` → every constraint reads the wave version above, and `dart pub deps --style=compact | grep -E 'grid_engine|grid_sdk'` shows `grid_engine 0.3.0-rc.11` / `grid_sdk 0.3.0-rc.9`.
Commit: `build(deps): floor the the_grid rc wave (engine rc.11 / sdk rc.9)`

### Step 2 — Add the `MountedStation` test-support root to grid_assets

The retired `StationKernel` did exactly two things the suites depend on: it
mounted an ambient stack over `Station(substations)` under a `TreeOwner` with a
coalesced-microtask flush loop, and it drove `StationDriver.afterFlush()` once
per completed flush. `runGrid` now owns the first (and carries the tg-60n
fail-closed guard the kernel held but never ran in production) and its
`onFlushed` rail drives the second. `MountedStation` composes exactly those two
and mounts the SAME five providers the kernel mounted, so a migrated suite
drives the same tree.

Create `packages/grid_assets/test/support/mounted_station.dart`:

```dart
// The acceptance harnesses' station root, after the_grid #284 deleted
// `StationKernel` (`the_grid#run-grid-is-the-single-flush-coordinator`,
// accepted 2026-09-02): `runGrid` is the ONE flush coordinator and
// `StationDriver` is the off-tree work-axis half (the bridge lifecycle, the
// D-5/F1 cooldown Timer, the unclaimed-frontier scan). This composes the two
// over the SAME ambient stack the retired kernel mounted — same providers,
// same order, same `Station(substations)` child — so a migrated suite drives
// an identical tree and no assertion has to move.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show GridConfiguration, GridDelegate, GridHandle, Provider, runGrid;

/// The station tree under test: the work-axis ambient stack, as a
/// `GridDelegate`'s master build.
///
/// Impls = DI (the_grid ADR-0008 D-H): every value is built OFF-tree by
/// [MountedStation] and enters the tree only as a provided value — this
/// delegate constructs no service in `build`.
class _StationRootDelegate extends GridDelegate {
  _StationRootDelegate({
    required this.notifier,
    required this.stationServices,
    required this.resolver,
    required this.leaseVendor,
    required this.registry,
    required this.substations,
  }) : super(const GridConfiguration());

  /// The work-axis notifier the mounted `WorkList` observes.
  final JoinedSnapshotNotifier notifier;

  /// The machine's ambient services (transport + the bd write chokepoint + the
  /// owned state rig).
  final StationServices stationServices;

  /// The bead-to-work-Seed seam.
  final SessionResolver resolver;

  /// The molecule model's process-lease seam — the SAME default the retired
  /// kernel installed at its root (tg-h4u), built off-tree.
  final ProcessLeaseVendor leaseVendor;

  /// The reentrant circuit registry; null when the resolver roots a
  /// non-reentrant subtree (a fake returning a plain leaf needs none).
  final CapabilityRegistry? registry;

  /// The station's substation scopes.
  final List<SubstationScope> substations;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    final registry = this.registry;
    return Nest(
      children: [
        Provider<JoinedSnapshotNotifier>.value(notifier),
        Provider<StationServices>.value(stationServices),
        Provider<SessionResolver>.value(resolver),
        Provider<ProcessLeaseVendor>.value(leaseVendor),
        if (registry != null) Provider<CapabilityRegistry>.value(registry),
      ],
      child: Station(substations),
    );
  }
}

/// A station mounted for a test — the `runGrid` tree half wired to the
/// [StationDriver] off-tree half exactly as production wires them
/// (`runGrid(onFlushed: driver.afterFlush)`).
///
/// Two-phase on purpose, mirroring the shape the suites already call: the
/// constructor ASSEMBLES (nothing mounts, so a test may assert the pre-mount
/// state), [start] starts the driver and mounts the tree, [dispose] tears the
/// tree down and THEN the driver — the bridge outlives the tree, never the
/// reverse.
class MountedStation {
  /// Assembles the station over [bridge]. Nothing mounts until [start].
  MountedStation({
    required this.bridge,
    required StationServices stationServices,
    required SessionResolver resolver,
    required List<SubstationScope> substations,
    CapabilityRegistry? registry,
  }) : _driver = StationDriver(bridge: bridge, registry: registry),
       _delegate = _StationRootDelegate(
         notifier: bridge.notifier,
         stationServices: stationServices,
         resolver: resolver,
         leaseVendor: defaultProcessLeaseVendor(stationServices),
         registry: registry,
         substations: substations,
       );

  /// The join bridge feeding the work axis — the driver owns its lifecycle.
  final StationJoinBridge bridge;

  final StationDriver _driver;
  final _StationRootDelegate _delegate;
  GridHandle? _handle;
  bool _disposed = false;

  /// Starts the driver (seeding the notifier's baseline BEFORE `WorkList`
  /// subscribes, as the kernel did), then mounts the tree through [runGrid] —
  /// the ONE flush coordinator — with `onFlushed` driving the driver's
  /// post-flush re-scans. Idempotent.
  Future<void> start() async {
    if (_handle != null || _disposed) return;
    _driver.start();
    _handle = await runGrid(_delegate, onFlushed: _driver.afterFlush);
  }

  /// Tears the tree down (unmounting every effect, so every spawn is killed)
  /// and then the driver (cancelling the backoff Timer, disposing the bridge).
  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _handle?.teardown();
    _handle = null;
    _driver.dispose();
  }
}
```

Re-export it from the pack's shared support library so no migrated file gains
an import. In `packages/grid_assets/test/support/asset_fakes.dart`, directly
below the existing `export 'package:grid_engine/testing.dart';` line, add:

```dart
export 'mounted_station.dart';
```

Test: `cd packages/grid_assets && dart analyze test/support/mounted_station.dart` → expect `No issues found!`.
Commit: `test(grid_assets): add the MountedStation runGrid+StationDriver root`

### Step 3 — Copy the same root into github_grid_assets

`github_grid_assets` cannot import `grid_assets`' test directory (a Dart
package exposes only `lib/`), and the two packs already carry parallel copies
of `test/support/asset_fakes.dart` for exactly this reason. Follow that
precedent rather than promoting test scaffolding into a published `lib/`:

```sh
cp packages/grid_assets/test/support/mounted_station.dart \
   packages/github_grid_assets/test/support/mounted_station.dart
```

Add the identical re-export line below `export 'package:grid_engine/testing.dart';`
in `packages/github_grid_assets/test/support/asset_fakes.dart`:

```dart
export 'mounted_station.dart';
```

Test: `cd packages/github_grid_assets && dart analyze test/support/mounted_station.dart` → expect `No issues found!`.
Commit: `test(github_grid_assets): mirror the MountedStation station root`

### Step 4 — Swap every harness onto `MountedStation`

The replacement takes the SAME five named arguments the kernel took
(`bridge`, `stationServices`, `resolver`, `registry`, `substations`), so the
migration is a rename plus one `await`. No suite passes `treeProjector`,
`wrapRoot`, `onFlushError`, `processLeaseVendor`, `rootCircuitFor`,
`onUnclaimedFrontier`, `clock` or `scheduleTimer` (verified by grep over both
test trees), so nothing else has to move. Run from the worktree root, BEFORE
the prose sweep — while `StationKernel(` and a line-leading `StationKernel `
still identify code unambiguously:

```sh
FILES=$(grep -rl 'StationKernel\|_buildKernel' packages/grid_assets/test packages/github_grid_assets/test)
perl -0pi -e '
  s/StationKernel\(/MountedStation(/g;
  s/^StationKernel /MountedStation /gm;
  s/\b_buildKernel\b/_buildStation/g;
  s/\b_kernel\b/_station/g;
  s/\bfinal kernel = /final station = /g;
  s/\bkernel\.dispose\b/station.dispose/g;
  s/\bkernel\.start\(\);/await station.start();/g;
' $FILES
```

The first two rules are exact code positions — a constructor call and the
line-leading return type of `_buildKernel` / `_kernel` — so neither can touch a
comment. Every `kernel.start();` site sits in an `async` body (each is inside a
`test('…', () async {` or an `async` helper such as
`discovery_acceptance_test.dart`'s `Future<Fakes> driveToRoute(…) async`), so
the added `await` compiles everywhere. `addTearDown(station.dispose)` keeps its
existing registration position, so the LIFO teardown order
(`state.close` → `work.close` → `f.provider.close` → the station) is unchanged.

Two behaviours change on purpose, and neither weakens a suite:

1. `runGrid` fires `onFlushed` after the MOUNT flush too, so the driver's
   cooldown + unclaimed-frontier re-scan runs one extra time at start. Both
   scans are inert here — every harness leaves `rootCircuitFor` and
   `onUnclaimedFrontier` null, and `StationDriver._scanUnclaimedFrontier` is
   all-or-nothing on those. This is what production does now.
2. `start()` is awaited rather than synchronous, because `runGrid` awaits
   `delegate.boot` (a no-op on the base `GridDelegate`). Every call site
   already awaits a settle immediately afterwards.

Do NOT touch the per-file private `_settle` wrappers or the shared `settle`
helper: `power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`
ruled that hoisting them "is an unrelated refactor that would widen a
station-health diff", and `test/settle_test.dart` pins the primitive's contract.

Test: `cd packages/grid_assets && dart test test/acceptance test/substation_service_bundle_test.dart` → expect `All tests passed!`.
Commit: `test(grid_assets)!: mount the acceptance harnesses through runGrid`

### Step 5 — Rewrite the PROSE that still names the retired class

Step 4 left the token only in comments, doc comments and two `SKILL.md`
copies. Each substitution below is an exact string, so the pass is idempotent
and order-independent:

```sh
FILES=$(grep -rl StationKernel packages)
perl -0pi -e "
  s/\`StationKernel\`'s constructor param/\`StationDriver\`'s constructor param/g;
  s/\`StationKernel\`'s \`onUnclaimedFrontier\` hook/\`StationDriver\`'s \`onUnclaimedFrontier\` hook/g;
  s/production roots — \`StationKernel\.start\`, \`runGrid\` —\n   always mount the scope/the production root — \`runGrid\` —\n   always mounts the scope/g;
  s/\(StationKernel\.start\)/(runGrid)/g;
  s/mounted automatically by \`StationKernel\`;/mounted automatically by the \`runGrid\` station root;/g;
  s/Mounted automatically by StationKernel \(tg-h4u\);/Mounted automatically by the runGrid station root (tg-h4u);/g;
  s/Mounted automatically by StationKernel;/Mounted automatically by the runGrid station root;/g;
  s/bypasses the kernel entirely/bypasses that station root entirely/g;
  s/the SAME default the kernel installs/the SAME default the station root installs/g;
  s/the ALREADY-AUTHORED StationKernel/the ALREADY-AUTHORED \`runGrid\` + \`StationDriver\` root/g;
  s/'StationKernel — the reactive loop/'runGrid + StationDriver — the reactive loop/g;
  s/\bStationKernel\b/runGrid station root/g;
" $FILES
```

The last rule is the catch-all for the eight remaining header comments ("the
REAL StationKernel + CircuitResolver", "the FULL StationKernel over fake
SnapshotSources", "the real StationKernel + the real `code` circuit", and the
line-wrapped "through the REAL StationKernel" / "+ CodeCircuitResolver" pair);
it is safe only because Step 4 already removed every code occurrence. The two
`extension/station_overlay/{claude,agents}/skills/asset-author/SKILL.md` copies
are byte-identical today and stay so — both are in `$FILES` and take the same
edit.

Test: `grep -rn StationKernel packages; echo "exit=$?"` → prints no match lines and `exit=1`; `cd packages/grid_assets && dart test test/acceptance` → expect `All tests passed!` (the prose pass changes no behaviour).
Commit: `docs(assets): name runGrid/StationDriver where the kernel was named`

### Step 6 — Re-home the kernel's own suite by name

Steps 4 and 5 already migrated the file's body. Rename it so the filename stops
naming a deleted class, keeping its single `test(` case intact:

```sh
git mv packages/grid_assets/test/station_kernel_test.dart \
       packages/grid_assets/test/run_grid_reactive_loop_test.dart
```

The file's opening comment (rewritten by Step 5 to "Track E/F — the REACTIVE
LOOP through the ALREADY-AUTHORED `runGrid` + `StationDriver` root.") already
reads correctly; the one line that still describes the retired flush loop is
its fourth paragraph. Replace that sentence in
`packages/grid_assets/test/run_grid_reactive_loop_test.dart`:

```dart
// Unlike Track A's reconcile test (which calls owner.flush() directly), THIS test
// goes through `runGrid`'s real coalesced-microtask flush loop, so every step
// settles the event queue to let the scheduled flush run.
```

The historical citations of `station_kernel_test.dart` in `docs/adr/ADR-0000`
and under `docs/decisions/` are RECORDS of what was true when written — leave
every one of them untouched.

Test: `cd packages/grid_assets && dart test test/run_grid_reactive_loop_test.dart` → expect `All tests passed!` with `+1` case.
Commit: `test(grid_assets): re-home the kernel loop suite onto runGrid`

### Step 7 — Run the github pack and the full analyze

```sh
dart analyze
cd packages/github_grid_assets && dart test test/acceptance
```

Test: `dart analyze` → expect `No issues found!`; `cd packages/github_grid_assets && dart test test/acceptance` → expect `All tests passed!`.
Commit: `test(github_grid_assets): mount the acceptance harnesses through runGrid`

### Step 8 — Record the decision

The call this bead makes autonomously — that the acceptance harnesses' station
root is `runGrid` over a pack-local `GridDelegate` plus `StationDriver`, rather
than a hand-rolled `TreeOwner` flush loop (a second flush loop, which the
upstream decision forbids) or a rewrite onto the SDK's
`StationWork`/`Substations` composition (a behaviour change in a suite whose
whole value is pinning behaviour) — is recorded, not appended to ADR-0000.

Invoke the vended `decide` skill and let it own the entry shape; supply it
these facts:

- slug: `acceptance-harnesses-mount-through-run-grid` (43 chars; verified
  collision-free against `docs/decisions/` on 2026-09-03)
- `decision-makers: ["agent"]`, `consulted: []`, `informed: []`
- `register.bead: pow-zvaw`
- `register.surfaces`: `packages/grid_assets/test/support/mounted_station.dart`,
  `packages/github_grid_assets/test/support/mounted_station.dart`,
  `packages/grid_assets/test/acceptance/**`,
  `packages/github_grid_assets/test/acceptance/**`
- `register.updates`: none (this entry implements
  `the_grid#run-grid-is-the-single-flush-coordinator` downstream; it amends
  nothing here)
- Context: the_grid #284 deleted `StationKernel`; power_station's carets
  admitted the rc and 24 analyzer errors turned CI red on every PR.
- Decision: `MountedStation` composes `runGrid` (tree + flush, carrying the
  tg-60n guard) with `StationDriver` (bridge lifecycle, cooldown Timer,
  unclaimed scan) over the kernel's exact five-provider ambient stack; it is
  duplicated per pack because a Dart package exposes only `lib/`, matching the
  existing `test/support/asset_fakes.dart` split.

Test: `ls docs/decisions | grep acceptance-harnesses-mount-through-run-grid` → prints one entry; `head -3 docs/decisions/*acceptance-harnesses-mount-through-run-grid.md` → shows `status: accepted`.
Commit: `docs(decisions): record the runGrid acceptance-harness root`

### Step 9 — Prove the whole change from a cold resolve

```sh
dart pub upgrade grid_engine grid_sdk grid_runtime beads_dart grid_cli grid_trajectory
dart analyze
grep -rn StationKernel packages
cd packages/grid_assets && dart test test/acceptance test/run_grid_reactive_loop_test.dart test/substation_service_bundle_test.dart
cd ../github_grid_assets && dart test test/acceptance
```

Test: as written above → `dart analyze` prints `No issues found!`, the grep prints nothing, both `dart test` runs print `All tests passed!`.
Commit: (no code change — this step only runs the gate)

## Touches

Created:
- `packages/grid_assets/test/support/mounted_station.dart` — created; `test/support/mounted_station.dart:MountedStation` (test-support only; nothing is added to any `lib/`, so no published symbol changes)
- `packages/github_grid_assets/test/support/mounted_station.dart` — created; a verbatim copy of the same class
- `docs/decisions/2026-09-03-acceptance-harnesses-mount-through-run-grid.md` — created by the `decide` skill

Renamed:
- `packages/grid_assets/test/station_kernel_test.dart` → `packages/grid_assets/test/run_grid_reactive_loop_test.dart` — renamed and migrated; its one `test(` case is unchanged

Modified — pubspecs:
- `packages/grid_assets/pubspec.yaml`, `packages/github_grid_assets/pubspec.yaml`, `packages/federated_grid_assets/pubspec.yaml`

Modified — test support:
- `packages/grid_assets/test/support/asset_fakes.dart`, `packages/github_grid_assets/test/support/asset_fakes.dart` (one `export` line each)

Modified — harnesses (`StationKernel` → `MountedStation`, `kernel` → `station`, `await station.start()`):
- `packages/grid_assets/test/acceptance/circuit_acceptance_test.dart`
- `packages/grid_assets/test/acceptance/discovery_acceptance_test.dart`
- `packages/grid_assets/test/acceptance/invariant_1_no_pipeline_subscription_test.dart`
- `packages/grid_assets/test/acceptance/invariant_2_only_the_chokepoint_writes_test.dart`
- `packages/grid_assets/test/acceptance/invariant_3_convergence_never_mounts_test.dart`
- `packages/grid_assets/test/acceptance/invariant_4_a37_pristine_source_test.dart`
- `packages/grid_assets/test/acceptance/migration_guard_acceptance_test.dart`
- `packages/grid_assets/test/acceptance/pdr_s7_acceptance_test.dart`
- `packages/grid_assets/test/acceptance/readiness_acceptance_test.dart`
- `packages/grid_assets/test/acceptance/spec_stage_acceptance_test.dart`
- `packages/grid_assets/test/substation_service_bundle_test.dart`
- `packages/github_grid_assets/test/acceptance/circuit_acceptance_test.dart`
- `packages/github_grid_assets/test/acceptance/invariant_2_only_the_chokepoint_writes_test.dart`

Modified — prose only (no code change):
- `packages/federated_grid_assets/lib/src/claim/claim_broadcaster.dart` (lines 6 and 107)
- `packages/grid_assets/test/track_c_committee_test.dart` (line 49)
- `packages/github_grid_assets/test/acceptance/pdr_s7_acceptance_test.dart` (lines 139, 148)
- `packages/grid_assets/extension/station_overlay/claude/skills/asset-author/SKILL.md` (line 60)
- `packages/grid_assets/extension/station_overlay/agents/skills/asset-author/SKILL.md` (line 60)

Re-validated against the live tree: `grep -rn StationKernel packages` finds 45 hits across the 19 files listed above (17 Dart files plus the two byte-identical `SKILL.md` copies), and every one of the ~20 construction sites passes exactly the five named arguments `MountedStation` declares; `bd dep list pow-zvaw` reports no dependencies and `bd search StationKernel` / `bd search runGrid` return only this bead, so no sibling touches these surfaces; `MountedStation` resolves nowhere in `packages/` or in the_grid today (`grep -rn MountedStation` is empty), so the name is new and uncontested; `StationDriver`, `runGrid`, `GridDelegate`, `Provider`, `Station`, `Nest` and `defaultProcessLeaseVendor` all resolve in the PUBLISHED grid_engine 0.3.0-rc.11 / grid_sdk 0.3.0-rc.9 / genesis_tree 0.3.0 already sitting in the local pub cache.

## ADR Alignment

Verified via grep on `StationKernel`, `runGrid`, `flush`, `prerelease`,
`pre-release` over `docs/adr` and `docs/decisions`; the hits were
`docs/adr/ADR-0003-private-git-tag-releases-and-prerelease-gate.md`,
`docs/adr/ADR-0000-ai-decision-register.md`,
`docs/decisions/2026-07-15-adr-0003-private-git-tag-releases-and-prerelease-gate.md`,
`docs/decisions/2026-07-21-a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule.md`
and `docs/decisions/2026-07-11-a11-bead-pow-ovh-the-search-domain-roster-resolution-is-an-o.md`.

- **`the_grid#run-grid-is-the-single-flush-coordinator`** (accepted 2026-09-02,
  the upstream decision this bead lands downstream of) — *"`StationKernel` is
  deleted in the same change — no delegation shim and no second flush loop,
  because two flush loops drift."* The plan IMPLEMENTS it: `MountedStation`
  adds no flush loop of its own; it calls `runGrid` and hangs the driver's
  `afterFlush` on the `onFlushed` rail, which is the same wiring
  `grid_cli`'s `defaultRunMountedGrid` uses in production.
- **`power_station#adr-0003-private-git-tag-releases-and-prerelease-gate` D3**
  (legacy id `docs/adr/ADR-0003-…` D3; D3/D4 stand, D1/D2 superseded
  2026-08-05) — *"Every downstream consumer resolves against the rc and runs
  `dart analyze && dart test`."* This bead IS power_station's D3 leg for the
  engine rc.11 / sdk rc.9 wave: Step 1 pins the floors, Step 9 runs the analyze
  and the suites from a cold resolve.
- **`power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`**
  — *"The three identical private `_settle` fixed-point wrappers … are
  deliberately NOT deduped here: they are unchanged by this fix and hoisting
  them is an unrelated refactor that would widen a station-health diff."*
  Step 5 CONSTRAINS the port to that ruling: the wrappers and the shared
  `settle` primitive are untouched, and no pump count moves.
- **the_grid ADR-0008 D-H, as restated in this repo's `CLAUDE.md`** — *"Config
  = VALUES in the tree; impls = DI — author configuration as mounted values,
  inject implementations (no services in a branch except injected)."*
  `_StationRootDelegate.build` constructs nothing: `defaultProcessLeaseVendor`
  is called in `MountedStation`'s constructor (off-tree) and enters the tree
  only as a provided value, exactly as the retired kernel built it in `start()`.
  D-H rule 2 (*"no public synchronous accessor over `StateNotifier` state"*)
  is honoured by construction — the delegate is held by `runGrid`, never
  provided ambiently, and `MountedStation` exposes no `.state`.
- **`docs/adr/ADR-0000-ai-decision-register.md` is READ-ONLY LEGACY.** The
  design's own call is recorded in Step 8 as a new `docs/decisions/` entry
  through the vended `decide` skill, never as an `A<n>` amendment.

No ADR governs the org terminology this change touches beyond the standing
invariants: the new name is `MountedStation` — a thing, not an agent-noun —
and no surface here is called a "plugin".

## Validation Plan
- [ ] No `StationKernel` reference survives under `packages/` → `grep -rn StationKernel packages; echo "exit=$?"` → prints no match lines and `exit=1`
- [ ] The two federated doc comments name `StationDriver` → `grep -n 'StationDriver' packages/federated_grid_assets/lib/src/claim/claim_broadcaster.dart` → two hits, at the constructor-param sentence and the `onUnclaimedFrontier` hook doc
- [ ] Workspace-wide `dart analyze` exits 0 after a FRESH resolve → `dart pub upgrade grid_engine grid_sdk grid_runtime beads_dart grid_cli grid_trajectory && dart analyze` → `No issues found!`
- [ ] Every acceptance suite under `packages/grid_assets/test/acceptance` passes → `cd packages/grid_assets && dart test test/acceptance` → `All tests passed!`
- [ ] Every acceptance suite under `packages/github_grid_assets/test/acceptance` passes → `cd packages/github_grid_assets && dart test test/acceptance` → `All tests passed!`
- [ ] No invariant assertion and no settle/pump is lost in the port → `for f in packages/grid_assets/test/acceptance/*.dart packages/github_grid_assets/test/acceptance/*.dart packages/grid_assets/test/substation_service_bundle_test.dart; do a=$(git show "main:$f" | grep -cE 'expect\(|await _settle\(|await pumpEventQueue\(\)'); b=$(grep -cE 'expect\(|await _settle\(|await pumpEventQueue\(\)' "$f"); [ "$a" = "$b" ] || echo "DRIFT $f $a -> $b"; done` → prints nothing
- [ ] `station_kernel_test.dart` is re-homed BY NAME, not deleted → `test -f packages/grid_assets/test/run_grid_reactive_loop_test.dart && ! test -e packages/grid_assets/test/station_kernel_test.dart && grep -c 'test(' packages/grid_assets/test/run_grid_reactive_loop_test.dart` → prints `1`
- [ ] The re-homed suite passes → `cd packages/grid_assets && dart test test/run_grid_reactive_loop_test.dart` → `All tests passed!` (`+1`)
- [ ] `substation_service_bundle_test.dart` passes on the migrated harness → `cd packages/grid_assets && dart test test/substation_service_bundle_test.dart` → `All tests passed!`
- [ ] The wave floors read the pinned versions and the workspace resolves them → `grep -n 'beads_dart:\|grid_runtime:\|grid_engine:\|grid_sdk:\|grid_cli:' packages/*/pubspec.yaml && dart pub deps --style=compact | grep -E 'grid_engine |grid_sdk |grid_runtime |beads_dart |grid_cli '` → constraints read `^0.2.0-rc.7` / `^0.2.0-rc.9` / `^0.3.0-rc.11` / `^0.3.0-rc.9` / `^0.5.0-rc.11`, and the resolved set shows `grid_engine 0.3.0-rc.11`, `grid_sdk 0.3.0-rc.9`, `grid_runtime 0.2.0-rc.9`, `beads_dart 0.2.0-rc.7`, `grid_cli 0.5.0-rc.11`
- [ ] The design call is recorded as an accepted `docs/decisions/` entry → `grep -l 'slug: acceptance-harnesses-mount-through-run-grid' docs/decisions/*.md | head -1 | xargs grep -n 'status: accepted'` → one file, `status: accepted`