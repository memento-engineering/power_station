## Implementation Plan

**What is already true (read the code before you change it).** A18 (`pow-8dx`)
already ships the whole describe seam: `PrDescription` carries a prose field
(`body`), `PrSection.summary` already leads `kDefaultPrSections`, and
`renderPrSection` already renders that prose FIRST. So this bead is NOT "add a
section" — the section exists. What is missing is everything that makes it a
DIGEST a human recognizes:

- it renders as **bare, unlabeled prose** — no `## Summary` heading, while every
  other section is headed (see the merged the_grid #52/#53 bodies: the paragraph
  floats above `## Circuit receipt` looking like an accident);
- the prompt's contract for it is ONE weak line (`a short paragraph or two, or
  bullets`) whose example JSON value is the self-describing string
  `"What changed and why, in a sentence or three."` — a model copies the
  exemplar's shape, so the exemplar IS the contract;
- **nothing enforces A18(4) in the narrative**: `sanitizeConventionalSubject`
  strips the bead id from the SUBJECT by construction, but the body prose has no
  such belt — the prompt merely asks;
- the field is named `body`, which now means two different things in this file
  (`PrDescription.body` the model's prose vs the PR's whole `body`).

The plan renames the field to what it is, gives it a heading, gives it a belt,
and gives the model a real contract. **`pr_describe.dart` needs no code change**
— the bead's SCOPE line places the prompt there, but `buildDescribePrompt` is a
PURE function and lives in `pr_composition.dart`; `describeBranch` merely calls
it. Only its library doc line is refreshed (Step 4).

**One thing this plan deliberately does NOT do:** it adds no code-side check that
the digest really is 2–5 sentences, and no `Gate` on a missing digest. A18(6)
ratified fail-SAFE: "a PR description is decoration", and a land must never fail
over prose. The sentence count is taught in the PROMPT; the only thing enforced
in code is the invariant A18(4) NAMES — the bead id rides the trailer and nothing
else — which Step 2 makes unrepresentable rather than guarded (the A18(3)
posture). A digest-presence provenance line in the receipt was considered and
rejected: the `- description: inference | fallback` line already tells a reader
which channel spoke.

### Step 1 — Name the digest, cap it, and parse it

In `packages/grid_assets/lib/src/code/pr_composition.dart`, add the cap beside
the existing `kMaxContextChars` const (~line 60):

```dart
/// The human DIGEST the PR body leads with, capped (bead `pow-8qb`) — a model
/// that answers with a whole essay (or a pasted diff) must not become the PR
/// body. Truncation is the belt; the prompt asks for 2–5 sentences.
const int kMaxSummaryChars = 2000;
```

Then rename `PrDescription.body` → `PrDescription.summary` (a BREAKING rename of
a public field; the one in-repo consumer is `renderPrSection`, migrated in Step
2, plus three test fixtures migrated in Step 5). In the ctor, `this.body = ''`
becomes `this.summary = ''`, and the field doc becomes:

```dart
  /// The HUMAN DIGEST: 2–5 sentences of prose saying WHAT changed and WHY, for
  /// a reader who skims the PR and never opens the diff (bead `pow-8qb`).
  /// Rendered FIRST, under [PrSection.summary]'s own `## Summary` heading and
  /// through [sanitizeDigest]; blank ⇒ the section is dropped.
  final String summary;
```

In `PrDescription.parse`, read the new key and keep the old one as a tolerance
(the parse is documented FAIL-SAFE and lenient by design; the PROMPT teaches
exactly one key). Replace the `body: _str(decoded['body']),` line of the
`PrDescription(...)` construction with:

```dart
                // The digest. A18's older `body` key is still ACCEPTED — a
                // model that answers in the shape it half-remembers still yields
                // a digest, and a lost digest is the exact defect this bead
                // fixes. `parse` is lenient by contract (never a throw).
                summary: _str(decoded['summary']).isEmpty
                    ? _str(decoded['body'])
                    : _str(decoded['summary']),
