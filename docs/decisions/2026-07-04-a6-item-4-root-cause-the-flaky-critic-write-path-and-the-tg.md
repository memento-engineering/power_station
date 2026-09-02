---
status: accepted
date: 2026-07-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a6-item-4-root-cause-the-flaky-critic-write-path-and-the-tg
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A6"
---
## A6 (2026-07-04) — item 4 (root-cause the flaky critic write path) and the tg-83y intra-round-ordering variant are left UNRESOLVED, documented rather than guessed at

**Decision:** the bead asked to "root-cause the flaky write path itself (critic cwd? turn budget exhausted before the write tool call? prompt drift?)." No conversation transcript for either live incident (tg-x1j r3 / tg-42f r1) was available from this worktree to distinguish the three hypotheses, and static review of `committee.dart`/`agent_harness.dart` found no engine-imposed turn cap or cwd anomaly that would explain it either way. Rather than assert a root cause I could not verify, I documented the open question in `committee.dart`'s header and shipped the two fixes (A4) that close the SYMPTOM regardless of which hypothesis is true. Separately, the bead's notes describe a THIRD incident class (tg-83y r3 — an intra-round ordering bug: critics graded a tree the agent was still editing) as needing a the_grid-side fix (gating the `review` mount on the agent's durable completion); I judged this genuinely out of this bead's power_station-only worktree scope, since every capability here trusts the ambient `Workspace`/bead state the_grid's engine hands it at entry and has no way to independently verify "is this the durable, final tree."
**Why:** the working agreement scopes this bead to `packages/grid_assets` (power_station); the_grid's own session/reconcile sequencing lives in a sibling repo this worktree cannot touch. Guessing at a root cause not visible from this vantage, or attempting a fix in the wrong repo's engine, seemed worse than a clearly-flagged open item.
**Affects (if promoted):** none directly — a future the_grid ADR/bead (the review-mount-fencing fix) would be the actual landing spot; this entry is a paper trail for why tg-bns's diff doesn't attempt it.
**Status:** pending.

