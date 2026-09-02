---
status: accepted
date: 2026-07-07
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A8"
---
## A8 (2026-07-07) — bead `tg-kx1`: the D-H doctrine rides the coding-agent working agreement + a new power_station `CLAUDE.md`; the Track F `GitHubGridAssets` ambient read is corrected to the SUBSCRIBING build verb

**Decision:** the companion to the_grid's `GridDelegate` D-H fix (Nico review, 2026-07-07) is carried into power_station three ways.
(1) **The D-H genesis_tree doctrine is appended to `buildAgentBrief`'s working agreement** (`packages/grid_assets/lib/src/code/code_capabilities.dart`) — the ONE prompt every coding agent this station spawns receives — as a tight four-bullet block (watch deps, never `??=`-cache reactive state / no public synchronous accessor over `StateNotifier` state, re-project as `InheritedSeed` + observe in `build` / config = VALUES in the tree, impls = DI / guards LOUD or GONE), scoped with a one-line "when you touch genesis_tree / grid code" lead-in and an ADR-0008 cite. It rides in the `workingAgreement` (static text, no bead/path interpolation), so it survives the Q3′ reference-inflation fence (Track E) untouched.
(2) **power_station gains a `CLAUDE.md`** (the repo had none since the split) whose `## Conventions` section carries the same four D-H bullets alongside the memento house set + bd rules, mirroring the_grid's `CLAUDE.md` shape. This was a placement call: the task said "add to power_station CLAUDE.md conventions," and with no file present, creating a tight, real CLAUDE.md (not a full org-map essay) was the faithful minimum.
(3) **The Track F audit fix.** `GitHubGridAssets.buildWithChild` (`packages/grid_assets/lib/src/assets/composition_assets.dart`, A7 point 3) read the ambient `ServiceBundle` GitGridAssets provides via the NON-subscribing effect verb (`getInheritedSeedOfExactType`) inside a `build` method — the same sync-notifier-read class the D-H fix names. Since `GitGridAssets` watches `SubstationScope` (`SubstationScope.of` = `dependOn*`) and re-provides a fresh `ServiceBundle` on a scope change, a snapshot-reading `GitHubGridAssets` would NOT rebuild and would keep re-providing a bundle wrapping the STALE source control. Corrected to `dependOnInheritedSeedOfExactType<ServiceBundle>()` (the build verb) so a re-provisioned bundle re-enriches. `sourceControlOf(TreeContext)` is LEFT on the effect verb (`get*`) — it is the effect-boundary resolver (the successor to `ServiceBundle.sourceControlFor`, called at a capability's `spawn`/`run` edge), where the non-binding read is correct per ADR-0008 D3.
**Why:** the doctrine is already ratified (the_grid ADR-0008's D-H); this bead PROPAGATES it, so no new doctrine is invented — only its application (which build read violated it, where the doctrine text lives) is an autonomous call. The audit surfaced exactly one instance of the class in the landed Track F file; the fix is the one-line build-verb swap the doctrine prescribes, and existing Track F tests (single build-pass) are byte-identical under it (a subscribing read returns the same value in one pass; it only additionally registers a dependency). The `CLAUDE.md` creation is the only net-new artifact and is flagged here so Nico can size it (fold into an org map, or keep as the seed of one).
**Affects (if promoted):** power_station code (built this bead): `packages/grid_assets/lib/src/code/code_capabilities.dart` (`buildAgentBrief` agreement + doc), `packages/grid_assets/lib/src/assets/composition_assets.dart` (`GitHubGridAssets` build-verb read + doc), new `CLAUDE.md`. the_grid: the `GridDelegate` D-H fix this companions; a future the_grid/genesis note could record that the coding-agent working agreement is where the D-H doctrine reaches every spawned agent.
**Status:** pending.

