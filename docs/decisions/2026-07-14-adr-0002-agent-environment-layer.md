---
status: accepted
date: 2026-07-14
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0002-agent-environment-layer
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "ADR-0002"
---
# ADR-0002 — The agent-ENVIRONMENT layer: named inference environments {harness, target, model}

**Status:** **Accepted** — this document records a decision Nico ratified in an interactive
design session on **2026-07-13**. It was authored under the org's DOC-BEFORE-CODE rule
(bead `pow-ebf.1`) ahead of the code that implements it. It contains
**no new decision of its own** — it TRANSCRIBES a human-ratified decision. Because a
decision reached collaboratively with Nico is already human-ratified, none of it is minted
as an ADR-0000 pending amendment (the org register rule — do not log a
collaboratively-reached decision).

**Supersedes:** the_grid `docs/adr/ADR-0008-authoring-sdk-and-reentrant-engine.md`
**Decision 10** ("the agent scope: harnesses over the agentic step") — its harness roster,
its `AgentConfig` D-C config ladder, and its `ModelTarget` sealed type as the top-level axis.
A companion the_grid bead stamps Decision 10 as superseded and strikes its
never-implemented "overridable per-substation" claim (see D5); that cross-repo stamp is NOT
made from this repo.

**Recording bead:** `pow-ebf.1` (epic `pow-ebf`). The implementation is its sibling beads
`pow-ebf.2`…`pow-ebf.6`.

## Context

`grid_assets` spawns agents — a coding build, a committee of critics, a read-only discovery
gather. Each spawn must know which tool runs, how the brief reaches it, where inference
happens, and on which model. ADR-0008 Decision 10 named the first form: an `AgentConfig`
{harness id, `ModelTarget`, params} carried as a tree value, resolved by a
station→substation→bead→step ladder, over a four-harness roster (claude, copilot, pi,
opencode).

Two forces have moved past that form:

1. **The model axis generalized.** ADR-0000 A20 split model selection by `AgentRole`, and its
   "REFINED FORWARD" footer named the successor: **role → tier → model** (bead `pow-2c9`) —
   a `ModelTiers` arming the current code already carries. The next rung, ratified here, is
   that a role selects not a bare model string but a complete, NAMED **environment**:
   {harness, target, model} together.
2. **gc already solved this, in production, richer than our first draft.** Gas City's
   `[providers.<name>]` table is exactly the named-inference-environment concept. Shaping the
   Dart types from its proven field set — rather than hand-rolling a smaller one and
   rediscovering its omissions one cut corner at a time — is D1 below.

This ADR is the umbrella decision. Its five parts (D1–D5) are each built by a sibling bead;
this document is the contract they implement.

## Grounding (the prior art this transcribes — not re-derived here)

- **gc's `ProviderSpec`** — `com.gastownhall/gascity`, `internal/config/provider.go:39`. The
  `[providers.<name>]` table is a named inference environment with inheritance (`base`),
  transport (`command`/`args`/`args_append`/`prompt_mode`/`prompt_flag`), a `path_check` for
  shell-wrapper commands, resume grammar (`resume_flag`/`resume_style`), and more. The
  environment value type's field set is SHAPED FROM this (D1) — not invented.
