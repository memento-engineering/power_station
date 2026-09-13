---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: state-root-takes-the-grid-home-and-unchecked-is-not-missing
  surfaces:
    - "packages/grid_assets/lib/src/filing/state_root_option.dart"
    - "packages/grid_assets/lib/src/filing/filing_contract.dart"
    - "packages/grid_assets/lib/src/filing/approve_command.dart"
  obsoletes: []
  updates: ["filing-and-approve-share-one-state-root-seam"]
  obsoleted-by: null
  updated-by: []
  bead: pow-ixag
  legacy-id: null
---
# `--state-root` takes the grid home, and an unchecked edge is not a missing one

## Decision Outcome

`--state-root` takes the GRID HOME — the value `--grid-home`,
`--state-workspace` and `--grid-root` already take everywhere else on the
runner, and exactly what `kStateRootHelp` has always documented.
`resolveStateRoot` appends the home's `.grid` state store when the selected
root holds one; a root that is already the state store (it holds `.beads`)
resolves to itself; a home holding both prefers `.grid`. The help line is not
rewritten to name `.grid`, because the option's contract is the home, not its
internals.

Before this, only the undocumented `.grid` form worked. The documented grid
home reached bd in the WORK store, where `list -t link --status open` dies on
`invalid issue type "link"` — the verb crashed on the value its own help named,
and every consumer had to know the undocumented one.

A selected root holding NEITHER child is refused by `StateError` naming the
root and both expected children, and both verbs render that refusal on stderr
with exit 1. Guards LOUD or GONE (`docs/adr/ADR-0008`): the silent arm of this
guard would read no link beads at all and report every wired cross-store
blocker as unwired — the same false fact this entry's second half removes.

## An unconsulted lookup is reported as unchecked, never as missing

`FilingContract.evaluate` takes `Set<String>? linkedBlockers`: NULL means the
state store was not consulted, an empty set means it was consulted and no link
matched. `FilingService.check` passes null exactly when `stateRoot` is null.

With the store unconsulted, only ids sharing the checked bead's own store
prefix may be called missing. Unwired foreign ids are reported through
`kUnconsultedCrossStoreDetail` — `cross-store edges not consulted — pass
--state-root` — alone, or after the genuinely missing local ids in the mixed
case. `missing outgoing blocks edges: <ids>` now asserts only what a consulted
lookup proved.

The old message asserted the edge was MISSING when the truth was that it was
never checked, and the vended `intake-refinement` corpus instructs a refiner on
exactly that string: *"wire each named id"*. A refiner reading it about a
blocker an open link bead already carries writes a duplicate — a wrong WRITE
driven by a read that never happened. That is why the two conditions get two
strings rather than a softened single one, and why both overlay legs of the
corpus now teach both details verbatim and pass the grid home in their `filing`
and `approve` examples.

## This stays inside the filing-completeness lane

`power_station#approval-is-the-stamp-the-grid-approved-label-retires` re-affirms
the boundary it inherits from
`power_station#the-refiner-exit-oracle-is-the-filing-verb`: *"FILING
COMPLETENESS in `lib/src/filing/`, MOUNT ELIGIBILITY in `lib/src/code/`,
neither subsuming the other, no third completeness predicate minted"*. Its
`register.surfaces` glob `packages/grid_assets/lib/src/filing/**` covers every
file changed here, and its Affects clause names `approve_command.dart` by name.

The unchecked arm is a refinement of the existing `dependencies` ROW — the
report still carries exactly four requirements, `FilingReport.passed` is
unchanged, and `mountEligibilityFindings` is not read, not called and not
duplicated. No fifth requirement and no second predicate is minted. The
`approve` verb still writes only the three `grid.approved_*` stamp keys and
still carries no `--add-label`.

`power_station#filing-and-approve-share-one-state-root-seam` is UPDATED, not
withdrawn: the option, its help, its `noStateRoot` default and its per-run
resolution still live once in `state_root_option.dart`, and both verbs still
ride it. Only the resolution grew a filesystem probe, and `ApproveCommand`'s
call moved inside the error boundary `FilingCommand` already had, so the two
verbs render the same refusal the same way. The read-only posture is retained
by construction: `query`, `dep list` and `list -t link --status open` remain the
whole argv surface.

## Consequences

The documented option value works, so a refiner and an operator can copy the
help. An unchecked cross-store edge is legible as unchecked and never produces
a duplicate wiring write. A misdirected `--state-root` fails loudly at the verb
instead of silently degrading the dependency row. A bead whose only blocker is
wired by a link bead still fails the preflight without a state root — that is
correct, and the message now says why.

## Affects

`packages/grid_assets/lib/src/filing/state_root_option.dart`,
`filing_contract.dart`, `approve_command.dart`, their three focused filing
suites, both `station_overlay` legs of `intake-refinement/SKILL.md`, and
`test/assets/skill_assets_test.dart`. Public symbol added:
`kUnconsultedCrossStoreDetail`. Signature changed:
`FilingContract.evaluate`'s `linkedBlockers` is now `Set<String>?`, defaulting
to null (unconsulted) rather than to an empty set.
