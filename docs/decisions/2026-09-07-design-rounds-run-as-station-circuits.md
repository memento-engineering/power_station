---
status: accepted
date: 2026-09-07
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: design-rounds-run-as-station-circuits
  surfaces:
    - "packages/grid_assets/lib/src/code/design_committee.dart"
    - "packages/grid_assets/lib/src/code/docs_committee.dart"
    - "packages/grid_assets/extension/rubrics/ruling-adherence.md"
    - "packages/grid_assets/extension/rubrics/ordering-and-rollback.md"
    - "packages/grid_assets/extension/rubrics/fold-fidelity-and-ops.md"
    - "packages/grid_assets/extension/rubrics/cite-verification.md"
  obsoletes: []
  updates:
    - a36-bead-pow-adh3-the-change-shape-gains-a-metadata-arm-an-a
    - a9-bead-pow-6wo-re-homed-from-the-grid-tg-fc6-the-committee
    - a13-bead-pow-6ao-the-specify-stage-spec-readiness-committee
  obsoleted-by: null
  updated-by: []
  bead: pow-gy7o
  legacy-id: null
---

# Design rounds run as station circuits

## Context and Problem Statement

The wave-2 design round (cut-wiring r6) ran as a Claude Code Workflow: a design
seat, two adversarial judges with distinct lenses, a verifier that reconciled
their claims and applied fixes, looped up to three passes. It ran there for one
reason — the station had no circuit of that shape. The docs committee
(`packages/grid_assets/lib/src/code/docs_committee.dart`) routes a docs bead to
three deterministic gates plus one `spec-adherence` critic, and nothing in it
reconciles what a critic says against the tree before the route acts on it.

Nico's ruling, 2026-09-07: **"This should be harness agnostic... the station is
the harness."** The r6 run was allowed to finish as the LAST one.

## Decision Outcome

A design round is a station bead running a station circuit. Its receipts land in
the trajectory and its grades land in the state store, exactly like every other
round.

### The classification is a PATH predicate, and only a path predicate

A fourth `ChangeShape` — `design` — is admitted by `isDesignPath`, an allow-list
of ONE prefix: a repo-relative file at any depth under the repo-root
`docs/design/` tree. `changeShapeOf` returns it only when EVERY path the bead's
`## Touches` section cites satisfies that predicate, and the arm is evaluated
BEFORE the docs arm — every design path is also a docs path, so the reverse
order would never reach it. A mixed set falls through the existing docs →
metadata → code ladder unchanged, so no bead that is not a design round moves
committee.

A bead-metadata key was considered and **rejected**. A36's reason binds here
identically: one path vocabulary serves both the classification and the lanes'
foreign-file fence, and a second classification channel is a second thing to
drift. So is a configured glob. The consequence for authors is deliberate and
small: a design round's document lives under `docs/design/`, and its bead cites
that path.

### The judges are adversarial lenses; the verifier is the new step

The three deterministic docs gates are mounted VERBATIM — same step ids, same
capability, same rubric params, same pinned-diff dependency. The single
`spec-adherence` critic is replaced by four judge lanes, each an ordinary
rubric-parametrized `critic` step and each a rubric asset with one lens:
`ruling-adherence`, `ordering-and-rollback`, `fold-fidelity-and-ops`,
`cite-verification`. Each is commanded to REFUTE with receipts and to grade its
findings BLOCKER / MAJOR / MINOR in one fixed line grammar, so a judgment is
readable as data rather than as prose.

Between the judges and the route sits `design-verify`, the step the docs circuit
lacks and the reason design rounds were hand-rolled. **A judge's rationale is
evidence, never fact.** The verifier reads every finding, CONFIRMS or REFUTES it
against the tree and the rulings the bead names, applies the confirmed fixes to
the document, and appends a per-round adjudication log to it (finding →
`CONFIRMED-FIXED` / `REFUTED` / `CONFIRMED-OPEN`). Only a `CONFIRMED-OPEN`
finding reaches the route.

### The loop and the receipts are the ones that already exist

`design-verify` joins all seven lanes; `route` joins `design-verify` alone, with
`critics` and `gating` both naming it. The shared route matrix therefore
hard-blocks on exactly one thing — a finding that survived verification — and
the existing rework loop turns: the next round's design seat is the ordinary
`agent` step reading the bead plus the verifier's note. No new loop machinery.

The judges write the established round-fresh `.grid/critique/<lane>.json`
verdicts through the existing critic transport, and the verifier writes its own
`.grid/critique/design-verify.json` carrying the same envelope fields plus the
full adjudication list, so gate medicine and the trajectory read them unchanged.

### Explicitly out of scope

* **No generic workflow engine.** The shape is a circuit of ordinary steps.
* **No change to the code circuit.** Its lanes, matrix and receipts are
  untouched.
* **No second route matrix**, no second verdict parser, and no second rubric
  loader: A13's hardened verdict-transport stack serves this committee too.

### Consequences

* Good, because the next design round (r7, the W2-D soak-gate design, an ADR
  revision) is a station bead — same spawn, same grades, same receipts — rather
  than a hand-driven session whose reasoning survives only in a transcript.
* Good, because a new lens is a new rubric asset plus a step, which is what the
  docs committee's own header already promised a new review type would be.
* Bad, because the verifier is a NEW inference edge whose answer rewrites a
  document; it is fenced by validating the whole response before any write, by
  refusing an out-of-scope document key, and by refusing a round whose documents
  exceed its brief budget rather than truncating one.
* Bad, because a design round now costs four judge lanes plus a frontier verify
  call. Four judges at A short-circuit the verify call entirely, which is the
  only cost this entry removes.