```

Test: `cd packages/grid_assets && dart analyze lib` → expect `No issues found!`
(the test suite does not compile until Step 5 — that is the intended intermediate
state; do not commit Steps 1–4 separately if you want a bisectable history,
squash them).
Commit: `feat(grid_assets)!: name the PR digest — PrDescription.body becomes .summary`

### Step 2 — The belt: the bead id never rides the narrative

Still in `packages/grid_assets/lib/src/code/pr_composition.dart`, add the pure
sanitizer directly above the private `_circuitReceipt` renderer:

```dart
/// The digest as it is RENDERED: every occurrence of [foreignRef] — its `#rN`
/// rework form, the brackets that wrap it and the separator it orphans —
/// REMOVED, inline whitespace tidied, paragraph breaks preserved, the whole
/// capped at [maxChars].
///
/// The BELT behind the prompt's never-write-the-tracker-id rule, on the side the
/// subject's [sanitizeConventionalSubject] does not cover. A18(4): the bead id
/// is a git TRAILER **and nothing else** — so a model that writes it into the
/// narrative anyway still cannot land it in the PR body. Pure; '' in ⇒ '' out
/// (the section then renders nothing — never a bare heading).
String sanitizeDigest(
  String digest, {
  required String foreignRef,
  int maxChars = kMaxSummaryChars,
}) {
  var text = digest.trim();
  if (text.isEmpty) return '';
  final ref = foreignRef.trim();
  if (ref.isNotEmpty) {
    text = text.replaceAll(
      RegExp(
        '[(\\[]?${RegExp.escape(ref)}(#r\\d+)?[)\\]]?[ \\t]*[-—:,]?[ \\t]*',
        caseSensitive: false,
      ),
      '',
    );
  }
  text = text
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return _truncate(text, maxChars);
}
```

(`_truncate` is the file's existing private helper — it trims and appends
`\n… (truncated)`. Reuse it; do not write a second one.)

Now give the section its heading. In `renderPrSection`, replace the summary arm

```dart
      PrSection.summary => context.description?.body.trim() ?? '',
```

with a call to a new private renderer that matches `_committeeGrades` /
`_validation` in shape:

```dart
      PrSection.summary => _summary(context),
```

and add, beside those two renderers:

```dart
/// The human DIGEST, under its own heading — the FIRST thing a reader of the PR
/// meets (bead `pow-8qb`: the receipt is PROVENANCE, it was never a
/// description). A blank digest renders '' — the section is dropped, never a
/// bare heading.
String _summary(PrCompositionContext context) {
  final digest = sanitizeDigest(
    context.description?.summary ?? '',
    foreignRef: context.beadId,
  );
  if (digest.isEmpty) return '';
  final b = StringBuffer()
    ..writeln('## Summary')
    ..writeln()
    ..writeln(digest);
  return b.toString();
}
```

Also refresh `PrSection.summary`'s enum doc (~line 66) to name the heading:

```dart
  /// The HUMAN DIGEST ([PrDescription.summary]) under a `## Summary` heading —
  /// 2–5 sentences of WHAT changed and WHY, the section a reader wants first
  /// (beads `pow-8qb` / `pow-yny`: composed with the provenance below, never
  /// clobbered by it). Absent inference ⇒ omitted.
  summary,
```

`kDefaultPrSections` ALREADY leads with `PrSection.summary` — leave it alone; the
ordering is proven by a test in Step 5, not changed here.

Test: `cd packages/grid_assets && dart analyze lib` → expect `No issues found!`.
Commit: `feat(grid_assets): render the PR digest under ## Summary, id-stripped`

### Step 3 — Teach the model what a digest is

Still in `packages/grid_assets/lib/src/code/pr_composition.dart`, in
`buildDescribePrompt`. Delete the weak body rule:

