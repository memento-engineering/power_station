## Implementation Plan

A section heading is markdown STRUCTURE, so it must be resolved at a LINE START.
Today `specStructuralFindings` resolves it with `String.indexOf`, which cannot
tell a SECTION from a sentence that NAMES one. The space-3ds receipt
(2026-09-03 03:32Z) anchored `## Validation Plan` at character 23465 — inside the
sentence `... the fast subset rather than the full house gate (see ## Validation Plan).` —
read the following paragraph as the section body, found no `- ` item, and
hard-blocked a 31959-character spec whose real section, at 28312, carried ten.
One helper, `headingOffset`, replaces every such lookup. Every finding string
stays byte-identical, so no route rule string moves.

Reproduced offline against this worktree's own code before specifying (the four
section checks and `proseOnly`/`sectionBodyAt` lifted verbatim into a scratch
harness, driven both ways):

| design shape | `indexOf` today | `headingOffset` |
|---|---|---|
| mention above the real sections (the receipt) | `has no numbered steps` + `has no items` | clean |
| mention, NO real `## Validation Plan` | clean (the mention SATISFIES the check) | `no ... section` |
| mention, NO real `## Implementation Plan` | clean | `no ... section` |
| mention, NO real `## Touches` | clean | `no ... section` |
| unterminated fence quoting the heading above the real section | `has no items` | clean |

The last row is why the resolver answers the LAST line-anchored match rather than
the first. Callers pass `proseOnly` output, so a heading quoted in a TERMINATED
fence, a blockquote, or an inline span is already blanked; what survives is an
unterminated fence, whose tail `proseOnly` leaves scannable by design. This
pack's own specs quote the four canonical headings inside `## Implementation Plan`
— ABOVE the sections they name — so LAST is what keeps a quotation from
displacing the authored section in exactly the case that survives the strip.

The lookup is deliberately no STRICTER than the substring search it replaces on
every axis but two, both named: the line start (the fix), and 0-3 spaces of
indentation (4+ is an indented code block, which is quotation by the same rule
that blanks a fence). Any heading level `##`…`######` still resolves (an
`indexOf` for `## X` matches inside `### X` today, and a spec that writes
`### Touches` must not newly park), as does any trailing text on the heading
line (`## Validation Plan (1:1)`) and any spacing after the hashes. The only
other documents it newly refuses are the ones that never wrote the section —
which is the gate doing its job, and which acceptance criteria 2 and 3 pin.

### Step 1 — Add `headingOffset`, the line-anchored heading resolver

Append to `packages/grid_assets/lib/src/code/specify.dart`, immediately after
`sectionBodyAt` (which ends the file, at line 1337 in this worktree):

