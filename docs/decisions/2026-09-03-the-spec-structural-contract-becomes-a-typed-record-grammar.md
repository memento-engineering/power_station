---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-spec-structural-contract-becomes-a-typed-record-grammar
  surfaces:
    - "packages/grid_assets/**"
  obsoletes: []
  updates:
    - "a19-bead-pow-77g-the-spec-s-structural-contract-becomes-one"
  obsoleted-by: null
  updated-by: []
  bead: pow-5ufz
  legacy-id: null
---
## The spec's structural contract becomes a typed RECORD GRAMMAR (2026-09-03) — bead `pow-5ufz`

**Decision (AI).** The spec stays ONE human-readable Markdown document — no
second JSON or YAML contract is embedded beside it — but the structure the spec
is WRITTEN in becomes a line-oriented record grammar with stable identifiers,
parsed by ONE total function, `parseSpecContract`, in `specify.dart` — measured
in shadow in this phase, never graded (call 4). Five exported constants are the
single source of every form:

* `kAcceptanceRecordForm` — `- [ ] AC-<n> — <criterion>`, ids unique and `1..N`;
* `kStepRecordForm` + `kStepFieldLabels` — a step carries all five labeled
  fields `Paths:`, `Change:`, `Test:`, `Expect:`, `Commit:`;
* `kTouchRecordForm` — one repo-relative backticked path plus a disposition;
* `kDecisionRecordForm` — one resolvable `<repo>#<slug>` plus a disposition;
* `kValidationRecordForm` — ``- [ ] AC-<n> → `<command>` → <expected>``, exactly
  once per acceptance id and never for an id no criterion declares.

The same constants are interpolated into `kSpecStructuralContract` and
`buildSpecifyBrief`, so neither phase can enforce or measure a form its brief
withholds (A19(1)); the shipped exemplar is written in the grammar and a test
parses it clean.

**Four calls this makes, and why each is the binding one.**

**1. One document, one total parser, source-located findings, NO repair.**
`parseSpecContract` never throws and never guesses. It projects only exactly
authored records into `SpecContract`; anything else becomes a typed
`SpecContractFinding` carrying its `SpecContractRule` and the AUTHORED line
number. A repairing parser would have to decide what the architect meant, and
every such guess is a silent contract change that the architect never sees and
the gate can never explain. Reporting "line 412 is not
`kValidationRecordForm`" is a fact; inferring the intended criterion id from a
near-miss is inference wearing a parser's clothes. Line numbers are only
truthful because `proseOnly` now preserves its input's LINE COUNT — the
prerequisite refactor, not a nicety.

**2. `Change:` replaces the mandatory implementation-sized code block.**
`plan-completeness` previously required a literal code block per step; it now
requires `Change:` to state the BEHAVIOR and INVARIANT a builder must produce,
and makes fenced code OPTIONAL EVIDENCE in Literalness, the bands, calibration
and ownership alike. Requiring the architect to pre-write the implementation
buys a plan that is expensive to produce, expensive to review, and then carried
in every later context window — while a diff that merely retypes the block
grades well without proving anything. The invariant is what a builder cannot
derive; the code is what a builder is for.

**3. Every A19 step opener remains accepted.** `1.`, `1)`, `### Step 1 —` and
`**Step 1:**` all still open a step. The new strictness lands entirely on what a
step CONTAINS. A19 ratified the opener language, and this decision extends that
ruling rather than narrowing it: re-litigating which openers count would break
shipped specs for no gain in what the gate can actually decide. The measured
cost of holding that line is recorded — see the phantom-step class below.

**4. Phase one is MEASUREMENT ONLY; all four semantic critics are retained.**
Record-contract findings are shadow-only until an explicit activation ruling; the five presence and placeholder checks remain the live A/F gate, and all five committee lanes remain unconditional.
`parseSpecContract` therefore never contributes findings to
`specStructuralFindings` in this phase. Activation requires a later accepted
ruling that names the migration posture and explicitly wires those findings
into the live result; the retained-corpus measurement cannot activate itself.
`kSpecCommitteeRubrics`, `kSpecLlmRubrics` and `kSpecReviewCircuit` remain
unchanged: no critic is removed, skipped, or made conditional on parser output,
and a test pins that lane set. `spec_contract_shadow.dart` runs the parser over
ten specs that ALREADY SHIPPED under the pre-change contract and renders what it
would have said — 408 findings, 0 parsing clean.

