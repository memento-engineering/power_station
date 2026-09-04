## Implementation Plan

ROUND 2. Round 1 already landed on this branch in four commits (`ee96f06`,
`aefd416`, `9ef918d`, `abe157c`): per-path evidence windows, the unique base
suffix rule, eight receipt tests and the decision entry. The governor UPHELD a
regression against it (bead notes, 2026-09-03 05:30Z): because `_evidenceWindow`
cuts the window at the neighbouring marker unconditionally, a single edit verb
governing a comma/`and` separated LIST of paths loses every path but the one
nearest the verb — a false NEGATIVE on a gating rubric, the inverse of the
defect round 1 fixed.

Baseline, MEASURED in this worktree before any edit of this round:
`cd packages/grid_assets && dart analyze` → `No issues found!`;
`dart test test/track_c_declared_tests_test.dart` → `+33: All tests passed!`;
`dart test -j 4` → `+1109 ~1: All tests passed!`. The regression itself was
reproduced here against the landed code:

```text
design      Modify `<A>`, `<B>`, and `<C>`.
authored    {<A>}                      <- <B> and <C> lost their verb
mentioned   {<B>, <C>}
declared    {<A>}                      <- with all three present at the base
```

The fix is one word again: the window is cut around the RUN, not around the
single path. Consecutive test paths joined by NOTHING but list separators
(whitespace, commas, semicolons, backticks, `and`, `or`) are one list governed
by one verb, so they share one window. A gap that carries any other word — as in
"Create `A`, built on the harness `B` already uses" — still splits the two into
separate runs, which is exactly what the three receipts need. Policy is
untouched: the vocabularies, the positional rule inside a window
(`_authoredEvidence`), the statement-wide run-line arm, and the base-match rules
of `declaredTestFiles` are all byte-identical after this round.

### Step 1 — Cut the evidence window around the RUN of sibling paths

One step, one file: `packages/grid_assets/lib/src/code/committee.dart`. The new
private `RegExp` and its only reader land together because the Dart analyzer
reports `unused_element` for an unreferenced private top-level declaration, so a
step adding the regex alone could not be green.

Replace the whole `_evidenceWindow` block — its doc comment and its body, lines
312-341 today, from the line `/// The slice of [statement] whose words govern
the path at [marker]: from the` down to the `}` that closes the function,
immediately above `/// Whether [window]'s edit-verb evidence PROMISES the path
at [marker].` — with:

```dart
/// The gap between two sibling test paths that carries NO evidence of its own —
/// whitespace, commas, semicolons, backticks and the conjunctions `and`/`or`.
///
/// A run of paths joined only by these separators is ONE list governed by one
/// verb ("Modify `a`, `b`, and `c`"), so [_evidenceWindow] keeps the run whole
/// instead of cutting each path off from the verb that promises it.
final RegExp _testPathListGap = RegExp(
  r'^(?:[\s,;&`]|\band\b|\bor\b)*$',
  caseSensitive: false,
);

