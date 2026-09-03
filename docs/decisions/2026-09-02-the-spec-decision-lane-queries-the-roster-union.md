---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-spec-decision-lane-queries-the-roster-union
  surfaces:
    - "packages/grid_assets/**"
  obsoletes: []
  updates:
    - "a13-bead-pow-6ao-the-specify-stage-spec-readiness-committee"
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---
# The spec committee's decision lane queries the ROSTER union

## Context and Problem Statement

The spec committee's decision lane read only the CURRENT repository's register.
Its lookup was a shell loop — `for register in docs/adr docs/decisions; do …
find … -exec grep -li …` — rooted at the worktree, so a decision recorded in a
SIBLING substation's register was structurally unreachable while grading. The
discovery decision lens and the cheap intake lens read the same local-only
surface.

Bead `space-my4` is the proof. It carried a file-system-watcher approach
through readiness, specify, a PASSING decision grade (A), discovery, and into a
build — while directly contradicting
`the_grid#a50-the-dev-mode-reload-tool-extending-adr-0001-d6-s-tool-en`: "**The
trigger is explicit only** — an in-process filesystem watcher (an auto-reload-
on-save would fire mid-build on a resident `--land` station) and a bare OS
signal (un-introspectable) were both rejected." That substation keeps no
`docs/adr` at all, so no local grep could ever have surfaced the contradiction.
The lane graded a spec internally coherent and correctly decided, against a
register it could not see. Decisions span repositories; the lens was repo-local.

The union lookup itself was already built and vended: `decisions index
--surface <repo>/<path>` resolves the live mounted-substation roster through
the grid adapter and returns every mounted register's entries. What was missing
was COMPOSITION — this pack still composed the local-only lane.

## Decision Outcome

The `adr-alignment` lane is replaced on the LIVE spec path by
`decision-alignment`, whose lookup is the composing station's roster-mode
`decisions index --surface <repo>/<path>`, run once per unique roster-qualified
path in the spec's own `## Touches` section. This UPDATES A13(4), which mapped
`adr-alignment` over the substation `docs/adr/` register with ADR-0000 `A<n>`
amendments binding; A13 remains in force for everything else it decided (the
deterministic gating lane, the `SpecCriticCapability` subclass, the transport
stack).

1. **No register-directory argument is ever rendered, and that omission is
   load-bearing.** It is what makes the grid adapter resolve the live roster
   and return the union rather than only this repo's register. Every rendered
   surface — the specify brief's `## ADR Alignment` instruction, the spec
   critic's live-tree verification, the discovery offence gate and decision
   lens, the intake lens — states this, and `kDecisionLookupRule` is the single
   string all of them embed.
2. **A sibling register's entry binds exactly as a local one does.** The rule
   and the rubric both require retaining results from every `originRegister`,
   and citing by the canonical `<repo>#<slug>` identity (a migrated entry's
   `register.legacy-id` still resolves).
3. **An empty union is a real result; a CRASHED lookup is not.** A lookup that
   fails or exits non-zero must be reported verbatim and never graded clean —
   roster mode currently aborts the whole index on a malformed entry in any one
   mounted register, and reading that crash as "no decision applies" would ship
   the same blindness in a new form.
4. **Surfaces are derived from the spec's OWN `## Touches` section**
   (`rosterQualifiedSurfaces`), never from title keywords: the lane cannot
   mis-derive its own scope, and lookup stays deterministic while judgement
   stays in the rubric.
5. **The frozen migration shapes keep the local-only lane.** A16(2) forbids a
   frozen shape following a future rename, so `circuit_migration.dart` keeps
   its literal `adr-alignment` step and rubric ids and
   `extension/rubrics/adr-alignment.md` stays on disk. Its retirement note now
   names that rubric as a co-retiring artifact.
6. **The canonical rubric is VENDORED, not depended on.** `PackagedAssetLoader`
   resolves rubrics only from this package's `extension/rubrics/`; there is no
   cross-pack rubric merge, and `decisions_grid_assets` is not a dependency of
   `grid_assets`. The copy carries two memento-local additions the pack's own
   fences require: the `## Ownership` section (A37) and Dart/house-set
   grounding. It also states "binds on write; there is no advisory tier" where
   the canonical text says "there is no pending state" — this pack fences the
   word `pending` out of every rendered register instruction.
7. **No second roster resolver is introduced.** The lane renders the station's
   own `decisions index` verb rather than resolving a roster in Dart, so
   `mountedRosterOf`/`codedRosterOf` (A11) stay the single Dart roster surface
   and the A11(1) offline mount happens exactly once, inside the adapter.

### Consequences

- **Benefit.** A decision recorded in ANY mounted substation now binds this
  committee. The `space-my4` shape — a spec adding a file-system watcher to a
  surface a sibling register governs — is caught rather than graded A, and the
  fixture in `test/decision_alignment_lane_test.dart` fails if the local-only
  read is ever restored.
- **Cost — a second copy of the canonical rubric.** `decisions/rubrics/
  decision-alignment.md` and this pack's vendored copy must be kept in step by
  hand until a cross-pack rubric merge exists.
- **Cost — a moved cursor key.** The step id moved with the rubric id (they
  must stay equal; the route joins a lane by reading `.grid/critique/<id>.json`
  at `<parent>/<id>`). A survivor mid-`spec_review` finds no cursor key at
  `decision-alignment`, which the frontier reads as `pending`, so the lane
  re-runs. A read-only critic re-grading is harmless, and A16's guard against
  spec-phase RE-ENTRY for a bead already mid-BUILD is not reachable this way.
