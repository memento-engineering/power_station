# section-structure [GATING]

A gating lane of the DOCS committee — a DETERMINISTIC check run in Dart
(`DocsCheckCapability`), never a model. It answers: did this edit keep the
document's required shape?

## What it checks

When — and only when — the bead NAMES the sections its documents must carry
(the CSV bead metadata key `docs_sections`), every changed document must carry
each named heading. Headings are read from PROSE: a heading that exists only
inside a fenced block is evidence, not a section. A leading `#` run on a
declared section name is stripped, so `## Decision` and `Decision` name the
same heading. A document the change DELETED is not held to them.

A bead that names no sections declares no requirement, and this lane grades A.
That is deliberate: a lane that invented its own required structure would gate
on taste, and a governance gate that fires on taste is worse than no gate.

## Bands

- **A** — every named section is present in every changed document, or the bead
  named none.
- **F** — a named section is missing; each finding names the document and the
  section.

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for rework.
