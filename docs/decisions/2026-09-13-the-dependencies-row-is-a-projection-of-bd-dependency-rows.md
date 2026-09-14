---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-dependencies-row-is-a-projection-of-bd-dependency-rows
  surfaces:
    - "packages/grid_assets/lib/src/filing/**"
    - "packages/grid_assets/lib/src/search/station_search.dart"
  obsoletes:
    - filing-and-approve-share-one-state-root-seam
  updates:
    - state-root-takes-the-grid-home-and-unchecked-is-not-missing
  obsoleted-by: null
  updated-by: []
  bead: pow-f6pc
  legacy-id: null
---

# The dependencies row is a projection of bd's dependency rows, and nothing else

## Context and Problem Statement

`filing-and-approve-share-one-state-root-seam` ratified a prose DECLARATION
grammar: a description segment OPENING with `Blocked by`, `Blocked on` or
`Depends on`, whose `<prefix>-<tail>` tokens were read as bead ids by prefix or
by a digit tail. The `dependencies` requirement then COMPARED those names
against the bead's wired edges.

The grammar's failure mode is that a spelling decides an outcome. On
2026-09-13 the hyphenated `Blocked-by:` read as absence, which cost a duplicate
link bead, a false P1 and a withdrawn approval in one day; earlier, a refusal
fired on a receipt that merely QUOTED the phrase mid-sentence.

## Decision Outcome

**Ruling (Nico, 2026-09-13), under `the_grid#the-grid-is-a-beads-controller`.**
A blocker is a declaration bd holds. The prose declaration grammar RETIRES.
Bead text is never parsed for blockers again anywhere in `grid_assets`; a
`Blocked by` sentence is prose, and so is the hyphenated spelling that read as
absence.

`FilingContract`'s `dependencies` requirement becomes a pure PROJECTION of the
dependency rows bd holds for the bead — `DependencyProjection`. Local targets
are reported and judged by nothing: a same-store row is the origin store's own
`bd ready` business. `external:<project>:<capability>` rows are resolved
through the station ROSTER by name and reported ARMED or NOT ARMED. The row
REFUSES only what the roster cannot resolve.

There is nothing left to compare the rows against, and that is the point.

## bd owns the vocabulary; this package consumes it

`external:` is bd's own cross-project row, and `beads_dart` models it. This
package parses NOTHING of its own: `ExternalDepRef` (and its `parse`) classify
each row, and the record-vs-resolving control is `externalDepRowsFrom`. A
second spelling of bd's vocabulary in a downstream package is the duplication
`the_grid#the-grid-is-a-beads-controller` forbids, so the only types minted
here are the ones bd has no opinion about: the ROSTER answer
(`ExternalResolution`, `ExternalBlocker`) and the projection itself.

## The read moved to bd's record surface

`ExactSubstationBeadSource.readExact` issues ONE `bd query "id=<id>" --all
--json` through `BdCliService.queryGraph` and takes the bead AND the dependency
rows the record embeds. The `bd dep list` read and the two-shape row normalizer
it needed are DELETED.

This is not an optimization. `bd dep list` RESOLVES each row to the issue
record it points at, and an `external:` target has no issue in this store to
resolve to, so the resolving surface returns cross-project rows NOT AT ALL. A
dropped blocking row silently ADMITS the work it blocks, so the projection
reads the surface that carries them — and reconciles the two through
`beads_dart`'s own `externalDepRowsFrom`, which REFUSES when the record surface
returns nothing while the resolving read returns rows. That control is the only
case that still spawns a second `bd`.

## Fail-closed on an unresolvable external row

An `external:` row naming a project the roster does not arm REFUSES the
dependencies requirement, names the project and the armed roster, and says to
arm that substation or re-point the row. That is `the_grid`'s Q4 refusal at the
filing seam.

A roster that was never supplied refuses too — an unasked roster cannot clear a
cross-project blocker — and the detail says which of the two conditions it is,
because the two need different corrections.

## The roster is not part of the approval basis

`FilingReport.approvalRevision` digests the bead's work fields, its validation
plan, and the dependency ROWS bd holds. It does NOT digest the roster's answer
about them. The roster is the STATION's posture, not the bead's content, and
arming a substation must not revoke a governor's approval of a bead nobody
edited. This is the same principle the basis already held: it records the
proofs FOUND, never the posture of the lookup.

The mount gate therefore needs no roster: it compares a re-derived revision
against a stamped one, and that comparison is roster-independent.

## `--state-root` retires from `filing`, `approve` and `unpark`

