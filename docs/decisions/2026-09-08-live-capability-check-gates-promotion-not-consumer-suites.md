---
status: accepted
date: 2026-09-08
decision-makers: ["nico"]
consulted: ["refiner"]
informed: []
register:
  spec: 1
  slug: live-capability-check-gates-promotion-not-consumer-suites
  surfaces:
    - "packages/dart_grid_assets/lib/src/dart/release_service.dart"
    - "packages/dart_grid_assets/lib/src/dart/release_command.dart"
    - "packages/grid_assets/extension/station_overlay/claude/skills/release/SKILL.md"
    - "packages/grid_assets/extension/station_overlay/agents/skills/release/SKILL.md"
  obsoletes: []
  updates:
    - "adr-0003-private-git-tag-releases-and-prerelease-gate"
  obsoleted-by: null
  updated-by: []
  bead: pow-483r
  legacy-id: null
---

# The promotion gate is the package's own live capability check, not consumer suites

## Context and Problem Statement

ADR-0003 D3 states the property "a stable release is never born until its rc
cleared every consumer", and the release skill implements that as
`validate-consumers`: resolve every consumer against the rc tag and run its
analyze/test. The consumer manifest that verb parses has never existed
(`release_service.dart:144-160`; `pow-jhpu`), so the gate has never validated
anything, and the question of whether to author it forced the prior question of
whether the gate is the right shape at all.

The 2026-09-08 lenny release wave supplied the evidence. Three real failures
occurred, and running consumers' suites would have caught **none** of them:

1. `leonard_host` and `leonard_tmux` shipped an unsatisfiable `leonard_contract`
   floor. Caught by the `scrub` declared-floor leg.
2. `leonard_flutter` removed a required parameter from the exported
   `captureScreenshot` and was planned as a PATCH. Caught by a human question
   and a hand-diff of the public barrel; the mechanical answer is
   `release classify` (`pow-dd6.1`).
3. `ext.leonard.core.screenshot` did not work at all on a running app
   (`lenny-p50d`). Caught only by booting the example app and driving it.

The third is decisive. `validate-consumers` runs the CONSUMERS' suites, and
those suites are static too — lunar, space and butane assert on types and
configuration, not on a live capture. Fanning a weak signal across more
repositories buys breadth, not depth, and would have reported green on a
`leonard_flutter` whose headline capability was broken.

The capability that failed had itself been accepted on a static
`validation_plan` (`lenny-7jhz`): it grepped that the literal string
`ext.flutter.inspector.screenshot` was PRESENT in its own source, then ran
analyze plus unit and widget tests. A grep for a symbol's own name is not
evidence that the symbol works.

## Decision Outcome

The gate that a breaking rc must pass before promotion to stable is the
**releasing package's own live capability check**: boot that package's example
under a real runtime and exercise its public capabilities, asserting real
output. Promotion is blocked until that check passes on the exact rc being
promoted.

`validate-consumers` is DEMOTED from a mandatory gate to an advisory check. It
may be run, and its result may be recorded, but a stable promotion no longer
waits on it and no consumer manifest is required for one. `pow-jhpu` is
re-scoped accordingly rather than completed as written.

ADR-0003 D3's property — that a stable release is never born untested — stands
unchanged. Only its EVIDENCE changes: from "every consumer's suite passed
against the rc" to "the package proved its own capabilities live at that rc".
The behavioural regressions consumer validation was meant to catch remain
caught, later and more cheaply, by each consumer's own CI when it adopts the
version.

### Consequences

* Good, because the evidence now exercises the thing being released, at the
  depth the failure actually lives — a package cannot be promoted having never
  run.
* Good, because it removes a manifest that must enumerate and track every
  consumer of every published package across two umbrellas, and that is stale
  the moment a consumer is added.
* Good, because it puts the check in the repository that owns the code, so the
  team that breaks a capability is the team whose CI goes red.
* Bad, because a live check needs a real runtime in CI — a booted app, a host
  platform — which is slower and more failure-prone than resolving packages,
  and its cost may push it off the default PR lane onto a release-gating leg.
* Bad, because a behavioural change that breaks a consumer without changing the
  API is no longer caught before publication. It surfaces when that consumer
  bumps, so the person who finds it is not the person who caused it.
* Bad, because this narrows a ratified decision on the strength of one wave's
  evidence, and one wave is a small sample.

### Confirmation

`lenny-v1l8` implements the first such check: it boots the workspace example
app, drives `observe` and `screenshot` over the VM service, and asserts a known
semantics node plus PNG magic bytes and non-zero decoded dimensions. Its
acceptance requires it to go RED against `leonard_flutter` 0.4.0-rc.1, the
version whose capability is broken, before it is trusted to gate anything.
