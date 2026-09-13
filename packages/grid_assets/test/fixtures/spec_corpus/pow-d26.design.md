## Implementation Plan

The change is a TEST-HARNESS fix in one shared wait primitive, plus the test that
pins it, plus the register entry that records the root cause. It is already
committed on branch `grid/pow-d26` (`9d0cdf0`, `37ef206`, `337cd5f`, `c70bc3f`);
each step below names the commit that carries it. **Idempotence rule for every
step: run the step's check FIRST. If the tree already matches the step's code
block, the step is landed — make no edit and create no second commit; if it does
not match, write exactly the block below and commit with the message given.**

### Step 1 — `settle` grants a REAL wall-clock slice per unsatisfied round

In `packages/grid_assets/test/support/asset_fakes.dart`, the shared bounded wait
must be exactly this (doc comment included — the doc IS the contract the three
private `_settle` wrappers count their plateau in):

```dart
/// Waits until [condition] holds, or [maxPumps] bounded rounds have run
/// (default 20). Each round drains the Dart event queue AND, when the
/// condition is still unsatisfied, sleeps a REAL [ioSlice] (default 1ms).
///
/// The real slice is the load-bearing half, not the pump (bead `pow-d26`). A
/// molecule mint's POUR crosses the actual filesystem BELOW the fake
/// `BdRunner` seam: `BdCliService.applyGraph` writes the graph-apply plan to a
/// temp file (`Directory.systemTemp.createTemp` → `File.writeAsString` →
/// `Directory.delete`) around the runner call, so a fake runner does not make
/// the pour offline. `pumpEventQueue` advances event-loop TURNS and grants
/// only microseconds of wall clock, so it can never wait out an OS completion
/// — and to a plateau-based fixed-point wrapper an in-flight filesystem call
/// looks exactly like quiescence. That is why raising the pump budget alone
/// never fixed the ~25%-per-run acceptance wedge, and why this helper now
/// yields real time instead.
///
/// [condition] is evaluated EXACTLY ONCE per round, at the TOP of the round —
/// so an already-satisfied condition costs one check and no sleep, and a
/// never-satisfied one costs exactly [maxPumps] checks. That one-check-per-
/// round rate is what the private `_settle` fixed-point wrappers in the
/// acceptance suites count their `stableRounds` plateau in.
///
/// Still bounded, so a genuine regression FAILS (its [condition] stays false
/// through [maxPumps] rounds) instead of hanging.
Future<void> settle(
  bool Function() condition, {
  int maxPumps = 20,
  Duration ioSlice = const Duration(milliseconds: 1),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await pumpEventQueue();
    await Future<void>.delayed(ioSlice);
  }
}
```

The signature is source-compatible: `ioSlice` is optional with a default, so every
existing call site (`test/station_kernel_test.dart:180,191,233,280,301`, the
private `_settle` wrappers in `test/acceptance/circuit_acceptance_test.dart:414`,
`test/acceptance/discovery_acceptance_test.dart:211`,
`test/acceptance/spec_stage_acceptance_test.dart:224`, and the direct calls in
`test/acceptance/readiness_acceptance_test.dart` and
`test/acceptance/migration_guard_acceptance_test.dart`) compiles unchanged. No
call site is migrated by this bead.

The same file's head comment block must name the new contract — lines 16-18 read:

```dart
// cheap-head-complete convenience over it. [settle] is the shared bounded
// wait helper; it grants REAL wall clock per round because the molecule
// mint's pour crosses the filesystem below the fake runner seam.
```

