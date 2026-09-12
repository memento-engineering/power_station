---
status: accepted
date: 2026-09-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: each-seat-preference-vends-its-own-provider-seed
  surfaces:
    - "packages/grid_assets/lib/src/agent/typed_environment.dart"
    - "packages/grid_assets/lib/src/agent/seat_environments.dart"
    - "packages/grid_assets/test/agent/seat_environment_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-ycoi
  legacy-id: null
---

# bead `pow-ycoi`: the MECHANISM of the open seat-preference collection — each `SeatPreference` vends its own provider seed and `TypedEnvironmentProvider` composes them with `Nest`

**Decision (AI; MECHANISM only).** The POLICY — value-keyed selection, "the TYPE
is the scope; nearest ancestor wins; a seat scopes by nesting under its
Substation" — is Nico's and lives in
`adr-0006-typed-environment-lookup-selects-by-value` (D2/D4); nothing here
touches it. What this entry records is the set of calls made autonomously to
reopen the mechanism that policy rides on. (1) A SEAT IS AN OPEN SUBTYPE, not a
closed four-field set: a new `SeatPreference extends ModelPreference` with one
abstract member, so nothing enumerates the seat universe and a station declares
a seat type without editing the vended pack. (2) EACH SEAT OWNS ITS PROVIDER
SEED — `SeatPreference.provider()` returns the `SingleChildSeed` that mounts
THIS seat under its own exact static type: `SeatProvider<T>` (a thin
`SingleChildStatelessSeed` over `InheritedSeed<T>`, needed only because
`InheritedSeed` requires its child at construction and so cannot itself be a
`Nest` link) for a plain seat, and `CriticSeatProvider`, which builds the
existing `CriticEnvironmentSeed`, for the one seat whose value is aspect-scoped.
Scoping therefore stays type-and-value keyed, and D4's lane-scoped invalidation
is preserved rather than re-derived. (3) THE PROVIDER NESTS, IT DOES NOT
ENUMERATE — `TypedEnvironmentProvider.buildWithChild` becomes
`Nest(children: [for (final seat in arming) seat.provider()], child: child)`.
`Nest` is `genesis_tree`'s own ordered-composition primitive and already states
the semantics ("wraps `child` with each of `children` in order, the first
outermost"), so the pre-change nesting order survives with no bespoke mount verb
and no reversed fold, and the build still reads and caches no ambient state
(`a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki`; ADR-0008 D3).
(4) `AgentArming` SURVIVES AS AN `Iterable<SeatPreference>` — const-
constructible, its four named fields, `isEmpty`, `seats`, equality, hash code
and string form intact, `iterator` delegating to `seats` — so the vended
four-seat call shape and the downstream re-exports keep compiling, a station's
boot-eager arming refusal can still walk the arming and name an offending seat
BY TYPE, and a fifth seat composes as `<SeatPreference>[...arming, MyEnv(...)]`.
(5) THE VOCABULARY/MECHANISM SPLIT IS HONORED, NOT BENT. The legacy register's
A39 (bead `pow-n6n.2`, Pending) governs both touched libraries and both of its
load-bearing clauses survive: its PLACEMENT clause puts "the four seat types
[…] in a NEW `lib/src/agent/seat_environments.dart`, not in
`typed_environment.dart`" so that "mechanism and vocabulary stay separable" —
and `SeatPreference`, being mechanism, is declared in `typed_environment.dart`
beside `ModelPreference` while the four concrete types stay where A39 put them;
its Why clause holds that "the seat types are deliberately trivial subclasses:
the TYPE is the whole scope (D2), so any state on them would be a second
selection key" — and `provider()` adds BEHAVIOR, not state: it takes no
`TreeContext`, reads nothing ambient, and selection still keys on the exact type
and `entries` alone, so no second selection key appears. A39's
`CriticEnvironmentSeed` and its `updateShouldNotifyDependent` are consumed
unchanged, which is exactly why the critic vends `CriticSeatProvider` rather
than the plain `SeatProvider`.

**Why.** The four-branch `if`-ladder in `buildWithChild`, paired with
`AgentArming`'s four named fields, put the set of possible agent seats in the
provider's control flow — the same closed set a string-to-environment map had,
moved into the type system, and closed in two places at once. Adding one seat
meant editing the vended pack, which is precisely what the typed design was
introduced to avoid. Opening it costs nothing the closure bought: the compile-
time safety is stronger, not weaker (a seat's provider is written by the seat,
under its own static type, so a mismatch is a compile error rather than a silent
miss), and the refusal path that walks the arming to name a seat by type is
preserved by keeping `AgentArming` iterable in the same order. `Nest` is used
rather than a hand-rolled fold because the package already authors its
single-child assets that way (`composition_assets.dart`) and a bespoke mount-
and-fold would only duplicate `Nest`'s stated semantics in miniature — that
alternative was drafted and withdrawn.

**Affects (if promoted):**
`packages/grid_assets/lib/src/agent/typed_environment.dart` (`SeatPreference`,
`SeatPreference.provider`),
`packages/grid_assets/lib/src/agent/seat_environments.dart` (`SeatProvider`,
`CriticSeatProvider`, `provider()` on `BuildAgentEnvironment`,
`SpecAgentEnvironment`, `CriticAgentEnvironment` and `GatherAgentEnvironment`,
`AgentArming.iterator`, `AgentArming.seats`,
`TypedEnvironmentProvider.arming`, `TypedEnvironmentProvider.buildWithChild`),
and the public exports in `packages/grid_assets/lib/grid_assets.dart`, which
carry the three new names out without an edit (both libraries are exported
wholesale). Tests:
`packages/grid_assets/test/agent/seat_environment_test.dart`. Composes with
`a35-bead-pow-n6n-1-the-mechanism-of-adr-0006-s-value-keyed-t` (the rung,
untouched: selection still never routes through `EnvironmentRegistry.resolve`,
and the name is still restored once at the boundary),
`the-composed-substation-seed-is-vended-from-github-grid-assets` (station
posture stays outside the pack), and
`roles-retire-typed-lookups-and-the-tier-subsume-the-role-map` (this adds
neither a role map nor a second selection mechanism).
