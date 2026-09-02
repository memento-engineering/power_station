# acceptance-testability

Are the bead's acceptance criteria TESTABLE — and is the validation plan a
1:1, runnable map onto them? Grade the acceptance field and the
`## Validation Plan` section together, nothing else. You are blind to the
other lanes' concerns (fit, ADR citations, plan detail) — weigh ONLY whether
"done" is checkable by command.

A criterion is testable when a named command can falsify it: a specific
`dart test` invocation, a `dart analyze` run, a grep with an expected hit (or
its absence), a CLI run with expected output. "Works well", "is fast", "is
robust" are not criteria — nothing can fail them. The validation plan then
carries, for EACH criterion, the exact command and its expected result — the
downstream build is validated by running exactly these, so a gap here is a
criterion that will never be checked.

## Bands

- **A** — every criterion is an independently testable checkbox, error/edge
  cases included, ordered most-critical first; the validation plan maps 1:1
  onto them (every criterion has its command + expected output, every item
  names its criterion); the commands are real for THIS tree (the named test
  files/paths exist or are created by the plan; the runner is the house one —
  `dart test`, `dart analyze`, or an exact shell line).
- **B** — the criteria are testable and the mapping is whole, with minor
  looseness: an expected output left implicit where the command makes it
  obvious, or one edge case folded into a broader criterion.
- **C** — the happy path is testable but failure modes are not, or the
  validation plan covers most-but-not-all criteria; the builder must invent
  checks for the gaps.
- **D** — criteria mix testable and untestable statements, or the validation
  plan is generic ("run the tests") rather than mapped; two builders would
  check different things and both could claim done.
- **F** — the criteria are goals, not checks ("committee works end to end"),
  or there are no checkboxes at all, or the validation plan is absent/asserts
  nothing a command can falsify. Nothing here can gate a wrong build.

## Calibration

- Actually verify one command per criterion block against the worktree: a
  validation item naming `test/<file>_test.dart` that neither exists nor is
  created by the implementation plan is a finding, not economy.
- A manual verification step is acceptable ONLY where no automated check can
  exist (a live external service), and must still name the exact action and
  expected observation. Prefer-automated is the house rule (pure logic tested
  before IO is wired).
- Vacuous checks grade no better than none: a validation item that passes even
  if the change were broken (an unconditional `dart analyze` on an untouched
  package) does not validate its criterion — treat the criterion as unmapped.
- Count the mapping BOTH ways: an unmapped criterion caps at C; a validation
  item mapped to no criterion suggests the criteria are incomplete — name it.

## Ownership — who can fix a D or an E?

Every `D` or `E` you write carries an `owner`, and it decides whether the
station corrects the spec automatically or asks a human:

- **`architect`** — the fix is derivable from the bead AS WRITTEN plus the
  tree. Re-running the specify stage with your rationale would produce it.
  Here: a criterion with no command, a validation item naming a path that does
  not exist, an unmapped criterion.
- **`author`** — the fix needs a decision the bead TEXT does not make. Here:
  "done" itself is undecided in the bead (which behaviour is the deliverable,
  which of two acceptance shapes is wanted), so no command can be named until
  a human says what passing means.

Choose `author` only when no re-run of the architect could converge, however
good it is: an `author` verdict spends NO auto-correction round and parks the
bead for a human immediately. When you do, name the CHOICE and its options in
your rationale — that text IS the gate a governor reads.
