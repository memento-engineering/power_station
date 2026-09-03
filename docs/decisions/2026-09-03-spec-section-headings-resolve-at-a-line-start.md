---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: spec-section-headings-resolve-at-a-line-start
  surfaces:
    - "packages/grid_assets/lib/src/code/specify.dart"
    - "packages/grid_assets/lib/src/code/committee.dart"
    - "packages/grid_assets/extension/rubrics/spec-validation.md"
  obsoletes: []
  updates:
    - "a19-bead-pow-77g-the-spec-s-structural-contract-becomes-one"
  obsoleted-by: null
  updated-by: []
  bead: pow-o3ti
  legacy-id: null
---
## Spec section headings resolve at a LINE START (2026-09-03) — bead `pow-o3ti`

**Decision (AI; MECHANISM only).** Every section heading the spec gate and the
code committee resolve is resolved at a LINE START, through one public helper —
`headingOffset(design, heading)` in `specify.dart`, beside `sectionBodyAt` and
`proseOnly`. It answers the LAST line-anchored match and `-1` when there is
none, so every call site keeps the `indexOf` contract it had and every finding
string is byte-unchanged.

**Why.** A19(3) moved the section lookup onto `proseOnly` output, but the lookup
itself stayed `String.indexOf('## X')`, and a substring search cannot tell a
SECTION from a sentence that NAMES one. On 2026-09-03 (space-3ds round 1) a
31959-character spec was hard-blocked with "design: `## Validation Plan` has no
items" because the architect had written "(see ## Validation Plan)" in a
paragraph 4847 characters above the real section, which carried ten items. The
gate parked a good spec, the governor reworded the sentence, and a round was
spent on the gate's own reading rather than on the spec. The same shape silently
went the OTHER way too: a design with only the mention and no section at all
PASSED all three presence checks, and in the code committee a mid-line mention
anchored an empty declaration body, losing a promised test file.

**LAST, not first.** Callers pass `proseOnly` output, so a heading quoted in a
terminated fence, a blockquote or an inline span is already blanked. What
survives the strip is an unterminated fence, whose tail `proseOnly` leaves
scannable by design — and this pack's own specs quote the four canonical
headings inside their `## Implementation Plan`, ABOVE the sections they name.
Taking the last line-anchored match is what keeps that quotation from displacing
the authored section; taking the first would reintroduce the same false block
one fence over.

**The match stays as permissive as the substring search it replaces** on every
axis but two: the line start, and 0-3 spaces of indentation (4+ is an indented
code block — quotation, by the same rule that blanks a fence). Heading levels
`##` through `######`, trailing text on the heading line, and spacing after the
hashes all still resolve. The two presence checks that used `String.contains`
(`## Touches`, `## ADR Alignment`) move to the same resolver, so a design that
only MENTIONS those headings no longer passes on the mention.

**`changeShapeOf` in `docs_committee.dart` is deliberately left on `indexOf`.**
It reads the RAW design, not `proseOnly` output, because the paths `citedPaths`
must collect live in inline code spans that `proseOnly` blanks; and its failure
mode is fail-to-code (the strict lane), not a hard block. Routing it through a
LAST-match resolver over unstripped text would change which quotation wins for
no gain in its own posture. It keeps its own bead.

**Standing under A17(4).** That clause froze `specStructuralFindings`/`proseOnly`
BYTE-UNCHANGED; Nico's 2026-07-30 governor-relayed amendment narrowed it — "the
freeze binds the STRUCTURE — no re-homing, the fence stays scoped off human
prose, the two functions keep their names and home — and does NOT bind the
fence-strip's implementation." The amendment's own authorization names
`proseOnly`'s fence parsing (the `pow-2kl` defect); this is the same CLASS of
in-place correctness fix in the same pair of functions, and it satisfies every
structural constraint the ruling kept: nothing is re-homed, both functions keep
their names and home, the new helper is ADDED beside them rather than displacing
either, and the fence is still never turned on `Bead.description`.

**The rule is stated where the architect reads it** — `kSpecStructuralContract`
item 2 and `extension/rubrics/spec-validation.md` — per A19(1): the gate never
enforces a rule its brief withholds.

**Consequences.**

* Good: the most expensive false block this gate can produce — a structurally
  whole spec parked on a sentence — cannot recur, and the fix costs no
  finding-string change, so the route's gate reasons and rule strings are
  untouched.
* Good: one resolver now serves both committees, so "a heading is structure,
  quotation is evidence" has a single home.
* Bad: a design that names `## Touches` or `## ADR Alignment` ONLY mid-sentence,
  and writes no such section, now grades F where `contains` passed it. That is
  the gate reading correctly, but it is a real tightening.
* Bad: a heading indented 4+ spaces no longer resolves. Markdown calls that an
  indented code block, but `proseOnly` does not blank one, so this is the one
  place the new lookup is stricter than the old for a reason outside the bug.

**Affects:** `packages/grid_assets/lib/src/code/specify.dart` (`headingOffset`,
`specStructuralFindings`, `kSpecStructuralContract`),
`packages/grid_assets/lib/src/code/committee.dart` (`testDeclarations`'s
declaration-heading loop and its `specify.dart` import),
`packages/grid_assets/extension/rubrics/spec-validation.md`.