```dart
    ..writeln(
      '- The body is prose (a short paragraph or two, or bullets): WHAT '
      'changed, and a HIGH-LEVEL WHY. Self-contained. No "this bead", no "per '
      'the spec", no ticket narrative.',
    )
```

and write the digest contract in its place:

```dart
    ..writeln(
      '- The `summary` is the PR\'s HUMAN DIGEST: 2 to 5 complete sentences of '
      'plain prose, for a reviewer who reads the pull request and NEVER opens '
      'the diff. Say WHAT changed — name the code\'s own types, files and '
      'behaviour — and WHY the change was worth making.',
    )
    ..writeln(
      '- The digest does NOT restate the title, does NOT narrate your process '
      '("first I…", "the tests now pass"), and carries NO ticket narrative ("this '
      'bead", "per the spec"). Write it in the repository\'s own terms.',
    )
    ..writeln(
      '- The digest is PROSE ONLY — no heading, no bullet list, no code fence. '
      'The asset renders it under its own `## Summary` heading.',
    )
```

In the never-write-the-tracker-id rule two bullets above, the trailing phrase
`in the title or in the body` becomes `in the title or in the summary`. Leave the
rest of that rule byte-identical — `track_e_reference_inflation_test.dart` and
`pr_composition_test.dart` both assert its opening substring
``NEVER write the tracker id `<id>` ``.

Finally the exemplar, which is the part the model actually copies. Replace the
answer object at the end of the builder:

```dart
    ..writeln(
      '{"type":"feat","scope":"landing","breaking":false,'
      '"description":"infer the pr title from the branch diff",'
      '"summary":"The land step now reads its own branch delta and hands it to '
      'a single cheap completion, so the title and the description say what the '
      'code actually does. The title was previously templated from the tracker, '
      'which could only ever restate the task it was filed under. A reader of '
      'the git log now learns what changed, and why, without leaving the '
      'repository.",'
      '"breakingChange":""}',
    );
```

Test: `cd packages/grid_assets && dart analyze lib` → expect `No issues found!`.
Commit: `feat(grid_assets): the describe prompt asks for a 2-5 sentence human digest`

### Step 4 — Refresh the one stale doc line in `pr_describe.dart`

`packages/grid_assets/lib/src/code/pr_describe.dart` needs NO code change (the
prompt builder it calls lives in `pr_composition.dart`). Its library doc's first
line still says the pass produces `the PR title/body parts` — one word is now
wrong. Change line 2 to:

```dart
/// branch's ACTUAL delta, producing the PR title + the human digest
/// ([PrDescription]).
```

Test: `cd packages/grid_assets && dart analyze lib` → expect `No issues found!`.
Commit: `docs(grid_assets): the describe pass produces a title and a digest`

### Step 5 — Migrate the fixtures, prove the digest

Three test fixtures answer in the old `"body"` shape and one asserts the old
field. Migrate all four, then add the new coverage.

**(a) `packages/grid_assets/test/pr_composition_test.dart`** — the shared fixture
at line 9 becomes a real digest:

```dart
const PrDescription _inferred = PrDescription(
  type: 'feat',
  scope: 'landing',
  description: 'Infer the pr title from the branch diff.',
  summary: 'The land step now reads the branch delta and describes it. '
      'Titles were terse and templated off the tracker.',
);
```

Line 147's `expect(parsed.body, 'prose');` becomes
`expect(parsed.summary, 'prose');` — and the canned stdout on line 140 keeps its
`"body":"prose"` key VERBATIM, because that assertion now proves the legacy-key
tolerance from Step 1. Add a sibling in the same `PrDescription.parse` group:

```dart
    test('reads the `summary` key — the digest the prompt now asks for', () {
      final parsed = PrDescription.parse(
        '{"type":"fix","description":"stop the clobber",'
        '"summary":"The receipt no longer writes the body."}',
      );
      expect(parsed!.summary, 'The receipt no longer writes the body.');
    });