Test: `cd packages/grid_assets && dart test test/settle_test.dart` → expect
`All tests passed!` (that file is Step 2's; if Step 2 has not run yet, check this
step with `cd packages/grid_assets && dart test -j1 test/station_kernel_test.dart test/acceptance/circuit_acceptance_test.dart` → expect `All tests passed!`).
Commit: `fix(assets): settle must grant real wall clock, not just queue turns`
(on the branch as `9d0cdf0`; the doc's check-per-round precision is `c70bc3f`).

### Step 2 — Pin the wall-clock contract so a revert fails LOUD

Create `packages/grid_assets/test/settle_test.dart` with exactly:

```dart
// The WAIT PRIMITIVE's own contract (bead `pow-d26`).
//
// `settle` is the shared bounded wait every acceptance suite here builds its
// private `_settle` fixed-point wrapper on. Its load-bearing property is NOT
// "pump the event queue": the molecule mint's pour crosses a REAL filesystem
// boundary below the fake `BdRunner` seam (`BdCliService.applyGraph` writes the
// graph-apply plan to a temp file), and an event-queue pump grants only
// microseconds of wall clock. So `settle` must yield REAL time per unsatisfied
// round, or a pending OS completion is indistinguishable from quiescence and
// the suite reads an empty observable. These tests pin that contract LOUD, so a
// revert to a pump-only wait fails HERE instead of reappearing as a ~25%
// acceptance flake.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'support/asset_fakes.dart';

void main() {
  group('settle — the bounded wait grants REAL wall clock', () {
    test('an ALREADY-satisfied condition costs exactly one check', () async {
      var checks = 0;
      await settle(() {
        checks++;
        return true;
      });
      expect(
        checks,
        1,
        reason: 'settle checks FIRST and sleeps only when unsatisfied',
      );
    });

    test('an unsatisfied condition is checked ONCE per bounded round', () async {
      var checks = 0;
      await settle(() {
        checks++;
        return false;
      }, maxPumps: 3);
      expect(
        checks,
        3,
        reason:
            'the acceptance suites count their stableRounds plateau in '
            'these checks — one per round, or the plateau silently halves',
      );
    });

    test('each unsatisfied round sleeps a REAL slice', () async {
      final sw = Stopwatch()..start();
      await settle(
        () => false,
        maxPumps: 5,
        ioSlice: const Duration(milliseconds: 4),
      );
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(20),
        reason:
            'five unsatisfied rounds at 4ms each — a pump-only wait '
            'returns in microseconds and can never outlast a filesystem call',
      );
    });

    test('a pending REAL filesystem round trip lands inside the budget', () async {
      var landed = false;
      unawaited(_tempPlanFileRoundTrip().then((_) => landed = true));
      await settle(() => landed, maxPumps: 200);
      expect(
        landed,
        isTrue,
        reason:
            'this is the exact IO shape BdCliService.applyGraph performs '
            'for every molecule pour',
      );
    });
  });
}

/// The IO shape `BdCliService.applyGraph` performs for every molecule pour: a
/// temp dir, a plan write, a recursive delete.
Future<void> _tempPlanFileRoundTrip() async {
  final dir = await Directory.systemTemp.createTemp('settle-io-probe');
  await File('${dir.path}/plan.json').writeAsString('{"nodes":[]}');
  await dir.delete(recursive: true);
}
```

Fakes, not mocks: the probe exercises the real `dart:io` shape the pour performs;
no mock framework is introduced.

Test: `cd packages/grid_assets && dart test test/settle_test.dart` → expect
`All tests passed!` (4 tests).
Commit: `test(assets): pin settle's real-wall-clock wait contract` (on the branch
as `37ef206`).

### Step 3 — Record the root cause in the AI decision register as A28 (pending)

Append to `docs/adr/ADR-0000-ai-decision-register.md`, after the A26 / ratified
discovery-gate block, exactly this amendment (Status pending — only Nico
promotes):

```markdown
## A28 (2026-07-21) — bead `pow-d26`: the acceptance-suite flake is the molecule pour's REAL filesystem hop BELOW the fake `BdRunner` seam, not the_grid `f2b79bf`; the shared `settle` primitive gains a real wall-clock slice per unsatisfied round

**Decision:** the ~25%-per-run wedge in `station_kernel_test.dart` ("specify spawned" reads 0 spawns) and `acceptance/circuit_acceptance_test.dart:753` ("a gating-F parks the route (state=gated)") is root-caused, and the fix is homed HERE (power_station's test harness), not upstream. Instrumenting the failing assertion to dump the fake bd runner's call log showed it frozen at exactly `[create --json, update <sid>, export --all]` on every captured failure — the session mint, the `grid.session.model` stamp, and the mint-dedup export probe — with the next hop, the molecule POUR, never reaching the runner at all. That hop is `BdCliService.applyGraph` (beads_dart `lib/src/services/bd_cli_service.dart:288-307`), which writes the graph-apply plan to a REAL temp file (`Directory.systemTemp.createTemp` → `File.writeAsString` → `Directory.delete`) AROUND the injected `BdRunner` call. Those `dart:io` round trips sit ABOVE the runner seam, so a fake runner does not make the pour offline: every molecule mint in this pack's offline suites crosses the filesystem. `settle` (`packages/grid_assets/test/support/asset_fakes.dart`) waited by pumping the event queue only, and `pumpEventQueue` advances event-loop turns while granting microseconds of wall clock — it cannot wait out an OS completion, and to a plateau-based fixed-point wrapper an in-flight filesystem call is indistinguishable from quiescence. That is why raising `maxPumps` 20→1000 and `stableRounds` 50→250 never moved the rate. `settle` now sleeps a real `ioSlice` (default 1ms) per UNSATISFIED round and evaluates its condition exactly once per round; `test/settle_test.dart` pins that contract so a revert to a pump-only wait fails LOUD there rather than reappearing as an acceptance flake.

**The `f2b79bf` suspicion is CLEARED, not merely unconfirmed:** the wedge lands before any process is spawned (the failing `station_kernel` assertion is that the FIRST spawn never happened), so the held-terminal latch-before-emit rework cannot be on the path. No the_grid change is required by this diagnosis.

**Why:** real filesystem IO in a production write path is legitimate; what was wrong is the harness's model of what a WAIT is. Fixing the shared primitive every suite already routes through is one edit for four suites, and it EXTENDS rather than reverses A27(7)(b)'s observable-targeted waits — the targets stay, and the wait underneath them can now actually reach them. The three identical private `_settle` fixed-point wrappers (`acceptance/circuit_acceptance_test.dart`, `acceptance/discovery_acceptance_test.dart`, `acceptance/spec_stage_acceptance_test.dart`) are deliberately NOT deduped here: they are unchanged by this fix and hoisting them is an unrelated refactor that would widen a station-health diff.

**Measured** at power_station `697f0d3` + the_grid `709dc93`, `-j1`, both named files: 5/15 failing before (and 4/15, 4/25 in the prior spec run); 0/40 after. The full `grid_assets` offline suite passes and `dart analyze` is clean.

**Affects (if promoted):** `packages/grid_assets/test/support/asset_fakes.dart` (`settle`), `packages/grid_assets/test/settle_test.dart` (new).
**Status:** pending.
```

Test: `grep -c '^## A28 (2026-07-21)' docs/adr/ADR-0000-ai-decision-register.md`
→ expect `1`, and `sed -n '/^## A28 /,/^\*\*Status:\*\*/p' docs/adr/ADR-0000-ai-decision-register.md | grep -c 'Status:\*\* pending'` → expect `1`.
Commit: `docs(adr): root-cause the acceptance flake to the pour's fs hop` (on the
branch as `337cd5f`).

### Step 4 — Write the 40-run receipt into the bead's notes

The diagnosis must outlive the worktree, so it lands on the bead through the bd
CLI (the only sanctioned mutation path). Check first:

```
bd show pow-d26 | grep -q '0/40 after'; echo $?
```

Expect `0` (the receipt is present; an exit-code check, because the spec body
itself quotes the phrase and a line COUNT is therefore not stable). If it prints
`1`, run exactly (one line, `--actor build`):

```
bd update pow-d26 --actor build --notes "DIAGNOSIS OF RECORD: ROOT CAUSE FOUND AND FIXED — the flake was NOT the_grid f2b79bf (cleared; clearing analysis in ADR-0000 A28, pending): asset_fakes.dart's settle() helper only pumped event-queue turns while BdCliService.applyGraph performs a real FILESYSTEM hop — the wait could exhaust its rounds without granting wall-clock time for the write to land. FIX: settle now sleeps a real ioSlice per unsatisfied round (9d0cdf0), contract pinned by settle_test.dart (37ef206). PROOF: 0/40 after the fix — 40 consecutive runs of station_kernel_test.dart + acceptance/circuit_acceptance_test.dart at -j1, all 'All tests passed!', zero FAIL markers. Prior measurement: 5-8/40."
```

Test: `bd show pow-d26 | grep -q '0/40 after'; echo $?` → expect `0`.
Commit: none — a bead mutation is not a tree change (nothing to commit for this
step).

### Step 5 — Run the gate that proves the flake is retired

The single line the code committee's gating lane runs (also the bead's
`validation_plan` metadata):