```dart

/// The offset of the heading LINE that opens [heading]'s section in [design],
/// or `-1` when there is none — the LAST match when several exist.
///
/// A heading is markdown STRUCTURE, so it is resolved at a LINE START. A
/// substring search is not, and that is the defect this replaces: it takes a
/// prose SENTENCE that NAMES the heading (`... the full house gate (see ##
/// Validation Plan).`) for the section itself, anchors [sectionBodyAt] at that
/// sentence, reads the following paragraph as the body, and hard-blocks a whole
/// spec on `has no items` while the real section, further down, carries ten
/// (bead `pow-o3ti`, receipt space-3ds 2026-09-03).
///
/// LAST, not first. Callers pass [proseOnly] output, so a heading quoted in a
/// TERMINATED fence, a `>` blockquote or an inline span is already blanked; what
/// survives is an UNTERMINATED fence, whose tail [proseOnly] leaves scannable by
/// design. This pack's own specs quote the four canonical headings inside their
/// `## Implementation Plan`, ABOVE the sections they name, so taking the LAST
/// line-anchored match is what keeps a quotation from displacing the authored
/// section in exactly the case that survives the strip.
///
/// As permissive as the `indexOf` it replaces on every axis but two: the line
/// start, and 0-3 spaces of indentation (4+ is an indented code block, i.e.
/// quotation). Any level `##`…`######` still resolves (`indexOf('## X')` matches
/// inside `### X` today, and a spec that writes `### Touches` must not newly
/// park), as does any trailing text on the heading line
/// (`## Validation Plan (1:1)`) and any spacing after the hashes.
///
/// PUBLIC for the same reason as [proseOnly] and [sectionBodyAt]: the code
/// committee's declaration headings resolve through this one definition too.
int headingOffset(String design, String heading) {
  final title = heading.replaceFirst(RegExp(r'^#+[ \t]*'), '');
  final matches = RegExp(
    r'^[ \t]{0,3}#{2,6}[ \t]*' + RegExp.escape(title),
    multiLine: true,
  ).allMatches(design).toList();
  return matches.isEmpty ? -1 : matches.last.start;
}
```

Test: `cd packages/grid_assets && dart analyze` → expect `No issues found!`.
Commit: `feat(specify): add the line-anchored headingOffset resolver`

### Step 2 — Resolve the four spec sections through it

In `packages/grid_assets/lib/src/code/specify.dart`, inside
`specStructuralFindings`, replace this block verbatim (lines 1241-1265 in this
worktree; the same bytes on `origin/main` at 1244-1269, so the edit is
rebase-safe):

```dart
  // The four design sections.
  final planAt = structure.indexOf('## Implementation Plan');
```

...through the closing brace of the `## Validation Plan` arm, with:

```dart
  // The four design sections. Each heading is resolved at a LINE START
  // ([headingOffset]): a sentence that NAMES `## Validation Plan` is a MENTION,
  // and a mention neither satisfies the gate nor displaces the real section
  // further down (bead `pow-o3ti`).
  final planAt = headingOffset(structure, '## Implementation Plan');
  if (planAt < 0) {
    findings.add('design: no `## Implementation Plan` section');
  } else if (!_numberedStep.hasMatch(sectionBodyAt(structure, planAt))) {
    findings.add(
      'design: `## Implementation Plan` has no numbered steps — every step '
      'must open with an ordinal (`1.` / `1)` list items, or `### Step 1 — …` '
      'headings)',
    );
  }
  if (headingOffset(structure, '## Touches') < 0) {
    findings.add('design: no `## Touches` section');
  }
  if (headingOffset(structure, '## ADR Alignment') < 0) {
    findings.add('design: no `## ADR Alignment` section');
  }
  final validationAt = headingOffset(structure, '## Validation Plan');
  if (validationAt < 0) {
    findings.add('design: no `## Validation Plan` section');
  } else {
    final body = sectionBodyAt(structure, validationAt);
    if (!RegExp(r'^\s*-\s*\S', multiLine: true).hasMatch(body)) {
      findings.add('design: `## Validation Plan` has no items');
    }
  }
```

Two `indexOf` calls and two `contains` calls become `headingOffset`; the finding
strings, the `_numberedStep` check and the `- ` item check are unchanged, and
`structure` is still `proseOnly(design)` (specify.dart:1231), so A19(3)'s
read-structure-from-prose clause is preserved exactly.

Test: `cd packages/grid_assets && dart test test/spec_committee_test.dart` →
expect `All tests passed!` (the pre-existing structural group — including the
fence-quoted-heading negative control at line 784 and the round-trip exemplar —
is the regression fence here).
Commit: `fix(specify): resolve spec section headings at a line start`

### Step 3 — State the rule in the contract the brief renders, and in the shipped rubric

A19(1): the contract is ONE string the brief renders and the gate enforces, so
the rule lands in both. In `packages/grid_assets/lib/src/code/specify.dart`,
inside `kSpecStructuralContract` (line 253), replace item 2:

```dart
2. **The design carries all four `## ` headings**, spelled exactly:
   `## Implementation Plan`, `## Touches`, `## ADR Alignment`,
   `## Validation Plan`.
```

with (the phrase `OPENING ITS OWN LINE` must stay whole on one physical line —
a validation grep counts it):

```dart
2. **The design carries all four `## ` headings**, spelled exactly:
   `## Implementation Plan`, `## Touches`, `## ADR Alignment`,
   `## Validation Plan` — each OPENING ITS OWN LINE. A heading NAMED inside a
   sentence ("the machine gate is the fast subset — see `## Validation Plan`")
   is a MENTION: it neither satisfies this rule nor displaces the real section
   further down. Backtick any heading you name in running prose.
```

Then in `packages/grid_assets/extension/rubrics/spec-validation.md`, restate the
same rule in the `## What it checks` bullet at line 14, replacing:

```markdown
- **The design carries all four sections** — `## Implementation Plan`,
  `## Touches`, `## ADR Alignment`, and `## Validation Plan` (with at least one
  `- ` item).
```

with (the phrase `read at a LINE START` must stay whole on one physical line):

```markdown
- **The design carries all four sections** — `## Implementation Plan`,
  `## Touches`, `## ADR Alignment`, and `## Validation Plan` (with at least one
  `- ` item). Each heading is read at a LINE START: a heading named inside a
  sentence ("see `## Validation Plan`") is a mention, not a section, and the
  real section further down is the one the check reads.
```

Test: `cd packages/grid_assets && dart test test/specify_stage_test.dart test/spec_rubric_pack_test.dart`
→ expect `All tests passed!` (the brief renders the contract verbatim; the
rubric pack's residue fence and the loader tests still hold).
Commit: `docs(specify): state the line-start heading rule in the contract and rubric`

### Step 4 — Route the code committee's declaration headings through the same resolver

`testDeclarations` resolves `## Declared Tests` / `## Files Touched` /
`## Touches` the same substring way, over the same `proseOnly` output, and its
failure mode is worse: a mid-line mention anchors an EMPTY body, the declaration
is silently LOST, and the gate stops checking a promised test file (verified
offline — the bucket goes from `{}` to `{<path>}` under the fix).

In `packages/grid_assets/lib/src/code/committee.dart`, widen the import at line
109:

```dart
import 'specify.dart' show headingOffset, proseOnly, sectionBodyAt;
```

and replace the loop at lines 370-374 (lines 505-509 on `origin/main`, byte-identical):

```dart
  for (final heading in _testDeclarationHeadings) {
    final headingAt = headingOffset(prose, heading);
    if (headingAt < 0) continue;
    declarationBodies.add(sectionBodyAt(prose, headingAt));
  }
```

Test: `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart`
→ expect `All tests passed!`.
Commit: `fix(committee): resolve declaration headings at a line start`

### Step 5 — Fence the behaviour with tests

In `packages/grid_assets/test/spec_committee_test.dart`, inside the group
`specStructuralFindings — each defect is a named, LOUD finding` (opens at line
546), insert after the `a validation plan without items` test (which closes at
line 587):

```dart

      test('a prose MENTION is not a section — the REAL section further down '
          'is the one the gate reads (bead `pow-o3ti`)', () {
        final mentioning = _specced().copyWith(
          design:
              'The machine gate for this bead is the fast subset rather than '
              'the full house gate (see ## Validation Plan), and every step is '
              'ordinal-led (see ## Implementation Plan).\n'
              '\n'
              '${_specced().design}',
        );
        expect(specStructuralFindings(mentioning), isEmpty);
      });

      test('a MENTION with no real `## Validation Plan` section blocks — the '
          'finding is unchanged, and today the mention SATISFIES the check', () {
        final mentionOnly = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '\n## Validation Plan\n',
            '\nEvery criterion is mapped (see ## Validation Plan).\n',
          ),
        );
        expect(
          specStructuralFindings(mentionOnly).single,
          contains('no `## Validation Plan` section'),
        );
      });

      test('a MENTION with no real `## Implementation Plan` section blocks — '
          'the finding is unchanged', () {
        final mentionOnly = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '## Implementation Plan\n',
            'Every step is ordinal-led (see ## Implementation Plan).\n',
          ),
        );
        expect(
          specStructuralFindings(mentionOnly).single,
          contains('no `## Implementation Plan` section'),
        );
      });

      test('a MENTION of `## Touches` no longer satisfies the PRESENCE check '
          '— the two `contains` lookups move to the same resolver', () {
        final mentionOnly = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '\n## Touches\n',
            '\nThe surfaces are enumerated under ## Touches in the epic.\n',
          ),
        );
        expect(
          specStructuralFindings(mentionOnly).single,
          contains('no `## Touches` section'),
        );
      });

      test('an UNTERMINATED fence quoting a heading ABOVE the real section '
          'does not displace it — the LAST line-anchored match wins', () {
        const ticks = '\x60\x60\x60';
        final quoting = _specced().copyWith(
          design: _specced().design.replaceFirst(
            'Commit: `feat(bus): add the peer heartbeat`\n',
            'Commit: `feat(bus): add the peer heartbeat`\n'
                '\n'
                'The exemplar this brief ships, quoted:\n'
                '${ticks}markdown\n'
                '## Validation Plan\n'
                'carrying no items\n'
                '\n',
          ),
        );
        expect(specStructuralFindings(quoting), isEmpty);
      });
