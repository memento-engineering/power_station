---
status: accepted
date: 2026-09-02
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: approval-is-the-stamp-the-grid-approved-label-retires
  surfaces:
    - "packages/grid_assets/lib/src/code/mount_eligibility.dart"
    - "packages/grid_assets/lib/src/filing/**"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates: ["the-refiner-exit-oracle-is-the-filing-verb"]
  obsoleted-by: null
  updated-by: []
  bead: pow-vwny
  legacy-id: null
---
## Approval IS the `grid.approved_*` stamp; the `grid.approved` label retires (2026-09-02) — bead `pow-vwny`

**Decision (Nico, ratified in the bead, 2026-09-02):** *"kill the label … we are
going to be using the approved_* flags moving forward and dropping the blanket
approval and the deferral hack."* `mountEligibilityFindings`
(`packages/grid_assets/lib/src/code/mount_eligibility.dart`) reads THREE
clauses — driveable type, non-empty `validation_plan`, and `isApprovalStamped`
— and never reads `bead.labels`. Its refusal is
`approval: not approved - run the approve verb`. `kApprovedLabel` is deleted and
the `approve` verb writes only the three stamp keys.

**Why one encoding.** A bead carried FOUR encodings of "not yet": `status:
deferred` plus `defer_until`, the `grid.approved` label, the
`grid.approved_by/at/rev` stamp, and bd history. The label and the stamp are the
same act written twice, and the duplication cost real time — a label any writer
can add mounted work ahead of its blockers (`pow-n6n`, which #159 answered with
a second gate), and then that second gate refused hand-labelled beads SILENTLY
(`work.mountEligibilityRefused` flares once per bead per boot and no operator
surface reports it), so `lenny-f7nx.6` sat ready 5.5 hours on 2026-09-02. One
marker only the verb can write ends both failures.

**What this updates.** `power_station#the-refiner-exit-oracle-is-the-filing-verb`
(accepted, 2026-09-02) describes mount eligibility as "driveable type,
`validation_plan`, and the STAMPED `grid.approved` label". The LABEL half of
that clause is withdrawn; the stamp half is all that remains. The entry's
load-bearing content — the two-contract boundary (FILING COMPLETENESS in
`lib/src/filing/`, MOUNT ELIGIBILITY in `lib/src/code/`, neither subsuming the
other, no third completeness predicate minted) — is untouched and still binds.
The filing preflight is not modified by this bead, and `intakeFindings` in
`lib/src/code/readiness.dart` remains the distinct intake gate.

**Alignment.** `docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md`
D1: *"Readiness is a property of the bead's FIELDS — which is what the
mount-eligibility predicate exists to compute."* The stamp is such a field, and
the predicate still computes readiness from fields alone. D2: *"Approval
ceremony must never be the reason a station sits idle"* — the 5.5-hour hang is
exactly that failure, and collapsing two markers into one removes it. D3
(*"An ADR departure is RECORDED, not blocking"*) is the mandate for this entry.
`power_station#a33-bead-pow-158-record-the-adr-0004-d1-split-guard-retireme`
justified retiring `--defer` from `discover`/`intake-refinement` because the
predicate *"already refuses beads missing `grid.approved`"*; that safety
invariant is PRESERVED and strengthened — the predicate now refuses every bead
missing a verb-written STAMP, which no hand edit can forge, so no timer staging
returns.

**Affects:** `packages/grid_assets/lib/src/code/mount_eligibility.dart`,
`lib/src/filing/approval_stamp.dart` (`kApprovedLabel` deleted),
`lib/src/filing/approve_command.dart` (no `--add-label`), the vended
`governor.md`, `discover/SKILL.md` and `intake-refinement/SKILL.md`, and the
suites `test/mount_eligibility_test.dart`, `test/filing/approve_command_test.dart`,
`test/track_f_composition_assets_test.dart` and `test/assets/skill_assets_test.dart`.
Public symbol removed: `kApprovedLabel`. No symbol added.
