---
name: intake-refinement
description: >
  Shape work beads so a resident the_grid station can drive them: prior-art
  search before a filing is accepted, the required validation_plan metadata,
  driveable issue types, dependency wiring, flagged EITHER/OR forks, the
  deterministic filing exit check,
  grid.approved_* stamp approval via the approve verb, and reconciling a
  backlog against what already shipped in mainline. Use when filing, approving,
  re-homing, or auditing beads in any store the station arms — including "why
  won't this bead mount" and "is this backlog actually current" questions.
compatibility: Requires bd (beads CLI) and git.
metadata:
  author: memento-engineering
---

# Intake refinement

A resident station's drive set IS the ready frontier: **ready = in**. Refinement
is the only gate between a bead and a live agent, so every rule here exists
because its violation put a real agent on wrong work.

## The bead contract

Every bead intended for the station needs:

1. **A driveable type** — only `task`, `bug`, `feature`, `chore` mount.
   `epic`/`decision`/`spike`/`story`/`milestone` are organizational and are
   correctly ignored by the mount boundary (they still show in `ready`).
2. **`validation_plan` metadata** — a real `sh` command, run from the bead's
   worktree root by the review committee's gating lane:

   ```
   bd -C <work repo> update <bead> --set-metadata \
     'validation_plan=cd packages/<pkg> && dart pub get && dart analyze && dart test' \
     --actor operator
   ```

   A plan-less bead grades **F by design** (the gating lane runs `false`) and
   hard-blocks at review. `dart pub get` first — worktrees start unresolved.
   Scope it by **Scope the validation_plan to every consumer** below.
3. **Acceptance criteria** — at least one `- [ ]` checkbox a named command can
   falsify: `bd -C <work repo> update <bead> --acceptance '- [ ] <outcome>'
   --actor operator`.
4. **Deps wired the right way round** — every blocker NAMED in the description
   and WIRED. See **Wire every dependency at intake**.
5. **A description an agent can act on alone** — the agent receives the bead
   text and a worktree, nothing else. Name packages and acceptance shape.

Rows 1–4 are the PRESENCE half of the ten rows the `filing` verb checks — the
other six ask whether what is present is VIABLE (**The exit check**). Row 5 is
the judgement this skill's reader owns. Never re-derive a verb row by reading
the bead — run the verb.

## Search prior art BEFORE accepting a filing

Before accepting any new filing, search the org backlog for the work already
being tracked, from the grid home:

```bash
{{runner}} search --json "<token>"
```

Query **single tokens** (`filing`, `refiner`, `overlay`), one call per token.
The lexical leg ANDs a multi-word query, so a two-word query is the reliable
way to MISS the duplicate. Read `hitCount` and each store's `outcome`; a real
duplicate is closed against the survivor with receipts, and a near-miss is
wired as a dependency instead of re-filed.

**Why:** filing a second bead for work an open sibling already owns spends a
full agent round producing a colliding branch, and the coherence lane grades
the second bead F for duplicating its sibling.

## Scope the validation_plan to every consumer

The plan runs every package the CHANGE reaches, not just the packages the diff
edits. A changed public API in `packages/<a>` that `packages/<b>` imports means
BOTH packages are in the plan:

```
validation_plan=cd packages/<a> && dart pub get && dart analyze && dart test && cd ../<b> && dart pub get && dart analyze && dart test
```

**Why:** a plan scoped to the diff's own package goes green while the consumer
no longer compiles; the break surfaces at the NEXT bead's `pub get`, after the
PR merged.

This is YOURS, not the verb's. Identifying every affected consumer is
blast-radius judgement over the package graph, not a mechanical read of the
bead's text, so validation-plan consumer coverage is deliberately NOT a
`filing` row — a lint that guessed at it would refuse legitimate work.

## Keep the plan inside the critic lane's runtime cap

The gating lane kills a validation plan at roughly 600 seconds. A plan that
overruns latches failed, mints NO gate, and strands the session invisibly —
there is nothing for an operator to clear. Budget the plan: scope it to the
packages the change reaches, prefer targeted `dart test <path>` legs over a
whole-repo sweep, and drop anything that rebuilds the world.

This is YOURS too. Duration cannot be decided from bead text — it needs the
plan executed or estimated — so the critic-lane time cap is deliberately NOT a
`filing` row; a wrong refusal here would block work that runs perfectly well.

## Wire every dependency at intake

- **Local (same store)** — name each blocker on its own `Blocked by:` or
  `Depends on:` description line, then wire it:

  ```bash
  bd -C <store root> dep add <blocked bead> <blocker bead> --actor operator
  ```

  The BLOCKED bead is the first argument. The `filing` verb's `dependencies`
  row reads the ids named in the description and fails until each one has an
  outgoing `blocks` edge.
