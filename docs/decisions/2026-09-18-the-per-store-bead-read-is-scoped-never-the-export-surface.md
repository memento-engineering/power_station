---
status: accepted
date: 2026-09-18
decision-makers:
  - "governor"
consulted:
  - "Nico Spencer"
informed: []
register:
  spec: 1
  slug: the-per-store-bead-read-is-scoped-never-the-export-surface
  surfaces:
    - "packages/grid_assets/lib/src/search/station_search.dart"
    - "packages/grid_assets/lib/src/filing/filing_contract.dart"
    - "packages/grid_assets/lib/src/filing/filing_command.dart"
  obsoletes: []
  updates:
    - "a11-bead-pow-ovh-the-search-domain-roster-resolution-is-an-o"
  obsoleted-by: null
  updated-by: []
  bead: pow-l5ag
  legacy-id: null
---

# The per-store bead read is scoped, never the export surface

## Context and Problem Statement

`a11-bead-pow-ovh-the-search-domain-roster-resolution-is-an-o` built the
search domain on a mutation-free `SubstationBeadSource` seam over CORE-typed
beads of all statuses, and its argv used the bd export surface to read a whole
store at once. pow-usbw (filing checks presence, not viability) needs a second
per-store read — the filing id catalog that resolves every id a bead's text
names — and its spec (rounds 1–5, reviewed by the committee) settled on the
scoped read for both, recording the ruling under this identity. The register
entry was never created by a round, so the spec cited an identity that did not
resolve; the governor records it here so the round cites rather than creates.

## Decision Outcome

Every per-store bead read in `grid_assets` is a SCOPED bd query, never the
export surface. The SEARCH corpus reads one all-status `bd query` per store.
The FILING id catalog reads one `bd list -t <type> --status all --json
--limit 0` per stable `IssueType.coreTypes` value per store. Both reads stay
on the mutation-free `SubstationBeadSource` seam, CORE-typed beads only, all
statuses; source and argv fences (`no_bd_export_test.dart`) preserve the
distinction, and `a11`'s obsolete export argv is the only clause this entry
changes. No caller takes a `--state-root`; the roster resolves the stores.

### Consequences

* Good, because a store is read through the same scoped surface bd's proxied
  mode supports everywhere, and an export of a 9 GB store never happens on a
  filing check.
* Bad, because the filing catalog costs one `bd list` per core type per store
  — bounded by `IssueType.coreTypes`, and cached per filing run.
