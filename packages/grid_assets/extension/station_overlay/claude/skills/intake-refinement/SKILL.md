---
name: intake-refinement
description: >
  Shape work beads so a resident the_grid station can drive them: the required
  validation_plan metadata, driveable issue types, dependency wiring, stamped
  grid.approved approval via the approve verb, and reconciling a backlog
  against what already shipped in mainline. Use when filing, approving,
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
   hard-blocks at review. Scope the plan to the package the work touches;
   `dart pub get` first — worktrees start unresolved.
3. **Deps wired the right way round** — `bd dep add <blocked> <blocker>`.
4. **A description an agent can act on alone** — the agent receives the bead
   text and a worktree, nothing else. Name packages and acceptance shape.

## Staging: approve with the approve verb, only after refinement

Drafts are created open without `grid.approved`; the human's approval is the
approve verb, which runs the filing preflight and then writes the label AND its
stamp in one `bd update`. Against a LIVE station, the mounted predicate refuses
any bead missing the label, and refuses a hand-added, unstamped one with
`approval: unstamped label - approve with the approve verb`, so the mount race
is closed without a timer:

- Create without `grid.approved`, wire deps, and finish the description and
  design. Only after human approval, from the owning store root, run:

  ```
  {{runner}} approve --actor operator --json "<bead>"
  ```

  The verb stamps `grid.approved_by` (the `--actor`), `grid.approved_at` (the
  UTC ISO-8601 instant) and `grid.approved_rev` (the store root's git HEAD sha)
  beside the label; that one stamped write is the final transition into the
  mounted frontier. A refusal writes nothing — fix the reported `reason` and
  rerun the verb.
- Removing `grid.approved` from a bead that is ALREADY mounted does not evict it
  — mounted work is never evicted for budget or readiness reasons; only a
  positive terminal (bead closed / session terminal) unmounts.

## Staleness reconciliation — run BEFORE arming any store

Backlogs rot: features get built in other sessions and the beads stay open. A
stale bead costs a full agent round on already-shipped work, and (until the
committee's diff-pinning fix is everywhere) can even come back A-graded because
critics reviewed the mainline code as if it were the bead's diff.

For each ready bead: check whether the named artifact already exists in the
work repo's mainline (`git log`/`grep` for the package, class, or file the bead
names). If shipped: `bd -C <work repo> close <bead> --reason "<receipts: file
paths, commit ids>"`. Closing a bead with a live agent on it is safe — that is
the designed positive-terminal unmount.

## Re-homing beads across stores

Re-creating a bead in another store carries the text, NOT the metadata:
re-stamp `validation_plan` (and any `grid.*` envelope keys) on the destination
or round 1 gates F.

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