/// The slice of [statement] whose words govern the path at [marker]: the
/// maximal RUN of sibling paths containing it, widened to the END of the path
/// before the run and the START of the path after it.
///
/// Evidence for one path never leaks onto another. In `Create A, built on the
/// harness B already uses`, the A-B gap carries words, so the two are separate
/// runs: A's window holds "Create" and B's holds only the reference clause.
/// In `Modify A, B, and C` every gap is a bare list separator
/// ([_testPathListGap]), so all three share one window and one verb promises
/// them all. [markers] is every marker in play (`pathByMarker.keys`); each
/// occurrence carries its OWN marker, so a marker absent from [statement] cuts
/// nothing.
String _evidenceWindow(
  String statement,
  String marker,
  Iterable<String> markers,
) {
  final markerAt = statement.indexOf(marker);
  if (markerAt < 0) return statement;
  final spans = <({int start, int end})>[
    (start: markerAt, end: markerAt + marker.length),
  ];
  for (final other in markers) {
    if (other == marker) continue;
    var at = statement.indexOf(other);
    while (at >= 0) {
      spans.add((start: at, end: at + other.length));
      at = statement.indexOf(other, at + 1);
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  final self = spans.indexWhere((span) => span.start == markerAt);
  bool listGap(int left) => _testPathListGap.hasMatch(
    statement.substring(spans[left].end, spans[left + 1].start),
  );
  var first = self;
  while (first > 0 && listGap(first - 1)) {
    first--;
  }
  var last = self;
  while (last < spans.length - 1 && listGap(last)) {
    last++;
  }
  return statement.substring(
    first == 0 ? 0 : spans[first - 1].end,
    last == spans.length - 1 ? statement.length : spans[last + 1].start,
  );
}
```

Three points a reader should not have to re-derive. (a) The self span is SEEDED
into `spans` and the other markers are added with `if (other == marker)
continue;`, so `self` is always a real index — there is no silent
"marker-not-found" fallback branch (guards LOUD or GONE). (b) `markerAt < 0` is
the one early return and it is the pre-existing contract, kept verbatim. (c) The
doc comment writes the examples as `Create A, built on…` rather than with angle
brackets: `dart analyze` raises `unintended_html_in_doc_comment` on bare
`<A>`-shaped placeholders in this comment, verified in a scratch copy of the
package.

NOTHING else in the file changes this round. `_authoredEvidence`,
`_referenceTestStatement`, `_authoredTestStatement`,
`_nonDeclarationTestStatement`, `_statementAround`, `_testStatementBoundary`,
`_collectTestDeclarations` (its call `_evidenceWindow(statement, entry.key,
pathByMarker.keys)` is signature-identical), `_collectTestLineFallback`,
`declaredTestFiles` and `missingDeclaredTestFiles` are all left byte-identical.

Test: `cd packages/grid_assets && dart analyze` → `No issues found!`, then
`cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart` →
`+33: All tests passed!` (every case already on this branch survives the
widening — verified in a scratch copy of the package before this spec was
written).
Commit: `fix(committee): one verb authors a whole run of sibling test paths`

### Step 2 — Pin the list receipts and the shapes that must NOT widen

Append these FIVE cases to
`packages/grid_assets/test/track_c_declared_tests_test.dart`, INSIDE `main()`,
after the last existing case (`pow-26dd a cue after the path leaves the path
authored`, which closes just before the file's final `}`). They reuse the file's
existing `_runGate` / `_diffFor` helpers and its `_BaseTreeGitRunner` fake
(Fakes, not mocks) — no helper is added or changed, and no existing case is
edited.

```dart
  test('pow-26dd r2 one verb authors a comma-and list', () {
    const design =
        'Modify `test/lane_a_test.dart`, `test/lane_b_test.dart`, and '
        '`test/lane_c_test.dart`.';
    const paths = {
      'test/lane_a_test.dart',
      'test/lane_b_test.dart',
      'test/lane_c_test.dart',
    };
    expect(testDeclarations(design).authored, paths);
    expect(testDeclarations(design).mentioned, isEmpty);
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {
          'packages/p/test/lane_a_test.dart',
          'packages/p/test/lane_b_test.dart',
          'packages/p/test/lane_c_test.dart',
        },
      ),
      paths,
    );
  });

  test('pow-26dd r2 one verb authors an and-joined pair', () async {
    const design = 'Create `test/pair_x_test.dart` and `test/pair_y_test.dart`.';
    const paths = {'test/pair_x_test.dart', 'test/pair_y_test.dart'};
    expect(testDeclarations(design).authored, paths);
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {
          'packages/p/test/pair_x_test.dart',
          'packages/p/test/pair_y_test.dart',
        },
      ),
      paths,
    );
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['test/pair_x_test.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale':
          'Design-declared test files missing from pinned diff: '
          'test/pair_y_test.dart',
    });
  });

  test('pow-26dd r2 a trailing verb authors the whole list', () {
    const design =
        '`test/tail_a_test.dart` and `test/tail_b_test.dart` — both modified.';
    expect(testDeclarations(design).authored, {
      'test/tail_a_test.dart',
      'test/tail_b_test.dart',
    });
  });

  test('pow-26dd r2 a worded gap keeps the runs separate', () {
    const design =
        'Create `test/run_u_test.dart`, `test/run_v_test.dart` and '
        '`test/run_w_test.dart`, built on the harness '
        '`test/run_h_test.dart` already uses.';
    expect(testDeclarations(design).authored, {
      'test/run_u_test.dart',
      'test/run_v_test.dart',
      'test/run_w_test.dart',
    });
    expect(declaredTestFiles(design), {
      'test/run_u_test.dart',
      'test/run_v_test.dart',
      'test/run_w_test.dart',
    });
  });

  test('pow-26dd r2 a two-path run line is still not a declaration', () {
    const design = 'Test: dart test test/run_r_test.dart test/run_s_test.dart';
    const paths = {'test/run_r_test.dart', 'test/run_s_test.dart'};
    final declarations = testDeclarations(design);
    expect(declarations.authored, isEmpty);
    expect(declarations.fallback, paths);
    expect(declaredTestFiles(design), paths);
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {
          'packages/p/test/run_r_test.dart',
          'packages/p/test/run_s_test.dart',
        },
      ),
      isEmpty,
    );
  });
