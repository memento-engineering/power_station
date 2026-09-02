---
status: accepted
date: 2026-07-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a10-bead-pow-72b-the-gitservices-carrier-reads-quiet-maybeof
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A10"
---
## A10 (2026-07-11) — bead `pow-72b`: the `GitServices` carrier reads QUIET (`maybeOf`, subscribing), not a loud `.of`; ctor overrides merge PER-FIELD; the carrier is a plain const class, not a freezed value

**Decision:** the git-machinery carrier that lets a substation seat read `GitGridAssets()` bare is one class, `GitServices` (`packages/grid_assets/lib/src/assets/composition_assets.dart` — defined in grid_assets so the space-station delegate PROVIDES against the same type the asset READS, per the bead's placement call). Three autonomous surface choices inside the bead's prescribed shape:
(1) **The read is `maybeOf` (quiet null on absence), not the bead text's literal `.of(context)`.** In the house `scopes.dart` vocabulary `of` is the LOUD variant (throws when absent) — but absence of git machinery IS the documented offline/dry-run posture the acceptance criteria require unchanged ("both null ⇒ provisioning + land no-op"), so a loud `of` would turn the valid offline build into a refusal, and a quiet `of` would silently redefine the house verb. `maybeOf` says exactly what it does; there is no invariant for a loud guard to protect (guards LOUD or GONE), and the existing bare-tree tests (GitGridAssets with no carrier at all) pass unmodified under it. It SUBSCRIBES (`dependOnInheritedSeedOfExactType`, the D-H build verb) — a new test proves re-provided machinery re-derives the seat's source control (offline → live flips `canLand`).
(2) **Ctor-vs-context merges per-field** (`provisioner ?? services?.provisioner`, `gitOps ?? services?.gitOps`), not carrier-wins-whole: "ctor wins when present, else context" read most naturally as each half independently, and it lets a test inject ONE half while the delegate's carrier supplies the other.
(3) **`GitServices` is a plain `const` class, not freezed** — it carries injected service impls (`StationGitService?`/`GitOps?`), not serializable config VALUES, so the freezed+json house pattern for tree values (e.g. `SubstationScope`) doesn't apply; identity semantics on an `InheritedSeed` re-provision are sufficient (a swapped carrier instance notifies dependents).
**Why:** the bead ratified the mechanism (one carrier seed named as a faculty — `GitServices` is its own suggested name — read in build, ctor as optional override, YAGNI: no locator/registry/options); only these three API-surface details were left to the run. Each reuses an established idiom (`maybeOf` from grid_sdk's scopes, per-field `??` from `HarnessProvider.registry`, subscribing build reads from A8) rather than inventing new surface.
**Affects (if promoted):** `packages/grid_assets/lib/src/assets/composition_assets.dart` (`GitServices`, `GitGridAssets` doc + build), `packages/grid_assets/lib/grid_assets.dart` (library doc), `packages/grid_assets/test/track_f_composition_assets_test.dart` (the pow-72b group + `_RecordingGitRunner`/`_ReprovidingServices` infra). The companion space-6ds delegate change (HELD until this lands) provides `InheritedSeed<GitServices>` once above the substation fan-out; if Nico instead ratifies a loud-`of` posture the offline documentation in the class doc changes with it.
**Status:** pending.

