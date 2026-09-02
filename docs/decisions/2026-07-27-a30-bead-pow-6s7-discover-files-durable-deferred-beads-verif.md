---
status: accepted
date: 2026-07-27
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a30-bead-pow-6s7-discover-files-durable-deferred-beads-verif
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A30"
---
## A30 (2026-07-27) — bead `pow-6s7`: discover files durable DEFERRED beads, verifies them through vended search, and uses A55 link beads for cross-store ordering — superseding A12(6)'s broken wisp promotion and false no-cross-store premise

**Decision:** A12(6)'s human-frontier invariant stands, but its persistence
mechanism is reversed. The discover skill creates a normal durable bead with
`bd create --defer <~1 week> --actor governor`; it never passes `--ephemeral`
and never attempts `bd update <id> --persistent`. Live reproduction on
2026-07-26 showed that `--ephemeral` mints a wisp outside the issues table, so
list, stats, vended search, and dependency foreign keys cannot see it even
though exact-id `bd show` and `bd update` resolve it. The documented persistence
update reports success without materializing the issue, while the actual
`bd promote` verb is unsupported in proxied-server mode in every armed store.
Deferral still keeps half-designed work outside the ready frontier, and only
the human blesses it by changing the defer state.

**Decision:** A12(6)'s statement that cross-store dependencies do not exist is
superseded by the_grid A44 and A55. Same-store homing remains the default when
one repository owns coupled work; repository ownership may require separate
beads in separate stores. Cross-store ordering is authored through A55's OPEN
grid-state `type=link` bead carrying
`grid.link.from=<blocked bead id>`,
`grid.link.to=<blocker bead id>`, and `grid.link.type=blocks`. Operators never
author the reversed A44 raw-foreign-id dependency row or run
`bd dep add <id> external:<project>:<capability>` for this purpose:
`bd doctor --fix` can classify that row as orphaned and sever it.
`StationJoinBridge._applyCrossLinks` projects valid link beads and the shared
`applyBlockGuard` enforces them; malformed links fail closed.

**Why:** this amendment follows A54's precedent for a ratified mechanism that
failed in live operation: ship the corrected mechanism and record the reversal
as pending for Nico rather than silently rewriting the ratified record. It
preserves A12's load-bearing staged/human-blessing outcome, replaces only the
unfindable promote-later implementation, and brings Filing into the A44/A55
cross-store model ratified after A12.

**Affects (if promoted):**
`packages/grid_assets/extension/station_overlay/claude/skills/discover/SKILL.md`
(Filing and design-approval prose),
`packages/grid_assets/test/assets/skill_assets_test.dart`, and
`packages/grid_assets/test/assets/overlay_materializer_test.dart`. No Dart
public symbol is added, removed, or renamed. SUPERSEDES ratified A12(6)'s
`--ephemeral`/`--persistent` mechanism and “cross-store deps do not exist”
premise; RETAINS A12(6)'s deferred staging and human-only frontier blessing;
CONSUMES the_grid A44's wiring reversal and A55's link-bead mechanism.

**Status:** Pending — Nico promotes or rejects.

