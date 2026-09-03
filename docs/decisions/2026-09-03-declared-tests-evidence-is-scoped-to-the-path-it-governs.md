---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: declared-tests-evidence-is-scoped-to-the-path-it-governs
  surfaces:
    - "packages/grid_assets/lib/src/code/committee.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-26dd
  legacy-id: null
---
## Declared-tests evidence is scoped to the PATH it governs (2026-09-03) — bead `pow-26dd`

**Decision (AI; MECHANISM only).** The `declared-tests-present` gate keeps its
policy verbatim — an authored path is a promise whatever the base holds; a run
or a citation of a file already on the base is not (beads `pow-0jc`, `pow-aoa`,
`pow-qev`). What changes is the SCOPE at which edit-verb evidence is read.
(1) An edit verb claims a path only when it falls inside that path's own WINDOW
— the statement cut at the neighbouring test-path markers (`_evidenceWindow`) —
never the whole statement. (2) Inside that window, position decides which
vocabulary governs: the LAST evidence token ending before the path wins, else
the FIRST token starting after it, else an edit verb anywhere in the window
claims it. A reference cue (`_referenceTestStatement`: "built on", "already
used in", "mirrors", "reuses", "as in") that governs the path demotes it to the
base-gated `mentioned` bucket — never to an unconditional exemption. (3) The
statement-wide arm — `_dartTestCommand` and `_nonDeclarationTestStatement` — is
UNCHANGED, because a rewritten `Test: dart test <M1> <M2>` line puts `dart test`
outside `<M2>`'s window and narrowing it would invert `pow-0jc`. (4) A
package-relative citation resolves against the repo-root base list verbatim or
by a UNIQUE path-boundary suffix; an ambiguous suffix identifies no file and
stays a declaration, extending `pow-qev`'s fail-closed posture rather than
relaxing it. The changed-files side (`missingDeclaredTestFiles`) keeps its
permissive `any`.

**Why.** Three hard blocks in 34 hours, each hand-verified green and landed by
the governor: `tg-5kb` (2026-09-03, gate `tranquility-frhxiv`), `space-fvg`
(2026-09-02, gate `tranquility-egzxb`, landed as space_station #65) and
`tg-czsf` (2026-09-02, landed as the_grid #278). In each, one sentence created a
test AND cited a pre-existing one as the pattern it copied; the statement-wide
verb filed BOTH as authored, and an authored path never reaches the
base-presence exemption, so a file the design promised to leave alone became a
required diff entry. The gate's own doc comment already stated the intent it
violated: "a file already on the base that the design merely RUNS or REFERS TO
is not a promise". Each false positive cost a governor round trip and hid real
declared-test failures behind noise. Honours A9(3) (an unknown scope fails
closed; guards LOUD or GONE) and ADR-0005 D2's grade-gated delivery: the gate
stays GATING (`kCodeGatingRubrics` still lists it) and every narrowing is pinned
by a receipt-shaped test.

**Affects (if promoted):** `packages/grid_assets/lib/src/code/committee.dart`
(`_referenceTestStatement`, `_evidenceWindow`, `_authoredEvidence`,
`_collectTestDeclarations`'s authored arm, `declaredTestFiles`'s base match) and
`packages/grid_assets/test/track_c_declared_tests_test.dart` (eight cases). No
public API changes. the_grid: none.
