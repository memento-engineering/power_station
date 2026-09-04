---
status: accepted
date: 2026-09-04
decision-makers:
  - "Nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: station-metrics-report-splits-never-a-global-cap
  surfaces:
    - "packages/analytical_grid_assets/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-2jdp
  legacy-id: null
---

# Station metrics split work and never recommend a global cap

## Context and Problem Statement

The station ledger now retains enough typed historical telemetry to report
health and effectiveness without reconstructing engine state. The operator's
2026-09-03 ruling requires token distributions rather than averages, explicit
sparse-data handling, distinct work kinds, and conservative local guidance
without turning an early data set into an enforced global budget.

## Decision Outcome

A report reads the composing grid's state store first and then the grid state
store of every mounted roster member, in roster order, de-duplicated by
canonical grid root. It reuses `mountedRosterOf` for roster resolution and
`projectSessionLedgerMetrics` for ledger interpretation; absent and failed
stores remain explicit outcomes.

Overall false-F values are summed from `falseFs`; overall cache rate is derived
after summing `cacheTokens.cacheRead`, `cacheCreate`, and `uncachedInput`;
overall landed cost is divided by landed count only after summing
`landedDeliveries`; rework maxima and grade counts likewise merge their
projection fields. Per-store ratios are never averaged and aggregate values are
never reconstructed from result nodes. Only day provenance, harness/model cache
rows, and other explicitly split reporting inspect `sessionsById`. The landed
token numerator is the one reading the owned components do not carry; it is
summed over exactly the node set the engine sums `landedCost` across, so the
two stay commensurable.

Token distributions split on six axes: circuit is the node path after stripping
the owning work-bead prefix; task is the owning work-bead id; lane is the
projected lane; capability is the recorded result capability or the circuit's
leading segment; harness and model are their projected values. Any missing axis
value is retained under `(unreported)`.

The first axis is named **circuit**, not seat. The operator's report shape
asked for a split "by seat", but `the_grid#agent-seat-and-agent-disc` (accepted
2026-09-01) reserves **Agent Seat** for a standing agent position — a role
definition plus a wake condition — its `register.surfaces` include the glob
`**/*_grid_assets/**`, which matches this pack by construction, and it names
space-5rp as the work freeing the word from existing code symbols. Minting a
third sense of the noun while the organization clears the second would collide,
so the axis carries the circuit noun it actually names: a coordinate in the
work bead's circuit. The reserved word appears in this pack only in the doc
comments that explain the distinction, enforced by `package_shape_test.dart`.

Percentiles use nearest rank over observed samples. Every split reports sample
count and distinct sampled-session count; fewer than five sampled sessions is
`insufficient-data`, so it emits no p50, p90, p99, maximum, or invented zero. A
sufficient split reports p50, p90, p99, maximum, and the session behind the
maximum.

Each node is classified by first match as typed non-result, replayed work,
substantive grade, or successful work. Every axis bucket builds a distinct
metric distribution for each work bucket; no distribution pools the four. A
fail-closed default, or a grade with absent transport, is a typed non-result; a
later session for an already-attempted work bead is replayed work; a remaining
grade is substantive; an ungraded remaining node is successful work.

Recommendations exist only per circuit and per task. They sum total tokens per
axis key within each healthy terminal session, take the observed high-water
mark when at least five sessions sampled, and apply explicit 1.5x headroom. A
healthy terminal session is closed, delivered, and carries no substantive F. No
global recommended cap ships, and this surface reports only: it enforces no
limit.

### Consequences

* Good, because operators and agents can compare like work with provenance
  while sparse or missing telemetry remains visible instead of becoming a
  misleading average or zero.
* Good, because owned aggregate math cannot drift from the engine projection.
* Bad, because five-session buckets deliberately withhold numeric guidance and
  the report remains descriptive until enough healthy terminal history exists.
* Cost, because the first split axis reads `circuit` where the operator's
  request said "seat"; the mapping is stated here and in the axis doc comment.

### Confirmation

`report_builder_test.dart`, `distribution_test.dart`, `split_axis_test.dart`,
`metrics_command_test.dart`, `package_shape_test.dart`, and
`reporting_only_fence_test.dart` pin the owned merges, split axes, nearest-rank
floor, structured and human faces, read-model import boundary, reserved-noun
fence, absence of a global cap, and reporting-only boundary.
