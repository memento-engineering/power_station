# coherence

Does the spec describe a change that lands as a coherent whole — carving scope
cleanly from its neighbour beads AND extending the code that already exists,
rather than duplicating concepts the codebase already owns? Grade the SPEC
(the bead's acceptance + design), not any code; the bead has not been built
yet. You are blind to the other lanes' concerns (testability, plan detail, ADR
citations) — weigh ONLY fit.

Coherence spans two axes, graded together; the WORSE axis sets the floor:

1. **The bead graph.** A bead is rarely alone: it may have a parent epic,
   sibling beads, and children. A coherent spec carves scope from its siblings
   (each named by id, with an explicit "out of scope here" line where surfaces
   could collide), engages the parent's design where one exists, and never
   proposes work a sibling already shipped. Verify with the bd CLI —
   `bd dep list <id>`, `bd show <sibling-id>`, `bd search <keyword>` — a
   claimed relationship that does not match the database is a finding.

2. **The existing codebase.** Every step that adds a type, function, or
   subsystem should answer: does something equivalent already live in this
   repo? A coherent spec extends what is there; an incoherent one
   parallel-builds beside it. This is conceptual duplication, not just literal
   file duplication — a second verdict-transport parser beside the committee's
   existing file→stray→envelope stack, a second rubric loader beside
   `PackagedAssetLoader`, a second git-runner seam beside the registry's
   shared one. Even clean Dart, in isolation, is incoherent if it re-expresses
   an abstraction the packs already own. Verify with grep over the worktree:
   a new symbol the spec introduces that `grep -rn "<symbol>" . --include='*.dart'`
   shows already defined — and the spec does not acknowledge — is a finding.

House terminology is part of fit: the seam word is **extension**, never
"plugin"; package and asset names are human faculties/crafts, never
agent-nouns. A spec that names its new surface against those rules does not
land coherently.

## Bands

- **A** — both axes covered: scope explicitly carved from every plausibly
  overlapping sibling (by id), the parent's design engaged where one exists;
  existing code cited by exact path/symbol with the relationship stated
  ("extends", "wraps", "leaves alone because…"). A reader can tell from the
  spec alone where this bead ends and both neighbours begin.
- **B** — both axes engaged with one small omission that reads as economy, not
  blindness: an obviously non-colliding sibling unmentioned, or a genuinely
  new helper added without a duplication disclaimer.
- **C** — a neighbour acknowledged but not used to constrain the spec; or a
  small, self-contained duplication (a private helper an existing package
  already provides) a quick grep would have caught. The fix is
  renaming/rerouting, not a redesign.
- **D** — the spec proceeds as if the bead were standalone on one axis: an
  existing parent/sibling ignored where surfaces overlap, or a parallel
  subsystem proposed at non-trivial scale (a new package, pipeline, or
  committee-like layer) without cross-referencing the existing one. The fix is
  a redesign that routes through what exists.
- **F** — a load-bearing collision: the spec duplicates work a closed sibling
  already shipped, contradicts its parent's design on a load-bearing point, or
  reinvents an existing subsystem from scratch (a second route matrix, a
  second asset loader). The author did not look, or looked and chose not to
  acknowledge.

## Calibration

- Acknowledged-and-rejected is NOT a failure: a deliberate parallel
  implementation is coherent IF the spec contrasts the two and says why the
  existing one is not reused. Ignored is F; acknowledged-and-justified can be
  A.
- A bead with no parent and no siblings grades on the codebase axis only —
  never penalise a truly standalone bead for not citing nonexistent
  neighbours.
- Count concepts, not files: many files expressing one concept is fine; one
  file carrying two unrelated concerns is the seam that caps the grade.
- Out of scope: taste (naming style beyond the house rules, idiom, error
  wording). Grade only graph fit and codebase duplication.
