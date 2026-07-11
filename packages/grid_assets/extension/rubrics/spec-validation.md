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
- **The design field carries all four sections** —
  `## Implementation Plan` (with numbered steps), `## Touches`,
  `## ADR Alignment`, and `## Validation Plan` (with at least one item).
- **No placeholder tokens** anywhere in the spec's PROSE — TBD, TODO,
  "implement later", "fill in later", "as needed",
  "appropriate error handling", "similar to step N". A spec that defers its own
  content is not implementation-ready. Markdown QUOTATION contexts are exempt:
  fenced code blocks, inline code spans, and `>` blockquote lines are stripped
  before matching, because a spec that quotes a token as evidence (a `// TODO`
  comment its plan deletes, an ADR clause cited verbatim) is pointing at work,
  not deferring it.

## Bands

- **A** — every structural element is present and placeholder-free. The spec is
  structurally whole; whether it is also COHERENT, ALIGNED, TESTABLE, and
  COMPLETE is the four judgement lanes' call, not this one's.
- **F** — any element missing, any placeholder present, or no spec at all (the
  pre-specify state — a bead whose specify stage never wrote, or was skipped,
  never silently passes).

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for spec rework. There is no partial credit and no LLM judgement in
this lane — a structural element is either present or it is not.
