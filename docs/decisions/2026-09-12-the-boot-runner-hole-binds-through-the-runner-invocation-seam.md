---
status: accepted
date: 2026-09-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-boot-runner-hole-binds-through-the-runner-invocation-seam
  surfaces:
    - "packages/grid_assets/lib/src/assets/assets_command.dart"
    - "packages/grid_assets/lib/src/assets/overlay_materializer.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-ln7a
  legacy-id: null
---

# The bootRunner hole binds through the existing runnerInvocation constructor seam

## Context and Problem Statement

A station has TWO runtimes, and until now the overlay could only spell one.

`{{bootRunner}}` and its runner-derived default already ship: the vended
`station-operations` skill renders its boot sites from the boot hole, the pack
declares the argument on both artifacts, and `renderOverlayTemplate` falls the
boot hole back to `{{runner}}` so a one-runtime station renders exactly as
before. What does NOT ship is a way for a station to set it. `AssetsCommand`
takes `runnerInvocation` alone, and `AssetsInstallCommand` builds
`GridAssetResolution.renderArguments` as a hardcoded two-key literal — `runner`
and `gridHome` — so no caller can add a third key. The hole therefore always
collapses onto the verb runner and the split is inert.

The two invocations are genuinely different shapes, and not as a quirk of one
station:

* The RESIDENT BOOT needs the JIT run form, because that is what carries
  `--enable-vm-service` and therefore hot reload, the `reload` verb and the
  leonard attach. A globally activated shim runs a snapshot and forwards no VM
  flags.
* EVERY OTHER VERB needs a name on PATH. A seat runs in a substation worktree
  where `dart run <station>:<station>` resolves no station package at all, so the
  run form names a command no seat can execute.

Measured on 2026-09-11 against the published `grid_assets` 0.6.0-rc.25: flipping
a station's single value to the global name made the seat verbs reachable AND
silently re-spelled the resident boot as a snapshot invocation. The generated
`station-operations` skill then contradicted itself — its own prose reads "the
station runs JIT via `dart run`, never an AOT binary" beside a command block
spelling the boot with the PATH name. The flip was reverted, for the second time.

So the remaining question is not WHETHER the two runtimes are separate values.
It is which seam a station binds the second one through.

## Considered Options

* Add a station-declaration hook — a `bootRunnerInvocation` property beside
  `runnerInvocation` on `GridDelegate` — so every composition path reads it off
  the station itself.
* Render a hole per VERB, so each vended command site can be spelled
  independently.
* Mirror `runnerInvocation`: an optional `bootRunner` constructor parameter on
  `AssetsCommand` and `AssetsInstallCommand`, carried into the existing render
  map.

## Decision Outcome

Chosen option: **mirror `runnerInvocation`.** Three clauses.

### 1. `bootRunner` mirrors `runnerInvocation` on both constructors

`AssetsCommand` and `AssetsInstallCommand` each take an optional named
`String? bootRunner` immediately beside `runnerInvocation`; the umbrella
forwards it to the subcommand, exactly as it forwards the verb invocation. The
install adds `kBootRunnerArg` to `GridAssetResolution.renderArguments` ONLY when
the value is non-null.

Null omission is the compatibility invariant, and it is a real one rather than a
convention: an omitted key leaves the existing `runner`/`gridHome` map
untouched, so `renderOverlayTemplate` supplies its own runner-derived default
and a station that names one runtime installs byte-identical files. A supplied
string is carried verbatim.

### 2. Code-registry callers already have the seam and get no second one

`buildCodeRegistry(overlayArgs:)` and `AgentCapability(overlayArgs:)` spread
their map into the same `renderArguments` after the capability's own defaults,
and `renderOverlayTemplate` applies supplied args AFTER its runner-derived
default. A caller that already carries `bootRunner` in `overlayArgs` therefore
wins on the worktree leg with no code change. Adding a dedicated parameter there
would be a second way to say the same thing, which is the drift this entry
exists to avoid.

### 3. A station-DECLARATION hook is not a grid_assets type

`runnerInvocation` reaches this Command from the composing station's own runner
builder, not from the resident-station context. Whatever property a station
reads the boot invocation OFF belongs to the downstream delegate that already
owns `runnerInvocation` — it rides the downstream station bead, not this one.

### Rejected, and why

* **A `GridDelegate` hook here.** `GridDelegate` is the shared resident-station
  context; the owning hook is downstream. Putting one station's runtime
  composition detail into the shared type would make every station answer a
  question only some of them have, and this Command already receives the verb
  invocation the other way.
* **A per-verb map.** The split names two RUNTIMES, not individual verbs. Every
  verb except the resident boot is reachable identically, so a hole per verb
  multiplies holes without naming the distinction that actually exists — and
  every station would then have to bind all of them.

### Consequences

* Good, because the defect is now expressible as a test: set the two holes to
  distinct sentinels, run the real install, and assert the verb sentinel never
  appears at a boot site. With one value that test could not be written, which
  is why the gap shipped green.
* Good, because omission is byte-identical, so no station that never splits its
  runtimes has to learn about the split.
* Good, because it reuses the seam a station already threads, so a composing
  station adds one named argument rather than a new type.
* Bad, because the value is threaded per composition path rather than declared
  once on the station, so a station with several composition paths can spell it
  in one and forget it in another. That cost is deliberate: the declaration hook
  is downstream work, and this entry does not pre-empt its shape.
* Bad, because two runtime values are two things to keep true, and a station
  that sets only the boot one gets no warning — the verb hole has its own
  default and cannot tell an omission from a deliberate match.

### Confirmation

The seam is in force when a real `AssetsInstallCommand`, handed distinct
`runnerInvocation` and `bootRunner` sentinels, installs a `station-operations`
skill whose `up` and JIT-restart sites carry the boot sentinel and whose seat,
status and down sites carry the verb sentinel — on BOTH harness targets — and
when omitting `bootRunner` installs bytes identical to setting it equal to
`runnerInvocation`.
