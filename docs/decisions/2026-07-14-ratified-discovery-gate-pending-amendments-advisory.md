---
status: accepted
date: 2026-07-14
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: ratified-discovery-gate-pending-amendments-advisory
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---
## RATIFIED — DISCOVERY GATE: pending amendments are ADVISORY, not binding (2026-07-14, Nico)

Nico's ratification, resolving the A21-vs-CLAUDE.md conflict that thrashed the pow-vvr / vendor-content work. At the discovery/violation gate (A21 / pow-96y), a **PENDING** ADR-0000 amendment is **ADVISORY ONLY** — surfaced as context for the spec committee's `adr-alignment` lane, NEVER grounds for a discovery HOLD. Only a **RATIFIED** standard (a ratified ADR, or an amendment whose Status is Ratified) can trigger a hold.

This **supersedes A21(2)'s** clause "the citable standard is a ratified ADR (its pending `A<n>` amendments included — they bind)", and aligns the gate with the org CLAUDE.md (amendments are candidates for ratification, not binding until ratified).

The gate additionally grades a bead's **INTENT** — a bead whose plan/acceptance REMOVES a cited offence PASSES (it is the fix), rather than holding on mere text-presence — per A21's own principle that "only an unwitting contradiction gates."

Implemented by **pow-d7i**.

