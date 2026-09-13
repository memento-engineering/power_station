---
status: accepted
date: 2026-09-13
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: pull-feedback-uses-explicit-references
  surfaces:
    - "packages/github_grid_assets/lib/src/github/reconciler_event.dart"
    - "packages/github_grid_assets/lib/src/github/reconciler_cursor.dart"
    - "packages/github_grid_assets/lib/src/github/github_reconciler.dart"
    - "packages/github_grid_assets/lib/src/github/ci_feedback.dart"
    - "packages/github_grid_assets/lib/src/github/ci_feedback_projection.dart"
  obsoletes: []
  updates: ["adr-0005-landing-policy-grade-gated-auto-merge"]
  obsoleted-by: null
  updated-by: []
  bead: pow-ocpf
  legacy-id: null
---

# Pull-request feedback is attributed by an explicit reference, never by a branch name

## Context and Problem Statement

The station polled open pull requests and their check runs, fed the result to
the governor — and then discarded every pull request whose head was not on a
`grid/` branch. A pull request opened by a seat, rather than minted by a round,
was therefore invisible to the whole loop: no CI feedback, no green-and-unmerged
event, no governor notification. It waited for a human to notice it.

The cost is not only latency. Measured across the org register's twelve merged
pull requests on 2026-09-12, the two `grid/` branches merged fast while pull
request 8 sat open for 15.9 hours. While it sat, `main` moved: pull request 9
landed the explicit roster-surface marker, pull request 8 then merged
UNCONVERTED, and `main` went red. A stalled pull request does not merely arrive
late — it merges against a base it was never checked against.

The filter existed for a reason, which is why widening it is not the fix: the
reconciler attributed a pull request to a bead THROUGH its branch name.
`grid/<bead>` parses; `org/some-slug` does not. A merely wider filter would
surface pull requests the governor could not attribute to anything, which is a
different failure — an event with no subject.

## Considered Options

* **Seats open pull requests on `grid/<bead>` branches.** Rejected. A
  seat-authored pull request is not a round, and harvest assumes a `grid/`
  branch has a session behind it.
* **A separate unattributed-pull watch as the primary mechanism.** Rejected. It
  grows a second watch surface, and the station owns one loop that assets attach
  to. Reporting an unattributed pull request stays part of this leg.

## Decision Outcome

Branch names stop being the attribution mechanism. Branch-name-as-database is
the fragile part of the design, not merely a narrow filter.

1. **Every open pull request rides the one existing poll and outbox.** The
   feedback leg emits one aggregate observation per open pull request on any
   branch, through the durable pending/acknowledge/replay path the cursor
   already owns. No second dispatcher, watcher, registration or loop.
2. **Attribution is stated, never inferred.** Exactly one `Refs: <bead>` trailer
   in the pull-request body wins outright and costs no correlation read. With no
   trailer, exactly one bead whose bd `external_ref` is `gh-<number>` supplies
   the id. No branch value takes part in any decision.
3. **Ambiguity or absence is reported, never dropped.** Two distinct trailers,
   or zero or many beads carrying the external reference, produce
   `reconciler.ciFeedbackUnattributed` and mutate nothing. Silence about an open
   pull request is the defect this removes, so an unattributable pull request
   degrades to a weaker event rather than to nothing.
4. **The one-hour stall flag is observation only.** `greenSince` is the latest
   successful check completion for the current head; a pull request becomes
   stalled at `kPullRequestGreenStallBound` — one hour — or more past it.
   Crossing the bound emits a distinct observation and performs no merge, no
   rework and no gate.

This UPDATES `adr-0005-landing-policy-grade-gated-auto-merge` in exactly one
sentence of D2 — "The station does not poll or reconcile the green path" —
and only in its observation half: the station now REPORTS green and stalled
open pull requests. Every other clause of ADR-0005 stands unchanged: the three
`DeliveryMethod` postures, the grade gate, GitHub owning the wait for required
checks, the merge behavior and strategy, and the loud-refusal policy. Nothing
here decides what the governor DOES with the event.

### Consequences

* Good, because a pull request opened by a seat, a human or a bot is now
  reported with its aggregate check state, mergeability and green instant, so
  the loop can no longer be silent about work that is finished and unmerged.
* Good, because any branch naming works and seats keep their own; the station
  stops owning a namespace it does not need to own.
* Bad, because a pull request that states no reference and carries no matching
  `external_ref` still needs a human — it is reported, but nothing can act on
  it.
* Bad, because aggregating one state per head is deliberately conservative: a
  head mixing successes with `skipped` or `neutral` completions reports
  `inconclusive` rather than green, so a seat that wants it to land must make
  those checks succeed or state the reference and land it by hand.

### Confirmation

`packages/github_grid_assets` analyzes clean, and its suite covers a non-`grid`
green pull request end to end, every aggregate check state, both attribution
paths, the unattributed report, the preserved `grid/` actions, and the
deterministic one-hour crossing from the bounded cursor cache.
