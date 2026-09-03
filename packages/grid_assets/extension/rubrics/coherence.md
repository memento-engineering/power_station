# coherence

Does the spec describe a change that lands as a coherent whole — extending the
code that already exists, rather than duplicating concepts the codebase already
owns? Grade the SPEC
(the bead's acceptance + design), not any code; the bead has not been built
yet. You are blind to the other lanes' concerns (testability, plan detail, ADR
citations) — weigh ONLY fit.

Coherence grades ONE axis — **the existing codebase**. The bead graph is
observed and REPORTED, never graded (station policy, ratified 2026-07-18):
tracker state is never the spec author's defect.

**The graded axis — the existing codebase.** Every step that adds a type,
function, or subsystem should answer: does something equivalent already live in
this repo? A coherent spec extends what is there; an incoherent one
parallel-builds beside it. This is conceptual duplication, not just literal
file duplication — a second verdict-transport parser beside the committee's
existing file→stray→envelope stack, a second rubric loader beside
`PackagedAssetLoader`, a second git-runner seam beside the registry's shared
one. Even clean Dart, in isolation, is incoherent if it re-expresses an
abstraction the packs already own. Verify with grep over the worktree: a new
symbol the spec introduces that `grep -rn "<symbol>" . --include='*.dart'` shows
already defined — and the spec does not acknowledge — is a finding.

**The reported axis — the bead graph.** A bead is rarely alone: it may have a
parent epic, sibling beads, and children. Verify with the bd CLI — `bd dep list
<id>`, `bd show <sibling-id>`, `bd search <keyword>`. A duplicate bead, a dep
edge pointing at the wrong id, a claimed relationship the database does not
have, a sibling that already shipped this work — these are REAL findings and you
must report them, in the verdict's `refinement` field, VERBATIM and in full.
They do NOT move your letter by one band: they are refinement work the station
routes to an operator, fixable with two bd commands, and no rewrite of this spec
would close them. A spec that never names a sibling is not penalised for it.
The ONE exception stays graded because it is a CODEBASE fact, not tracker state:
a spec that proposes work a sibling ALREADY SHIPPED into this tree duplicates
code that is there, and grades on the codebase axis.

House terminology is part of fit: the seam word is **extension**, never
"plugin"; package and asset names are human faculties/crafts, never
agent-nouns. A spec that names its new surface against those rules does not
land coherently.

## Bands

- **A** — existing code cited by exact path/symbol with the relationship stated
  ("extends", "wraps", "leaves alone because…"). A reader can tell from the
  spec alone where this bead's change ends and the code it builds on begins.
- **B** — the codebase axis is engaged with one small omission that reads as
  economy, not blindness: a genuinely new helper added without a duplication
  disclaimer.
- **C** — a small, self-contained duplication (a private helper an existing
  package already provides) a quick grep would have caught. The fix is
  renaming/rerouting, not a redesign.
- **D** — a parallel subsystem proposed at non-trivial scale (a new package,
  pipeline, or committee-like layer) without cross-referencing the existing
  one. The fix is a redesign that routes through what exists.
- **F** — a load-bearing collision: the spec reinvents an existing subsystem
  from scratch (a second route matrix, a second asset loader), or duplicates
  code a closed sibling already SHIPPED into this tree. The author did not
  look, or looked and chose not to acknowledge.

## Calibration

- Acknowledged-and-rejected is NOT a failure: a deliberate parallel
  implementation is coherent IF the spec contrasts the two and says why the
  existing one is not reused. Ignored is F; acknowledged-and-justified can be
  A.
- Count concepts, not files: many files expressing one concept is fine; one
  file carrying two unrelated concerns is the seam that caps the grade.
- Out of scope: taste (naming style beyond the house rules, idiom, error
  wording), and the BEAD GRAPH. Grade only codebase duplication.
- A bead-graph finding belongs in `refinement`, never in your grade or your
  rationale — the station flags it for refinement and the spec author owes it
  nothing.

## Ownership — who can fix a D or an E?

Every `D` or `E` you write carries an `owner`, and it decides whether the
station corrects the spec automatically or asks a human:

- **`architect`** — the fix is derivable from the bead AS WRITTEN plus the
  tree. Re-running the specify stage with your rationale would produce it.
  Here: an unacknowledged duplication of an existing symbol the spec could
  simply route through.
- **`author`** — the fix needs a decision the bead TEXT does not make. Here:
  which of two existing subsystems this change should extend, or whose symbol
  names win where the bead text does not say.

Choose `author` only when no re-run of the architect could converge, however
good it is: an `author` verdict spends NO auto-correction round and parks the
bead for a human immediately. When you do, name the CHOICE and its options in
your rationale — that text IS the gate a governor reads.