That number is **migration cost, not critic redundancy**, and the distinction is
the whole reason the lanes stay. Every corpus entry predates the grammar, so its
architect was never told the forms; a high count on a rule says the old brief
was SILENT about it, not that a lane was failing. The report's overlap column is
correspondingly the weak claim it looks like: it says a lane ASKS for the same
property in prose — each clause quoted verbatim from the packaged rubric and
asserted as a substring in test — not that the lane CAUGHT it, since these specs
passed those lanes carrying the deviations counted. Establishing redundancy
needs a corpus written UNDER the new brief. Structure and referential integrity
are represented and measured in code but do not route in this phase; whether a
test PROVES behavior, whether a plan is COHERENT, and whether a decision is
INTERPRETED correctly stay inference.

**The decision lane's failed lookup stays typed, not flattened.** Per
`the-spec-decision-lane-queries-the-roster-union`, an empty roster union is a
real result and a CRASHED lookup is not. `DecisionLookupNarrative` distinguishes
cited decisions, a verified empty union, a failed lookup, and a SILENT alignment
section — the last of which the grammar refuses outright, because silence is
exactly how a crashed lookup used to read as clean.

**One deterministic false positive is measured and deliberately LEFT.** The
ratified opener language matches `<digits>.` at the start of ANY line, including
an INDENTED prose continuation. Under the old boolean check ("has this plan any
ordinal step at all") that cost nothing; the record parser turns every match into
a step, which then reports the five fields it was never going to carry. Narrowing
it to column 0 would change a ratified rule, so it is counted in the report and
not fixed here.

**The shadow measurement rides the pack's existing shape.** `search_recall.dart`
already owns a retained-corpus measurement, and `spec_contract_shadow.dart` is
deliberately the same shape — retained corpus, pure render, a runner behind a
thin `tool/` CLI that is read-only by default and writes only under `--record`.
The one MECHANISM that shape needs is now shared outright rather than forked:
`recordArtifact` in `lib/src/io/recorded_artifact.dart` is the pack's single
owner of the temp-file-plus-rename discipline, both measurements record through
it, and a test refuses a second rename site anywhere in `lib/`. The corpus
decoders, the measurement step and what `--record` MEANS stay separate and are
documented as such: one decodes versioned JSON rows, the other retains verbatim
Markdown; one needs a live subprocess seam, the other is pure; one rewrites its
own baseline only on green, the other rewrites a derived report nothing reads
back.

**Consequences.**

* Good: an addressable id exists for every criterion the strict parser accepts,
  so acceptance ↔ validation integrity is a fact the shadow report can measure.
* Good: every shadow finding names a rule and an authored line, so the measured
  migration cost identifies the exact record deviation without changing a
  bead's grade.
* Good: the expensive half of the old plan format — pre-written implementation
  code — stops being mandatory in the brief, the rubric, and every later context.
* Bad: real migration cost, deferred rather than avoided. No pre-grammar spec in
  the retained corpus parses clean, so the specs written between this ruling and
  an activation one keep tripping forms their authors have not internalised yet
  — visibly in the report, and only there.
* Bad: some counts are contract FRICTION rather than sloppiness — a gate-only
  final step writing `Commit: none` is a deliberate, readable choice the grammar
  refuses. Those are the calls a follow-up should revisit with the numbers in
  hand.
* Bad: the indented-ordinal phantom-step class is live and known. It is measured,
  not fixed, because fixing it edits a ratified rule.

**Affects:** `packages/grid_assets/lib/src/code/specify.dart` (`proseOnly`,
`sectionAt`, `lineOf`, the five record-form constants, `SpecContract`,
`SpecContractRule`, `SpecContractFinding`, `DecisionLookupNarrative`,
`parseSpecContract`, `kSpecStructuralContract`, the exemplars,
`buildSpecifyBrief`, `specStructuralFindings`, `SpecValidationCapability`),
`packages/grid_assets/lib/src/code/decision_register.dart` (the shared
empty-union and failed-lookup phrases),
`packages/grid_assets/lib/src/code/spec_contract_shadow.dart`,
`packages/grid_assets/lib/src/io/recorded_artifact.dart`,
`packages/grid_assets/lib/src/search/search_recall.dart`,
`packages/grid_assets/extension/rubrics/spec-validation.md`,
`packages/grid_assets/extension/rubrics/plan-completeness.md`.