- **the_grid ADR-0008, line 65 (Amended 2026-06-28, ratified Nico):** "Dart-first for the
  dynamic half (formulas + capabilities at the existing seam); the TOML `PackInflater` is
  deferred (Decision 3's 'TOML *or* Dart' — **TOML is the lower-priority serialization**)."
  This is the ground of D2: the Dart type is the source of truth; a TOML/data front door is a
  later, mechanical parse surface onto the identical types. This ADR does NOT un-defer the
  `PackInflater`.
- **gc's site binding** — `internal/config/site_binding.go:154`
  (`SiteBinding{workspace_name, workspace_prefix, rig[{name,path}]}`): `city.toml`
  (committed) declares rigs by NAME; `.gc/site.toml` (machine-local) binds each name to a
  path on THIS box. The ground of D3.
- **ADR-0008 Decision 3 / M4-CONFIG-SUBSTRATE-BRAINSTORM #9** — "two front doors, one Seed
  tree": `Grid.fromToml` builds the SAME Seeds you'd author by hand. Corroborates D2.
- **bd memory `no-deprecations-until-public`** (Nico): "no deprecations. delete and
  undocument. until we go public, no deprecations for the_grid and its assets/instance." The
  ground of D4.

## Decision

An **AgentEnvironment** is ONE complete, named inference environment: which tool runs, how the
brief reaches it, where inference runs, on which model. Selection resolves a NAME to an
environment; a role points at an environment name; the ladder overrides the name rung by
rung. The five parts:

### D1 — Shape the environment value type from gc's `ProviderSpec` field set; do not re-invent it.

gc's `[providers.<name>]` table (`ProviderSpec`, `provider.go:39`) IS the named-environment
concept, in production and richer than this epic's first draft. The environment/harness value
type is SHAPED FROM its field set — `base` (inheritance, with the LOAD-BEARING tri-state
absent-vs-empty distinction), `command`/`args`/`args_append` (append ACCUMULATES across
layers; args REPLACES), `env`, `prompt_mode`/`prompt_flag` (the brief transport, as DATA),
`path_check` (the real binary to PATH-check when `command` is a shell wrapper — exactly the
hand-rolled FT-2 `sh -c` usage-capture case), and the resume grammar
(`resume_flag`/`resume_style`, whose gc doc comment already knows codex).

**Rationale:** we were demonstrably already rediscovering these omissions one at a time (the
FT-2 `sh -c` wrapper was built without noticing gc has `path_check` for exactly that).
Porting a proven field set, with an explicit line-by-line deferral audit for every field NOT
ported, prevents silent omission. *(The port + deferral audit is bead `pow-ebf.2`.)*

### D2 — DART-FIRST. The Dart type is the source of truth; TOML/data is a lower-priority parse surface, not a fork.

Nico: "we're always focusing on dart/runtime first and data/toml second. Static configs are
just a matter of parsing into our dart types." Already ratified — ADR-0008 line 65 (**"TOML is
the lower-priority serialization"**) and M4-CONFIG-SUBSTRATE-BRAINSTORM #9 ("two front doors,
one Seed tree").

**Rationale:** get the types right; the parser is downstream. This epic builds the DART TYPES
(shaped by D1). A TOML/data front door is a later, mechanical deserializer onto the IDENTICAL
types, added when a non-Dart author needs one. **This ADR does NOT un-defer the
`PackInflater`.**

### D3 — BOX CONFIG: adopt gc's SITE BINDING split. Committed code declares NAMES + semantics; a machine-local binding supplies MACHINE FACTS.

gc: `city.toml` (committed) declares rigs by NAME; `.gc/site.toml` (machine-local) binds
name → path on THIS box (`site_binding.go:154`). This design draws the same line one rung
down, applied to the ARMING itself:

- **COMMITTED Dart** declares WHAT ENVIRONMENTS EXIST and what a name means SEMANTICALLY
  (harness + model). Portable; identical on every box.
- A **MACHINE-LOCAL SITE BINDING** supplies the MACHINE FACTS — endpoints, ports, whether a
  local model even exists here. Never compiled in, never on argv, never in a bead.
- **An environment whose machine fact is UNBOUND on this box REFUSES AT BOOT** — loud, never a
  silent default. (The same failure class this codebase already kills: the no-wedge rule,
  "never a '' sentinel".)

A step/bead names a NAME. **Only the site binding names a URL.** Per D2 the site binding is a
Dart TYPE first; the file it parses from is a low-priority detail. *(The site binding is bead
`pow-ebf.6`.)*

**Rationale:** a URL on the command line is the same mistake as a URL in a bead — it makes
every box's `space up` line different and bakes a machine fact into portable config. space
already has this problem badly (substation roots are `../<repo>` relative paths baked into
`SpaceDelegate` plus a gitignored `pubspec_overrides.yaml`); this is the mature form of what
we already do implicitly.

### D4 — OPERATOR KNOBS: DELETE. No deprecations.

Nico (bd memory `no-deprecations-until-public`): "no deprecations. delete and undocument.
until we go public, no deprecations for the_grid and its assets/instance." So — DELETED and
UNDOCUMENTED, not carried, not projected:

- **`--openai-base` / `--swift-base`** — MACHINE FACTS. Deleted from argv; they move to the
  site binding (D3).
- **`--model` / `--grader-model`** — replaced by environment arming. DELETED, not
  deprecated-and-projected.
- **`AgentConfig.graderModel`** — self-documented as kept only so an unmigrated station keeps
  arming its critics, retiring "at that point." That point is NOW. Delete it. The transitional
  `ModelTiers` pre-tier projection that carried it (`armedTiers`) goes with role → tier when
  role → env replaces it.
- A20(2)'s no-wedge rule (an operator flag must never be SILENTLY ignored) is SATISFIED BY
  DELETION — a removed flag is a loud argparse error, not a silent drop. It was never a
  mandate to keep flags alive.

**Rationale:** the environment name replaces every one of these knobs; a machine fact belongs
in the site binding, not on argv. *(The deletions land with their replacements across beads
`pow-ebf.4`/`pow-ebf.5`/`pow-ebf.6`; `AgentConfig.graderModel` and `ModelTiers` retire when
role → env replaces role → tier in `pow-ebf.5`.)*

### D5 — PER-SUBSTATION ARMING: make it real. It is nearly free, and it is the only safe way to evaluate a new harness.

ADR-0008 Decision 10 already CLAIMS the config is "overridable per-substation." It is NOT:
`SpaceDelegate.build` mounts ONE `HarnessProvider` ABOVE the Substations fan-out
(`space_delegate.dart:183`) and no seat nests its own — a claimed-but-unexercised rung, a
doc/reality gap. `HarnessProvider` is an `InheritedSeed`, so a nested one ALREADY shadows;
making the rung real is a seat mounting its own:

```dart
Substation('power_station',
  HarnessProvider(config: ambient.merge(env: 'codex-frontier'), child: Nest([...])))
```

**Rationale:** beyond tidiness, per-substation arming is the ONLY safe way to EVALUATE a new
harness or a local model — arm ONE substation on it, let the committee grade both, compare —
instead of betting the whole org on an unproven harness. *(The bead/step rungs and role → env
are bead `pow-ebf.5`.)*

## The ladder, as settled

Each rung names an ENVIRONMENT; the more specific rung wins:

```
station default          (Dart, committed)
  -> substation seat      (D5 — a nested HarnessProvider; NOW REAL)
    -> bead               (the grid.agent envelope: env / harness / model)
      -> step             (StepArgs.params: env / harness)
```

A step/bead names a NAME. Only the SITE BINDING (D3) names a URL.

## What this supersedes in ADR-0008 Decision 10

Decision 10 stands as the origin of the harness vocabulary, the "config is a value, impls are
DI" doctrine, `AgentBrief`, and the two-moment (boot-eager + per-work fail-closed) validation
— all of which this layer KEEPS. What it SUPERSEDES:

- **The harness roster and `ModelTarget` as the top-level axis** → subsumed into the named
  `AgentEnvironment` (D1). `ModelTarget` (`ProviderManaged`/`OpenAiCompatible`/`SwiftInfer`)
  survives as the environment's `target` field; the endpoint URL it carried moves to the site
  binding (D3).
- **The D-C config ladder over `AgentConfig`** → becomes the ladder over an environment NAME
  (the ladder above), role → env replacing role → tier → model.
- **Decision 10's "overridable per-substation" claim** → was never implemented; D5 makes it
  real, and the companion the_grid stamp strikes the false claim.

## Consequences

- The sibling beads build it: `pow-ebf.2` (the `AgentEnvironment` value type + deferral
  audit), `pow-ebf.3` (the name → environment registry with base-inheritance), `pow-ebf.4`
  (the four `AgentHarness` classes collapse into declarative values — harnesses become DATA),
  `pow-ebf.5` (env at the bead/step rungs; role → env), `pow-ebf.6` (the site binding type).
- No `PackInflater` is un-deferred (D2); no TOML front door is built here.
- The deleted operator knobs (D4) leave no deprecation shims — a removed flag is a loud error.

## Still open (empirical, not design)

Does "gather" on a cheap/local model hold up in the discovery circuit, or does cheap-and-local
degrade citation quality below the cite-the-offence gate? D5 is the instrument that answers
this: arm one seat, compare grades. This is an empirical question the live arm answers, not a
design decision this ADR makes.
