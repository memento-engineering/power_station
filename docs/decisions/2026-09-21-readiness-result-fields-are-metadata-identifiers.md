---
status: accepted
date: 2026-09-21
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: readiness-result-fields-are-metadata-identifiers
  surfaces:
    - "packages/grid_assets/lib/src/code/readiness.dart"
    - "packages/grid_assets/test/readiness_test.dart"
  obsoletes: []
  updates:
    - "readiness-route-joins-on-a-published-verdict-never-on-absence"
  obsoleted-by: null
  updated-by: []
  bead: pow-d7cy
  legacy-id: null
---

# A result field this package writes is a metadata IDENTIFIER: the readiness route's source provenance is `source_state` and `source_path`

## Context and Problem Statement

Measured 2026-09-21 over lunar epoch 92 (grid_assets `0.7.0-dev.4` on
grid_engine `0.4.0-dev.11`, bd `1.1.0`): EVERY session minted under the wave
failed at the readiness route with `step.persistFailed op=advance` —
`BdUpdatePartialFailure: 1 of 1 issues failed to update` — retried three times
and gated. Three sessions across two beads, no exception. Sessions minted under
the previous wave and re-adopted kept advancing untouched. The lunar floors were
rolled back to `0.7.0-dev.2` at 21:10Z, which is what the wave cost.

The cause is a WIRE constraint the route's payload did not honour. A step result
persists through the engine's `ResultKeys.keyFor`, which renders
`grid.result.{encoded node path}.{field}` with the FIELD segment RAW. `bd`
refuses a metadata key carrying a hyphen, and it refuses the WHOLE update rather
than the offending key — so a single such field fails every write that step
makes, and the failure surfaces as a partial failure of one of one issues, which
names neither the key nor the reason.

`readiness-route-joins-on-a-published-verdict-never-on-absence` added exactly
two new fields, and spelled both with a hyphen: `source-state` and
`source-path`. Every field earlier waves wrote — `grade`, `transport`,
`pr_url`, `route_verdict`, `merged_sha` — happens already to be an identifier.
That is the whole reason the defect arrived with that wave and with nothing
else, and the reason it was invisible until the first session tried to advance.

The ENGINE-side half of this — validating the field at the writer and naming the
refusal, rather than letting a wire rule surface as an unattributed partial
failure — belongs to `the_grid` and is decided there. What this entry decides is
the spelling this package writes.

## Considered Options

* **Encode the field segment at the writer** (percent- or dash-escape it) so any
  name is legal. Rejected: the key shape is the engine's, published and read by
  other consumers; a second encoding applied at one consumer desynchronises
  every reader of that key and moves a shared contract inside one pack.
* **Keep the hyphenated names and add a compatibility read** for both spellings.
  Rejected: there is nothing to migrate. `bd` refused every write, so the
  hyphenated keys never persisted on any bead, in any store; a shim would read a
  key that has never existed and would keep a refused name alive in the code.
* **Drop the two fields** and carry the source only in the escalation prose.
  Rejected: the provenance is load-bearing on the PASSING arm, where there is no
  prose — it names which of the three states decided and the exact path read.

## Decision Outcome

**Every field name this package hands to a step result is an identifier matching
`^[a-z0-9_]+$`, because that name is rendered into a `bd` metadata key raw.**

1. **The readiness route's source provenance is `source_state`, `source_path`
   and `transport`.** The VALUES and the semantics are unchanged: `source_state`
   is still `PRESENT`, `source_path` is still the canonical verdict path the
   route read, `transport` is still the candidate's own transport.
2. **The three-state route is untouched.** Passing drives, a present failing
   grade holds with the refinement ask verbatim, and absence waits or fails
   loudly. This entry narrows the SPELLING of two payload fields inside the
   passing arm and decides nothing else about the join.
3. **No shim, no dual write, no dual read.** The hyphenated spellings never
   persisted, so nothing anywhere reads them; carrying them would preserve a
   name the wire refuses.
4. **The complete field set is fenced by a test**, not by review. The readiness
   suite pins the route's payload keys exactly and asserts each against the
   identifier alphabet, with the refused spelling as the negative control — so a
   new field has to be enumerated and spelled for the wire before it can ship.

**Why a rule and not a rename.** The rename alone would fix this one wave and
leave the next new field exactly as exposed, because the constraint is invisible
at the call site: the payload is an ordinary Dart map, hyphens are legal in it,
and the refusal appears much later, on another machine, as a count. Naming the
alphabet — and pinning it where the fields are written — is what makes the
constraint checkable at the point a field is added.
