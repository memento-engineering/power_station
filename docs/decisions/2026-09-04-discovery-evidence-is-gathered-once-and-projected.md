---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: discovery-evidence-is-gathered-once-and-projected
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/extension/prompts/discovery.md"
  obsoletes: []
  updates:
    - "a21-bead-pow-96y-the-discovery-circuit-a-nested-read-only-ga"
    - "the-spec-decision-lane-queries-the-roster-union"
    - "a23-bead-pow-kzx-the-station-overlay-delivery-lib-renders-an"
  obsoleted-by: null
  updated-by: []
  bead: pow-ri9c
  legacy-id: null
---
# Discovery evidence is gathered once and projected by capability

`AnchorsCapability` remains the single deterministic gather. Once per discovery
round it writes one round-stamped canonical evidence profile, including explicit
truncation, unavailable-source, and lookup-failure states. The three existing
lenses receive bounded capability-specific projections and synthesize only that
evidence; they do not repeat tree, decision-index, prior-art, or history reads.

This updates the roster-union decision only in placement: its exact
`decisions index --surface` command and cross-register semantics are preserved,
but the deterministic gather executes the command before fan-out and the
decision lens consumes the persisted result.

The roster-union lookup moves earlier without inventing an executable. An
injected `DecisionIndexSource` is the in-process composition seam; where this
pack has only a shell, `buildCodeRegistry` passes the station invocation from
`overlayArgs['runner']` into `commandDecisionIndexSource`. The gather never
falls back to a literal binary name. A blank runner records the decision source
as unavailable and performs no shell call.

That is a deliberate, narrow departure from A23(4), which binds `runner`
in-store from `kDefaultOverlayRunner` (`'space'`) so an unconfigured station
still installs a working vended skill. A23(4)'s default is untouched and still
right where it is: it RENDERS prose into a materialized skill, where a wrong
verb is legible to whoever reads it. This decision governs the other use — the
pack EXECUTING that verb itself and grading the result as evidence — where the
same default is a hazard rather than a convenience. On a station whose verb is
`dart run lunar:lunar`, `space` exits 127, and under the gate below a crashed
lookup would hold every bead naming a roster-qualified surface. So the executing
path takes no default at all.

This updates A21(3) with a narrow distinction. An absent lens remains MISSING
and eventually advances as A21 requires. Required evidence that is TRUNCATED or
FAILED is a known non-answer: it overrides a clean-looking report, regathers the
affected lane once, and then holds. UNAVAILABLE means the optional service is
absent; it remains explicit in the projection and dossier, but the lens
narrates without it, its report stands, and no regather budget is spent — which
is A21(5)'s "NOBODY LOOKED" posture, applied to the decision index.