```

Then add a sibling group for the resolver itself, at the SAME indentation as
`group('the brief ↔ gate ROUND TRIP (`pow-77g`)', …)` (which opens at line 739),
inserted after that group closes at line 826 and before the `  });` at line 827:

```dart

    group('headingOffset — a heading is STRUCTURE, read at a line start', () {
      test('a mid-sentence mention is not a heading', () {
        expect(
          headingOffset(
            'see ## Validation Plan for the map\n',
            '## Validation Plan',
          ),
          -1,
        );
      });

      test('the LAST line-anchored heading wins', () {
        const doc = '## Touches\nfirst\n\n## Touches\nsecond\n';
        expect(headingOffset(doc, '## Touches'), doc.lastIndexOf('## Touches'));
      });

      test('a deeper level and trailing text still read as the heading — no '
          'stricter than the substring search it replaces', () {
        expect(
          headingOffset(
            '### Validation Plan (1:1)\n- [ ] x\n',
            '## Validation Plan',
          ),
          0,
        );
      });

      test('an absent heading answers -1 — the `indexOf` contract every call '
          'site keeps', () {
        expect(headingOffset('## Touches\nx\n', '## Validation Plan'), -1);
      });

      test('0-3 spaces still indent a heading; 4+ is an indented code block, '
          'i.e. quotation', () {
        expect(
          headingOffset('   ## Touches\n- x\n', '## Touches'),
          0,
        );
        expect(
          headingOffset('    ## Touches\n- x\n', '## Touches'),
          -1,
        );
      });
    });
