# adr-alignment

Does the spec respect the substation's recorded decisions? A substation's local
decision register may contain `docs/adr/`, `docs/decisions/`, or both. Treat a
missing directory as absent and continue with the other. `docs/adr/` is
READ-ONLY LEGACY: it holds the ratified ADRs plus `ADR-0000`, whose `A<n>`
amendments were converted with `status: accepted` and bind as accepted.
`docs/decisions/` is where decisions are RECORDED now, and an entry BINDS ON
WRITE. A spec
that touches a surface those decisions govern must cite the relevant decision
and either implement it, extend it, or explicitly propose overriding it. A spec
that silently contradicts a recorded decision is the most expensive failure
this committee can miss: it undoes deliberated work, usually unnoticed until
the contradiction ships.

Legacy ADR citations name the file plus an ADR number or `A<n>` clause, for
example `docs/adr/ADR-0000-ai-decision-register.md A17(4)`. Entries in
`docs/decisions/` use `<repo>#<slug>`, for example
`the_grid#admission-authority-boundary`; migrated entries may also carry
`register.legacy-id` so their old citations continue to resolve.

You are blind to the other lanes' concerns (fit, testability, plan detail) —
weigh ONLY decision alignment.

## Before grading: search for precedent

Enumerate the decisions that COULD apply before judging novelty. Extract 3-6
keywords from the bead's title + touched surfaces, then run, from the worktree
root:

```sh
for register in docs/adr docs/decisions; do [ ! -d "$register" ] || find "$register" -type f -not -path '*/views/*' -name '*.md' -print; done
for register in docs/adr docs/decisions; do [ ! -d "$register" ] || find "$register" -type f -not -path '*/views/*' -name '*.md' -exec grep -li "<keyword1>\|<keyword2>\|<keyword3>" {} +; done
```

Read every hit — including ADR-0000's amendments, which often carry the
placement/naming/seam rulings that bind a spec most directly. Record the
keywords you used in your rationale (e.g. "verified via grep on `committee`,
`rubric`, `gate` — A9 applies"), so the claim "no decision applies" is itself
verifiable.

## Bands

- **A** — the spec's `## ADR Alignment` section cites every load-bearing
  decision by file path plus clause (an ADR number or an `A<n>` amendment id),
  or by its `<repo>#<slug>` identity, with a one-sentence quote of the
  constraining clause, and states how the plan aligns (or how it extends the
  decision, by name). Where no decision applies, the section says so explicitly
  with the grep keywords that verified it.
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

- Legacy `A<n>` amendments bind for grading purposes exactly as
  `docs/decisions/` entries do: both are the recorded state of the world, and a
  recorded entry binds on write. A spec free to contradict one must SAY it
  proposes overriding a recorded decision — that names the conflict for the
  human instead of hiding it.
- Decisions are RECORDED at `docs/decisions/`, never appended to
  `docs/adr/ADR-0000-ai-decision-register.md` — that file is READ-ONLY legacy.
  A spec whose plan appends an `A<n>` amendment is writing to the wrong home:
  grade it and name `docs/decisions/` plus the vended `decide` skill.
- Do not demand citations for decisions that genuinely do not touch the spec's
  surfaces — a padded ADR section citing everything is noise, not alignment.
  The A-grade signal is the LOAD-BEARING citation, quoted.
- The org invariants (the seam word is **extension**, never "plugin"; package
  names are human faculties, never agent-nouns; bd CLI only, never SQL) count
  as recorded decisions even when a local ADR does not restate them.

## Ownership — who can fix a D or an E?

Every `D` or `E` you write carries an `owner`, and it decides whether the
station corrects the spec automatically or asks a human:

- **`architect`** — the fix is derivable from the bead AS WRITTEN plus the
  tree. Re-running the specify stage with your rationale would produce it.
  Here: a governing decision the spec failed to cite, where the fix is adding
  the citation with its quoted clause.
- **`author`** — the fix needs a decision the bead TEXT does not make. Here:
  the spec would OVERRIDE or supersede a ratified decision, or two recorded
  decisions conflict on the surface it touches — revisiting a precedent is a
  human call.

Choose `author` only when no re-run of the architect could converge, however
good it is: an `author` verdict spends NO auto-correction round and parks the
bead for a human immediately. When you do, name the CHOICE and its options in
your rationale — that text IS the gate a governor reads.