```

In the body-composition group, the ordering test at line 198 leads with the
heading rather than the bare prose:

```dart
        final order = [
          body.indexOf('## Summary'),
          body.indexOf('The land step now reads the branch delta.'),
          body.indexOf('## Circuit receipt'),
          body.indexOf('## Committee'),
          body.indexOf('## Validation'),
          body.indexOf('Refs: tg-1'),
        ];
```

Then a NEW group — this bead's own proof:

```dart
  group('the human DIGEST leads the body (pow-8qb)', () {
    test(
      'an inferred digest renders under `## Summary`, ABOVE the receipt — the '
      'reader meets the change before its provenance',
      () {
        final body = const PrComposition().bodyOf(
          _context(description: _inferred, titleSource: 'inference'),
        );
        expect(body, startsWith('## Summary\n\n'));
        expect(body, contains('The land step now reads the branch delta.'));
        expect(
          body.indexOf('## Summary'),
          lessThan(body.indexOf('## Circuit receipt')),
        );
      },
    );

    test('a digest that smuggles the bead id is STRIPPED — the id rides the '
        'trailer and nothing else (A18(4))', () {
      final body = const PrComposition().bodyOf(
        _context(
          description: const PrDescription(
            type: 'feat',
            description: 'add the digest',
            summary: 'tg-1 — the land step now writes a digest. '
                'Fixes tg-1 (tg-1#r2) for good.',
          ),
          titleSource: 'inference',
        ),
      );
      expect(body, contains('## Summary'));
      expect(body, contains('the land step now writes a digest.'));
      expect('tg-1'.allMatches(body).length, 1);
      expect(body.trimRight(), endsWith('Refs: tg-1'));
    });

    test('NO digest ⇒ NO heading (an absent section is dropped, never bare)', () {
      const bare = PrComposition();
      expect(bare.bodyOf(_context()), isNot(contains('## Summary')));
      expect(
        bare.bodyOf(
          _context(
            description: const PrDescription(
              type: 'feat',
              description: 'add the thing',
            ),
            titleSource: 'inference',
          ),
        ),
        isNot(contains('## Summary')),
      );
      expect(
        bare.bodyOf(
          _context(
            description: const PrDescription(
              type: 'feat',
              description: 'add the thing',
              summary: '   \n  ',
            ),
            titleSource: 'inference',
          ),
        ),
        isNot(contains('## Summary')),
      );
    });

    test('a runaway digest is CAPPED (an essay must not become the PR body)', () {
      final long = 'word ' * (kMaxSummaryChars ~/ 2);
      final digest = sanitizeDigest(long, foreignRef: 'tg-1');
      expect(digest.length, lessThan(kMaxSummaryChars + 32));
      expect(digest, endsWith('… (truncated)'));
    });

    test('sanitizeDigest is pure prose surgery: paragraphs survive, the ref '
        'does not', () {
      expect(sanitizeDigest('', foreignRef: 'tg-1'), isEmpty);
      expect(
        sanitizeDigest('One. \n\nTwo.', foreignRef: 'tg-1'),
        'One.\n\nTwo.',
      );
      expect(
        sanitizeDigest('The tg-1 work adds x.', foreignRef: 'tg-1'),
        'The work adds x.',
      );
    });
  });
```

And extend the prompt group with the digest contract:

```dart
    test('asks for a 2-5 sentence human digest, prose-only, and EXEMPLIFIES it '
        'in the answer object (pow-8qb)', () {
      final prompt = buildDescribePrompt(
        bead: const Bead(id: 'tg-1', title: 'better titles'),
        beadId: 'tg-1',
        baseBranch: 'main',
        commitLog: 'feat(x): do a thing',
        diffStat: ' lib/x.dart | 2 +-',
        diff: '+the change',
      );
      expect(prompt, contains('HUMAN DIGEST'));
      expect(prompt, contains('2 to 5 complete sentences'));
      expect(prompt, contains('NEVER opens the diff'));
      expect(prompt, contains('no heading, no bullet list, no code fence'));
      expect(prompt, contains('"summary":"The land step now reads its own'));
      expect(prompt, isNot(contains('or bullets')));
    });
