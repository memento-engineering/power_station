---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: code-validation-preserves-diagnostics-and-reports-deadline
  surfaces:
    - "packages/grid_assets/lib/src/agent/captured_output.dart"
    - "packages/grid_assets/lib/src/code/committee.dart"
    - "packages/grid_assets/lib/src/code/landing.dart"
  obsoletes: []
  updates: ["revalidate-cfe-diagnostics-lead-before-tail"]
  obsoleted-by: null
  updated-by: []
  bead: pow-cbii
  legacy-id: null
---
# Code validation preserves diagnostics and reports its deadline

## Decision Outcome

The deterministic `code-validation` lane writes every Validation Plan's full
combined stdout and stderr to `.grid/critique/code-validation.log` while
preserving `.grid/critique/code-validation.rc` byte-for-byte. On non-zero exit,
`Error:`, `Failed to load`, and line-leading `[E]` diagnostics are deduplicated
in encounter order, bounded to 320 characters, and placed before the route's
lane-named hard block; the advice-stripped tail and relative full-log path
follow. A zero exit retains its prior grade-A payload with no rationale.

`code-validation` and `RevalidateCapability` share the diagnostic extractor,
head bound, and full-log I/O in `captured_output.dart`. The gating shell remains
the writer for `code-validation`, because its output exists only in the spawned
process; `CriticCapability.result` reads that promised log through the shared
helper.

The lane arms a deadline stamp before the Validation Plan and removes it only
after writing the normal rc. The runtime provider's watchdog `Died` event is
completed only when it carries the explicit exceeded-deadline-and-killed reason;
the remaining stamp then makes the timeout a durable grade-F result that names
the ten-minute `kGatingDeadline`. Every other process death retains the existing
failed-event behavior.

## The stamp lives outside the swept critique dir

`power_station#a34-bead-pow-uok-a15-5-alt-a-s-round-stamp-gets-a-capability`
governs where a survival marker may live: "The marker lives OUTSIDE
`.grid/critique/`, under `.grid/critique-incarnation/`, because
`sweepStaleCritique` empties the critique dir of everything except the current
round's `<rubric>.json`" — a marker inside it would be deleted by a mid-wave
sweep (the tg-60t race) and the fix would silently degrade. The deadline stamp
is exactly such a marker, and it is armed for the whole ten-minute window, so it
is written to `.grid/critique-incarnation/code-validation.deadline`. A stamp
that outlives an unrelated round is harmless for A34's own reason: only a spawn
can precede a probe, and every spawn rewrites it.

The `.log` and the `.rc` stay together inside `.grid/critique/`: they are the
one run's two artifacts, written by the same script and read only as a pair, so
the sweep must retire them together. That is also why the shared log READER is
tolerant while the writer stays loud — a log the sweep removed under a running
lane degrades to `<no output captured>` inside a reason that still names the
exit class and the log path, instead of throwing out of a result hook and
reproducing the blind hold this mechanism exists to prevent.

## Why this extends the revalidate rule

`power_station#revalidate-cfe-diagnostics-lead-before-tail` established that
front-end diagnostics lead a retained tail and that the full output is durable
on disk. The code-validation lane runs the same bead-owned Validation Plan on
every review round, so hiding its output would preserve the same diagnosed
failure at a more frequently executed boundary. Sharing the extractor and log
I/O makes the two lanes one mechanism. `[E]` broadens the recognized validation
shape for both, but only at the START of a line: `dart test` marks a failing
PROGRESS line with a trailing `[E]`, and promoting those would lead the reason
with progress rather than the cause — the tail-first receipt
`power_station#captured-process-output-escalates-tail-first` and bead `pow-gy41`
pinned, which stays byte-identical.

## Consequences

A failed review gate identifies the failing file or tool line before the
engine's reason cap, while the full worktree log remains authoritative. A
watchdog kill is distinguishable from a plan that never produced an rc. The
round-start critique sweep owns cleanup of the log, the disarmed stamp is
removed by the lane itself, and an unrelated process death cannot masquerade as
a timeout.

## Affects

`packages/grid_assets/lib/src/agent/captured_output.dart`,
`packages/grid_assets/lib/src/code/committee.dart`,
`packages/grid_assets/lib/src/code/landing.dart`, their focused committee and
landing tests, and the updated register edge on
`power_station#revalidate-cfe-diagnostics-lead-before-tail`.