- **Cross-store** — never a local dependency row, and never
  `bd dep add <id> external:<project>:<id>`: mint an OPEN grid-state
  `type=link` bead with the station's link verb, arming BOTH endpoint
  prefixes:

  ```bash
  {{runner}} link <blocked bead> --blocked-by <blocker bead> \
    --prefix <blocked bead prefix> --prefix <blocker bead prefix> \
    --actor operator --reason "<why this ordering exists>"
  ```

  The link bead carries `grid.link.from`, `grid.link.to` and
  `grid.link.type=blocks`; the station projects it and the shared block guard
  enforces it. A malformed link fails closed. `{{runner}} link ls` lists what
  is wired.

**Why:** an unwired blocker leaves the blocked bead in `ready`, so the station
mounts it and its agent builds against an API the blocker has not shipped. A
raw foreign-id dependency row is worse: `bd doctor --fix` can classify it as
orphaned and sever it silently.

## FLAG an EITHER/OR fork — never decide it

When refinement finds two viable designs, write BOTH into the bead as a named
fork and stop:

```
FORK (author decides): (A) extend the existing service with a second mode, or
(B) mint a sibling service. NOT decided at intake.
```

Do not pick, and do not approve the bead until a human picks.

**Why:** a fork settled at intake by inference reaches the build stage looking
decided; the round is spent before the human ever sees that there was a choice.

## Stamp architecture constraints into the CHILD bead

An agent reads ONE bead: its own. A constraint recorded only in a parent epic —
the seam to extend, the package that owns the surface, the doctrine that binds
— does not exist for the child's agent. Copy every constraint that governs the
child INTO the child's own description.

**Why:** the epic said "extend the existing loader", the child said "add a
loader", the agent built a second loader, and the coherence lane graded it F.

## Repo-relative paths in every declared test list

Every path a bead names is written relative to the REPO ROOT —
`packages/grid_assets/test/assets/skill_assets_test.dart`, never a bare
`test/assets/skill_assets_test.dart` and never an absolute machine path.

**Why:** the agent's cwd is a fresh worktree root, so a bare path resolves
under whichever package it happened to enter; the declared test is "not found"
and the criterion goes unchecked.

## Point at the primitive that already exists

When the work extends something the tree already owns, write the pointer into
the bead body as `path:line` plus the relationship:

```
COMPOSE: packages/grid_assets/lib/src/filing/filing_contract.dart:765 owns the
ten-row completeness contract — CALL it; do not add a second predicate.
```

**Why:** without the pointer the build stage re-expresses the primitive beside
the one that exists. That is the duplication the coherence lane F-grades, and
it is why this skill CALLS the `filing` verb instead of carrying a completeness
checker of its own.

## The exit check — `filing` is the oracle, and it is a COMMAND