```

**(b) `packages/grid_assets/test/pr_describe_test.dart`** — the canned `_answer`
(line 30) answers in the new shape:

```dart
const String _answer =
    '{"type":"feat","scope":"landing","breaking":false,'
    '"description":"infer the pr title from the branch diff",'
    '"summary":"The land step reads the branch delta and describes it. '
    'The title no longer restates the tracker.","breakingChange":""}';
```

and the assertions at lines 110–111 gain the digest:

```dart
        expect(outcome.description!.summary, startsWith('The land step reads'));
```

**(c) `packages/grid_assets/test/landing_circuit_test.dart`** — the inference
test's fake answer (line 471) answers in the new shape
(`'"summary":"The land step now describes the actual diff.",'`), and the
composed-body assertions (~line 484) gain the heading:

```dart
      expect(opened.body, startsWith('## Summary'));
      expect(
        opened.body,
        contains('The land step now describes the actual diff.'),
      );
```

The existing `expect('tg-1'.allMatches(opened.body).length, 1);` on line 492
stays exactly as it is — it now also fences the digest.

Test: `cd packages/grid_assets && dart test test/pr_composition_test.dart test/pr_describe_test.dart test/landing_circuit_test.dart` → expect `All tests passed!`.
Commit: `test(grid_assets): the PR body leads with a Summary digest`

### Step 6 — The pack gate, then the register

Run the machine gate (the same line the code committee's gating lane runs):
`cd packages/grid_assets && dart pub get && dart analyze && dart test` → expect
`No issues found!` then `All tests passed!`. If the worktree's
`pubspec_overrides.yaml` path-deps are relative, make them absolute and re-run
`dart pub get` — a per-bead worktree sits two levels deeper than the checkout the
overrides were written for.

Then log the autonomous calls in the register. `docs/adr/ADR-0000-ai-decision-register.md`
gets ONE new amendment at the NEXT FREE ordinal — grep `^## A[0-9]` to find it
(A22 at spec time; the register moves, so check). It records, with
`**Status:** pending`, the four calls this plan makes: (1) `PrDescription.body`
is RENAMED to `.summary` rather than joined by a second prose field — one prose
blob, named for what it is, with the legacy key still parsed; (2) the digest gets
its OWN `## Summary` heading, and an absent digest drops the heading with it;
(3) the trailer-only invariant (A18(4)) is enforced in the NARRATIVE by
`sanitizeDigest`, extending A18(3)'s by-construction posture from the subject to
the body; (4) the 2–5 sentence shape is taught in the PROMPT and NOT checked in
code — A18(6)'s fail-safe stands, so a thin digest is never a land blocker.

Test: `cd packages/grid_assets && dart pub get && dart analyze && dart test` →
expect `All tests passed!`; `grep -c '^## A2[0-9]' ../../docs/adr/ADR-0000-ai-decision-register.md` → a count one higher than before the edit.
Commit: `docs(adr): register the PR-digest calls (pending)`

## Touches

- `packages/grid_assets/lib/src/code/pr_composition.dart` — MODIFIED.
  - `lib/src/code/pr_composition.dart:kMaxSummaryChars` — NEW const (2000).
  - `lib/src/code/pr_composition.dart:sanitizeDigest` — NEW public pure function.
  - `lib/src/code/pr_composition.dart:PrDescription.summary` — **BREAKING
    RENAME** of `PrDescription.body` (public field; ctor param renamed with it).
  - `lib/src/code/pr_composition.dart:PrDescription.parse` — reads `summary`,
    still tolerates the legacy `body` key.
  - `lib/src/code/pr_composition.dart:renderPrSection` — the `PrSection.summary`
    arm now renders `## Summary` + the sanitized digest (private `_summary`).
  - `lib/src/code/pr_composition.dart:buildDescribePrompt` — the digest contract
    + the exemplar answer object.
  - `PrSection`, `kDefaultPrSections`, `PrComposition`, `PrCompositionContext`
    are UNCHANGED in shape — the enum value and its lead position already exist.
  - Both new symbols reach the pack's public API through the EXISTING wholesale
    `export 'src/code/pr_composition.dart';` at `lib/grid_assets.dart:102` — no
    export edit.
