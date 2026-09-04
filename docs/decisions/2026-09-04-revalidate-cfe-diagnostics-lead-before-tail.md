---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: revalidate-cfe-diagnostics-lead-before-tail
  surfaces:
    - "packages/grid_assets/lib/src/code/landing.dart"
  obsoletes: []
  updates: ["captured-process-output-escalates-tail-first"]
  obsoleted-by: null
  updated-by: []
  bead: pow-gvfx
  legacy-id: null
---
# Revalidate CFE diagnostics lead before the retained tail

## Decision Outcome

For `RevalidateCapability` alone, a non-zero validation result containing an
`Error:` or `Failed to load` line leads its escalation reason with those lines,
deduplicated in encounter order and bounded to 320 characters, before the
existing advice-stripped `landReasonTail`. The diagnostic head and tail share
`kRevalidateReasonTailChars`; every failed run also writes the full captured
`ShellRunResult.output` to `.grid/critique/revalidate.log`, and the enriched CFE
reason names that relative path.

A result with no CFE diagnostic line retains the existing reason byte-for-byte.
The shared `landReasonTail`, `planOutputWithoutPubAdvice`, git/gh delivery
callers, exit-code lead, and path diagnostic are unchanged.

## Why this narrows rather than reverses tail-first

`power_station#captured-process-output-escalates-tail-first` says the useful
line is at the end and the tail keeps the diagnosis rather than progress noise.
That remains correct for git, gh, ordinary command failures, and the retained
portion of revalidate output. The Dart front end is the measured exception: it
prints its file:line:column and missing-symbol cause first, followed by many
loading lines and a failure index. Leading only those recognized CFE lines
preserves that cause under the engine's head-first 500-character persistence
cap without changing any other captured-output consumer.

## Consequences

The short gate reason carries both the CFE cause and its cause-last context,
while the worktree log remains the unabridged source. Duplicate diagnostics do
not consume the head budget. A diagnostic set longer than 320 characters is
marked with a trailing ellipsis; the full lines remain in `revalidate.log`.
A log write failure stays loud rather than returning an escalation that claims
provenance was persisted.

## Affects

`packages/grid_assets/lib/src/code/landing.dart`
(`RevalidateCapability.route` plus private extraction/bounding constants and
helpers), `packages/grid_assets/test/landing_circuit_test.dart`, and this entry.
