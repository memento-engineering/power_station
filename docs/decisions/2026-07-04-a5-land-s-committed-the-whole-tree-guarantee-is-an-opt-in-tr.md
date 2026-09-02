---
status: accepted
date: 2026-07-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a5-land-s-committed-the-whole-tree-guarantee-is-an-opt-in-tr
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A5"
---
## A5 (2026-07-04) — land's "committed the WHOLE tree" guarantee is an OPT-IN `TreeVerifiableSourceControl` interface (mirrors `ReceiptCapableSourceControl`), reusing `GitOps.hasUncommittedWork` rather than a new git call

**Decision:** `LandCapability` now Gates (never silently pushes) when, after `commitAll`, the `SourceControl` ALSO implements a new `TreeVerifiableSourceControl` marker interface AND its `uncommittedResidue` reports non-null residue (or a probe failure — fail-closed). `GitSourceControl` implements it by delegating to `GitOps.hasUncommittedWork` (the SAME three-gate `git status --porcelain` probe the worktree-reap logic already trusts) — no new git call. A plain `SourceControl` (bare test fakes, a future non-Git impl) is left untouched — the check is skipped entirely, exactly like `ReceiptCapableSourceControl`'s existing opt-in posture for the PR body.
**Why:** `SourceControl.commitAll` (the grid_engine interface) returns `void`, so `LandCapability` has no OTHER signal that its own commit actually captured everything (the tg-x1j r1 incident the bead names — a botched land silently committed a subset, stripping `session_scope.dart` edits from the PR). Widening the engine interface itself is out of this bead's worktree scope (a the_grid change); the `is`-detected marker interface is the SAME power_station-local stopgap pattern this file already uses for `ReceiptCapableSourceControl`, so it composes with zero engine changes and zero behavior change for any caller using a plain `SourceControl` fake (verified: every existing `LandCapability` test in `track_h_code_extension_test.dart` passed unmodified).
**Affects (if promoted):** `packages/grid_assets/lib/src/code/code_capabilities.dart` (`TreeVerifiableSourceControl`, `GitSourceControl.uncommittedResidue`, `LandCapability.run`'s post-commit check) + new tests in `track_h_code_extension_test.dart`. A future the_grid change that widens `SourceControl.commitAll` to return a result itself would let this stopgap retire, same as the receipt-regression gap's own note.
**Status:** pending.

