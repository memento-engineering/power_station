---
status: accepted
date: 2026-08-24
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a32-skills-home-s-placement-split-is-stale-every-vended-skil
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A32"
---
## A32 (2026-08-24) — SKILLS-HOME's placement split is stale: EVERY vended skill lives under the station_overlay tree; audience is manifest metadata, never a placement axis

**Decision (AI; supersedes the ratified SKILLS-HOME rule's placement clause, pending Nico).** The 2026-07-14 SKILLS-HOME rule's on-disk split (agent → flat `extension/skills/<name>/SKILL.md`; operator → `extension/station_overlay/.claude/skills/<name>/SKILL.md`) no longer describes the tree or the installer, and citing it ships uninstallable assets. Two verified facts: (1) power_station commit `4b217ed` (2026-07-13, refs pow-kzx/A23) re-homed `discover` — the ecosystem's ONLY agent-audience skill, A12's own subject — out of flat `extension/skills/` into the station_overlay tree, where it lives today (`extension/station_overlay/claude/skills/discover/SKILL.md`); nothing has lived at flat `extension/skills/` since. (2) The installer (`grid_assets` `OverlayInstallService` / `loadStationOverlaySourceFromPaths` / `OverlayMaterializer`) materializes ONLY files under a `station_overlay` root — a flat `extension/skills/` file is never installed by `assets install`. The rule going forward: ALL vended skills live under `extension/station_overlay/<mapping>/skills/<name>/SKILL.md` (the `claude`-vs-`.claude` source form is the pack's `station_overlay.mappings` style choice; both are schema-valid); `audience:` in `extension/mcp/config.yaml` remains load-bearing exactly as A24 ratified it — the deny-list keeping operator skills out of build-agent briefs — but it dictates VISIBILITY, never path. Detected by swift-infer-1gt's spec_review coherence lane (grade F, 2026-08-24), which caught a spec following the stale clause verbatim into a non-installable placement.

**Why.** A54's precedent: when a ratified mechanism fails in live operation, ship the correction and record the reversal as pending rather than silently rewriting the ratified record. The placement clause was ratified describing an intended split whose implementation converged differently the day before ratification; the audience split's real value (A24's deny-list) survives intact.

**Affects (if promoted):** the SKILLS-HOME register-foot rule (placement clause only); every future pack's skill placement (butane_grid_assets and swift_infer_grid_assets already comply); no code changes — the tree and installer already implement this.

**Status:** Pending — Nico promotes or rejects.

