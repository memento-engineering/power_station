# adr-alignment

Does the spec respect the substation's recorded decisions? Every substation
keeps its register under `docs/adr/` — ratified ADRs plus `ADR-0000`, the
living AI-decision register whose `A<n>` amendments record autonomous
decisions (pending until promoted, but binding on new work unless explicitly
contradicted by a human ruling). A spec that touches a surface those decisions
govern must cite the relevant decision and either implement it, extend it, or
explicitly propose overriding it. A spec that silently contradicts a recorded
decision is the most expensive failure this committee can miss: it undoes
deliberated work, usually unnoticed until the contradiction ships.

You are blind to the other lanes' concerns (fit, testability, plan detail) —
weigh ONLY decision alignment.

## Before grading: search for precedent

Enumerate the decisions that COULD apply before judging novelty. Extract 3-6
keywords from the bead's title + touched surfaces, then run, from the worktree
root:

```
ls docs/adr/
grep -li "<keyword1>\|<keyword2>\|<keyword3>" docs/adr/*.md
```

Read every hit — including ADR-0000's amendments, which often carry the
placement/naming/seam rulings that bind a spec most directly. Record the
keywords you used in your rationale (e.g. "verified via grep on `committee`,
`rubric`, `gate` — A9 applies"), so the claim "no decision applies" is itself
verifiable.

## Bands

- **A** — the spec's `## ADR Alignment` section cites every load-bearing
  decision by file path AND clause (an ADR number or an `A<n>` amendment id)
  with a one-sentence quote of the constraining clause, and states how the
  plan aligns (or how it extends the decision, by name). Where no decision
  applies, the section says so explicitly with the grep keywords that verified
  it.
- **B** — the relevant decision is cited, but without the load-bearing clause:
  a reader can tell WHICH decision is implemented but not which clause
  constrains the work.
- **C** — the spec is clearly downstream of a recorded decision (it extends a
  surface the decision established) but never cites it; the alignment is
  accidental rather than acknowledged. Or: the section claims "no ADR applies"
  without naming the keywords that verified it.
- **D** — your grep returns a decision that plainly governs a surface this
  spec touches, and the spec does not cite it. The fix is mechanical — add the
  citation with the quoted clause and apply (or explicitly distinguish) the
  precedent — so this routes to spec rework, not a human.
- **F** — a structural contradiction: the spec, AS WRITTEN, would invert or
  undo a load-bearing clause of a recorded decision, and no citation paragraph
  can fix it — implementing the spec means the precedent no longer holds. The
  route parks the bead at a gate; revisiting a precedent is a human call
  (supersede the decision, or rework the spec to align).

## Calibration

- ADR-0000's PENDING amendments bind for grading purposes: they are the
  register's whole point (an autonomous decision awaiting promotion is still
  the recorded state of the world). A spec free to contradict one must SAY it
  proposes overriding a pending amendment — that names the conflict for the
  human instead of hiding it.
- Do not demand citations for decisions that genuinely do not touch the spec's
  surfaces — a padded ADR section citing everything is noise, not alignment.
  The A-grade signal is the LOAD-BEARING citation, quoted.
- The org invariants (the seam word is **extension**, never "plugin"; package
  names are human faculties, never agent-nouns; bd CLI only, never SQL) count
  as recorded decisions even when a local ADR does not restate them.
