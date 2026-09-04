---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: discovery-evidence-is-gathered-once-and-projected
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/extension/prompts/discovery.md"
  obsoletes: []
  updates:
    - "a21-bead-pow-96y-the-discovery-circuit-a-nested-read-only-ga"
    - "the-spec-decision-lane-queries-the-roster-union"
  obsoleted-by: null
  updated-by: []
  bead: pow-ri9c
  legacy-id: null
---
# Discovery evidence is gathered once and projected by capability

`AnchorsCapability` remains the single deterministic gather. Once per discovery
round it writes one round-stamped canonical evidence profile, including explicit
truncation, unavailable-source, and lookup-failure states. The three existing
lenses receive bounded capability-specific projections and synthesize only that
evidence; they do not repeat tree, decision-index, prior-art, or history reads.

This updates the roster-union decision only in placement: its exact
`decisions index --surface` command and cross-register semantics are preserved,
but the deterministic gather executes the command before fan-out and the
decision lens consumes the persisted result. It updates A21(3) with a narrow
distinction: an absent lens remains MISSING and eventually advances as A21
requires, while a typed statement that required canonical evidence is truncated,
unavailable, or failed regathers once and then holds. The latter is a known
non-answer, not absence and not a model verdict.