- `packages/grid_assets/lib/src/code/pr_describe.dart` — doc-comment line only
  (no code change; `InferenceRunner`, `DescribeOutcome`, `describeBranch` all
  keep their signatures).
- `packages/grid_assets/test/pr_composition_test.dart` — MODIFIED: the `_inferred`
  fixture, the `parsed.body` assertion, the section-order list; NEW group `the
  human DIGEST leads the body (pow-8qb)` + the prompt-contract test.
- `packages/grid_assets/test/pr_describe_test.dart` — MODIFIED: the `_answer`
  fixture + a digest assertion.
- `packages/grid_assets/test/landing_circuit_test.dart` — MODIFIED: the
  `FakeInferenceRunner` answer + the `## Summary` assertions.
- `docs/adr/ADR-0000-ai-decision-register.md` — NEW pending amendment (next free
  `A<n>`).

Re-validated against the live tree: `grep -rn "PrDescription\|\.body\b" --include='*.dart' packages/` finds the field's ONLY consumers at `pr_composition.dart:349` (the render arm, migrated in Step 2) and `pr_composition_test.dart:147` (migrated in Step 5); every other `.body` hit is `pr.opened.single.body` — the PR record's own body, a different symbol, untouched. The `"body":` JSON key appears in exactly three test fixtures (`pr_composition_test.dart:140`, `landing_circuit_test.dart:471`, `pr_describe_test.dart:33`), all three migrated above. `bd dep list pow-8qb` reports NO dependencies and no siblings, so nothing this plan consumes is being added elsewhere; the plan is self-contained.

## ADR Alignment

Grepped from the worktree root: `ls docs/adr/` → `ADR-0000-ai-decision-register.md`,
`ADR-0001-packaged-ai-asset-skill-command-coupling.md`; then
`grep -li "pull request\|PR title\|describe\|summary\|conventional\|digest" docs/adr/*.md`
→ `ADR-0000` only.

