---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: observation-durability-rides-the-cursor-document
  surfaces:
    - "packages/github_grid_assets/lib/src/github/reconciler_cursor.dart"
    - "packages/github_grid_assets/lib/src/github/github_reconciler.dart"
  obsoletes: []
  updates: ["the-intake-cursor-caches-pull-heads-beside-its-etags"]
  obsoleted-by: null
  updated-by: []
  bead: pow-oe97
  legacy-id: null
---
## Observation durability rides the cursor document, acknowledged per delivery leg (2026-09-03) — bead `pow-oe97`

**Decision (AI; MECHANISM only).** The pending/delivered delivery states of a
GitHub observation live in `GitHubReconcilerCursor` (a new `pending` field), not
in a sibling store beside `FileGitHubCursorStore`. One `GitHubCursorStore.save`
of `cursor.deliver(id)` flips pending to delivered atomically through the
existing temp-write-then-`rename`; a two-document design would need two writes
with a crash window between them, and would re-express the file store's
absolute-path guard, atomic rename and versioned decode a second time.
`hasObserved` keeps its meaning: it is the DELIVERED check, never the pending
one.

**The document stays version 1, EXTENDING
`power_station#the-intake-cursor-caches-pull-heads-beside-its-etags` rather than
departing from it.** That decision holds that *"`pull_heads` is ADDITIVE and its
absence decodes to an empty cache. A version bump is rejected because
`GitHubReconcilerCursor.fromJson` throws on `version != 1`: bumping would make
every cursor already on disk at a live seat unloadable and stop that seat
polling."* The same rule governs `pending`: absent decodes to an empty queue, so
a live seat upgrades in place. A `pending` present but not a list is refused with
a `FormatException` — additive is not permissive, and the guard is loud or it is
gone.

**Acknowledgement is per delivery leg, because one observer is not idempotent
across a restart.** A pending entry carries an `acked` list; the reconciler's own
sink is the reserved leg `sink` and every observer registers under a name
(`GitHubReconciler.addObserver(leg, observer)`, a duplicate or reserved name
refused with `ArgumentError`). A replay drives only the legs that have not acked.
This exists for `CiFeedbackProjection`
(`packages/github_grid_assets/lib/src/github/ci_feedback_projection.dart`), which
the resident composition registers as an observer in
`lib/src/assets/github_grid_assets.dart` under the new leg `ci-feedback`. Its
`_handled` guard is IN-MEMORY and a restart empties it; two of its three effects
survive a re-drive (`grid.landing_ready=true` re-writes one key to the same
value, and `createCapGate` reuses the deterministic id
`<beadId>-ci-rework-cap`), but the third does not — `decideCiFeedback` recomputes
`round` from the live exported ledger, and a rework that already succeeded has
incremented it, so a re-drive would mint a SECOND rework round against
`kMaxReworkRounds` for one CI failure. Per-leg acks remove that exposure without
changing the projection's own behaviour: it gains a leg-name constant and
nothing else.

**Replay is a step of `reconcileOnce`, not a coordinator operation.**
`GitHubReconcilerRuntime._run` already wraps the whole cycle in
`GitHubPollCoordinator.schedule(installationId, ...)`, so replaying at the top of
`_reconcile` runs under the poll's own installation quota slot, and the first
cycle after a process restart IS the startup replay. A separately scheduled
replay would double the installation's start rate for no gain.
`github_reconciler_runtime.dart` is unchanged.

**Head-of-line blocking is chosen deliberately.** A leg that keeps throwing keeps
its observation queued and keeps the cycle failing, so the runtime's failure
observer flares every poll and the seat stops advancing. The alternative —
skipping past a stuck observation — is the at-most-once silent loss this change
removes.

**No ADR-0004 D1 interaction.** D1 retires deferral "as a PENDING/QUEUEING
mechanism" for BEAD readiness. The queue recorded here is a transactional
durability buffer inside one poll cycle, holding transport observations that have
not been acknowledged; it decides nothing about a bead's mount eligibility,
readiness or scheduling, and it never writes a date. The intake sink's own
far-future parking date is untouched by this bead and remains `pow-5wo`'s call.

**Affects:** `packages/github_grid_assets/lib/src/github/reconciler_cursor.dart`,
`packages/github_grid_assets/lib/src/github/github_reconciler.dart`,
`packages/github_grid_assets/lib/src/github/ci_feedback_projection.dart`
(leg-name constant only),
`packages/github_grid_assets/lib/src/assets/github_grid_assets.dart` (four call
sites), `packages/github_grid_assets/test/github/github_reconciler_test.dart`,
`packages/github_grid_assets/test/github/file_cursor_store_test.dart`,
`packages/github_grid_assets/test/github/reconciler_delivery_test.dart` (new),
`packages/github_grid_assets/test/fixtures/pending_cursor.json` (new).
IMPLEMENTS
`power_station#intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel`:
the outbox sits ABOVE that channel and retries through it by re-entering the same
injected sink, so `github_reconciler.dart` and `reconciler_cursor.dart` import no
bd surface before or after this change, and no second write path to bd exists.
EXTENDS `power_station#the-intake-cursor-caches-pull-heads-beside-its-etags`
(same additive-at-version-1 rule). Departs from nothing.
