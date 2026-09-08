---
status: accepted
date: 2026-09-08
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: decision-surface-evidence-selects-bead-names-before-index-order
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
  obsoletes: []
  updates:
    - "discovery-evidence-is-gathered-once-and-projected"
  obsoleted-by: null
  updated-by: []
  bead: pow-mrg8
  legacy-id: null
---
# Decision-surface evidence selects bead names before index order

The decision-surface gather MUST select every decision named by the work bead before filling from roster-index order. The only searched bead fields are description, design, and notes. A returned slug may be named directly, by canonical `<originRegister>#<slug>` identity, or by its token-delimited legacy `A<n>` or `ADR-<nnnn>` prefix; partial-token matches do not count.

Each surface keeps at most 96 entries. Named entries retain index order ahead of unnamed fill entries. More than 96 named entries is a FAILED lookup rather than a partial named answer. After the named set is secured, omitted unnamed entries retain the existing TRUNCATED receipt, so growth past the cap remains a known non-answer.

An explicit reference (a canonical token under a register the index contains, or an `ADR-<nnnn>` id) that has no matching index record is FAILED with the missing name in the reason and is never represented as TRUNCATED; a bare legacy `A<n>` token or a canonical-shaped token under an unknown register never fails a surface. Existing slugs may be recognized from the returned register set, but arbitrary hyphenated bead prose is not inferred to be a missing citation.

This extends `power_station#discovery-evidence-is-gathered-once-and-projected`: `AnchorsCapability` remains the one deterministic gather, `commandDecisionIndexSource` remains its roster-mode read-only extension seam, and `DecisionSurfaceEvidence` plus `EvidenceState` remain the one evidence and completeness vocabulary.

## Unaffected: the round/session stamps and the sweep

`power_station#discovery-lens-reports-carry-the-round-and-the-wipe-sweeps` also
governs this surface and names `AnchorsCapability.run` among its symbols. It is
untouched and continues to rule unchanged. The gather's only change at that
symbol is threading the ambient work bead — already captured synchronously at
entry, before any await (ADR-0008 D3) — into the decision seam. No stamp, no
fence and no sweep moves: `_freshLensReport` still refuses a foreign `nodePath`
or a non-current round, `sweepStaleDiscovery` still keeps exactly this session's
current-round reports, and the route's lane classification is the same. Nothing
here is a departure from that decision, and it is not updated by this one.
