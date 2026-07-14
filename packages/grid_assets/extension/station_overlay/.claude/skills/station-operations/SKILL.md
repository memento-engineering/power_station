---
name: station-operations
description: >
  Operate the resident the_grid station: boot ({{runner}} up), bounce, tear
  down, read /status, seed a grid home's state store, and diagnose a station
  that is up but driving nothing. Use when starting, restarting, or arming the
  station, when a boot looks healthy but ready > 0 with mounted 0 and no
  output, or when preparing a fresh grid home — even if the symptom is just
  "nothing is happening."
compatibility: Requires dart + the `{{runner}}` runner (the station runs JIT via `dart run`, never an AOT binary), bd (beads CLI), git.
metadata:
  author: memento-engineering
---

# Station operations

## Boot

From the grid home (the repo whose `.grid/` holds the state store and lock):

```
{{runner}} up --no-dry-run \
  --grid-home {{gridHome}} \
  --substation '<name>[@<prefix>]=<abs work-repo root>' ...
  [--max-agents N]
```

- One `--substation` per work repo; `@prefix` only when the store's issue-id
  prefix differs from the name (`the_grid@tg=…`). Names and prefixes must be
  disjoint across substations — assembly refuses collisions.
- Delivery is a per-substation BINDING, not a flag (the_grid ADR-0000 A51): every
  coded seat authors `GitHubGridAssets`, so a LIVE arm (`--no-dry-run`) pushes and
  opens a PR per landed bead. `--dry-run` binds nothing (the commit-only posture).
  There is no land flag to omit.
- The station is resident: it runs until `{{runner}} down`. Run it in the
  background and read the banner from its log.

Verify the boot with effects, not the banner: `{{runner}} status --state-workspace
{{gridHome}}` should show `station: UP`, and within a minute of ready work
existing you should see `mounted`/`live sessions` > 0, per-bead worktrees under
`<work-repo>/.grid/worktrees/<substation>/<bead>`, and real agent processes.

## Bounce / down

```
{{runner}} down --state-workspace {{gridHome}}    # scoped stop via the lock
{{runner}} up ...                                 # same arming
```

Bounce whenever station-side state is latched (see the silent-death runbook) or
after changing a store's config. `down` kills only the station's own process
group — never pkill by name.

## Reading /status

- `ready` counts the raw ready frontier (includes epics and other
  non-driveable types that will correctly never mount — do not chase them).
- `mounted` and `live sessions` count non-terminal SESSION BEADS in the state
  store — not tree branches. Zero sessions with ready work means the mint or
  spawn path is broken, not that the tree is empty.
- `last sync` only moves when a store changes; a frozen timestamp on an idle
  board is normal.

## Silent-death runbook (ready > 0, mounted 0, no errors)

The station prints nothing when every session mint fails — the failure is
latched per-scope with no retry. Work the chain from the store outward:

1. **Sessions:** `bd -C {{gridHome}}/.grid export --include-infra` — zero beads
   at all means no write ever landed (also check `.beads/last-touched` exists).
2. **The mint seam:** `session` is NOT a core bd issue type. A state store
   seeded by bare `bd init` refuses `bd create -t session` ("invalid issue
   type"). Fix: add to `{{gridHome}}/.grid/.beads/config.yaml`:

   ```yaml
   types:
     custom:
       - session
   ```

   Verify with `bd types`. Then **bounce** — the failed scopes are latched and
   will not retry on their own.
3. **If sessions exist but nothing spawned:** check worktrees on disk and agent
   processes; then read the gate/critique artifacts (`gate-medicine`).
4. **When the chain reads clean but the tree still mounts nothing:** reproduce
   with a dry probe — assemble the same stores with the sdk's dry-run posture
   in a throwaway script and print what the frontier sees per gate (type,
   ownership, readiness). Dry mode is safe against real stores: no writes, no
   spawns.

## Seeding a fresh grid home

- State store lives EXACTLY at `{{gridHome}}/.grid/.beads` (never walk-up — a
  dual-role repo's root `.beads` is a WORK store; binding it lands sessions in
  the work source).
- bd derives the minted id prefix from the store's `dolt_database` name — name
  it deliberately; that prefix joins the ownership allow-set.
- Seed `types.custom: [session]` at creation (step 2 above) — the #1 cause of
  a silently dead first boot.

## The watch

Run a background loop rather than polling by hand. Exit (and re-engage the
governor) on ANY of: an open gate bead in the state store, live sessions
returning to zero after being live ("harvest time"), station not UP, or a
timeout heartbeat (~45min while work is in flight, ~3h idle). Scan gates via
`bd -C {{gridHome}}/.grid export --include-infra` filtered to open
`issue_type: gate` — never `bd show` in the loop.

## Gotchas

- The banner's "work-driving: ARMED" is derived from config, not from the tree
  actually driving — trust only effects.
- A landed engine/sdk change is picked up by re-running from source on a bounce or
  hot-reload — there is no recompile step. Run the `{{runner}}` station JIT (via
  `dart run`), never a compiled binary: a binary loses the VM service, hot-reload,
  and the current-source guarantee (space is JIT-only — see its CLAUDE.md).
- The dry smoke CANNOT prove the write path (dry = no-op bd writer): the first
  live boot of any new composition is the only prover — treat it as an
  instrumented experiment, not a formality.
