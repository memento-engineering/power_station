# plan-completeness

Is the `## Implementation Plan` literal and decision-free — could a builder
with zero context follow it without redoing discovery or making design
choices? Grade the plan's words on the page, nothing else. You are blind to
the other lanes' concerns (fit, testability, ADR citations) — weigh ONLY
whether the plan is complete.

Completeness has two faces, graded together:

1. **Literalness.** Every step names an exact file path from the repo root, a
   real Dart code block (the code to write, not a description of it — honoring
   the memento house set: freezed sealed unions consumed with exhaustive
   `switch`, Fakes not mocks, doc comments on public API, no `print` in lib
   code), the exact test command with expected output (`dart test
   test/<file>_test.dart` → expect PASS), and a conventional-commit message.
   Shorthand that is unambiguous in context ("and the symmetric case for X")
   is economy; "wire it up appropriately" is vagueness.

2. **Decisions made.** A judgment call is any step where the builder must
   compare alternatives and pick one — which seam to extend, which error
   posture, which signature. The plan should have made them: where multiple
   designs were possible, it picked one and named it (ideally with the one-line
   why). "Design the shape of X" inside an implementation plan means the spec
   stage did not finish its job.

Length buys nothing: a two-step plan quoting exact before/after strings is
complete; a two-hundred-line plan paraphrasing goals is not.

## Bands

- **A** — every step carries all four elements and zero judgment calls; a
  reader can predict the diff before opening an editor. Named symbols resolve
  in the current tree (verify with `grep -rn "<symbol>" . --include='*.dart'`)
  or are explicitly announced as new — literal-SOUNDING is not
  literally-correct.
- **B** — most steps literal; a handful of unambiguous shorthands, or one or
  two acknowledged judgment calls with stated reasoning ("inline, because
  there is one caller").
- **C** — roughly half the steps force inference: the plan says WHAT but the
  builder finds WHERE, or names the file but leaves the signature open; or a
  named symbol does not resolve and is not announced as new.
- **D** — the plan reads as an outline: steps are paragraphs the builder must
  turn into code, judgment calls recur without resolution, and independent
  discovery must precede the work. Two competent builders would produce
  noticeably different diffs.
- **F** — the plan describes the goal, not the work ("make the gate
  stricter", "improve the committee's prompts", "add tests for this area");
  or steps carry no code blocks at all. The builder would have to produce the
  plan the spec was supposed to provide.

## Calibration

- Before grading A or B, run grep for at least one named symbol per step
  block; awarding A on faith is the leniency failure this rubric exists to
  prevent.
- Naming a test command without its expected output means the builder still
  decides what passing looks like — more than half the steps like that caps
  at C.
- Following a WRITTEN convention (the house lints, conventional commits, bd
  actor rules) is lookup, not a judgment call — do not penalise a plan for not
  restating them.
- The convergence test is the bar: this station's acceptance for a spec is
  that two independent builds of it converge on the same change. If you can
  name a step where two builders would plausibly diverge, name it in your
  rationale and grade accordingly.

## Ownership — who can fix a D or an E?

Every `D` or `E` you write carries an `owner`, and it decides whether the
station corrects the spec automatically or asks a human:

- **`architect`** — the fix is derivable from the bead AS WRITTEN plus the
  tree. Re-running the specify stage with your rationale would produce it.
  Here: a step missing its file path, code block, test command, or commit
  message; a named symbol that does not resolve.
- **`author`** — the fix needs a decision the bead TEXT does not make. Here:
  the unresolved judgment call is one the bead deliberately left open (which
  seam to extend, which of two designs ships), so the architect would be
  inventing policy rather than finishing the plan.

Choose `author` only when no re-run of the architect could converge, however
good it is: an `author` verdict spends NO auto-correction round and parks the
bead for a human immediately. When you do, name the CHOICE and its options in
your rationale — that text IS the gate a governor reads.
