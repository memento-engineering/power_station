---
status: accepted
date: 2026-09-08
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: own-workflow-failures-are-self-approved
  surfaces:
    - "packages/github_grid_assets/lib/src/code/workflow_run_intake_rule.dart"
    - "packages/github_grid_assets/lib/src/github/github_reconciler.dart"
    - "packages/github_grid_assets/lib/src/github/reconciler_event.dart"
    - "packages/github_grid_assets/lib/src/intake/**"
  obsoletes: []
  updates: ["github-intake-files-open-and-unstamped"]
  obsoleted-by: null
  updated-by: []
  bead: pow-1rn.7
  legacy-id: null
---
## A workflow run of the seat's OWN repository is SELF authority, and a declared rule self-approves its failure (2026-09-08) — bead `pow-1rn.7`

**Decision (Nico, 2026-09-08).** When a COMPLETED GitHub workflow run matches a
seat-declared `WorkflowRunIntakeRule` and concluded badly, the station files the
failure as work; and because the run is the repository's OWN workflow — SELF
authority, not an external actor's — a rule carrying `approve: true` also
approves it, so an agent mounts and investigates without a human in the loop.

**The occasion.** lenny's nightly (`ci.yaml`, cron `0 6 * * *`) was red on ten
consecutive runs, 2026-08-30 through 2026-09-07, and nothing noticed until a
hand sweep on 2026-09-08. The reconciler polls the repository every minute, but
its feedback leg enumerates OPEN PULLS and keeps only heads starting with
`grid/`, so a scheduled run on the default branch with no pull request could
never become an event at all. The station was not slow to react; it was
structurally blind.

**What SELF means here, exactly.** `GitHubSelfTrust` admitted exactly one
identity — a human `github` login. A run has no human author, so it is
represented as `ActorIdentity(scheme: 'github-workflow', id: 'OWNER/REPO')`, and
that identity is `TrustLevel.self` only when `OWNER/REPO` is the seat's own
configured owner/repository. Every other repository stays EXTERNAL. A fork's run
is refused twice over: `WorkflowRunIntakeRule`'s default event set excludes
`pull_request`, and the poll leg drops any run whose `head_repository.full_name`
is not the seat's, BEFORE it spends a request on that run's jobs.

**Approval rides the VERB, never a hand-written key.** Intake calls
`grid_assets`'s `ApproveService.approve` with `actor: 'github-workflow'` — the
same service `approve_command.dart` exposes to a human — so the four-row filing
preflight (driveable type, validation plan, acceptance criteria, dependencies)
remains the ONLY route to the `grid.approved_by` / `grid.approved_at` /
`grid.approved_rev` stamp that `mountEligibilityFindings` reads. This package
constructs none of those keys. A bead whose preflight fails — the designed
outcome for a rule whose `validationPlan` is blank — is left OPEN and UNSTAMPED
with the refused rows appended to its notes. Self-approval is therefore an
authority statement, not a bypass: it says WHO may approve, and changes nothing
about WHAT must be true first.

**What a rule declares.** `workflowPath` and `validationPlan` are required;
`events` defaults to `{schedule, push, workflow_dispatch}`, `conclusions` to
`{failure, timed_out}`, `branches` to the seat's default branch, `priority` to
1 and `approve` to true. An empty rule list — the `GitHubReconcilerConfig`
default — is the FEATURE-OFF value, and the poll leg returns before its first
request rather than spending a rate-limit unit on a seat that never opted in.
Declaration order is authoritative: the FIRST matching rule wins, so two
overlapping rules can never file one run twice.

**One bead per unfixed workflow, not one per night.** `externalRef
github:<run node id>` dedupes re-observation of the SAME run. A fresh run is a
fresh node id, so intake additionally refuses to file when an OPEN bead already
carries the same `github.workflow_path` and `github.head_branch`: it writes
NOTHING and logs. Appending a note to the existing bead was rejected — a note on
a stamped bead evicts its live round. Re-opening a bead closed before the next
night fails again is explicitly out of scope; a fresh run mints fresh, and that
is acceptable for v1.

**Transport.** The poll leg is enough. A webhook transport (`pow-1rn.6`) stays
deferred, and the normalized `NormalizedGitHubEvent.workflowRunConcluded`
variant is deliberately free of seat policy so a webhook decoder can later
produce the same envelope; the intake projection RESELECTS the rule rather than
reading it off the event.

**Alignment.** `power_station#github-intake-files-open-and-unstamped` said
*"`approve_command.dart` stays the only writer of the stamp
`mountEligibilityFindings` reads, so an intake bead is mountable only after a
human runs the approve verb."* This entry UPDATES that clause and narrows it:
the sole-writer half is preserved exactly, and the human-only half now admits
one further authority — the seat's own workflow identity, under a declared rule.
Human issue and pull intake is untouched and still files OPEN and unstamped.
`docs/adr/ADR-0004` D1 supplies the posture this depends on — readiness is a
property of the bead's FIELDS, and *"approval ceremony must never be the reason
a station sits idle"* — while the filing preflight remains the ceremony that
cannot be skipped.
`power_station#observation-durability-rides-the-cursor-document` and
`power_station#the-intake-cursor-caches-pull-heads-beside-its-etags` are both
EXTENDED without departure: the new leg emits through the same enqueue /
per-leg-acknowledgement / replay path, and `workflow_runs_since` is ADDITIVE at
cursor `version: 1` exactly as `pull_heads` was.
`power_station#intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel`
binds unchanged — every read and write here rides `BdCliService` over the seat's
injected `BdRunner`, and metadata is written PER KEY.
`power_station#ci-feedback-projection-is-a-value-the-binding-provides` binds
unchanged: no second dispatcher and no second registration; the feedback leg
RETURNS from a workflow run, and the sealed union makes that disjointness a
compile error to break.

**Affects:** `packages/github_grid_assets/lib/src/code/workflow_run_intake_rule.dart`
(new), `lib/src/github/reconciler_event.dart` (`WorkflowRunFailedJob`,
`NormalizedGitHubEvent.workflowRunConcluded`),
`lib/src/github/reconciler_cursor.dart` (`workflowRunsSince`),
`lib/src/github/github_reconciler.dart` (the `_runs` leg),
`lib/src/github/ci_feedback_projection.dart` (an explicit return arm),
`lib/src/intake/github_self_trust.dart` (`repository`),
`lib/src/intake/github_intake_projection.dart`,
`lib/src/intake/github_intake_store.dart`,
`lib/src/assets/github_reconciler_assets.dart` (`defaultBranch`,
`workflowRuns`), and `lib/src/assets/github_reconciler_binding_assets.dart`.
No live bead store is mutated by this change. Wiring lunar's own seat with the
lenny nightly rule is a `lunar_station` change and is filed separately.