```

In `packages/grid_assets/test/track_c_declared_tests_test.dart`, add as the last
test of `main()` (before the file's closing `}` at line 507) the control that
discriminates the committee half. It asserts the `mentioned` bucket, not
`authored`: a bare path with NO edit verb is collected ONLY when the declaration
BODY is resolved, so this fails on the pre-fix code and passes after it:

```dart

  test('a mid-sentence `## Declared Tests` mention does not anchor the '
      'declaration body — the REAL section does (bead `pow-o3ti`)', () async {
    final path = _fixtureTestPath('line_anchored_declaration');
    final design =
        '''
The regression coverage is listed under ## Declared Tests below.

## Declared Tests
- (`$path`) carries the regression case.
''';
    expect(testDeclarations(design).mentioned, {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/src/code/specify.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });
```

Test: `cd packages/grid_assets && dart test test/spec_committee_test.dart test/track_c_declared_tests_test.dart`
→ expect `All tests passed!`.
Commit: `test(specify): fence the line-anchored heading lookup`

### Step 6 — RECORD the decision under `docs/decisions/`

The design makes an autonomous call (line-anchored, LAST match, level- and
trailing-text-permissive, 0-3 indent; the code committee's declaration loop
routed through the same resolver; `changeShapeOf` left alone) that substantively
extends A19(3), so it is recorded as a decision entry, never appended to the
read-only `docs/adr/ADR-0000-ai-decision-register.md`. Create
`docs/decisions/2026-09-03-spec-section-headings-resolve-at-a-line-start.md`
(if the build runs on a later date, use that date in both the filename and the
`date:` field — the slug never changes):

```markdown
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
```

Test: `cd /Users/nico/development/engineering.memento/power_station/.grid/worktrees/power_station/pow-o3ti && ls docs/decisions/*-spec-section-headings-resolve-at-a-line-start.md && head -1 docs/decisions/*-spec-section-headings-resolve-at-a-line-start.md`
→ expect the single new path, then `---` (no `decisions` CLI is installed in
this worktree — `command -v decisions` answers nothing — so the manual check
applies: filename and slug agree, each `surfaces` entry resolves on disk,
`status: accepted`, cached back-edges at their birth values).
Commit: `docs(decisions): record the line-start heading rule`

### Step 7 — Run the house gate

```sh
cd /Users/nico/development/engineering.memento/power_station/.grid/worktrees/power_station/pow-o3ti/packages/grid_assets
dart analyze && dart test
grep -rn "indexOf('## \|contains('## " lib/src/code/specify.dart lib/src/code/committee.dart
```

→ expect `No issues found!`, then `All tests passed!` (this worktree's baseline
is 1101 passing / 1 skipped, measured before specifying; the six new spec tests
and the one committee test take it to 1108 / 1 skipped), and no output from the
`grep` (exit status 1). Do NOT run `dart format` — this machine's SDK is ahead of
the pinned `^3.11` and reflows unrelated files.
Commit: none — this step is the gate run; fold any fix into the step commits above.

## Touches
- `packages/grid_assets/lib/src/code/specify.dart` — modified; ADDS
  `lib/src/code/specify.dart:headingOffset` (public, reaching the pack API
  through the existing wholesale `export 'src/code/specify.dart';` at
  `packages/grid_assets/lib/grid_assets.dart:177`); rewrites
  `specStructuralFindings`'s four section lookups and `kSpecStructuralContract`
  item 2. No signature change, no finding-string change, no re-homing.
- `packages/grid_assets/lib/src/code/committee.dart` — modified; the
  `specify.dart` import `show` list (line 109) and `testDeclarations`'s
  declaration-heading loop (lines 370-374). No new symbol.
- `packages/grid_assets/extension/rubrics/spec-validation.md` — modified; one
  bullet of the `## What it checks` section.
- `packages/grid_assets/test/spec_committee_test.dart` — modified; five new
  structural tests and a new `headingOffset` group.
- `packages/grid_assets/test/track_c_declared_tests_test.dart` — modified; one
  new declaration-heading control.
- `docs/decisions/2026-09-03-spec-section-headings-resolve-at-a-line-start.md` —
  created.
- NOT touched, by decision: `packages/grid_assets/lib/src/code/docs_committee.dart:209`
  (`changeShapeOf`'s `indexOf('## Touches')`) — it reads the RAW design because
  `citedPaths` needs the inline code spans `proseOnly` blanks, and it
  fails-to-code rather than hard-blocking. Named in the decision entry.

Re-validated against the live tree: `grep -rn "indexOf('## \|contains('## \|sectionBodyAt" lib test`
returns exactly the five resolve sites this plan enumerates (`specify.dart`
1242/1252/1255/1258, `committee.dart:371`) plus the deliberate exception
(`docs_committee.dart:209`), the `sectionBodyAt` definition
(`specify.dart:1332`) and the `show` import (`committee.dart:109`);
`grep -rn "headingOffset" . --include='*.dart'` returns nothing, so the new
symbol collides with nothing (`committee.dart:371` has a LOCAL named
`headingAt`, which step 4 rewrites rather than shadows). `specStructuralFindings`
has one non-test caller (`respec.dart:591`) and its signature is unchanged;
`testDeclarations` is consumed by `declaredTestFiles`/`missingDeclaredTestFiles`
in the same file and its signature is unchanged too. `bd dep list pow-o3ti`
reports no dependencies and no parent, so there is no sibling Touches to
cross-check; the nearest neighbour, `pow-26dd` (`_collectTestDeclarations`'s
per-path edit-verb claiming, same function), CLOSED and landed as PR #189 on
2026-09-03 — this worktree is 7 commits behind that merge, but `git show
origin/main:...` confirms both blocks this plan rewrites are BYTE-IDENTICAL on
`origin/main`, so the edits rebase without conflict and the two changes do not
overlap. Baseline confirmed green before specifying: `dart analyze` →
`No issues found!`, `dart test` → 1101 passed, 1 skipped.

## ADR Alignment
Verified via grep on `heading`, `structural`, `prose`, `section lookup`,
`specStructuralFindings` over `docs/adr` and `docs/decisions` (21 files hit;
every hit read).

- `power_station#a19-bead-pow-77g-the-spec-s-structural-contract-becomes-one`
  (`docs/decisions/2026-07-12-...md`, `legacy-id: A19`, `status: accepted`;
  ADR-0000 records it **Ratified (Nico, 2026-07-12)** with clause (3) in the
  accepted list). Clause (3): "The numbered-step check is SCOPED to the
  `## Implementation Plan` section's own body, and section lookup moves to
  `_proseOnly` output… a `## ` heading or a step ordinal quoted inside a fenced
  block is evidence, not structure. That is load-bearing for this pack, whose
  own specs quote all four headings verbatim." This plan EXTENDS that clause and
  is recorded as `updates:` it: the lookup STAYS on `proseOnly` output (step 2
  passes `structure`, which is `proseOnly(design)` at specify.dart:1231 — the
  discovery flag reading it as raw text is answered there), and now also anchors
  at a line start, because a sentence that NAMES a heading is evidence by exactly
  the same argument that a fenced one is. The clause's own "this pack's specs
  quote all four headings" is also what forces LAST-match over first.
  Clause (1) — "a gate whose contract the brief does not state is a trap" — is
  why step 3 changes `kSpecStructuralContract` and the shipped rubric in the same
  commit as the code, not after it.
- `docs/adr/ADR-0000-ai-decision-register.md` A17(4) (**Ratified**, Nico
  2026-07-12) and its **Amendment (Nico, 2026-07-30, governor-relayed)**. A17(4)
  froze "`specStructuralFindings`/`_proseOnly` in `specify.dart` … BYTE-UNCHANGED";
  the amendment narrows it — "the freeze binds the STRUCTURE — no re-homing, the
  fence stays scoped off human prose, the two functions keep their names and
  home — and does NOT bind the fence-strip's implementation; an in-place
  correctness fix … is authorized." This plan is the same class of in-place
  correctness fix that authorization drove (`pow-2kl`, `proseOnly`'s
  line-unanchored fence parsing): nothing is re-homed, both functions keep their
  names and home in `specify.dart`, the fence stays scoped off human prose
  (`Bead.description` is never read here), and the new helper is ADDED beside
  them rather than displacing either.
- `docs/adr/ADR-0000-ai-decision-register.md` A13(10) (Status **pending**, and
  its content re-ratified through A19): "the placeholder fence reads PROSE, not
  QUOTATION… a spec that QUOTES a token as evidence is pointing at work, not
  deferring it." The line-start rule is that same principle applied to the
  STRUCTURE axis; A13(2)'s "guards LOUD" contract is preserved exactly, since
  `SpecValidationCapability` is untouched and every finding string is
  byte-identical, so the route's gate reasons and rule strings do not move. This
  is also `CLAUDE.md`'s D-H clause "Guards LOUD or GONE" — the guard stays loud
  and now names a real invariant rather than a substring coincidence.
- `power_station#the-spec-decision-lane-queries-the-roster-union`
  (`docs/decisions/2026-09-02-...md`, `status: accepted`) governs the
  `decision-alignment` LANE's rubric text, not the deterministic
  `spec-validation` rubric this plan edits. Step 3 touches only
  `extension/rubrics/spec-validation.md`, so that entry is cited and
  distinguished, not implemented.
- This design's own autonomous call is RECORDED as a new `docs/decisions/`
  entry in step 6 (`status: accepted`, a `register` block carrying `spec: 1`,
  resolving `surfaces`, `bead: pow-o3ti`, and an authored `updates:` edge to
  A19 — the shape every 2026-09 entry in this register uses). Nothing is
  appended to `docs/adr/ADR-0000-ai-decision-register.md`, which is read-only
  legacy.
- Org invariants: no new surface is named here, so "extension, never plugin" and
  the human-faculty naming rule are not engaged (`headingOffset` is a verb over
  a document, not an agent-noun); every bead mutation in this bead's circuit
  rides the bd CLI with an `--actor`, never SQL.

## Validation Plan
- [ ] A spec whose PROSE mentions both headings before the real sections passes → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name 'a prose MENTION is not a section'` → `+1: All tests passed!`
- [ ] A MENTION with no real section hard-blocks with the unchanged findings → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name 'section blocks'` → `+2: All tests passed!`
- [ ] A MENTION of `## Touches` no longer satisfies the presence check → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name 'no longer satisfies the PRESENCE check'` → `+1: All tests passed!`
- [ ] `headingOffset` is line-anchored, LAST-match, `-1`-on-absent, level-, trailing-text- and 0-3-indent-permissive → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name 'headingOffset'` → `+5: All tests passed!`
- [ ] An UNTERMINATED fence quoting a heading above the real section does not displace it → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name 'UNTERMINATED fence'` → `+1: All tests passed!`
- [ ] No section heading is resolved by substring in the validator or the committee → `cd packages/grid_assets && grep -rn "indexOf('## \|contains('## " lib/src/code/specify.dart lib/src/code/committee.dart` → no output, exit status 1
- [ ] `testDeclarations` reads its declaration body line-anchored → `cd packages/grid_assets && dart test test/track_c_declared_tests_test.dart` → `All tests passed!`
- [ ] The contract and the shipped rubric both state the line-start rule → `cd packages/grid_assets && grep -c 'OPENING ITS OWN LINE' lib/src/code/specify.dart && grep -c 'read at a LINE START' extension/rubrics/spec-validation.md && dart test test/specify_stage_test.dart test/spec_rubric_pack_test.dart` → `1`, then `1`, then `All tests passed!`
- [ ] The decision is recorded under `docs/decisions/` with its A19 edge → `ls docs/decisions/*-spec-section-headings-resolve-at-a-line-start.md && grep -n 'a19-bead-pow-77g' docs/decisions/*-spec-section-headings-resolve-at-a-line-start.md` → the single new path, then the `updates:` line
- [ ] House gate green → `cd packages/grid_assets && dart analyze && dart test` → `No issues found!` then `All tests passed!` (1108 passing / 1 skipped: the 1101 baseline plus 7 new tests)