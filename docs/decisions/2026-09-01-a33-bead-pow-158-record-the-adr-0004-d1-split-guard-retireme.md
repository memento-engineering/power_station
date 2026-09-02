---
status: accepted
date: 2026-09-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a33-bead-pow-158-record-the-adr-0004-d1-split-guard-retireme
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A33"
---
## A33 (2026-09-01) — bead `pow-158`: record the ADR-0004 D1 split guard retirement

**Decision:** This amendment records `pow-158`'s deliberate departure from
ADR-0004 D1's historical same-change ordering. `space-05g` mounted the
`MountEligibilityAssets` predicate on 2026-08-21 without updating either
`discover` or `intake-refinement`; `pow-158` later retires `--defer` from both
skills together. The two safety conditions now hold—the predicate already
refuses beads missing `grid.approved`, and both skills change atomically
here—but they did not land in one historical change.

**Why:** After `space-05g` closed with the predicate half only, literal
compliance with D1's original landing order became impossible. Leaving the
skills on timer staging would keep operator guidance in conflict with the live
predicate. ADR-0004 D3 says the governor takes the correct action, records the
departure with the clause and reason, and moves on; this amendment is that
record.

**Affects (if promoted):**
`packages/grid_assets/extension/station_overlay/claude/skills/discover/SKILL.md`
and
`packages/grid_assets/extension/station_overlay/claude/skills/intake-refinement/SKILL.md`
replace timer staging with the already-enforced `grid.approved` transition;
the paired asset tests pin source rendering and operator installation. DEPARTS
from ADR-0004 D1's historical same-change ordering only; IMPLEMENTS D1's
paired-skill retirement and PRESERVES its predicate-before-teaching safety
invariant. No Dart public symbol changes.

