---
status: accepted
date: 2026-07-14
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: ratified-skills-home-cross-amendment-rule
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---
## RATIFIED CROSS-AMENDMENT RULE — SKILLS-HOME (2026-07-14, Nico)

Nico's ratification. Promotes **A12, A23, A24, A26** to **Ratified**. A vended skill's on-disk home follows its declared `audience` (`extension/mcp/config.yaml`):

- **agent** (invoked by a build agent; named in its brief) → `packages/grid_assets/extension/skills/<name>/SKILL.md` (A12).
- **operator** (for the human/governor operating a station; NEVER named in a build agent's brief) → `packages/grid_assets/extension/station_overlay/.claude/skills/<name>/SKILL.md` (A23 established the overlay tree → A24 the audience split → A26 the root-relative `.claude/` form).

Audience is declared in the manifest and enforced as a deny-list so a build agent's brief never offers an operator skill (A24(3)). Consequence: the `release` skill (pow-vvr) and the four station-operator skills are OPERATOR-audience; `discover` is AGENT-audience.

---

