# spec-validation [GATING]

The hard gate of the spec-readiness committee. This lane does not weigh opinion
— it is a DETERMINISTIC structural check over the spec the bead carries (the
`spec-validation` capability runs it in Dart; no model, no judgement). It is
the answer to "a bead must never reach the build stage without an
implementation-ready spec": the specify stage writes the spec INTO the bead,
and this lane verifies the structure landed whole.

## What it checks

- **Acceptance criteria** — at least one testable `- [ ]` checkbox criterion in
  the bead's acceptance field.
- **The design carries all four sections** — `## Implementation Plan`,
  `## Touches`, `## ADR Alignment`, and `## Validation Plan` (with at least one
  `- ` item). Each heading is read at a LINE START: a heading named inside a
  sentence ("see `## Validation Plan`") is a mention, not a section, and the
  real section further down is the one the check reads.
- **`## Implementation Plan` carries ORDINAL-LED steps.** Every step opens with
  an ordinal: an ordered-list item (`1. …` / `1) …`) or an ordinal heading
  (`### Step 1 — …` / `### 1. …` / `**Step 1:** …`). Both are ordered and
  addressable; a bulleted or prose-only plan is neither and fails, however
  complete it is. The check reads the `## Implementation Plan` section's own
  body — an ordinal in another section does not stand in for a step.
- **Every record is ADDRESSABLE.** Inside those sections the spec is a
  line-oriented grammar, parsed into one typed contract: acceptance criteria
  are `- [ ] AC-<n> — <criterion>` with unique, contiguous ids; each
  implementation step carries `Paths:`, `Change:`, `Test:`, `Expect:` and
  `Commit:` lines (a fenced code block beside `Change:` is optional evidence,
  never a required field); each `## Touches` item carries one repo-relative
  backticked path and a disposition; each `## ADR Alignment` item carries a
  resolvable decision identity and a disposition, and the section is never
  silent about the lookup itself — it states either that no recorded decision
  governs the queried surfaces, or that the lookup FAILED and what it printed
  (an unknown union is not an empty one); each `## Validation Plan` item is
  ``- [ ] AC-<n> → `<command>` → <expected>``, exactly once for every
  acceptance id and never for an unknown one. Every deviation is reported with
  the line it is on. Structure and referential integrity are decided here;
  whether a test PROVES the behaviour, whether the plan is COHERENT, and
  whether a decision is INTERPRETED correctly stay the judgement lanes'.
- **No placeholder token in PROSE** — `TBD`, `TODO`, `implement later`,
  `fill in later`, `as needed`, `appropriate error handling`,
  `similar to step`. A spec that defers its own content is not
  implementation-ready.
- Structure and tokens are read from PROSE alike: markdown QUOTATION contexts
  (fenced code blocks, `inline code` spans, `>` blockquote lines) are stripped
  before matching. A spec that QUOTES a token as evidence — a `// TODO` comment
  its plan deletes, an ADR clause cited verbatim — is pointing at work, not
  deferring it; and a heading that exists only inside a code block is evidence,
  not a section.

The contract is not this lane's secret: `kSpecStructuralContract` states it
verbatim in the specify agent's own brief, and the exemplar the brief ships is
round-tripped through this check in test. A spec F'd here failed a rule it was
told.

## Bands

- **A** — every structural element is present, every record matches its
  documented form, and no placeholder appears. The spec is structurally whole;
  whether it is also COHERENT, ALIGNED, TESTABLE, and COMPLETE is the four
  judgement lanes' call, not this one's.
- **F** — any element missing, any record malformed, any acceptance id
  unmapped or double-mapped, any placeholder present, or no spec at all (the
  pre-specify state — a bead whose specify stage never wrote, or was skipped,
  never silently passes).

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for spec rework. There is no partial credit and no LLM judgement in
this lane — a structural element is either present or it is not.