The option existed on those verbs for ONE reader: the cross-store link beads in
the grid home's state store. That read is gone (grid_engine 0.4.0-dev.3,
the_grid#447) and the `dependencies` row now reaches no second store at all, so
the option is GONE from them rather than accepted and ignored — a verb that
takes a root it never reads teaches an operator that the root matters to its
answer. `park` and `show` keep it: they genuinely reach the state store's
session-lifecycle beads, and `kStateRootHelp` says so.

`power_station#filing-and-approve-share-one-state-root-seam` is OBSOLETED:
both of its halves are gone — the shared seam it describes has no reader on
those verbs, and the declaration grammar it ratified is retired.
`power_station#state-root-takes-the-grid-home-and-unchecked-is-not-missing` is
UPDATED, not withdrawn: its first half — the option takes the GRID HOME and
`resolveStateRoot` probes for `.grid`/`.beads` — is untouched and still governs
`park` and `show`. Only its second half, the unchecked-vs-missing arm, dies
with the read that produced it.

## This stays inside the filing-completeness lane

`power_station#approval-is-the-stamp-the-grid-approved-label-retires` holds:
*"FILING COMPLETENESS in `lib/src/filing/`, MOUNT ELIGIBILITY in
`lib/src/code/`, neither subsuming the other, no third completeness predicate
minted"*. The report still carries exactly four requirements with unchanged
wire names and order; `dependencies` changed its CONTENT, not its identity. No
fifth requirement and no second predicate is minted.

## Consequences

Every `grid.approved_rev` over a bead whose description NAMED a blocker
re-derives to a different digest, because the dependency basis changed shape.
Those receipts read as STALE and their beads need re-approval — the loud arm
rather than a silent pass. The basis PREFIX stays `filing:v1:sha256:`: a new
prefix is a v2 receipt SCHEME and its own bead, not a side effect of this row.

A bead that names a blocker only in a sentence now PASSES the dependencies row
and mounts unblocked. That is the ruling's own consequence: wiring the row is
the act, and the vended `intake-refinement` corpus says so in both overlay
legs.

No station threads its roster into `filing`/`approve` YET. The seam is
`armedSubstations` — `Set<String>? Function()`, defaulting to
`noArmedSubstations` — and the value it takes is the roster a station already
resolves through `codedRosterOf(delegateFactory)`. Until one passes it, EVERY
`external:` row refuses both verbs with the unconsulted detail: the fail-closed
arm working as ruled, and also a composition gap. Both `intake-refinement` legs
say so where the row is taught and again where the refusal is corrected, so an
agent that wires the row per the corpus reads its own refusal as a composition
gap instead of a bead defect. The live `AttachedRoster` this SDK provides
in-tree is NOT that value — it carries only RUNTIME-attached seats, so a coded
substation resolves as not-armed — which is why no seed in this package fills
the seam and why the mount gate deliberately needs none. Threading it is
`space-7tj`.

`space_station` does not compile at this bump until it moves:
`buildSpaceFilingCommands` passes `stateRoot:` to `FilingCommand`,
`ApproveCommand` and `UnparkCommand`, and that parameter is gone from all
three. Dropping it and passing the roster space ALREADY resolves through
`codedRosterOf(delegateFactory)` as `armedSubstations` is the whole migration,
and it is what closes the gap above.

The GitHub workflow-run intake supplies no roster, so a self-authored record
carrying an `external:` row refuses its preflight fail-closed and the refusal
lands in the bead's notes, unstamped.

## Touches

`packages/grid_assets/lib/src/filing/filing_contract.dart`,
`packages/grid_assets/lib/src/filing/filing_command.dart`,
`packages/grid_assets/lib/src/filing/approve_command.dart`,
`packages/grid_assets/lib/src/filing/park_command.dart`,
`packages/grid_assets/lib/src/filing/state_root_option.dart`,
`packages/grid_assets/lib/src/search/station_search.dart`,
`packages/grid_assets/lib/src/assets/composition_assets.dart`,
`packages/grid_assets/lib/grid_assets.dart`,
`packages/grid_assets/extension/station_overlay/claude/skills/intake-refinement/SKILL.md`,
`packages/grid_assets/extension/station_overlay/agents/skills/intake-refinement/SKILL.md`,
`packages/github_grid_assets/lib/src/intake/github_intake_store.dart`.

Public symbols added: `DependencyProjection`, `ExternalBlocker`,
`ExternalResolution`, `noArmedSubstations`, and the `armedSubstations`
parameter on `FilingContract.evaluate`, `FilingService.inspect`/`check`,
`ApproveService.approve`, `UnparkService.unpark` and the three commands.
Public surface REMOVED with no compatibility arm: the `stateRoot` parameter of
`FilingCommand`, `ApproveCommand` and `UnparkCommand`, and the
`--state-root` option on the `filing`, `approve` and `unpark` verbs. `bd dep
list` also stops being called on the exact read.
