---
status: accepted
date: 2026-07-10
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a9-bead-pow-6wo-re-homed-from-the-grid-tg-fc6-the-committee
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A9"
---
## A9 (2026-07-10) — bead `pow-6wo` (re-homed from the_grid `tg-fc6`): the committee gains a `pin-diff` pre-critic step that GATES an empty `origin/<base>...HEAD` delta and pins the critics' scope to that diff

**Decision:** the `code_review` circuit (`packages/grid_assets/lib/src/code/committee.dart`) gains one new step, `pin-diff` ([PinDiffCapability], a `ServiceCapability`), inserted between `clear-critique` and the four critic lanes — `clear-critique → pin-diff → {4 critics} → route`, with the critics' `dependsOn` re-pointed from `clear-critique` to `pin-diff` (they still transitively depend on `clear-critique`). Several autonomous calls the bead's fix-direction left open:
(1) **The empty-delta terminal is a `Gate` (human ruling), not an auto-close/auto-flag.** The bead offered "gate for human ruling, OR auto-flag stale-bead"; I chose `Gate` because it reuses the committee's existing park-for-a-human affordance (a `type=gate` bead minted through the chokepoint, A37-safe) with zero new outcome machinery, and because "this bead's work is already in mainline" is a judgement call a human should confirm before the ready-bead is closed. The critics `dependsOn pin-diff`, so the `Gate` withholds them — the empty delta never reaches a critic (the load-bearing half of the fix).
(2) **"Empty" is defined as an empty `git diff origin/<base>...HEAD`** (three-dot, from the merge-base — a base that moved forward while the bead ran can never widen the scope). This catches the exact live condition (a branch with ZERO commits beyond origin/main) AND a net-zero diff (commits that cancel out); the Gate reason distinguishes the two by the `git log origin/<base>..HEAD` commit count. I did NOT fetch first: for emptiness detection the worktree's local `origin/<base>` ref (as of the worktree cut) is a conservative-safe baseline (fetching can only widen a diff, never shrink an empty one to non-empty), and skipping the fetch keeps `pin-diff` free of a network failure mode — the landing circuit's `rebase` already fetches when currency actually matters.
(3) **A git error (unresolvable `origin/<base>`, or a `git` that won't launch) is `Failed` (LOUD), not `Gate`.** An unknown scope must not masquerade as a stale bead nor silently advance critics against an empty scope; failing closed routes to supervision (guards LOUD or GONE). A write failure of the pinned-diff file is likewise `Failed` (a missing pinned diff would drop the critics back to free rein — the exact failure being closed).
(4) **The critics receive the pinned diff via a FILE, not inline in the prompt.** `pin-diff` writes the delta to `<workspaceDir>/.grid/critique/pinned.diff` (round-fresh: `clear-critique` wipes the dir first, then `pin-diff` — which `dependsOn` it — rewrites), and each LLM critic's prompt (`buildCriticPrompt`) names that ABSOLUTE path as its EXCLUSIVE review scope with an OUT-OF-SCOPE instruction for pre-existing / already-in-mainline code. A file (not inline embedding) keeps a large diff off the `claude -p <prompt>` argv (ARG_MAX) and mirrors how the critic already WRITES its verdict to a file; the agent reads it on demand.
(5) **`pin-diff` reuses the `code` registry's existing `gitRunner` seam** (`buildCodeRegistry(gitRunner:)`, the one `rebase` already rides) rather than a new param — one git seam for the registry's git-running capabilities. Its offline/dry-run posture is a no-op-to-`Ok` when the `Workspace` is absent OR the worktree directory does not exist on disk (the synthetic `/grid/worktrees/...` path an offline suite mounts), mirroring `GitSourceControl.provisionWorkspace` / `AgentCapability._linkWorkspace` (A1) — so the offline acceptance/kernel tests drive it without a fake git at all, and a LIVE review (a real worktree the agent just worked in) always runs the guard.
**Why:** the live-arm finding (first live arm, 2026-07-10; the bead re-homed from the_grid `tg-fc6` per Nico's partition call — the committee is power_station's): 4 of 6 ready genesis beads were already shipped in mainline; for two (hjj, zxf) the branch had ZERO commits beyond origin/main, yet the critics graded A/B-range verdicts by reviewing PRE-EXISTING mainline work as if it were the bead's diff (zxf's spec-adherence A explicitly cited a 2026-06-14 mainline commit). Nothing pinned the review to the branch's own delta. This lives in grid_assets code/committee (the fix-here half); the companion INTAKE discipline — reconcile a substation's ready frontier against mainline BEFORE arming it — belongs to backlog refinement, not this bug (see the_grid `docs/SCRATCH-memento-composition.md` §4), and is NOT attempted here.
**Affects (if promoted):** power_station code (built this bead): `packages/grid_assets/lib/src/code/committee.dart` (`kPinDiffStep`, `pinnedDiffPath`, `PinDiffCapability`, the `kCodeReviewCircuit` shape, `buildCriticPrompt`'s scope section), `packages/grid_assets/lib/src/code/code_capabilities.dart` (`buildCodeRegistry` registers `pin-diff`), new `test/track_c_pin_diff_test.dart`, and the committee/acceptance/kernel tests updated for the new circuit shape (`track_c_committee_test.dart`, `track_c_critic_test.dart`, `circuit_acceptance_test.dart`, `station_kernel_test.dart`, `pdr_s7_acceptance_test.dart`, `invariant_2_only_the_chokepoint_writes_test.dart`, `support/asset_fakes.dart`'s `kPinDiffNode`). the_grid: `tg-fc6`'s companion mainline-reconcile intake (`SCRATCH-memento-composition.md` §4) is a SEPARATE, un-built follow-up.
**Status:** pending.

