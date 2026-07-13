---
name: harvest-review
description: >
  Review and land what a the_grid station built: verify each terminal
  session's branch delta, committee grades, and validation plan in the real
  worktree, then push and open a PR with receipts. Use when the watch reports
  all sessions terminal ("harvest time"), when deciding keep vs rework vs
  close-as-stale for a finished round, or when landing grid/<bead> branches —
  even when the ask is just "what did the station produce."
compatibility: Requires git, gh, bd (beads CLI), dart.
metadata:
  author: memento-engineering
---

# Harvest review

Harvest when every live session reaches terminal (the watch's "harvest time").
The station does not push, PR, or close work beads on a commit-only arm — the
harvest is where a human-adjacent reviewer turns branches into landings.

## Per-bead verification (all four, in order)

For each work bead with a terminal session:

1. **Session outcome** — from the state store export: `complete` with no open
   gate is clean; anything gated/escalated goes back to `gate-medicine`.
2. **The branch delta** — in the worktree:

   ```
   git log --oneline origin/main..HEAD
   git diff --stat origin/main..HEAD
   ```

   **Trust no grade on a zero-commit branch.** Critics have graded
   pre-existing mainline work as the bead's own diff (A/A/A citing a
   weeks-old mainline commit). Zero delta + open bead = stale intake → close
   the bead with receipts (`intake-grooming`), no landing.
3. **Committee verdicts** — read the rationales in
   `.grid/critique/<rubric>.json`. A/B with substantive rationales supports
   landing; a C names the follow-up (quote it in the PR or the next round's
   note); the gating `code-validation.rc` must be `0`.
4. **The validation plan, run by YOU** — re-run the bead's `validation_plan`
   in the worktree and watch it pass. The rc file proves it passed once;
   your run proves it still does.

## Keep / rework / close

- **Keep** — real delta, grades hold up, plan green → land it.
- **Rework** — a critic's finding is real and actionable → `{{runner}} rework`
  with the finding quoted as the note (see `gate-medicine`).
- **Close-as-stale** — zero delta, work already in mainline → close with
  receipts.

A good round can also FIX its predecessor's finding — compare rounds: a
round-2 commit that addresses round 1's C (and a regraded verdict) is the
system working; say so in the PR.

## Landing

```
git -C <worktree> push origin grid/<bead>
gh pr create -R <org>/<repo> --base main --head grid/<bead> \
  --title "<conventional-commit title> (<bead>)" --body "<receipts>"
```

The PR body carries the receipts: bead id, commit list, committee grades,
the validation command + test count, and anything a reviewer must know
(rework rounds, quoted critic findings). End with the house attribution
footer.

- **Merges are squash-only** (one commit per bead) and **stay with the human**
  unless explicitly delegated per-PR.
- On merge: close the work bead with the PR URL as the receipt, and delete
  the worktree branch if the provisioner hasn't.

## Reporting the harvest

Lead with the verdict: what landed, what needs the human, what was stale.
Per bead one line — delta, grades, plan result, disposition. Then the queues:
PRs awaiting merge, beads awaiting bless, findings filed. The reader stepped
away hours ago; write for them.

## Gotchas

- `mounted`/`live sessions` in /status count session beads; the harvest
  trigger is live sessions returning to ZERO after being live.
- Worktrees survive the harvest — they are the review surface; don't clean
  them until the bead is closed.
- A bead left OPEN with a terminal session does not respawn (the cursor is
  durable) — but it still occupies the ready frontier until closed.
- Pushing a branch and opening a PR is reversible; merging is not — hold the
  gate.
