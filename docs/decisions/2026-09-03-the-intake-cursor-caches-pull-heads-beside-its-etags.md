---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-intake-cursor-caches-pull-heads-beside-its-etags
  surfaces:
    - "packages/github_grid_assets/lib/src/github/reconciler_cursor.dart"
    - "packages/github_grid_assets/lib/src/github/reconciler_event.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-40a4
  legacy-id: null
---
## The intake cursor caches pull heads beside its etags, at version 1 (2026-09-03) — bead `pow-40a4`

**Decision (AI; MECHANISM only).** The GitHub intake poll fetches the full
`/repos/{owner}/{repo}/pulls/{number}` resource for every PR-shaped issues row,
and `GitHubReconcilerCursor` gains `pullHeads` — head refs keyed by pull node id
— beside its existing `etags`. The conditional tag for a pull lives in `etags`
under `intake/pull/<nodeId>`, and `recordPullHead` writes, retains (newest 512)
and evicts a head together with that tag, so a `304` always has a ref to answer
with and the two never diverge.

**The cursor document stays `version: 1`.** `pull_heads` is ADDITIVE and its
absence decodes to an empty cache. A version bump is rejected because
`GitHubReconcilerCursor.fromJson` throws on `version != 1`: bumping would make
every cursor already on disk at a live seat unloadable and stop that seat
polling.

**`NormalizedGitHubEvent.pullRequestOpened` gains a REQUIRED `headRef`.** An
optional-or-defaulted ref would let a caller emit a silently empty branch — the
silent-guard shape `CLAUDE.md` forbids ("guards LOUD or GONE"). Both in-repo
construction sites are migrated in the same change.

**Why:** the issues row for a pull request carries no `head`, so the CI feedback
path could not get a branch from a `PullRequestOpened`. Fetching once at the
source beats pushing the fetch onto every consumer. Caching the ref, rather than
only the tag, is what makes the conditional re-fetch usable: without it a `304`
would leave the poll with a new observation and no ref.

**Affects:** `packages/github_grid_assets/lib/src/github/reconciler_cursor.dart`
(`pullHeads`, `pullEtagKey`, `recordPullHead`, `copyWith`, `toJson`,
`fromJson`), `reconciler_event.dart` (`PullRequestOpened.headRef` and its
generated parts), `github_reconciler.dart` (`_pullHead`),
`test/fixtures/poll_observation.json`, `test/fixtures/pull_resource.json`.
