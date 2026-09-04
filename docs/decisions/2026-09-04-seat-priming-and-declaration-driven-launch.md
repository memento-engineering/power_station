---
status: accepted
date: 2026-09-04
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: seat-priming-and-declaration-driven-launch
  surfaces:
    - "packages/grid_assets/lib/src/agent/agent_environment.dart"
    - "packages/grid_assets/lib/src/agent/agent_harness.dart"
    - "packages/grid_assets/lib/src/seat/**"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - the_grid#agent-disc-file-shape-and-home
  obsoleted-by: null
  updated-by: []
  bead: pow-lv6t
  legacy-id: null
---

# Seat priming sources and declaration-driven launch

## Context and Problem Statement

Making an Agent Seat occupiable and replacing the dead `bd prime --hook-json`
registration runs into two constraints the original field list cannot carry.
Nico, 2026-09-03: "nothing vendor-specific lives in the launcher — it lives on
AgentEnvironment beside resumeFlag, or nowhere", while the same acceptance
requires the launcher to drop the one-turn prompt flag and permission-skipping
args and to refuse unless the selected harness's role-definition asset exists.
Neither the driven-session argv nor the role-definition path is derivable from
the three declarations the work was scoped around.

The priming source also required a human ruling.
`the_grid#agent-disc-file-shape-and-home` section 5 says: "The only hook that
touches the disc is `SessionStart` with the `compact` matcher, which references
the seat's newest `handoff` after a compaction: the one case where the process
survives its own context." On 2026-09-04 the governor recommended startup +
clear + compact, not resume; Nico answered, "That sounds good."

## Decision Outcome

**1. Five declarations, not three, and three are redeemed deferrals.**
`AgentEnvironment` gains `roleArgs`, `memoryDirArgs` and `primeMode` plus
`drivenArgs` and `roleAsset`. These fields redeem gc `ProviderSpec` deferrals in
`power_station#adr-0002-agent-environment-layer`: `print_args` becomes
`drivenArgs`; `instructions_file` becomes `roleAsset`; and `supports_hooks` is
narrowed to the one seat-priming path as `primeMode`. The deferral audit in
`agent_environment.dart` is corrected in the same change.

**2. Handoff injection occurs on startup, clear and compact, never resume.**
This entry DEPARTS from and UPDATES
`the_grid#agent-disc-file-shape-and-home` section 5's compact-only clause. The
vended SessionStart matcher remains `""` so the one hook still echoes bd on
every source, but the prime verb branches on the payload: `startup`, `clear` and
`compact` append the seat's newest handoff; `resume` returns bd's context
byte-for-byte because its context survives and another injection is pure
inference cost. Unknown or malformed sources also return bd's context only.
Everything else in section 5 remains binding: nothing injects the disc or
disc-recording instructions per session, and there is no `PreCompact` guard.

**3. The agents-leg role projection is `.agents/agents/<seat>.md`.**
The claude leg reads `.claude/agents/<seat>.md`. The agents-leg path is
`.agents/agents/<seat>.md`, mirroring `overlay_manifest.dart`'s
`kDefaultStationOverlayMappings` (`agents` -> `.agents`). Until an authored role
asset is installed there, occupying that environment REFUSES with the missing
path named; this change authors no new role definition.

**4. The station composition is a separate bead.**
`space`'s `buildRunner` lives in the `space_station` repo. `grid_assets` vends
`PrimeCommand` and `SeatCommand`; the one-line `..addCommand(...)` composition
lands with space_station's own bead, exactly as
`power_station#a11-bead-pow-ovh-the-search-domain-roster-resolution-is-an-o`
landed `search`.

### Consequences

* Good, because the launcher contains no vendor flag literal and a harness gains
  a seat capability by changing its environment value.
* Good, because startup, clear and compact receive the successor handoff while
  resume pays no duplicate inference cost.
* Good, because the five builtins' one-turn argv remains byte-for-byte
  unchanged: `spawnFor` renders `drivenArgs` in the slot `args` used to occupy.
* Bad, because every environment must now declare its role-asset projection and
  priming posture before an operator can occupy it.
* Constraint: the relaunch predicate compares a full-precision launch instant
  against file mtimes this platform reports at whole-second resolution, so a
  handoff written in the same second as the launch reads as not-newer. The
  direction is deliberate — a missed relaunch is recoverable, a spurious one
  loops forever — but it is a resolution the predicate depends on.
