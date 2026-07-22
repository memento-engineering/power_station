# terminology-ban [GATING]

A gating lane of the DOCS committee — a DETERMINISTIC check run in Dart
(`DocsCheckCapability`), never a model. It enforces the org's one
non-negotiable naming rule in the only place a prose diff can break it.

## What it checks

The org rule: the seam word is **extension**. The other word — the one this
lane bans, `plugin` — is reserved for third-party artifacts named that way by
their own ecosystems (`Flutter platform plugins`, `Gradle plugins`). Every
ADDED doc line is read with its markdown QUOTATION and EMPHASIS spans blanked,
then scanned.

Two exemptions, both mechanical:

- **Mention, not use.** A backticked, quoted, or emphasized occurrence is a
  MENTION — this rubric and two others state the ban in exactly that form, and
  stating a rule must never trip it. A bare occurrence in running prose is a
  USE, and that is the offence.
- **A third-party proper noun.** An occurrence led by a Capitalized name —
  optionally with a lowercase modifier word or two between them — is the rule's
  own carve-out. No vendor list is maintained: the capital IS the signal. A
  capital that is merely grammatical (a sentence-opening `The`, `A`, `This`,
  `Each`, …) is not a name and never exempts.

Only ADDED lines are read.

## Bands

- **A** — no bare use in any added doc line.
- **F** — one or more; each finding names the document and quotes the line.

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for rework.
