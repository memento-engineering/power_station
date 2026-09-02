---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a38-bead-pow-n6n-3-the-mechanism-of-adr-0006-d3-s-availabili
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A38"
---
## A38 (2026-09-02) — bead `pow-n6n.3`: the MECHANISM of ADR-0006 D3's availability seed — presence is a BOOLEAN probe over the boot-validated set, arming is an AMBIENT VALUE so ADR-0002 D5 nesting composes, and the "failure signal" is the probe's own failure

**Decision (AI; MECHANISM only).** The POLICY is ratified in
`docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md` D3. The
autonomous calls this bead made: (1) PRESENCE IS A BOOLEAN — `EnvironmentProbe`
returns `Future<bool>`; a refusal reason no rung reads would be a dead field, and
D3 makes the tree itself the answer. (2) THE PASS RUNS OVER
`EnvironmentRegistry.validatedEnvironments` ONLY, so presence NARROWS the
boot-legal set and can never widen it — A35(1)'s "validated by construction"
property survives live probing untouched. (3) THE SEED IS ARMED, NOT DEFAULT-ON:
`HarnessProvider.probe` defaults to null, leaving A35(5)'s boot-validated default
set and byte-identical pre-`pow-n6n.3` behaviour; default-on would make every
existing composition and Track F test touch the machine at mount. (4) ARMING IS
AN AMBIENT VALUE (`EnvironmentProbeArming`, an `InheritedSeed` a
`HarnessProvider` publishes and a nested one WATCHES), because ADR-0002 D5's
per-substation arming nests a second `HarnessProvider` that re-provides its
registry unconditionally; without inherited arming a seat overriding only its
registry would read an ancestor's presence set computed over a different
registry. This is the `GitServices` impl-carrier precedent applied to arming.
(5) THE FAILURE SIGNAL is the probe's own failure (false OR a throw) plus a
watched dependency change (registry / site binding); an engine-side
spawn-failure bus is out of scope because `ServiceBundle.transport` is documented
as the OUTBOUND sink with no inbound handle, and the bounded tick is the recovery
path. (6) A `SiteBindingError` at probe time is ABSENCE, not a crash — the LOUD
guard for an unbound machine fact is the composition root's boot refusal.
(7) THE TICK IS DI (`ProbeSchedule`/`ProbeTicker` over `Timer.periodic`) so the
bounded re-probe is fired deterministically in test, and the real probe composes
three injected IO primitives so its target-dispatch logic is pure and tested
while only the defaults touch the box.

**Why.** D3 prescribes the SHAPE ("a probing StatefulSeed mounts and unmounts
environment presence") but not who arms it, what a probe returns, or what
"failure signal" means in a pack with no inbound event handle. Each call above is
the smallest one that keeps three existing properties intact:
legality-by-construction (A35(1)), no-regression-before-probes (A35(5)), and
per-substation arming (ADR-0002 D5, which ADR-0006's Consequences reconfirm is
"GENERALISED, not undone").

**Affects (if promoted):** `packages/grid_assets/lib/src/agent/environment_probe.dart`
(`kEnvironmentProbeTimeout`, `EnvironmentProbeRequest`, `EnvironmentProbe`,
`ProcessEnvironmentProbe`, `commandOnPath`, `socketReachable`, `listedModels`),
`availability_assets.dart` (`kEnvironmentProbeInterval`, `ProbeTicker`,
`ProbeSchedule`, `timerProbeSchedule`, `EnvironmentProbeArming`,
`AvailabilityAssets`), `assets/composition_assets.dart` (`HarnessProvider.probe`,
`HarnessProvider.probeInterval`), `packages/grid_assets/lib/grid_assets.dart`;
tests: `packages/grid_assets/test/agent/availability_seed_test.dart`. Composes
with A35, A8 and ADR-0002 D5. Does not touch `pow-n6n.2`'s typed subclasses or
`pow-n6n.4`'s role retirement, and does not mount `InheritedSeed<SiteBinding>`
(bead `pow-2eg`).

**Status:** Pending — Nico promotes or rejects.