```

Test: `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart`
→ `+38: All tests passed!`
Commit: `test(committee): pin one verb over a run of sibling test paths`

### Step 3 — Amend the recorded decision in place

`docs/decisions/2026-09-03-declared-tests-evidence-is-scoped-to-the-path-it-governs.md`
already exists on this branch and records THIS decision. The `decide` skill
(`~/development/engineering.memento/decisions/skills/decide/SKILL.md`, step 2)
rules on the collision explicitly: "Read the existing entry and cite it when it
is the same decision. Choose a different slug only when the new decision is
substantively different." Round 2 refines the same mechanism, so the entry is
amended in place — no second entry, no new slug, and legacy
`docs/adr/ADR-0000-ai-decision-register.md` stays untouched.

Make exactly three edits to that file.

(a) Replace this sentence of clause (1):

```markdown
(1) An edit verb claims a path only when it falls inside that path's own WINDOW
— the statement cut at the neighbouring test-path markers (`_evidenceWindow`) —
never the whole statement.
```

with:

```markdown
(1) An edit verb claims a path only when it falls inside that path's own WINDOW
(`_evidenceWindow`), never the whole statement. The window is cut around the
RUN, not the single path: consecutive paths joined by NOTHING but list
separators — whitespace, commas, semicolons, backticks, `and`, `or`
(`_testPathListGap`) — are one list governed by one verb, so "Modify `a`, `b`,
and `c`" promises all three, while a gap that carries any other word ("Create
`a`, built on the harness `b` already uses") splits the two into separate runs.
```

(b) Replace the first line of the "Affects" paragraph:

```markdown
(`_referenceTestStatement`, `_evidenceWindow`, `_authoredEvidence`,
`_collectTestDeclarations`'s authored arm, `declaredTestFiles`'s base match) and
`packages/grid_assets/test/track_c_declared_tests_test.dart` (eight cases). No
```

with:

```markdown
(`_referenceTestStatement`, `_testPathListGap`, `_evidenceWindow`,
`_authoredEvidence`, `_collectTestDeclarations`'s authored arm,
`declaredTestFiles`'s base match) and
`packages/grid_assets/test/track_c_declared_tests_test.dart` (thirteen cases). No
```

(c) Append this paragraph at the END of the file, after the "Affects" paragraph:

```markdown
**Round 2 (governor-upheld regression, 2026-09-03).** The first pass cut the
window at the neighbouring marker unconditionally, which lost a shared verb: for
`Modify `a`, `b`, and `c`` only `a` stayed authored, `b` and `c` fell to the
base-gated `mentioned` bucket, and a design promising three files gated on one —
a false NEGATIVE on a gating rubric, the inverse of the defect this entry fixes.
The RUN rule in clause (1) is the correction: a path's window spans the maximal
run of siblings joined only by list separators, so one verb governs the whole
list whether it LEADS it ("Modify `a`, `b`, and `c`") or TRAILS it ("`a` and `b`
— both modified"), while any other word in a gap still separates the runs and
preserves the `tg-5kb` / `space-fvg` / `tg-czsf` receipts. The widening is
evidence-symmetric, not policy: a reference cue governing a run demotes the
whole run to the same base-gated bucket, so `pow-qev`'s fail-closed posture and
`pow-0jc`'s run-line arm are unchanged, each pinned by a case in
`track_c_declared_tests_test.dart`.
```

Test: `grep -q '_testPathListGap' docs/decisions/2026-09-03-declared-tests-evidence-is-scoped-to-the-path-it-governs.md && git diff --stat origin/main...HEAD -- docs/adr/ADR-0000-ai-decision-register.md`
→ exit 0 with EMPTY diffstat output.
Commit: `docs(decisions): record the run rule for shared declared-test verbs`

### Step 4 — Run the house gate

Run the machine gate this bead is graded by, from the worktree root:

```sh
cd packages/grid_assets && dart analyze && dart test -j 4
```

Expected: `No issues found!` then `+1114 ~1: All tests passed!` (the measured
`+1109 ~1` baseline plus the five new cases), exit 0. The single skip is the
pre-existing `~1`, not a new one.

`-j 4` is deliberate and MEASURED, not a softening: at the default concurrency
this pack's acceptance suite flakes on temp-directory and molecule-pour IO
unrelated to this bead. On the UNTOUCHED round-1 tree in this worktree, the
default concurrency was observed RED and `-j 4` GREEN, twice each — a different
trio of acceptance/kernel suites failing each red run:

```text
dart test        +1106 ~1 -3: Some tests failed.
dart test -j 4   +1109 ~1: All tests passed!
```

That flake is
already tracked and deferred as bead `pow-1qcz` (PR #184, "fix asset test flake
by removing real io from fake"); it is not this bead's defect and the whole
suite still runs. Do NOT run `dart format`: the machine on this worktree
resolves a 3.12 formatter against the repo's 3.11 house set and reformats
untouched files; `dart analyze` is the house check and does not read formatting.

No commit: this step is verification only and produces no diff. If it is red,
fix forward in the step that owns the failure — do not amend the gate.

## Touches
- `packages/grid_assets/lib/src/code/committee.dart` — modified. Adds ONE private
  member, `_testPathListGap` (a `RegExp`, immediately above `_evidenceWindow`),
  and rewrites `_evidenceWindow`'s body and doc comment. `_evidenceWindow` keeps
  its exact signature `String _evidenceWindow(String, String, Iterable<String>)`
  and its single caller at `committee.dart:410` is unchanged. NO public symbol is
  added, removed, or re-signatured: `testDeclarations`, `TestDeclarations`,
  `declaredTestFiles`, `missingDeclaredTestFiles`, `baseTreeFiles`,
  `DeclaredTestsCapability` and `kDeclaredTestsRubric` keep their exact
  signatures, so `packages/grid_assets/lib/src/code/code_capabilities.dart:1073`
  (the registry wiring) needs no change.
- `packages/grid_assets/test/track_c_declared_tests_test.dart` — modified; five
  cases appended inside `main()`. No helper added or changed, no existing case
  edited.
- `docs/decisions/2026-09-03-declared-tests-evidence-is-scoped-to-the-path-it-governs.md`
  — modified in place (three edits: clause (1), the Affects line, one appended
  paragraph). Its `register` front matter — `slug`, `surfaces`, `bead`,
  `status: accepted`, the four edge lists — is unchanged: same decision, same
  identity, same governed surface.
- NOT touched, deliberately: `_authoredEvidence` and `_referenceTestStatement`
  (the positional rule and the citation vocabulary are correct and pinned by the
  round-1 cases); `_statementAround` and `_testStatementBoundary`;
  `_collectTestDeclarations` (its statement-wide `_dartTestCommand` /
  `_nonDeclarationTestStatement` arm stays statement-wide, so a rewritten
  `Test: dart test <M1> <M2>` line is still a run reference — pinned by the new
  two-path run-line case); `_collectTestLineFallback`; `declaredTestFiles` and
  `missingDeclaredTestFiles` (the verbatim-or-unique-suffix base match and the
  permissive changed-files `any` are round-1 rulings, both still pinned);
  `baseTreeFiles`; `_endsWithPath`.

Re-validated against the live tree:
`grep -rn "_evidenceWindow\|_authoredEvidence\|_referenceTestStatement\|_testPathListGap" . --include='*.dart'`
returns hits only inside `committee.dart` — `_evidenceWindow` has exactly ONE
caller (`committee.dart:410`, signature-identical after this round) and
`_testPathListGap` has none, so it is new. The public-surface grep
(`grep -rln "testDeclarations\|declaredTestFiles\|missingDeclaredTestFiles\|baseTreeFiles\|kDeclaredTestsRubric\|DeclaredTestsCapability" . --include='*.dart'`)
returns exactly `committee.dart`, `code_capabilities.dart` (registry wiring,
signature-stable), `track_c_declared_tests_test.dart` (this plan's suite) and
`track_c_route_test.dart` (which asserts on GRADES, not on classification) — no
migration is owed. `bd dep list pow-26dd` reports no dependencies and no parent;
the nearest open neighbours do not collide — `pow-1qcz` is the deferred
acceptance-suite IO flake (a test fake, not the classifier), `pow-o3ti` is the
spec-validation heading-substring bug in `specify.dart`, `pow-87s` is
validation_plan shell-text discrimination (the gate's COMMAND, not its
classifier), and `pow-bhm` / `pow-0gg` are committee ROUTING, none of which read
`testDeclarations`. The algorithm and all five new cases in Step 2 were executed
against a scratch copy of this package — 38/38 green, `dart analyze` clean —
before this spec was written.

## ADR Alignment
Verified via grep on `declared`, `committee`, `rubric`, `fail-closed`,
`evidence`, then narrowed on `declared-tests`, `pow-0jc`, `pow-aoa`, `pow-qev`,
run as
`for register in docs/adr docs/decisions; do [ ! -d "$register" ] || find "$register" -type f -not -path '*/views/*' -name '*.md' -exec grep -li ... {} +; done`
from the worktree root.

- `power_station#declared-tests-evidence-is-scoped-to-the-path-it-governs`
  (`docs/decisions/2026-09-03-declared-tests-evidence-is-scoped-to-the-path-it-governs.md`,
  `status: accepted`, `bead: pow-26dd`) — LOAD-BEARING and this round's own
  prior entry. Its clause (1) reads: "An edit verb claims a path only when it
  falls inside that path's own WINDOW — the statement cut at the neighbouring
  test-path markers (`_evidenceWindow`) — never the whole statement." That is
  precisely the clause the governor's regression indicts, so Step 3 AMENDS it in
  place rather than contradicting it silently: the window is cut around the RUN,
  not the single path. Clauses (2) (the positional rule), (3) (the statement-wide
  run-line arm) and (4) (the unique base suffix) are re-affirmed unchanged, and
  the entry keeps its slug, surfaces and edges. Amending in place is the `decide`
  skill's own instruction for a same-decision slug collision (its step 2).
- `power_station#a9-bead-pow-6wo-re-homed-from-the-grid-tg-fc6-the-committee`
  (`docs/decisions/2026-07-10-a9-bead-pow-6wo-re-homed-from-the-grid-tg-fc6-the-committee.md`,
  `status: accepted`, `legacy-id: A9`) clause (3) — LOAD-BEARING: "An unknown
  scope must not masquerade as a stale bead nor silently advance critics against
  an empty scope; failing closed routes to supervision (guards LOUD or GONE)."
  This round ALIGNS on both halves. Fail-closed: the widening only ever moves a
  path from `mentioned` (base-gated) to `authored` (unconditional) when a verb
  governs its run, so no path becomes LESS declared than the round-1 rule made
  it; the ambiguous-suffix and unreadable-base cases are untouched and still
  pinned. Guards LOUD or GONE: the rewritten `_evidenceWindow` seeds its own span
  into `spans` precisely so there is no silent "marker not found" fallback — the
  only early return is the pre-existing `markerAt < 0` contract.
- `docs/adr/ADR-0005-landing-policy-grade-gated-auto-merge.md` D2 — "The default
  auto-merge policy enables GitHub native auto-merge only when the round's
  code-validation receipt has rc 0 and no committee grade is below B." This round
  RESTORES gate power rather than relaxing it: the regression made a real
  multi-file test promise unenforceable, and the new
  `pow-26dd r2 one verb authors an and-joined pair` case asserts the gate still
  answers `F` with the missing path named. `kDeclaredTestsRubric` remains in
  `kCodeGatingRubrics` (`committee.dart:119`) and an `F` still hard-blocks.
- `docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md` D3 —
  "when compliance would halt the station and the correct action lies outside a
  ratified decision, the governor TAKES the action, records it ... and moves on."
  This round is that shape and records the action; D3's sentence names ADR-0000
  as the home, but that HOME is superseded by the substation's live convention
  (ADR-0000 is read-only legacy; decisions are recorded under `docs/decisions/`
  and bind on write). Step 3 follows the live convention and appends NOTHING to
  ADR-0000, which the Step-3 test asserts with an empty diffstat.
- The D-H doctrine restated in this substation's `CLAUDE.md` — "Guards LOUD or
  GONE — a guard exists only if it protects a NAMED invariant and is loud
  (throws/refuses) when violated." ALIGNED: the named invariant ("a design-declared
  test file must appear in the pinned diff") stays loud, and this round makes the
  guard fire on a promise it had started dropping. `DeclaredTestsCapability.run`
  keeps reading its ambient values with the non-binding
  `getInheritedSeedOfExactType` effect verb at the `run` edge — untouched.
- NO recorded decision governs the list-separator vocabulary itself. `pow-0jc`
  (a base-present `Test:` run line is not a declaration), `pow-aoa` (a
  base-present bare prose mention is not a declaration) and `pow-qev`
  (authored-marker precedence; an unknown base declares everything) live in
  `committee.dart` comments and in the test suite, never in either register; each
  binds this plan as IMPLEMENTED behaviour and each is preserved byte-identically
  and re-pinned (the two-path run-line case is added specifically to prove
  `pow-0jc` did not invert). The run-vs-worded-gap geometry is therefore the one
  novel autonomous call this round, which is exactly what Step 3 records.

## Validation Plan
- [ ] One edit verb governing a comma/and list authors EVERY path in it → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "comma-and list"` → `+1: All tests passed!`
- [ ] An and-joined pair is authored whole and still GATES (`F`, rationale names only the missing path) → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "and-joined pair"` → `+1: All tests passed!`
- [ ] A verb that FOLLOWS the list governs the whole list → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "trailing verb"` → `+1: All tests passed!`
- [ ] A gap that carries WORDS keeps two runs separate; the cited harness is not swallowed → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "worded gap"` → `+1: All tests passed!`
- [ ] A two-path `Test: dart test <R> <S>` run line stays a fallback, never authored — `pow-0jc` not inverted → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "two-path run line"` → `+1: All tests passed!`
- [ ] The three round-1 receipts still classify as pinned and grade `A` → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "tg-5kb|space-fvg|tg-czsf"` → `+3: All tests passed!`
- [ ] An AMBIGUOUS base suffix stays declared and an EMPTY base declares every base-gated path → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart --name "ambiguous base suffix"` → `+1: All tests passed!`
- [ ] Every pre-existing case in the suite still passes, 33 + 5 → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart` → `+38: All tests passed!`
- [ ] The recorded decision states the RUN rule and legacy ADR-0000 is untouched → `grep -q '_testPathListGap' docs/decisions/2026-09-03-declared-tests-evidence-is-scoped-to-the-path-it-governs.md && git diff --stat origin/main...HEAD -- docs/adr/ADR-0000-ai-decision-register.md` → exit 0 with EMPTY diffstat output
- [ ] House gate green → `cd packages/grid_assets && dart analyze && dart test -j 4` → `No issues found!` then `+1114 ~1: All tests passed!`, exit 0