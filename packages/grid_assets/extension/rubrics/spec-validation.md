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
- **The record grammar is measured in SHADOW.** `parseSpecContract` strictly
  parses addressable acceptance ids, the five labeled step fields,
  repo-relative Touches records, resolvable decision records, and the one-to-one
  validation map into one typed `SpecContract`; deviations are source-located
  typed findings and are never repaired or guessed.
  Record-contract findings are shadow-only until an explicit activation ruling; the five presence and placeholder checks remain the live A/F gate, and all five committee lanes remain unconditional.
  The checked-in shadow report measures those findings against retained shipped
  specs, their overlap with the judgement rubrics, deterministic false
  positives, and the semantic residue. Whether a test proves behaviour, whether
  a plan is coherent, and whether a decision is interpreted correctly remain
  inference.
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

The live contract is not this lane's secret: `kSpecStructuralContract` states
items 1–5 verbatim in the specify agent's own brief, and the exemplar the brief
ships is round-tripped through `specStructuralFindings` in test. The same brief
also teaches the shadow grammar before it can be activated. A spec F'd by the
live gate failed a presence or placeholder rule it was told.

## Bands

- **A** — all five live presence and placeholder checks pass. Record-contract
  findings may still appear in the shadow report and do not lower this grade.
- **F** — a live structural element is missing, a placeholder appears, or no
  spec exists (the pre-specify state). A malformed record alone does not lower
  this grade before an explicit activation ruling.

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for spec rework. There is no partial credit and no LLM judgement in
this lane; record-contract measurement never routes the bead in this phase.
