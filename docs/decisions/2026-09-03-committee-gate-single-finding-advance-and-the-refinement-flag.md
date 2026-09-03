---
status: accepted
date: 2026-09-03
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: committee-gate-single-finding-advance-and-the-refinement-flag
  surfaces:
    - "packages/grid_assets/**"
  obsoletes: []
  updates:
    - a14-bead-pow-7nm-the-spec-route-auto-respecs-a-fixable-spec
    - a13-bead-pow-6ao-the-specify-stage-spec-readiness-committee
  obsoleted-by: null
  updated-by: []
  bead: pow-bhm
  legacy-id: null
---
## The committee gate re-tunes: a single D ADVANCES with its finding carried, two-plus action grades GATE, and the bead-graph axis stops grading

**Decision (Nico-ratified 2026-07-18, interactive session; bead `pow-bhm`).**
Three dials, all in grid_assets. (1) ROUTE RULE — both committee routes
hard-gate ONLY on `F` or on two-or-more action grades; a SINGLE `D` ADVANCES
with that lane's finding attached VERBATIM to the build brief as a binding
fix-in-flight item, and the code committee re-checks it at review. (2)
COHERENCE SCOPE — the bead-graph axis stops GRADING; its findings ride a new
non-grading `refinement` verdict column into an operator flag. (3)
ADR-ALIGNMENT BAND — a verbatim-correct quote attributed to the wrong decision
number is a `C`-band correction; `D` is reserved for a MISSING governing
decision or a misapplied constraint that changes the design.

**Why:** `tg-h4u` burned four spec rounds; the two substantive ones each gated
on a SINGLE sub-C lane — round 1 on an adr-alignment `D` whose load-bearing
defect was a citation misattribution (right clause verbatim, wrong decision
number), round 3 on a coherence `F` whose finding was TRACKER STATE (a
duplicate bead plus a dep edge keyed to it): a real integrity problem, not a
defect of the spec under review, and fixable by two bd commands at refinement.
Meanwhile `space-ojl` advanced on an acceptance-testability `C` — sub-A
tolerance already exists in the route. Every catch keeps its value; a
single-finding round stops burning a full respec cycle.

