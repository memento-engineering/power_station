---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a35-bead-pow-n6n-1-the-mechanism-of-adr-0006-s-value-keyed-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A35"
---
## A35 (2026-09-02) — bead `pow-n6n.1`: the MECHANISM of ADR-0006's value-keyed typed rung — legality moves to where values ENTER the tree, and `EnvironmentRegistry.nameOf` converts the winner back to a NAME exactly once

**Decision (AI; MECHANISM only).** The POLICY — value-keyed selection, "no strings at the composition layer" — is Nico's, ratified in the 2026-09-02 routing interview and recorded where ADR-0004's Consequences require it: the numbered `docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md` (D2), NOT here. What this amendment records is the set of calls this bead made autonomously to implement ADR-0006 D2's rung: (1) LEGALITY MOVES TO POINT OF ENTRY — an `AvailableEnvironments` set only ever holds registry members that passed the boot legality check (`EnvironmentRegistry.validatedEnvironments`, reusing the same private `_legalityRefusal` `validate` applies), so a value the lookup returns is validated BY CONSTRUCTION and the typed rung does not route through `EnvironmentRegistry.resolve(name)` for selection; the `SiteBinding` bind stays a WHOLE-REGISTRY boot refusal and is deliberately not re-checked per member (a per-member filter would be unreachable — a failing bind throws at the composition root and no work mounts). (2) THE NAME IS RESTORED AT THE BOUNDARY — a typed win sets `config.harness := registry.nameOf(typedEnvironment)`, a new reverse map over the registry's existing `builtins`/`custom` maps, compared in a new derived `AgentEnvironment.flattened` normal form (`AgentEnvironment.resolve([this])` — no new field, no second fold) so a canned layer carrying `EnvBaseUndeclared` matches the registry's flattened resolution of the same environment; the transport key, the `SiteBinding` lookup and the model ladder below therefore keep reading a valid registry NAME and no rung re-resolves it. (3) FAIL CLOSED — a typed value no armed name resolves to is a programming error: `nameOf` throws a `StateError` naming the value and the armed set (A8, guards LOUD or GONE), never a silent fall-through to a lower rung. (4) LAZY — the rung is `??`-short-circuited below the step and bead NAME rungs, so a losing typed rung never converts and never throws. (5) THE DEFAULT PRESENCE SET, until the availability seed (bead `pow-n6n.3`) publishes live probes, is exactly the boot-validated registry members, so nothing regresses. (6) THE EFFECT VERB — `resolveEnvironment`, `firstAvailable` and `availableEnvironmentsOf` read with the non-binding `getInheritedSeedOfExactType`, per A8(3) and ADR-0008 D3, because they are effect-boundary resolvers called at a capability's `spawn`/`run` edge; the subscribing build verb belongs to the seed that MOUNTS the value (bead `pow-n6n.3`).

**Why.** ADR-0006 D2 makes the typed rung carry a VALUE while every rung below it — `AgentConfig.harness`, `SiteBinding.endpointFor`, the model ladder — reads a NAME. Something has to bridge the two, and the choice of WHERE decides whether legality survives. Re-resolving the value's name through the registry at the rung would reintroduce the name as the selection key and make the type stop being the scope; skipping legality entirely would let an unvalidated environment spawn. Moving legality to the point where values ENTER the tree keeps both properties: selection is pure value equality, and the only values selectable are ones the registry already validated. `nameOf` then converts once, at the boundary, so no consumer below changes at all. The `flattened` normal form is required rather than cosmetic: without it a hand-authored canned preference entry never equals the registry's resolution of the same environment, and every typed lookup would silently miss.

**Affects (if promoted):** `packages/grid_assets/lib/src/agent/typed_environment.dart` (`ModelPreference`, `AvailableEnvironments`, `AvailableEnvironments.fromRegistry`, `AvailableEnvironments.none`, `availableEnvironmentsOf`, `firstAvailable`, `resolveEnvironment`), `environment_registry.dart` (`EnvironmentRegistry.nameOf`, `EnvironmentRegistry.validatedEnvironments`), `agent_environment.dart` (`AgentEnvironment.flattened`), `agent_domain.dart` (`resolveAgentConfig`'s `typedEnvironment` rung), `packages/grid_assets/lib/grid_assets.dart`; tests: `packages/grid_assets/test/agent/typed_environment_test.dart`. Composes with A20 (the model ladder is untouched and a typed win still stamps an explicit `params['model']`, so A20(3)'s no-unpinned-spawn floor holds) and A8. DISTINCT from bead `pow-n6n.4`'s amendment, which records a different subject (the retirement of `AgentRole` / `AgentConfig.roleEnvironments` and the role rung).

