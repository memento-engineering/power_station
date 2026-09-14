---
status: accepted
date: 2026-09-14
decision-makers:
  - "governor (lunar station seat)"
consulted: []
informed:
  - "Nico Spencer"
register:
  spec: 1
  slug: notes-are-receipts-and-a-phantom-legacy-token-is-reported-not-failed
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
  obsoletes: []
  updates:
    - decision-surface-evidence-selects-bead-names-before-index-order
  obsoleted-by: null
  updated-by: []
  bead: pow-rrlf
  legacy-id: null
---

# Bead notes are receipts, not citations, and an unresolvable legacy ADR token in prose is reported, never a failed surface

## Context and Problem Statement

`decision-surface-evidence-selects-bead-names-before-index-order` made three rules that together produce a false hold: the searched bead fields are description, design AND notes; an explicit `ADR-<nnnn>` id with no index record FAILS the surface; and a failed surface holds the round at discovery. Notes are the operator's receipt channel — a governor writing "reverted the ADR-0000 amendment" or quoting a hold reason into a note is recording history, not citing a decision — and the register's own file name (`ADR-0000-ai-decision-register.md`) yields a bare `ADR-0000` token that no register can ever hold. Measured on lunar 2026-09-13/14: pow-9g0o, pow-wbhb, tg-d15o (twice) and pow-g4zh itself — the bead filed to fix this — each held at discovery on a token that lived only in notes or in prose about the phenomenon; seven rounds burned. The readiness lens on pow-g4zh (round 07kk7z) correctly held the fix because it contradicts the ratified clauses and no entry decided which way to go.

## Decision Outcome

Citation extraction reads description and design only. Notes contribute no decision requests: a `repo#slug` or `ADR-<nnnn>` token present only in notes yields nothing, while the same token in description or design still does.

An explicit legacy `ADR-<nnnn>` id that resolves to no entry in any register is REPORTED in the gather's evidence — naming the source field and a bounded excerpt around the token — and does not fail the surface or hold the round. A canonical `repo#slug` that resolves to nothing under a register the index contains keeps the existing rule and fails with the missing name, because that form is unambiguous authorship of a citation.

pow-g4zh lands under this entry; the rest of the updated decision (named-before-fill selection, the 96-entry bound, TRUNCATED semantics) stands.

### Consequences

* Good, because a receipt written by an operator can no longer hold a round, and the register's own file name stops being a phantom citation.
* Good, because a real misspelled legacy id is still visible in the evidence, where a lens can read it, instead of hidden behind a hold.
* Bad, because a bead that cited a legacy entry ONLY in its notes must now cite it in the description or design to have it gathered; the filing verb's citation row already asks for that.