- `docs/adr/ADR-0000-ai-decision-register.md` **A18** (bead `pow-8dx`) — the
  amendment this bead is the named follow-up to. Its Status line closes with:
  "LANDED + PROVEN: the #52/#53/#13 squash titles are clean conventional
  commits. Follow-up: **the human-readable digest (deferred bead)**." This bead
  IS that deferral, so A18's clauses bind the plan:
  - **A18(4)** — "The bead id is a git TRAILER (`Refs: <bead>`, token
    configurable) and NOTHING else". The plan's `sanitizeDigest` (Step 2) is what
    makes that clause true of the NARRATIVE, which today only the prompt asks
    for; the test asserts the id appears exactly once in the composed body.
  - **A18(3)** — "Compliance is BY CONSTRUCTION, not by trust… the bead id is
    STRIPPED… asserted as an invariant over adversarial inputs, not hoped for."
    The plan extends that posture from the subject to the digest: the belt is a
    pure function on the render path, proven against a digest that smuggles the
    id three ways (bare, parenthesized, `#rN`).
  - **A18(6)** — "Fail-SAFE over fail-closed, deliberately… a PR description is
    decoration". This is why the plan adds NO sentence-count check and NO gate on
    a missing digest: a blank digest drops its section and the land proceeds. Per
    CLAUDE.md's "guards LOUD or GONE", the only guard added is the one protecting
    a NAMED invariant (A18(4)'s trailer-only rule).
  - **A18(2)** — the describe pass runs INSIDE the land step behind the injected
    `InferenceRunner`, never a new spawned circuit step (it would mint a fourth
    persisted cursor-key shape inside `pow-3p4`'s migration surface). The plan
    reuses that seam exactly: no new step, no circuit change, no cursor key.
  - **A18(1)** — the inference reads `origin/<base>...HEAD`, the same three-dot
    range `PinDiffCapability` pins the critics to. Unchanged: the digest is
    another field on the SAME one-shot answer, not a second call.
- `docs/adr/ADR-0000-ai-decision-register.md` **A10(3)** — "the carrier is a
  plain const class, not a freezed value". `PrDescription` and `PrComposition`
  stay plain const classes; the plan adds no freezed union (there is no sum type
  here — one answer shape, one render).
- `power_station/CLAUDE.md`, the D-H genesis_tree doctrine (ADR-0008) — **config
  = VALUES in the tree, impls = DI**. `PrComposition` remains the mounted config
  VALUE (`GitHubGridAssets(composition: …)` → `InheritedSeed<PrComposition>`) and
  the digest rides it (`sections`, `trailerToken`, `model`); the plan adds NO new
  knob and NO service in a branch. Everything in `pr_composition.dart` stays PURE
  — the git reads and the inference call remain in `pr_describe.dart` and reach
  the renderers as DATA, so no `dependOn*`/`StateNotifier` surface is touched.
- `docs/adr/ADR-0001-packaged-ai-asset-skill-command-coupling.md` — does not
  apply: the plan ships no skill, command, or manifest section.

## Validation Plan

- [ ] The digest renders under a `## Summary` heading as the FIRST section of the PR body, above the circuit receipt → `cd packages/grid_assets && dart test test/pr_composition_test.dart` → `All tests passed!` — Step 5(a)'s new group, test "an inferred digest renders under ## Summary, ABOVE the receipt".
- [ ] A digest that smuggles the bead id is STRIPPED — the id appears EXACTLY once in the composed body, on the trailer line → `cd packages/grid_assets && dart test test/pr_composition_test.dart test/landing_circuit_test.dart` → `All tests passed!` — the `'tg-1'.allMatches(body).length` assertion in the new digest group and at the land edge.
- [ ] A blank or absent digest drops the heading with its section, and the PR still lands → `cd packages/grid_assets && dart test test/pr_composition_test.dart test/landing_circuit_test.dart` → `All tests passed!` — test "NO digest ⇒ NO heading" plus the existing land-still-opens tests.
- [ ] `PrDescription.parse` reads the `summary` key and still recovers a legacy `body` key → `cd packages/grid_assets && dart test test/pr_composition_test.dart` → `All tests passed!` — the `PrDescription.parse` group's new test plus the migrated `expect(parsed.summary, 'prose')`.
- [ ] A runaway digest is capped at `kMaxSummaryChars`, and `sanitizeDigest` preserves paragraph breaks → `cd packages/grid_assets && dart test test/pr_composition_test.dart` → `All tests passed!` — tests "a runaway digest is CAPPED" and "sanitizeDigest is pure prose surgery".
- [ ] `buildDescribePrompt` states the digest contract (2 to 5 sentences, human reader, prose-only) and its exemplar answer object carries a real `summary` → `cd packages/grid_assets && dart test test/pr_composition_test.dart` → `All tests passed!` — test "asks for a 2-5 sentence human digest".
- [ ] The pack is green end to end — no analyzer issue, no regression in the landing / describe / reference-inflation suites → `cd packages/grid_assets && dart pub get && dart analyze && dart test` → `No issues found!` then `All tests passed!`
- [ ] The autonomous calls are logged as ONE pending ADR-0000 amendment at the next free ordinal → `grep -c '^## A2' docs/adr/ADR-0000-ai-decision-register.md` → one higher than before the edit, and the new amendment's `**Status:**` line reads `pending`.