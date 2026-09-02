---
status: accepted
date: 2026-07-20
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0001-packaged-ai-asset-skill-command-coupling
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "ADR-0001"
---
# ADR-0001 — Packaged-AI-Asset = coupled skill + command

**Status:** **DRAFT** — proving out over the next few days (Nico, 2026-07-10). Not yet Accepted; the
first instances (below) are the dogfood. Nico ratifies the promotion Draft → Accepted once the
pattern holds in practice. Recording bead: `pow-p94`.

## Context

An agentic asset (a skill, an agent definition, rubric prose) often needs a *mechanical* operation as
part of its job: search the attached substation stores, grep a repo's ADRs, cross-check epic
siblings, pin a diff. Left to the agent, each of these is re-derived by **inference** every run —
which is nondeterministic where it has no business being: the same query yields different coverage run
to run, silently misses a store the roster mounted, and drifts as the model changes. The operation is
not a judgement call; it is a lookup.

The `the_grid/docs/SCRATCH-pub-capability-and-repo-split.md` CLI-SDK model already establishes that
tool exposure rides shared/exported **Commands**, and that a Command must be a thin adapter over
UI-drivable lib logic ("logic is never on the Command"). This ADR names the pattern that couples that
Command surface to the agentic assets that consume it.

## Decision

A Packaged-AI-Asset in `grid_assets` vends a **coupled pair**:

- an **agentic file** (skill / agent-def / rubric prose), shipped via the D-9 Packaged-AI-Asset
  loader, and
- a **deterministic Command**, exposed by the composing grid instance via the CLI-SDK
  `..addCommand(...)`.

**The skill CALLS the command** rather than re-deriving the operation by inference. A grid instance
that adopts the asset gets both, wired — e.g. `space_station` gets `space search <query>` and
`/discover` together.

Constraints on the Command half:
- **Thin adapter over UI-drivable lib logic** (the layering redline) — a Flutter app could invoke the
  same service.
- **Roster-aware, read-only across foreign stores** — resolves the attached/resident substations from
  the resident-station context at run time (never a hardcoded list); honors the A37
  read-only-foreign-store fences.
- **Structured results** — the skill parses a schema, never scrapes prose.

**The line:** lookup → command; judgement → the agentic half. Do not wrap a genuine judgement
(grading, design, "is this the right next step") in a command; do not leave a mechanical lookup to
inference.

## First instances (the proving ground)

| Half | Bead | What |
|---|---|---|
| Command | `pow-ovh` | `search` — queries the attached/resident substation stores; `space search <query>` |
| Skill | `pow-88p` | `discover` — the HITL front door; **calls** `space search` (depends on `pow-ovh`) |
| Applies to | `pow-6ao` | `specify` — its ADR-grep / sibling cross-check are the **next commands** to vend |

## Consequences

- **Determinism where it belongs.** Coverage of a cross-store search stops depending on the model's
  mood; the agentic budget is spent on judgement, not on re-inventing a lookup.
- **Reuse.** The same lib service backs the CLI, a future UI, and every skill that needs the
  operation — one implementation, one test surface.
- **A new obligation per asset.** Vending an asset now means shipping *and maintaining* a Command +
  its lib service, not just prose. Worth it when the operation is mechanical and repeated; overkill
  for a one-off.
- **Open (to settle while proving out):** the result schema each command returns; whether code-grep
  rides `search` or a sibling command; how the resident-station context exposes the attached-substation
  set to a Command at run time (ties to the roster, `space-6ds`).
- **The missing leg — skill DELIVERY / installation (`pow-kzx`), RESOLVED to skill-file install.**
  Print-mode audit (2026-07-10): the harness spawns `claude --dangerously-skip-permissions -p <brief>`
  — **non-`--bare`, so it discovers `.claude/skills/`, and skip-permissions allows the `Skill` tool.**
  Print mode supports only **explicit `/skill-name`** invocation (no autonomous selection) — fine here,
  because the station composes each stage's brief and names the skill. So delivery = **materialize the
  vended `SKILL.md` into the worktree's `.claude/skills/` at provision (+ the operator's dir at setup)
  and have the brief invoke it** — *not* MCP or injection (MCP is reserved for autonomous, un-briefed
  tool use). `extension/` still needs a `skills/` home added; the skill body then calls its vended
  Command via Bash. Full detail on `pow-kzx`.

## Safety rails

Read-only across foreign stores (A37); roster-driven, never hardcoded; doc-before-code; **Nico
ratifies** Draft → Accepted.
