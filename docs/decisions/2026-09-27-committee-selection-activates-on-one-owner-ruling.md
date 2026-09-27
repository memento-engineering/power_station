---
status: accepted
date: 2026-09-27
decision-makers:
  - "Nico"
  - "governor"
consulted: []
informed: []
register:
  spec: 1
  slug: committee-selection-activates-on-one-owner-ruling
  surfaces:
    - "packages/grid_assets/lib/src/code/committee_selection.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-clq2
  legacy-id: null
---

# Committee selection activates on one owner ruling

## Context and Problem Statement

Selective committee routing has run in shadow since the 2026-09-03 owner direction: every round records the lanes it would have elected while the full spec and code committees stay authoritative. The activation bead under the adaptive-committee epic required, for every rule, a separate owner ruling consuming a structured per-rule evidence packet before that rule could suppress a lane. Measured 2026-09-27 over the seventeen surviving shadow receipts, the rules as written elected the full committee on fifteen rounds, and the spec committee costs about a third of station inference while running roughly 3.8 rounds per spec produced. A per-rule ruling ceremony would delay every saving behind a human docket for each rule.

## Decision Outcome

Activation is ONE decided owner ruling, not a ruling per rule. Once the deterministic per-run classifier exists and its shadow receipts show which lanes it elects and why, the owner rules once that the classifier's elections become authoritative for both review stages; the receipt keeps recording elected and omitted lanes with the rule that omitted each, deterministic gating lanes are always elected, and a respec round re-runs only the lanes that returned an action grade. No per-rule evidence packet or per-rule docket is required; the receipts are the evidence and the owner can revoke the single ruling the same way.

### Consequences

* Good, because the saving ships behind one ruling instead of one docket per rule, and the receipt still shows every omission.
* Bad, because a single ruling activates every rule at once; a bad rule is caught by the committee grades and the receipt rather than by a pre-activation packet, so the first weeks after activation need the grade distribution watched.
