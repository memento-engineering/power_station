---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-worktree-overlay-scope-widens-to-every-skill-tree
  surfaces:
    - "packages/grid_assets/lib/src/assets/overlay_materializer.dart"
    - "packages/grid_assets/lib/src/assets/overlay_manifest.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - a26-bead-pow-hhs-the-station-overlay-becomes-a-root-relative
  obsoleted-by: null
  updated-by: []
  bead: pow-99g
  legacy-id: null
---

# The worktree overlay scope widens from one skill tree to every harness skill tree

## Context and Problem Statement

A26(4) scoped the worktree leg of the station_overlay to `.claude/skills`
alone, reasoning that "the scope is what keeps A23(6) true": a loose file such
as `.claude/settings.json` cannot be fenced by a per-asset-dir `.gitignore`, so
an unscoped leg would leak into the bead's PR or overwrite a tracked repo file.
The station now arms `--build-harness codex`, and Codex discovers skills at
`.agents/skills/<name>/SKILL.md`. With the scope naming ONE tree, the vended
skills install for the operator seat and never reach a codex build worktree —
silently, with nothing to warn on.

## Decision Outcome

`kWorktreeOverlaySubtrees` carries a SET of per-harness SKILL trees
(`.claude/skills`, `.agents/skills`) rather than the single claude tree, and
`AgentCapability._materializeStationOverlay` fences every subtree in that list
with A23(6)'s self-ignoring per-asset-dir `.gitignore` instead of only the
first. A26(4)'s load-bearing half is preserved verbatim: the worktree leg still
takes SKILL trees only, every path in scope still sits inside an `<id>/` asset
dir, and no loose file — including `AGENTS.md`, ruled unvended by Nico on
2026-09-02 — is materialized into a worktree. What is amended is the
enumeration, from one tree to the set.

The codex leg is authored as a byte-identical COPY of the claude leg under
`extension/station_overlay/agents/skills/`, pinned by test rather than by a
mechanism; the materializer gains no placement branching, so A26's
path-preserving invariant is untouched. The placement is grounded in the LIVE
tree, not in a pending amendment: `extension/station_overlay/claude/skills/`
is the undotted source form already on disk, and `kDefaultStationOverlayMappings`
(`overlay_manifest.dart`) already carries `agents -> .agents`, landed by
the closed+merged pow-1mp (PR #82). A32 proposes exactly this placement rule
but is PENDING (its body closes "Status: Pending — Nico promotes or rejects"),
so per `power_station#ratified-discovery-gate-pending-amendments-advisory` it
is treated as ADVISORY context here and is NOT relied on. The ratified
SKILLS-HOME rule's `.claude/skills` placement clause for operator-audience
skills is untouched by this entry, and whether the source form is `claude/` or
`.claude/` remains A32's open question for Nico, not this bead's to settle.

No copilot rendering is authored: Copilot CLI reads the claude and agents trees
directly. The unreachable `copilot -> .copilot` head is removed from
`kDefaultStationOverlayMappings`.

### Consequences

* Good, because a codex build agent now spawns with the same vended material a
  claude one does, and the fence is derived from the scope list rather than
  restated beside it, so the two cannot drift apart again.
* Good, because `.agents/` being partly repo-owned (`bd init` tracks
  `.agents/skills/beads/`) is safe by the materializer's existing never-clobber
  rule: a hand-authored file there is BLOCKED and receives no fence.
* Neutral, because the operator install leg (whole tree, unscoped) now also
  fills a station repo root's `.agents/skills/`; `OverlayInstallReport.installedSkillIds`
  stays scoped to `kClaudeSkillsSubtree`, so its reported id set is unchanged.
* Bad, because the codex leg is a duplicated copy of seven files, so every
  skill edit must land twice; the byte-identity test is what makes that loud
  instead of silent.
* Bad, because vendor skill-discovery paths churn (OpenAI has an unresolved
  regression where `$HOME/.agents/skills` stopped being discovered), so this
  scope list is a fact about someone else's product and will need revisiting.

### Confirmation

`cd packages/grid_assets && dart test test/assets/overlay_golden_test.dart
test/assets/overlay_codex_leg_test.dart` — the golden gate asserts a build
worktree receives both trees and no loose root file, and the codex-leg gate
asserts byte identity.
