---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel
  surfaces:
    - "packages/github_grid_assets/**"
    - "the_grid/packages/beads_dart/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "pow-0nvg"
  legacy-id: null
---
## bead `pow-0nvg` — the GitHub intake argv rides `BdCliService`, metadata is a PER-KEY channel on both create and update, and carrying `--defer 9999-12-31` forward is a RECORDED ADR-0004 D1 departure

**Decision (AI; mechanism only).** `BdGitHubIntakeStore` stops building `bd`
argv. `BdCliService.listScope` gains an optional `type`, an `externalRef`
filter and `includeClosed`; `createArgs`/`create` gain `defer`, `externalRef`
and a `setMetadata` map emitted as repeated `--set-metadata k=v`. Four
mechanism calls the bead text leaves open:

1. **`listScope.type` becomes optional rather than a new `listByExternalRef`
   method.** A correlation read is type-agnostic, and a second list builder
   beside the existing one would be the duplication the compatibility rails
   exist to prevent. Emitted argv is byte-identical for every existing caller.
2. **`bd create --set-metadata` is NEGOTIATED, not assumed.** Probed
   read-only on 2026-09-02: `bd version HEAD-a45199a` advertises
   `--metadata` on `create` but not `--set-metadata`, so the create-then-
   `update` fallback is the live path. It is still asked of the binary — once
   per process off `bd create --help`, plus an `unknown flag` runtime
   fallback — mirroring `_probeGuardedWrites` and the_grid A54's precedent
   that a capability question is asked of the store, never pinned to a
   version. The file-private `_GuardedWriteSupport` enum is renamed
   `_FlagSupport` and the `--help` flag-row parser is extracted so the two
   probes share one implementation.
3. **The intake store's `id is! String` shape guard is DELETED, its
   empty-id guard KEPT.** `Bead.fromJson` now owns the non-string case and
   refuses it loudly; a second check over a layer that already fails is a
   silent duplicate. `Bead` admits `id: ''`, so that guard still protects a
   named invariant and stays.
4. **Carrying `--defer 9999-12-31` forward is RECORDED HERE AS A DEPARTURE
   from ADR-0004 D1, not justified by D1's guard exception.** D1's carve-out
   —
   "It does **not** retire the ATOMIC CREATE-THEN-WIRE GUARD in `discover` /
   `intake-refinement`, where `--defer` closes a seconds-wide mount race" —
   no longer covers anything: the entry
   `docs/decisions/2026-09-01-a33-bead-pow-158-record-the-adr-0004-d1-split-guard-retireme.md`
   (legacy `A33`) records that "`pow-158` later retires `--defer` from both
   skills together", and on the live tree `grep -c defer` returns `0` for
   both `packages/grid_assets/extension/station_overlay/claude/skills/discover/SKILL.md`
   and `.../intake-refinement/SKILL.md`. GitHub intake's
   `--defer 9999-12-31` was never that guard anyway: it has no
   wire-dependencies step and no seconds-wide race — it is a permanent
   triage-pending marker, which is exactly the PENDING/QUEUEING idiom D1
   retires. This bead does NOT fix it, because the bead text scopes it out
   ("this bead only moves the argv, it does not change the pending-state
   contract") and because the replacement lifecycle is a human call already
   owned by bead `pow-5wo` (OPEN, type `decision`, "Decide ADR-0004-compliant
   pending state for GitHub intake beads"), whose own acceptance requires
   Nico's ruling. Per ADR-0004 D3 — "the governor TAKES the action, records it
   as an … amendment naming the clause departed from and why, and moves on" —
   this paragraph is that record: the clause is D1, the reason is that a
   hygiene reroute must not silently change a lifecycle a `decision` bead is
   holding open, and the date survives byte-for-byte behind the named constant
   `kGitHubIntakeDeferUntil` so `pow-5wo` has exactly one symbol to retire.

**Why.** The hand-built argv was outside the rails (`tg-8cuu`: corpus replay,
fixture drift, the exact-argv pins), and it used bd's whole-object
`--metadata` replace on `update` — which silently drops every key this writer
did not send, including `validation_plan` and
`grid.approved_by`/`_at`/`_rev` written by the grid on the same bead. The
per-key channel was ratified by the governor on the bead (2026-09-02) after a
readiness hold; this entry records only the mechanism that carries it, plus
the D1 departure above.

**Not this.** No `replaceMetadata` parameter on `BdCliService` (explicitly
refused on the bead). No `grid.approved`-style label gate substituted for the
defer date here — that is `pow-5wo`'s ruling to make, and inventing one in a
hygiene bead would pre-empt a `decision` bead.

**Affects:** `the_grid/packages/beads_dart/lib/src/services/bd_cli_service.dart`
(`listScope`/`listScopeArgs`/`create`/`createArgs` signatures — additive; new
`@visibleForTesting resetCreateMetadataCapabilityForTesting`),
`packages/github_grid_assets/lib/src/intake/github_intake_store.dart` (new
`kGitHubIntakeDeferUntil`; `BdGitHubIntakeStore`'s constructor is no longer
`const`).