**OVERRIDES ratified A14(2) — the code committee's route is no longer
byte-unchanged.** A14(2)
(`power_station#a14-bead-pow-7nm-the-spec-route-auto-respecs-a-fixable-spec`,
ratified Nico 2026-07-12) reads: *"a new `SpecRouteCapability` (over the pure
`decideSpecRoute`) serves the spec committee and `RouteCapability` is left
**byte-unchanged** for the code committee"*, and its Status line ratifies *"(2)
the per-committee decision-matrix FORK (`SpecRouteCapability` distinct from
`RouteCapability`, verdict-transport shared) — the departure from A13(5)
stands"*. That clause's `RouteCapability` is TODAY's `CodeRouteCapability` (A25
renamed it, mechanically: *"`RouteCapability` is RENAMED `CodeRouteCapability`
— grid_engine now EXPORTS an abstract `RouteCapability`, and the local
declaration shadowed it"*). This decision OVERRIDES the byte-unchanged half of
A14(2) and KEEPS the fork half: the two committees still own two separate
matrices in two separate capabilities, and the verdict TRANSPORT is still one
shared stack (A13(3)) — what changes is that the code committee's matrix is now
edited too, because the ratified policy names it explicitly ("ROUTE RULE
(spec_review route + code route in committee.dart)"). A14(2) said
byte-unchanged because THAT bead had no reason to touch the code side; this one
does, by human instruction. The fork's invariant is unharmed: divergence still
lives in the matrix, not in a naming param, and `CodeRouteCapability` still has
no respec arm — a single `E` and every two-plus join park for a human there,
because the code committee has no auto-correction loop downstream of a build.

**Also updates ratified A14(3) and A14(4).** A14(3) — *"the fixable/escalate
boundary is the GRADE: `D`/`E` = fixable, `F` = human"* — is NARROWED: a single
architect-owed `D` with a rationale now ADVANCES rather than respec-ing, a
single `E` still respecs under A15(4)'s untouched bound, and two-or-more action
grades escalate instead of respec-ing. A14(4) — *"The spread ≥ 3 'human
ultimatum' rule is REMOVED from the spec route (and KEPT in the code route)"* —
is EXTENDED to the code route for the identical reason A14(4) gives (*"A spread
≥ 3 across A..F necessarily puts some lane at `D` or worse, so the D/E/F arms
already cover every case it caught"*) and because keeping it would veto the
single-`D` advance this decision requires (`A` + `D` is a spread of exactly 3).
A37's owner column and its author-owed park are UNCHANGED and still fire FIRST
— an author-owed `D` parks before the single-finding arm can carry it. A13(3)'s
one verdict transport and A13(5)'s "a hard block NAMES its lane" both hold.

**Also updates ratified A13(4) — the graph-axis FOLD is demoted to REPORTING.**
A13(4)
(`power_station#a13-bead-pow-6ao-the-specify-stage-spec-readiness-committee`,
ratified Nico 2026-07-12) folded the retired `scope` rubric into `coherence`:
*"`scope`'s graph-collision half folded into `coherence`'s graph axis (its
decompose semantics ride the route's existing rework gate — the station has no
separate decompose verdict)"*. Dial 2 keeps the fold's HOME (the findings still
belong to the `coherence` lane, and no `scope` rubric returns) and changes its
EFFECT: the graph half stops moving a letter and rides the non-grading
`refinement` column to an operator instead. The decompose half of A13(4) is
UNCHANGED — an `F` from any lane is still the scope/decompose-class ruling that
escalates (A14(3), arm 2), and the codebase axis retains the one graph-shaped
`F` that is really a codebase fact (work a sibling ALREADY SHIPPED into this
tree). The receipt is A13(4)'s own reason for folding: `scope` was folded
because the station has no separate decompose VERDICT, never because tracker
hygiene should cost the spec author a band.

**Affects:** `packages/grid_assets/lib/src/code/fix_in_flight.dart` (new),
`refinement_flag.dart` (new), `committee.dart` (`kVerdictRefinementKey`,
`kVerdictRefinementInstruction`, `verdictJsonTemplate`'s `refinement` flag, the
decoder column, `CodeRouteCapability`'s matrix, the critic prompt's re-check
block), `respec.dart` (`SpecLane.refinement`, `SpecAdvance.fixInFlight`,
`refinementNotes`, `decideSpecRoute`'s `multi-action-grade` and single-`D`
arms, the route's file writes), `specify.dart`, `code_capabilities.dart`,
`readiness.dart`, `pr_composition.dart`, `grid_assets.dart`, the vended
`coherence.md` / `adr-alignment.md` rubrics and `spec-critic.md`. NO engine
change: `grid_engine` stays at `^0.3.0-rc.10` and its
`Advance`/`Escalate`/`RouteCapability` are consumed unchanged.

**HONOURS A34, A4 and A19 on the verdict transport.** The `refinement` column
rides the machinery
`power_station#a34-bead-pow-uok-a15-5-alt-a-s-round-stamp-gets-a-capability`
authored and changes none of it: `restampVerdictRound`'s `{...decoded}` spread
carries the column through a re-stamp with zero new code, and the column's read
is TOLERANT so A34(6)'s *"one and only place a malformed verdict fails the
lane"* is still `_verdictFromFile`'s strict decode. A34(2)'s
outside-the-swept-dir placement precedent is followed by the two new files,
which sit under `.grid/spec` beside the respec ledger. A4's `nodePath` fence,
its envelope fallback and its `transport` field are unchanged — the column is
read after the grade and before the fence, and mirrored onto the recovery paths
so a transport repair does not drop it. Per A19, the column is TAUGHT to the
spec family only and HELD on none.

**Status:** Accepted — ratified by Nico on 2026-07-18 in an interactive
session, recorded here (the bead's own instruction: cite as ratified in code
comments; do NOT mint a pending ADR-0000 amendment).
