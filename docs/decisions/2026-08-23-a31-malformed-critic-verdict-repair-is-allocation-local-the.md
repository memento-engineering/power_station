---
status: accepted
date: 2026-08-23
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a31-malformed-critic-verdict-repair-is-allocation-local-the
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A31"
---
## A31 (2026-08-23) — malformed critic verdict repair is allocation-local; the second invalid artifact escalates while circuit crash supervision keeps its default budget

**Decision:** `_CriticAllocation` recognizes only `AllocationFailed` reasons beginning `result threw: invalid critic verdict at `. The first match starts one structured critic repair; the second match is converted to `AllocationEscalated`, so no grade and no restartable `AllocationFailed` reaches circuit supervision. `kCodeReviewCircuit` and `kSpecReviewCircuit` carry no explicit `maxRestarts`, preserving `Circuit`'s default budget of three for unrelated crashes. This uses escalation because resolved `grid_engine 0.3.0-rc.7` exposes no recoverability field on `AllocationFailed`; `CapabilityHost` persists `AllocationEscalated` through the latching escalation path. Unknown verdict read exceptions use the same named invalid-verdict path. Regex grade recovery, tolerant decoding, and a third critic process remain forbidden.

**Why:** A6 deliberately left the LLM write-path root cause unresolved and shipped boundary fixes that “close the SYMPTOM regardless of which hypothesis is true.” The tg-nlwo and pow-1rn.5 invalid-escape incidents are the same symptom class. Strict decode plus one bounded allocation-local repair extends that boundary posture without stripping ordinary restart supervision from unrelated circuit steps.

**Affects (if promoted):** `packages/grid_assets/lib/src/code/committee.dart` (`_CriticAllocation._receive`, `kCodeReviewCircuit`), `packages/grid_assets/lib/src/code/specify.dart` (`kSpecReviewCircuit`), and their critic/circuit tests.
**Status:** rejected — `pow-q5n` verified that `CapabilityHost._createAllocationOrFlare` routes every `ProcessCapability` through `ProcessLeaseVendor.lease.createAllocation(ctx)`; `CriticCapability.createAllocation` is therefore unreachable on the live station and its direct `ProcessAllocation` would bypass leased identity and crash adoption if invoked.

