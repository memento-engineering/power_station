---
status: accepted
date: 2026-09-15
decision-makers:
  - "governor (power_station)"
consulted: []
informed: []
register:
  spec: 1
  slug: seat-provider-seeds-replace-agent-arming
  surfaces:
    - "packages/grid_assets/lib/src/agent/seat_environments.dart"
    - "packages/github_grid_assets/lib/src/assets/substation_seed.dart"
  obsoletes: []
  updates:
    - "each-seat-preference-vends-its-own-provider-seed"
    - "the-composed-substation-seed-is-vended-from-github-grid-assets"
  obsoleted-by: null
  updated-by: []
  bead: pow-r8va
  legacy-id: null
---

# Seat provider seeds ARE the arming mechanism: `AgentArming` and `TypedEnvironmentProvider` are retired

**Decision (governor; MECHANISM only).** The POLICY is untouched and is not
this entry's to move: value-keyed selection — "the TYPE is the scope; nearest
ancestor wins; a seat scopes by nesting under its Substation; the station
default is mounted at the root" — stays exactly as
`adr-0006-typed-environment-lookup-selects-by-value` (D2/D4) states it. What
this entry records is the retirement of the two types that were the arming
MECHANISM before `each-seat-preference-vends-its-own-provider-seed` reopened
it, and the amendment of the two entries that named them.

(1) EVERY SEAT MOUNTS THROUGH ITS OWN PROVIDER SEED, IN THE CONSUMER'S OWN
`Nest`. `SeatPreference.provider()` already returns the `SingleChildSeed` that
mounts THIS seat under its exact static type — `SeatProvider<T>` for a plain
seat, `CriticSeatProvider` (building `CriticEnvironmentSeed`) for the one seat
whose value is aspect-scoped — so a consumer composes
`Nest(children: [for (final seat in seats) seat.provider()], child: child)`
itself. That is the whole of what `TypedEnvironmentProvider.buildWithChild`
did, which is why the wrapper is DELETED rather than deprecated: a seed whose
only body is a line its caller can write is not a mechanism, it is an alias.

(2) THE ARMING IS ANY ORDERED `Iterable<SeatPreference>`, AND NOTHING NAMES
FOUR. `AgentArming`'s four nullable fields named four members of a set that
clause (1) of the superseded entry had already declared open, and after that
entry it carried no behavior beyond iterating them in order — it survived only
so the vended four-seat call shape and the downstream re-exports kept
compiling. Every station has since migrated: no Dart source in this repository,
in the released `space_station_assets`, or in `lunar` references either type.
So the record is DELETED too, and the ordered collection — a plain
`List<SeatPreference>` — is the whole arming value.

(3) THE BOOT-EAGER ARMING REFUSAL WALKS ANY `Iterable<SeatPreference>`. That
guard is STATION-OWNED and already open over the iterable in released
`space_station_assets`; it still names an offending seat BY TYPE, from the same
stable declaration order, because the order is now the authored list's. Nothing
in the vended pack gains a guard, and no silent compatibility guard replaces
the deleted shapes — an UNARMED case is an empty collection, which resolves and
refuses exactly as four null fields did
(`a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki`: guards LOUD or
GONE).

(4) `SeatEnvironments` STAYS, AND STAYS FOUR. It is the offline PROJECTION of
the four vended resolutions at a point in the tree — the banner line and the
suites' assertion surface — not an arming, so opening the seat set never made
it wrong. `seatChannelPolicy`, `resolveEnvironment`, `CriticAgentEnvironment.of`
and `RelayAgentEnvironment.of` are unchanged.

(5) THE VENDED SUBSTATION SEED TAKES THE SEEDS, NOT A RECORD.
`SubstationSeed.arming` becomes `SubstationSeed.seatSeeds`, a
`List<SingleChildSeed>` of the provider seeds the seats themselves vend,
copied at construction and spread OUTERMOST in the seat's existing `children`
list — ahead of the mounted projection, the selected generated definitions, the
reconciler legs, `GitGridAssets`, `GitHubGridAssets` and
`MountEligibilityAssets`, whose relative order is unchanged. The per-substation
rung of `adr-0002-agent-environment-layer` D5 is therefore REAL in exactly the
way it was: a seat the substation mounts shadows the station's BY EXACT TYPE
and a type it does not mount keeps resolving through the station's, which the
seed's own suite proves offline through the SDK's mounted-value walk. The seed
now enumerates no seat type at all.

**Why.** `each-seat-preference-vends-its-own-provider-seed` kept `AgentArming`
alive under an explicit compatibility rationale — clause (4) of that entry says
so in as many words — and kept `TypedEnvironmentProvider` because something had
to spread the seats while consumers still passed a record. Both reasons expired
when the last station migrated. Leaving them would keep the CLOSED four-member
shape in the vended vocabulary of a pack whose entire point is that the seat set
is open, and would keep two ways to mount a seat where one suffices; a reader
would have to learn which is canonical.
`adr-0002-agent-environment-layer` D4 is unambiguous about how that ends —
"DELETE. No deprecations." — and `adr-0003-private-git-tag-releases-and-prerelease-gate`
already routes breaking work through the dev rung, so both packages mark the
source break in their changelogs with a one-line migration and promotion stays
outside this change.

**Departure declared and cured.** `the-composed-substation-seed-is-vended-from-github-grid-assets`
names "the arming MECHANISM — `AgentArming`, `TypedEnvironmentProvider`,
`SeatEnvironments`" as what is appended to `seat_environments.dart`. This entry
REPLACES the first two of those three names with the per-seat provider seeds and
`Nest`, and RETAINS the third; the placement itself — mechanism in `grid_assets`,
composition in `github_grid_assets`, no reverse dependency edge — is untouched,
and so is the vend's direction. The departure was declared in the filing at the
governor's 2026-09-15 ruling on discovery hold `tranquility-uk82t` rather than
taken silently, which is what this amendment settles.

**Affects.** `packages/grid_assets/lib/src/agent/seat_environments.dart`
(`AgentArming` and `TypedEnvironmentProvider` deleted; `SeatProvider`,
`CriticSeatProvider`, `CriticEnvironmentSeed`, `SeatEnvironments`,
`seatChannelPolicy` and every seat type's `provider()` unchanged) and the
wholesale public export in `packages/grid_assets/lib/grid_assets.dart`, which
drops the two names without an edit.
`packages/github_grid_assets/lib/src/assets/substation_seed.dart`
(`SubstationSeed.seatSeeds` for `SubstationSeed.arming`;
`MountedSubstationSeed.environments` unchanged). Tests:
`packages/grid_assets/test/agent/seat_environment_test.dart`,
`packages/grid_assets/test/agent/relay_assets_test.dart`,
`packages/grid_assets/test/agent/seat_permission_policy_test.dart`,
`packages/github_grid_assets/test/assets/substation_seed_test.dart`. Composes
with `one-asset-resolution-defines-tree-and-writers` (the selected-definition
resolution and its spread are untouched: only the outer seat children move) and
with `adr-0006-typed-environment-lookup-selects-by-value` (no name key is
introduced; the exact type remains the whole scope).
