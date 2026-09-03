---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: []
register:
  spec: 1
  slug: scaffold-restore-merges-dirs-and-unwinds-its-provision
  surfaces:
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/test/track_h_code_extension_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-kjw0
  legacy-id: null
---

# Scaffold restore merges directories, and a discarded provision unwinds the worktree and branch it minted

## Context and Problem Statement

`GitSourceControl.provisionWorkspace` stashes the engine's pre-acquire `.grid`
scaffold, provisions a fresh worktree, and restores the scaffold into it. The
restore refused on ANY existing target path. Since
`the_grid#agent-disc-file-shape-and-home` made `.grid/seats/` tracked state,
every fresh the_grid checkout already carries a `.grid` directory, so the
restore refused on the shared DIRECTORY name and the failure handler deleted
the freshly added worktree while leaving git's registration and the minted
`grid/<bead>` branch behind. Every subsequent mount then wedged on git's "is a
missing but already registered worktree".

## Decision Outcome

A directory meeting a directory is a MERGE, not a collision: the restore moves
the stash entry's children into the existing directory, recursively, and only a
FILE landing on an existing path raises the existing "scaffold path collision"
error. Collisions are detected across the whole tree before anything moves, so
the refuse-before-moving guarantee holds at every depth.

A discarded provision is UNWOUND rather than half-deleted: `git worktree remove
--force` from the root repo, `git worktree prune`, and `git branch -D` for a
branch THIS call minted (never an adopted one), then a verification pass that
refuses LOUDLY, naming what survived, when the registration or the minted branch
is still there.

`the_grid#adr-0006-dogfood-rig-and-live-write-authorization` Decision 3's
fail-closed cleanup — "A worktree is removed only when its lifecycle bead is
closed AND the branch is pushed, and only after the three-gate check passes" —
governs the REAPER, a worktree an agent has worked in. The unwind acts inside a
single failed `provisionWorkspace` call, on the path that call just registered,
before any agent is spawned, and it completes a `deleteSync(recursive: true)`
that already ran unconditionally — so it removes strictly less than the previous
code did. The three gates stay in force for `reap`, and the unwind keeps that
decision's other clause verbatim: `git worktree remove` runs from the root repo,
never from inside the worktree.

### Consequences

* Good, because a fresh worktree in a substation that tracks anything under
  `.grid/` provisions normally, and a failed provision leaves git exactly as it
  found it, so the retry mints fresh instead of wedging forever.
* Bad, because the unwind spends three or four extra git invocations on the
  failure path, and a merge means the scaffold and the checkout now share
  directories, so a future tracked FILE at a scaffold path is still a refusal.