Refinement EXITS on the verb, never on a reading. From the grid home (the verb
resolves the owning store by the id's prefix), and ALWAYS with `--state-root`
pointed at that grid home, so the cross-store link beads are actually read:

```bash
{{runner}} filing --json --state-root "<grid home>" "<bead>"
```

`--state-root` takes the GRID HOME, the same value `--grid-home` takes; the
verb appends its `.grid` state store itself. Omitting it does not make the
check stricter — it makes the check BLIND to every blocker wired by a link
bead.

The report is one JSON object: `{id, passed, requirements, error?}`.
`requirements` carries exactly ten rows, in order — `driveable_type`,
`validation_plan`, `acceptance_criteria`, `dependencies`,
`validation_plan_syntax`, `validation_plan_portability`, `repo_relative_paths`,
`bead_references`, `release_versions`, `decision_references` — each
`{requirement, passed, detail}`. `passed` is true only for a found bead whose
ten rows ALL pass.

The first four ask whether a field is PRESENT. The six after them ask whether
what is present is VIABLE: a bead used to pass filing carrying a plan that
could not parse, acceptance criteria that went stale on the next release wave,
and prose that broke the anchor extractor. Every one of those cost a round.

For every row reporting `"passed": false`, apply its `detail` as the
correction. The detail NAMES the offending text — do not go looking for it:

- `<type> is not driveable` — re-type the bead to `task`/`bug`/`feature`/
  `chore`, or re-home the work under a driveable child.
- `validation_plan is blank` — author one, scoped by **Scope the
  validation_plan to every consumer**.
- `acceptance_criteria is blank` — author `- [ ]` checkboxes a named command
  can falsify.
- `missing outgoing blocks edges: <ids>` — the store WAS consulted and each
  named id is genuinely unwired: wire it per **Wire every dependency at
  intake**.
- `cross-store edges not consulted — pass --state-root` — the store was NOT
  consulted, so nothing is known about the foreign blockers this bead names.
  RERUN with `--state-root "<grid home>"`. Never wire an edge off this
  detail: the blocker it would name may already be wired by an open link bead,
  and the duplicate is a WRITE driven by a read that never happened.
- `validation_plan does not parse: <slice>` — the lane shell refused the named
  construct: rewrite as one parseable POSIX-shell command. The two shapes that
  cost rounds are a `#` inside a quoted `$(…)` command substitution, and an
  apostrophe carried in from design prose into a single-quoted program
  (`lane's`). Neither leaves a log: the lane dies at PARSE and surfaces as a
  harness throttle.
- `validation_plan is dash-incompatible: <slice>` — replace the Bash-only
  construct with POSIX sh syntax. Process substitution (`<(…)`, `>(…)`) is
  the usual one: it parses on a mac and parse-dies on CI, whose `sh` is dash.
- `absolute file paths: <paths>` — use a repository-relative path. An absolute
  path in bead text turns the round's receipt into a FAILED git-log record.
  An absolute grid-home DIRECTORY is fine; a rooted FILE is not.
- `unminted bead ids: <ids>` — mint it before citing it or cite an existing
  attached-store id. Guessed ids have shipped; create the bead first and take
  the id from the `Created` line.
- `exact release versions in acceptance_criteria: <versions>` — use
  release-relative language or a version range. Specify copies the acceptance
  list into a plan leg, and a pin goes stale on the next wave.
- `unrecorded decision citations: <citations>` — a round may not cite a
  decision it creates; cite an existing entry or describe the proposed entry
  without a citation. Discovery holds every round on a citation whose entry
  cannot exist until the work lands.

A row reporting that existence is `unchecked` is a REFUSAL about the LOOKUP,
not about the bead: a store would not read, the decision index is unwired or
crashed, or a shell could not be spawned. Restore the evidence source and
rerun — never edit the bead to satisfy an unchecked row.

Then RERUN the verb. Repeat until the report reads `"passed": true`; only then
stage the bead for approval. Nothing else stages a bead — a reading of the
fields is not the check, and this skill deliberately owns no completeness
predicate of its own.

A report carrying `error` (`bead not found`) is a REFUSAL, not a pass: the id
is wrong or the cwd is the wrong store. Correct the id or the store root and
rerun. Never approve past an `error`.

## Staging: approve with the approve verb, only after refinement

Drafts are created open and UNSTAMPED; the human's approval is the approve
verb, which re-runs the same ten-row filing preflight and then writes the
`grid.approved_*` stamp in one `bd update`. Against a LIVE station, the
mounted predicate refuses any unstamped bead with
`approval: not approved - run the approve verb` — the retired `grid.approved`
label is not read — so the mount race is closed without a timer:

- Create UNSTAMPED, wire deps, finish the description and design,
  and drive `{{runner}} filing --json --state-root "<grid home>" "<bead>"` to
  `"passed": true`. Only after human approval, from the grid home, run:

  ```
  {{runner}} approve --actor operator --json --state-root "<grid home>" "<bead>"
  ```

  The verb stamps `grid.approved_by` (the `--actor`), `grid.approved_at` (the
  UTC ISO-8601 instant) and `grid.approved_rev` (the digest of the FILING
  BASIS the preflight just evaluated — the bead's work fields, its validation
  plan and its dependency proofs); that one stamped write is the final
  transition into the mounted frontier. Approval is granted to that basis, not
  to the bead id: EDITING an approved bead's description, acceptance, design,
  validation plan or blockers refuses it at the gate with
  `approval: stale - rerun the approve verb`, so rerun the verb after any
  approved-bead edit. A refusal writes nothing — it reports `"approved": false`
  with a `reason` plus the failing filing rows; fix them and rerun the verb.
- Removing the `grid.approved_*` stamp from a bead that is ALREADY mounted does
  not evict it
  — mounted work is never evicted for budget or readiness reasons; only a
  positive terminal (bead closed / session terminal) unmounts.

## Staleness reconciliation — run BEFORE arming any store

Backlogs rot: features get built in other sessions and the beads stay open. A
stale bead costs a full agent round on already-shipped work, and (until the
committee's diff-pinning fix is everywhere) can even come back A-graded because
critics reviewed the mainline code as if it were the bead's diff.

For each ready bead: check whether the named artifact already exists in the
work repo's mainline (`git log`/`grep` for the package, class, or file the bead
names). If shipped, CLOSE IT AS STALE WITH RECEIPTS — the reason carries the
file paths and commit ids that prove it:

```bash
bd -C <work repo> close <bead> --reason "<receipts: file paths, commit ids>" \
  --actor operator
```

Closing a bead with a live agent on it is safe — that is the designed positive-
terminal unmount.

## Re-homing beads across stores

Re-creating a bead in another store carries the text, NOT the metadata:
re-stamp `validation_plan` (and any `grid.*` envelope keys) on the destination
or round 1 gates F. Re-run the exit check in the DESTINATION store before
staging.

## bd footguns

- `bd update` with an EMPTY id resolves the LAST-TOUCHED bead — never
  interpolate a possibly-empty variable into an id slot.
- Writes route by CWD: always `bd -C <store-root>` (a leading `cd` in a
  compound also re-routes the command through permission classifiers).
- `bd create --deps 'blocks:X'` makes the NEW bead block X (inverted from the
  common intent) — wire with `bd dep add` after creating.
- Grouped mutations: `bd batch` (one transaction). Bulk reads: `bd export`.
  Never `bd show` from a polling path; never spawn bd per issue in a loop.
- `--actor operator` on every mutation; reasons carry receipts.
