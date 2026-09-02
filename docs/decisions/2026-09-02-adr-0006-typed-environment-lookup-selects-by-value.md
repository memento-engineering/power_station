---
status: accepted
date: 2026-09-02
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0006-typed-environment-lookup-selects-by-value
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "ADR-0006"
---
# ADR-0006 — The typed environment lookup: a scope's environment is selected by VALUE, not by name

**Status:** **Accepted** — this document records a decision Nico ratified in the
**2026-09-02 routing interview**, filed on "let's file the epic" as the description of epic
`pow-n6n`. Like `ADR-0002`, it contains **no new decision of its own** — it TRANSCRIBES a
human-ratified decision, so none of it is minted as an ADR-0000 pending amendment (the org
register rule: do not log a collaboratively-reached decision).

**Why this is a NUMBERED ADR and not an ADR-0000 amendment.**
`docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md`, Consequences: "Nico's own
directives are ratified on arrival and belong in a numbered ADR — never in the AI register.
This ADR exists because that rule was violated when the directive was first recorded as an A31
amendment." `docs/adr/ADR-0005-landing-policy-grade-gated-auto-merge.md`, Ground, is the
standing precedent for applying that clause: "ADR-0004 D3 does not apply: this is a
twice-ratified human directive, not an autonomous governor departure. ADR-0004's Consequences
require Nico's directives to live in a numbered ADR and never in ADR-0000." ADR-0004 D3
therefore does not govern THIS document either. It governs the separate, AUTONOMOUS mechanism
choices the first implementing bead makes, which are filed as pending ADR-0000 amendment `A35`:
the policy is here, the mechanism is there.

**Supersedes:** `docs/adr/ADR-0002-agent-environment-layer.md` — its Decision preamble clause
"Selection resolves a NAME to an environment; a role points at an environment name; the ladder
overrides the name rung by rung" (line 71), and the matching line of its section "The ladder, as
settled" ("Each rung names an ENVIRONMENT; the more specific rung wins", line 170) — **for the
TYPED rung only**. Everything else in ADR-0002 STANDS and is untouched: D1's `ProviderSpec`-shaped
field set (this layer adds no field), D2 Dart-first, D3's site-binding split including "A step/bead
names a NAME. Only the SITE BINDING (D3) names a URL" (line 179 — the step and bead rungs still
resolve a name through `EnvironmentRegistry.resolve`, and no URL enters), D4's no-deprecations
deletion, and D5's per-substation arming (which this layer generalises rather than replaces). Per
the house precedent — ADR-0004 supersedes ADR-0000 clauses, ADR-0005 grounds itself on ADR-0004,
and neither EDITS the document it supersedes — ADR-0002's text is left byte-unchanged; this header
is the stamp.

**Recording bead:** `pow-n6n.1` (epic `pow-n6n`). The implementation is that bead and its
siblings `pow-n6n.2` (typed lookups at the six spawn sites), `pow-n6n.3` (the availability
seed) and `pow-n6n.4` (roles retire).

## Context

ADR-0002 settled WHAT an inference environment is — one complete, named value {harness,
target, model, transport} — and how a NAME is overridden rung by rung. It left the selection
key a string: a role points at an environment name, a seat's arming is a name, and every
composition-layer author writes that name by hand. Two costs followed. A name is unchecked at
the composition layer (a typo is a boot refusal at best, a wrong environment at worst), and
"which environment does THIS capability want" had no scope other than the role enum, so two
capabilities sharing a role could not diverge.

Nico settled both in the 2026-09-02 routing interview. The quotations below are from epic
`pow-n6n`'s description, filed in that session.

## Decision

### D1 — A lookup value is a PREFERENCE: an ordered list of environment VALUES, not names.

Verbatim: "A lookup value is a PREFERENCE: an ordered list of AgentEnvironment VALUES (the
existing value type: harness, target, model), not names. Canned sets are const Dart declared
beside the environments in the station's arming. No strings at the composition layer; the only
strings left are provider-facing wire values inside AgentEnvironment."

### D2 — The TYPE is the scope: an effective typed lookup, specific then generic, nearest ancestor wins.

Verbatim: "Every invocation of a model runtime resolves its environment by an EFFECTIVE TYPED
LOOKUP: the capability asks its TreeContext for its own specific type first
(SpecAgentEnvironment, CriticAgentEnvironment, GatherAgentEnvironment, BuildAgentEnvironment),
then falls back to the generic AgentEnvironment preference. The type is the scope; nearest
ancestor wins; a seat scopes by nesting under its Substation; the station default is mounted at
the root. No invocation key, no rule table, no node-path matching, no engine hook — the_grid
engine is untouched."

And the ladder, verbatim: "step params > bead grid.agent envelope > the typed lookup (specific
then generic) > ambient. The step and bead rungs stay as they are (they ride bead metadata)."

This is the clause that departs from ADR-0002's preamble: the typed rung does not NAME an
environment, it CARRIES one. The rest of the ladder keeps its name currency, so an
implementation converts a typed winner back to its registry name at the boundary rather than
letting a value leak into the transport key. HOW that conversion is done, and where legality is
enforced once selection no longer routes through a name, are MECHANISM and are recorded in
ADR-0000 `A35`, not here.

### D3 — Availability is PRESENCE IN THE TREE.

Verbatim: "Availability is PRESENCE IN THE TREE: a probing StatefulSeed mounts and unmounts
environment presence (harness binary present, endpoint reachable, model listed); the resolver
takes the first preference entry present in the ambient AvailableEnvironments set (value
equality). No probe cache, no try-then-fall-through."

### D4 — Same-class invocations that differ by DATA use an aspect-scoped lookup.

Verbatim: "Same-class invocations that differ by data (the critics, one class, four rubrics)
use an aspect-scoped lookup: CriticAgentEnvironment.of(context, lane:) over genesis_tree's
InheritedModelSeed (genesis-8zb, cross-store blocker of the critic child)."

### D5 — Roles retire; a dynamic workflow is the same type, not a second mechanism.

Verbatim: "Roles retire: AgentRole / AgentConfig.roleEnvironments (agent_harness.dart) and the
role rung in resolveAgentConfig (agent_domain.dart) are subsumed by the typed lookups; pow-t1w's
architect role folds into SpecAgentEnvironment." And: "Dynamic workflows later: a StatefulSeed
that rebuilds its typed value from runtime state — same type, same lookup, no second mechanism."

## Consequences

- ADR-0002's ladder gains one rung between the bead envelope and the (retiring) role rung, and
  its top-level selection key is no longer a string at the composition layer.
- The four sibling beads build it: `pow-n6n.1` (the value types, the effective lookup, the
  rung), `pow-n6n.2` (the four specific types at the six spawn sites plus D4's lane aspect),
  `pow-n6n.3` (D3's availability seed), `pow-n6n.4` (D5's role retirement). Station arming is
  space_station's companion bead.
- ADR-0002 D5's per-substation arming is GENERALISED, not undone: a seat still scopes by nesting
  an `InheritedSeed` under its Substation — the value it nests is now typed rather than a name.
- The autonomous mechanism decisions this layer required are ADR-0000 `A35` (pending). If Nico
  rejects `A35`, this ADR's policy stands and the mechanism is re-chosen.

## What this does NOT decide

- The mechanism of value-to-name conversion, of where legality is enforced, and of the rung's
  failure posture — ADR-0000 `A35`.
- `genesis-8zb` (`InheritedModelSeed` in genesis_tree), D4's cross-store blocker.
- Which environments a given station actually prefers: that is arming, composed per seat.
