---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-handoff-ritual-vends-as-an-operator-audience-skill
  surfaces:
    - "packages/grid_assets/lib/src/assets/asset_loader.dart"
    - "packages/grid_assets/extension/station_overlay/**"
    - "packages/grid_assets/extension/mcp/config.yaml"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-pry0
  legacy-id: null
---
## The handoff ritual vends as an OPERATOR-audience skill (2026-09-03) — bead `pow-pry0`

**Decision (AI; a CLASSIFICATION under an existing rule, establishing no new
policy).** The vended `handoff` skill declares `audience: operator` and joins
`kOperatorSkills`, so no build agent's brief ever names it. Everything that
FOLLOWS from that — where the file lives, and that the deny-list is what
withholds it — is already settled by
`power_station#ratified-skills-home-cross-amendment-rule` (Nico's own
ratification, 2026-07-14): "A vended skill's on-disk home follows its declared
`audience` … **operator** (for the human/governor operating a station; NEVER
named in a build agent's brief) → `packages/grid_assets/extension/station_overlay/…/skills/<name>/SKILL.md`
… Audience is declared in the manifest and enforced as a deny-list so a build
agent's brief never offers an operator skill (A24(3))." This entry re-states
none of that and amends none of it. What it records is the one thing the master
rule cannot decide for a skill it has never seen: WHICH audience `handoff` has.

**Why the call had to be made here.** The bead names TWO requesters — the human
types `/handoff`, and the agent self-initiates at a boundary — while the
manifest's `audience` field is binary, so the reading is not mechanical. It
resolves to `operator` because the skill fails A24(3)'s one test twice over:
does the skill contradict the brief that would offer it? It writes to an Agent
Disc that exists at `<grid home>/.grid/seats/<seat>/`
(`the_grid#agent-disc-file-shape-and-home`) and nowhere else — a per-bead
worktree has no seats tree at all — and it ENDS a turn by asking the outer
harness to compact, clear, or relaunch the seat, where a build agent's working
agreement is to finish its bead and commit. The `agent` audience would hand
every build agent a documented way to stop early. The file still MATERIALIZES
into every worktree (A23: one tree, two consumers); only the NAME is withheld,
which is the whole of the guard.

**Consequence.** `kOperatorSkills` gains its first member that was never
re-homed from the composing station, so the `reHomed`-keyed equality in
`packages/grid_assets/test/assets/skill_assets_test.dart` widens by exactly one
id while the `reHomed` corpus itself is untouched. Placement is unremarkable:
`handoff` ships at
`extension/station_overlay/{claude,agents}/skills/handoff/SKILL.md` like every
other vended skill, which is where the master rule puts an operator skill and
where the installer — which materializes only under a `station_overlay` root —
can reach it. (`power_station#a32-skills-home-s-placement-split-is-stale-every-vended-skil`
reaches the same placement, but it is `**Status:** Pending` in its own body, so
per `power_station#ratified-discovery-gate-pending-amendments-advisory` it is
ADVISORY here and nothing above rests on it.)
