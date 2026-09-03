---
status: accepted
date: 2026-09-03
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: ci-feedback-projection-is-a-value-the-binding-provides
  surfaces:
    - "packages/github_grid_assets/lib/src/assets/github_reconciler_binding_assets.dart"
    - "packages/github_grid_assets/test/github_reconciler_binding_assets_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-3q45
  legacy-id: null
---

# The CI feedback projection is a seat VALUE the reconciler binding provides

## Context and Problem Statement

`GitHubReconciler` already carries named delivery legs with per-leg durable
acknowledgement, and `_FeedbackBinding` already registers the reserved
`ci-feedback` leg. Nothing constructed the `CiFeedbackProjection` it routes to,
so `context.watch<CiFeedbackProjection>()` resolved null on every live seat and
every `CheckConcluded` was discarded. Only the missing PROVIDER was in question;
the delivery seam was not.

## Decision Outcome

`GitHubReconcilerBindingAssets` provides `InheritedSeed<CiFeedbackProjection>`
beside the cursor and intake-sink providers it already returns, so the value
mounts ABOVE both `GitHubReconcilerAssets` and `GitHubGridAssets` in the seat
stack and no downstream station composition changes.

The ambient `GridRoot` is read QUIET and SUBSCRIBING (`GridRoot.maybeOf`), not
with the loud `GridRoot.of`: absence of an enclosing grid root is the documented
offline/unit posture, and `projectCiFeedback` already encodes a null projection
as a no-op, so no invariant is left for a loud guard to protect. The one real
invariant stays loud — `GridStateStore.forGridRoot` still refuses a
non-absolute root.

The projection's `bd` runner is derived over the GRID STATE store
(`GridStateStore.forGridRoot(gridRoot).runtimeDir`), never the binding's
existing seat WORK-store `runner`, because the session beads a check is
correlated against live in the grid's state store. Two optional constructor
seams, `feedbackCommandSender` and `stateRunnerFor`, carry the production
default and let an offline suite substitute both.

No second dispatcher and no second registration are introduced: the reconciler's
outbox stays the only dispatcher and `_FeedbackBinding` stays the only caller of
`addObserver` for the `ci-feedback` leg.

### Consequences

* Good, because CI red on a station-opened pull request now reaches the rework
  rails on a live seat with no change outside this pack.
* Good, because a seat with no enclosing grid root, and an inert `dry`/`offline`
  arm, still bind intake exactly as before.
* Bad, because the projection is re-derived on every build of the binding seed,
  which empties its in-memory handled-key set; per-leg durable acknowledgement,
  not that set, is therefore the idempotency rail across a re-delivery.
