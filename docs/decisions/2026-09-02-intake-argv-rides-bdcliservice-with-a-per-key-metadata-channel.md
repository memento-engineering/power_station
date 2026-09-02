---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel
  surfaces:
    - "packages/github_grid_assets/lib/src/intake/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-0nvg
  legacy-id: null
---
## The GitHub intake argv rides BdCliService, with a per-key metadata channel (2026-09-02) — bead `pow-0nvg`

**Decision (AI; MECHANISM only).** `BdGitHubIntakeStore`
(`packages/github_grid_assets/lib/src/intake/github_intake_store.dart`) stops
hand-building `bd` argv and stops parsing envelopes directly. All three of its
surfaces — the external-ref correlation read, the create, and the update — go
through `BdCliService` over the same injected `BdRunner`. The store keeps its
`BdRunner`-shaped constructor and builds the service internally, so no call site
moves.

**Metadata is written PER KEY, never as one whole object.** The four intake keys
(`github.node_id`, `github.kind`, `github.repository`, `github.actor`) ride
`BdCliService.update`'s merge channel — one set-metadata flag per key, whose
server-side merge overwrites named keys and preserves absent ones. bd's
whole-object create-time metadata form REPLACES the bead's map, which on the
update path would clobber `validation_plan` and the approval stamp that other
writers own on the same bead. No `replaceMetadata` parameter is minted. This
consumes, and does not re-decide,
`the_grid#bd-create-metadata-rides-a-follow-up-update`, which fixed the
create-time metadata write as an unconditional create-then-update pair; the
visible cost here is that the new-node-id path spends three spawns where it
previously spent two.

**DEPARTURE from `docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md`
D1 (status: Accepted, ratified by Nico 2026-08-12).** D1 says: *"This retires
deferral as a PENDING/QUEUEING mechanism — the 'park it until someone gets to
it' idiom that produced the 76 lapsed dates. It does not retire the ATOMIC
CREATE-THEN-WIRE GUARD in `discover` / `intake-refinement`, where the deferral
flag closes a seconds-wide mount race while dependencies are wired against a
live station."* This store is neither of those two skills, and A33
(`power_station#a33-bead-pow-158-record-the-adr-0004-d1-split-guard-retireme`)
has since EMPTIED that guard exception: it records that `pow-158` retires the
deferral flag from `discover` and `intake-refinement` together, because
`space-05g`'s `MountEligibilityAssets` predicate *"already refuses beads missing
`grid.approved`"*. So there is no exception left for this store to sit inside.
The `9999-12-31` parking date is nevertheless carried forward UNCHANGED by
`pow-0nvg`, which is a hygiene bead that moves argv and changes no behaviour.
Removing the parking date here would silently promote every admitted GitHub
issue into the live ready frontier in the same change that reroutes the argv —
a lifecycle decision, not a hygiene one.

**`pow-5wo` owns the replacement lifecycle.** `pow-5wo` ("Decide
ADR-0004-compliant pending state for GitHub intake beads", OPEN, `type=decision`)
is the bead where Nico rules on the GitHub-intake pending state; its own
acceptance already contemplates either removing the parking behaviour or
recording an explicit ADR-0004 D1 departure. This entry IS that record, filed in
advance so `pow-5wo` inherits a named departure rather than an unwitting
contradiction. ADR-0004 D3 governs the form: *"the governor TAKES the action,
records it as an ADR-0000 amendment naming the clause departed from and why, and
moves on"* — recorded here under `docs/decisions/`, which is where decisions are
written now.

**Affects:** `packages/github_grid_assets/lib/src/intake/github_intake_store.dart`
(`BdGitHubIntakeStore` loses its `const` constructor and its private argv/JSON
helpers; `GitHubIntakeRecord` and the `GitHubIntakeStore` interface are
unchanged), `packages/github_grid_assets/test/intake/github_intake_store_test.dart`,
and the spawn-count assertion in
`packages/github_grid_assets/test/github_reconciler_binding_assets_test.dart`.
DEPARTS from ADR-0004 D1; PRESERVES A30's durable-not-ephemeral filing shape
(no ephemeral flag is introduced). No change under `the_grid`.
