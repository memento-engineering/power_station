---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: github-intake-files-open-and-unstamped
  surfaces:
    - "packages/github_grid_assets/lib/src/intake/**"
  obsoletes: []
  updates: ["intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel"]
  obsoleted-by: null
  updated-by: []
  bead: pow-5wo
  legacy-id: null
---
## GitHub intake beads are filed OPEN and unstamped; the defer-9999 departure closes (2026-09-03) — bead `pow-5wo`

**Decision (AI).** `BdGitHubIntakeStore`
(`packages/github_grid_assets/lib/src/intake/github_intake_store.dart`) stops
parking admitted GitHub intake beads on `9999-12-31`. It files them OPEN, with
no `defer_until` and no approval marker of any kind. ABSENCE of the approve
verb's `grid.approved_*` stamp IS the pending state: readiness-based rather
than time-based, and it never fires on its own. The mechanism is the removal of
one argument — `BdCliService.create` takes `DateTime? defer`, so omitting it
drops `--defer 9999-12-31` and changes nothing else about the argv.
`GitHubIntakeStore.upsertDeferred` is renamed `upsert`, because a method named
for a behaviour the store no longer has is drift; this is breaking on a
published surface and rides `0.1.0-rc.8`.

**The store writes NO approval marker.** Not the retired `grid.approved` label,
and none of `grid.approved_by` / `grid.approved_at` / `grid.approved_rev`.
`packages/grid_assets/lib/src/filing/approve_command.dart` stays the only
writer of the stamp `mountEligibilityFindings` reads, so an intake bead is
mountable only after a human runs the approve verb.

**The parent epic `pow-1rn`: its INVARIANT is preserved, its MECHANISM is
superseded.** The epic's ratified design clause (4) THE TRUST MODEL says:
*"No external actor may ever mint ready work; everything lands deferred and
blessing stays the human lever."* Its closed child `pow-1rn.4` restates it as a HARD
INVARIANT: *"nothing arriving from GitHub ever mints a ready bead. Everything
lands deferred; approval stays the human lever."* This entry keeps the first
half of both sentences and retires the second. Two reasons, in order:
(a) `docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md` D1 was
ratified by Nico on 2026-08-12 — AFTER the epic's design (2026-08-07) and after
`pow-1rn.4` landed (#110, 2026-08-10) — and retires deferral as the pending
mechanism org-wide, so the epic's wording is superseded by a later ratified
decision rather than contradicted by this bead; (b) the epic's OWN refinement
note already relocated the enforcement away from this producer: *"ENGINE/SDK
owns … the invariant that origin-untrusted work cannot enter the ready frontier
without explicit approval … WHY IT MATTERS: if github_grid_assets enforces
'never mint ready', a bug in the NEXT external producer breaks it."* That is
exactly what `mountEligibilityFindings` does today, and it is where the
invariant now lives.

**Stated plainly, because it is the real behavioural delta:** an admitted intake
bead now BECOMES VISIBLE to `bd ready`, where the parking date previously hid
it. It does NOT become driveable. The mount gate refuses it with `approval: not
approved - run the approve verb`, and `packages/github_grid_assets/test/intake/intake_pending_state_test.dart`
pins both directions — the unstamped bead is refused, and the same bead with a
`validation_plan` and the three stamp keys is accepted. Visibility in a human's
work list is the intended outcome of ADR-0004 D1; mountability is not, and is
still gated.

**This CLOSES the departure declared by**
`power_station#intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel`
(accepted 2026-09-02, bead `pow-0nvg`), which recorded: *"The `9999-12-31`
parking date is nevertheless carried forward UNCHANGED by `pow-0nvg`, which is
a hygiene bead that moves argv and changes no behaviour … `pow-5wo` owns the
replacement lifecycle."* That entry's MECHANISM half — all three surfaces ride
`BdCliService`, and metadata is written per key on the follow-up `update`,
never as one whole object — is untouched and still binds; this bead consumes
it. Only its DEPARTURE half is retired.

**Alignment.** ADR-0004 D1: *"A date is a TIMER, not a decision: it cannot say
why, and it fires whether or not anyone approved. Work is filed OPEN with the
fields that make it driveable"* and *"Readiness is a property of the bead's
FIELDS — which is what the mount-eligibility predicate exists to compute."*
This entry IMPLEMENTS D1 for the last remaining producer and departs from
nothing. `power_station#approval-is-the-stamp-the-grid-approved-label-retires`
supplies the field that carries readiness, and its safety invariant is
PRESERVED. `power_station#a33-bead-pow-158-record-the-adr-0004-d1-split-guard-retireme`
retired the same flag from `discover` and `intake-refinement`; this is the third
and last producer.

**Migration is deliberately NOT in scope.** ADR-0004's own "What this does NOT
decide" says of beads already parked by date: *"They stay parked until touched;
nothing sweeps them automatically."* The 139 intake beads carrying
`defer_until 9999-12-31` in the swift-infer (51) and butane_flutter (88) stores
— measured 2026-09-02 — are cleared by an operator script run on Nico's word
(`bd -C <store root> update <bead id> --defer '' --actor operator`; note that
`--status open` alone does NOT clear the date). Neither store is in this
checkout and no bead data is mutated by this change.

**Affects:**
`packages/github_grid_assets/lib/src/intake/github_intake_store.dart`
(`_intakeDeferral` deleted; `GitHubIntakeStore.upsertDeferred` renamed
`upsert`), `lib/src/intake/github_intake_projection.dart`,
`lib/src/assets/github_reconciler_binding_assets.dart` (doc comment only), and
the suites `test/intake/github_intake_store_test.dart`,
`test/intake/github_intake_projection_test.dart`,
`test/intake/intake_pending_state_test.dart` (new),
`test/github_reconciler_binding_assets_test.dart`,
`test/github/github_reconciler_test.dart`. Public symbol renamed:
`GitHubIntakeStore.upsertDeferred` -> `GitHubIntakeStore.upsert`. No symbol
added. No change under `the_grid`, `grid_assets`, or any live bead store.