```
cd packages/grid_assets && dart analyze && dart test -j1 -x integration && for i in 1 2 3 4 5 6 7 8 9 10; do dart test -j1 test/station_kernel_test.dart test/acceptance/circuit_acceptance_test.dart || exit 1; done
```

Test: that command → expect `No issues found!` from analyze and
`All tests passed!` from every one of the 11 test invocations, exit code 0.
Commit: none — this step runs the gate; it writes no files.

## Touches
- `packages/grid_assets/test/support/asset_fakes.dart` — modified (head comment
  lines 16-18 and the wait helper); `test/support/asset_fakes.dart:settle` —
  existing public helper, signature gains the optional named
  `Duration ioSlice = const Duration(milliseconds: 1)`; `maxPumps` keeps its
  default of 20. No new public symbol.
- `packages/grid_assets/test/settle_test.dart` — created; no public symbols
  (`main` plus the private `_tempPlanFileRoundTrip`).
- `docs/adr/ADR-0000-ai-decision-register.md` — modified; amendment A28 appended,
  `**Status:** pending`.
- bead `pow-d26` notes — the 40-run receipt (bd CLI, no file).
- NOT touched, deliberately: the three identical private `_settle` fixed-point
  wrappers (`test/acceptance/circuit_acceptance_test.dart:414`,
  `test/acceptance/discovery_acceptance_test.dart:211`,
  `test/acceptance/spec_stage_acceptance_test.dart:224`) — hoisting them is an
  unrelated refactor that would widen a station-health diff (A28's own clause).
  No `lib/` code and no genesis_tree surface is touched by this bead.

Re-validated against the live tree: `grep -rn "settle(" packages/grid_assets/test --include='*.dart'` returns call sites in `settle_test.dart`, `station_kernel_test.dart` (5), and the `acceptance/` suites (circuit, discovery, spec_stage, readiness, migration_guard) — all positional-condition calls with at most named `maxPumps`, so the added optional `ioSlice` migrates none of them; `bd dep list pow-d26` reports no dependencies and `bd search settle` returns no other bead, so there is no sibling to carve scope from; the four commits above are present on branch `grid/pow-d26` with a clean `git status`, and `dart test test/settle_test.dart` was observed green (4 tests) while drafting this spec.

## ADR Alignment
Verified via `ls docs/adr/` and `grep -li "settle\|flake\|acceptance\|pump\|wait" docs/adr/*.md` (keywords: `settle`, `flake`, `acceptance`, `pump`, `wait`, `molecule`) → `ADR-0000-ai-decision-register.md`, `ADR-0001-packaged-ai-asset-skill-command-coupling.md`, `ADR-0002-agent-environment-layer.md`.

- `docs/adr/ADR-0000-ai-decision-register.md` A28 (Status: pending) — "the fix is
  homed HERE (power_station's test harness), not upstream." This spec IS A28's
  implementation: Steps 1-2 are the `settle` change and its contract test, Step 3
  is the amendment itself. Nothing here overrides a recorded decision.
- `docs/adr/ADR-0000-ai-decision-register.md` A28, on the wait doctrine it
  extends — "it EXTENDS rather than reverses A27(7)(b)'s observable-targeted
  waits — the targets stay, and the wait underneath them can now actually reach
  them." The plan changes only the wait primitive; every acceptance-suite
  observable target is left exactly as written. (`grep -n "^## A27" docs/adr/ADR-0000-ai-decision-register.md`
  returns nothing — no `A27` heading survives in the current register, so A28's
  paraphrase is the citable record of that clause.)
- `docs/adr/ADR-0000-ai-decision-register.md`, RATIFIED entry of 2026-07-14
  (Nico) — "a **PENDING** ADR-0000 amendment is **ADVISORY ONLY** … NEVER grounds
  for a discovery HOLD." A28 is cited here as advisory context and is filed
  `**Status:** pending`; this spec does not promote it and does not treat it as
  ratified.
- Repo `CLAUDE.md` house set (genesis ADR-0001 D7) — "**Fakes, not mocks**; pure
  logic tested before IO is wired." Step 2's test uses the pack's existing fakes
  plus a real `dart:io` probe; no mock framework is added.
- `docs/adr/ADR-0008` (the D-H genesis_tree doctrine, cited by repo `CLAUDE.md`)
  does not apply: this bead touches only `test/` support code and the register —
  no `build`, no `InheritedSeed`, no `StateNotifier`, no `lib/` file is modified
  (see `## Touches`).
- `docs/adr/ADR-0001` (skill/command coupling) and `docs/adr/ADR-0002` (agent
  environment layer) matched the keyword grep but govern packaged-asset shape and
  the model/environment layer — neither surface is touched by a test-harness wait.

## Validation Plan
- [ ] `station_kernel_test.dart` + `acceptance/circuit_acceptance_test.dart` green across 10 consecutive `-j1` runs → `cd packages/grid_assets && for i in 1 2 3 4 5 6 7 8 9 10; do dart test -j1 test/station_kernel_test.dart test/acceptance/circuit_acceptance_test.dart || exit 1; done` → `All tests passed!` ten times, exit code 0
- [ ] `settle` sleeps REAL wall clock per unsatisfied round (5 rounds at 4ms >= 20ms) → `cd packages/grid_assets && dart test test/settle_test.dart` → `All tests passed!` (test `each unsatisfied round sleeps a REAL slice`)
- [ ] `settle` evaluates its condition EXACTLY ONCE per round (1 check satisfied; 3 checks at `maxPumps: 3`) → `cd packages/grid_assets && dart test test/settle_test.dart` → `All tests passed!` (tests `an ALREADY-satisfied condition costs exactly one check` and `an unsatisfied condition is checked ONCE per bounded round`)
- [ ] a pending REAL filesystem round trip lands inside `settle`'s budget → `cd packages/grid_assets && dart test test/settle_test.dart` → `All tests passed!` (test `a pending REAL filesystem round trip lands inside the budget`)
- [ ] the full offline `grid_assets` suite passes and `dart analyze` is clean → `cd packages/grid_assets && dart analyze && dart test -j1 -x integration` → `No issues found!` then `All tests passed!`
- [ ] `ADR-0000` carries A28 with `**Status:** pending` → `grep -c '^## A28 (2026-07-21)' docs/adr/ADR-0000-ai-decision-register.md && sed -n '/^## A28 /,/^\*\*Status:\*\*/p' docs/adr/ADR-0000-ai-decision-register.md | grep -c 'Status:\*\* pending'` → `1` then `1`
- [ ] the bead's notes carry the 40-run receipt → `bd show pow-d26 | grep -q '0/40 after'; echo $?` → `0`