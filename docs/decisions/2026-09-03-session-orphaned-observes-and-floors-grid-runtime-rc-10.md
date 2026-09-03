---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: session-orphaned-observes-and-floors-grid-runtime-rc-10
  surfaces:
    - "packages/grid_assets/lib/src/agent/agent_session.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/pubspec.yaml"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-1409
  legacy-id: null
---
## `SessionOrphaned` is an OBSERVATION on the flare sink, and it floors `grid_runtime` at rc.10 (2026-09-03) — bead `pow-1409`

**Decision (AI; MECHANISM only).** `AgentSession.onRuntimeEvent` gains an
explicit `SessionOrphaned()` arm that RECORDS and RETURNS. It emits an
`agent.sessionOrphaned` flare (`sessionId`, `pgid`, `memberCount`) on an
optional `ExplorationTransport`, injected into `AgentSession` and resolved in
`AgentCapability.createSession` from the ambient `ServiceBundle.transport`. It
writes NOTHING to the `ProcessSessionUpdate` stream, marks nothing terminal, and
neither schedules nor suppresses a respawn; the `Exited`/`Died` that follows the
provider's bounded grace remains the SOLE terminal. The switch stays exhaustive
with no `default` and no `_` arm.

**Why the arm is an observation and not a state change.** The upstream variant's
own contract fixes the semantics — it is *"Emitted ONCE per session, and NOT a
terminal: those survivors are still consuming resources and still mutating the
worktree, so the session stays supervised until the group empties or the bounded
grace elapses and the group is signalled."* Failing the session on it would
convert a non-terminal notice into a terminal and abandon supervision of live
members that are still mutating the worktree — the exact inversion the upstream
doc rejects. The choice of CARRIER follows from `AgentSession` owning only one
output channel: every value on `ProcessSessionUpdate` is a protocol observation
the cursor reads, and an orphan notice is neither protocol nor a cursor signal,
so it rides the out-of-band emit-only sink (D-8) instead. The sink is read at
`createSession` — an EFFECT edge, not a `build` — so the NON-binding
`getInheritedSeedOfExactType` is the correct verb per ADR-0008 D3, matching the
precedent `committee.dart` already sets for its own flares. A null transport
DROPS the observation rather than refusing: no guard is added, because a guard
here would protect no named invariant (guards LOUD or GONE).

**Decision (AI): the `grid_runtime` floor moves to `^0.2.0-rc.10`.** No single
source can be exhaustive over `RuntimeEvent` under both `0.2.0-rc.9` (no
`SessionOrphaned` symbol) and `0.2.0-rc.10` (with it), and the same candidate
added the `ProcessGroupController.groupMembers` member this pack's three test
fakes now implement — so neither half of this change compiles against rc.9. The
caret was admitting a candidate this pack cannot build against, which is the
failure the bead was filed to pre-empt. Per ADR-0003 D3 (every downstream
consumer resolves against the rc and runs `dart analyze && dart test`) this pack
IS that gate for the candidate, run ahead of the wave; per its 2026-08-05
correction the adoption mechanism is a semver constraint rather than a tag pin;
and per D6 (producers tag before consumers pin) flooring at an rc.10 that is not
yet on pub.dev is the correct ORDER, not a premature pin. `grid_assets` is
bumped to `0.6.0-rc.10` because `0.6.0-rc.9` is already published and its
CHANGELOG section describes a shipped release. This worktree resolves the
unpublished candidate through the machine-local `pubspec_overrides.yaml`
path-override that ADR-0003 D5 preserves for local co-development.

**Affects (if promoted):** `packages/grid_assets/lib/src/agent/agent_session.dart`
(the arm + the optional `transport` field),
`packages/grid_assets/lib/src/code/code_capabilities.dart` (the
`createSession` wiring), `packages/grid_assets/pubspec.yaml` (version + floor),
and this pack's three `ProcessGroupController` fakes. A different resolution —
a `default` arm, a `ProcessSessionUpdate` for the orphan, or a
back-compatible shim spanning rc.9 and rc.10 — would look different at all of
these surfaces. Consequence to carry: `grid_assets 0.6.0-rc.10` cannot publish
until `grid_runtime 0.2.0-rc.10` does, coupling this pack's release to that
wave; and a station that mounts no `ExplorationTransport` drops the observation
silently.

**Status:** pending.
