---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: roles-retire-typed-lookups-and-the-tier-subsume-the-role-map
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---
## Roles retire (2026-09-02) — bead `pow-n6n.4`: the typed lookup takes the ENVIRONMENT half of `AgentRole` and the declared `AgentTier` takes the MODEL half; nothing replaces the role itself

**Decision (AI; MECHANISM only).** The POLICY is
`docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md` D5 (Nico, ratified
2026-09-02): "Roles retire: AgentRole / AgentConfig.roleEnvironments
(agent_harness.dart) and the role rung in resolveAgentConfig (agent_domain.dart) are
subsumed by the typed lookups; pow-t1w's architect role folds into
SpecAgentEnvironment." This records the calls this bead made autonomously to carry it
out. (1) THE ROLE ANSWERED TWO QUESTIONS AND ONLY ONE OF THEM IS SUBSUMED — a role
selected an ENVIRONMENT (`roleEnvironments`, the role rung) and a MODEL CLASS
(`tierFor`). The typed lookup takes the first; the second stays, so the SPAWN SITE now
declares its `AgentTier` directly: `resolveAgentConfig` swaps `required AgentRole role`
for `required AgentTier tier`, which is exactly the value `tierFor(role)` was computing
for it. Every floor is preserved (frontier ⇒ build + spec author, mid ⇒ the three
critic lanes, cheap ⇒ the discovery lenses). (2) DELETING THE TIER DECLARATION TOO WAS
REJECTED — the only total floor left would be the frontier one, which would move ~18
critic spawns per bead onto `opus` and invert A20's ratified "grade cheap, build
strong"; and A20(3) ("no `fallbackModel` and no unpinned spawn", ratified) is true by
construction only because that floor is total. (3) `AgentConfig.stationModelFor` IS
DELETED, NOT REWRITTEN — it was A20(2)'s projection for a station's `up` banner, its
only remaining caller was its own test, and ADR-0006's Consequences carve station
arming and its banner to space_station's companion bead (`space-rz6`). (4)
`EnvironmentRegistry.validate`'s `roleEnvironments` parameter is RENAMED `armedNames`,
not deleted — it is a label-agnostic `Map<String, String>` carrying the ratified
`pow-a9o` boot guard (a non-claude environment pinning a claude-native model), which is
live and tested; only the role VOCABULARY retires, and its refusals now read
`arming "<label>"`. (5) NO DEPRECATIONS (`docs/adr/ADR-0002-agent-environment-layer.md`
D4: "delete and undocument. until we go public, no deprecations") — no shim, no
re-export, no deprecated alias, and the doc comments that named the retired symbols are
rewritten rather than left dangling (an in-suite fence in
`test/agent/model_ladder_test.dart` greps `lib` for all six).

**Why.** The lineage is one axis being replaced piece by piece: `pow-edp` (A20) minted
`AgentRole` and mapped it straight to a model; `pow-2c9` split that into role → tier →
model so a retune stopped touching roles; `pow-k7l` added role → env so a role could
name a whole environment; `pow-t1w` added `AgentRole.architect` so the spec author could
diverge from the build. ADR-0006 then made the environment selectable BY VALUE and BY
TYPE, which is strictly more expressive than a role key on both counts — `pow-k7l`'s and
`pow-t1w`'s reasons for the role are gone. What is NOT gone is the reason `pow-2c9`
existed: models still vary by class of work. Keeping that as the declared tier costs one
enum argument at six sites, keeps A20's live "grade cheap, build strong" property exact,
and leaves the model arming (`ModelTiers`/`graderModel`) untouched for bead `pow-2c6`,
whose closed-but-unlanded scope is to delete it and re-home A20(3) as a loud refusal.

**Affects (if promoted):** `packages/grid_assets/lib/src/agent/agent_harness.dart`
(DELETED: `AgentRole`, `tierFor`, `defaultModelFor`, `AgentConfig.roleEnvironments`,
`AgentConfig.modelForRole`, `AgentConfig.stationModelFor`), `agent_domain.dart`
(`resolveAgentConfig`'s `tier` parameter; the role rung deleted),
`environment_registry.dart` (`validate(armedNames:)`), the six spawn sites in
`lib/src/code/{code_capabilities,specify,committee,readiness,discovery}.dart`, plus doc
comments in `model_tier.dart`, `typed_environment.dart`, `seat_environments.dart` and
`lib/grid_assets.dart`; tests: `test/agent/role_model_ladder_test.dart` DELETED and
`test/agent/model_ladder_test.dart` created, plus `model_tier_test.dart`,
`env_selection_test.dart`, `env_native_model_test.dart`, `typed_environment_test.dart`,
`environment_registry_test.dart`, `seat_environment_test.dart`, `specify_stage_test.dart`
and `discovery_test.dart`. Composes with A35 (the typed rung, unchanged), A39 (the seat
types, unchanged) and A38. **space_station (NOT this worktree — bead `space-rz6`, which
its own `agent_arming.dart` already names):** `AgentArming.roleEnvironments` and
`kMementoStationArming` no longer compile against this pack and must become typed
preference providers; the `up` banner's typed-value projection is that bead's too.

**Status:** Pending — Nico promotes or rejects.
