## Implementation Plan

Every command below runs from the worktree root
`/Users/nico/development/engineering.memento/power_station/.grid/worktrees/power_station/pow-77g`.
The build spawn materializes pub linkage (`pubspec_overrides.yaml`) itself
(ADR-0000 A1), so `cd packages/grid_assets && dart pub get` resolves before
step 1 and `dart analyze` returns `No issues found!` after every step.

**The finding, stated once.** `pow-kzx`'s implementation plan is 1226 lines, and
the `plan-completeness` critic graded it **A** ("every step names an exact file
path, quotes exact before/after code blocks"). It carries **zero** lines matching
the gate's `^\s*1[.)]\s` — its steps are `### Step 1 — Relocate the discover
skill …` headings, which is the shape a plan with a fenced Dart block per step
must take (a `1.` list item would have to indent every following block to stay
inside the item). The gate rejected the plan's markdown dialect, not its content,
and it rejected a dialect the brief never named. Three edits close it: name the
contract (step 3), enforce the invariant the contract actually states (step 2),
and stop banning tokens the brief never listed (step 1).

1. **Derive the placeholder fence from ONE exported token list.** The brief names
   three banned tokens; the fence bans seven. The four it omits are ordinary
   English an architect writes without thinking, so a good spec parks on a rule
   nobody stated. Make the list the single source and export it, so the brief
   (step 3) enumerates exactly what the fence compiles.

   In `packages/grid_assets/lib/src/code/specify.dart`, replace the
   `_placeholderPatterns` declaration (currently lines 698-712, the doc comment
   through the closing `];`) with:

   ```dart
   /// The placeholder tokens that anchor an automatic structural F — a spec that
   /// defers its own content is not implementation-ready.
   ///
   /// This list is the ONE source: [_placeholderPatterns] compiles it (single
   /// words on word boundaries, so an identifier that merely CONTAINS the
   /// letters never trips; the phrases verbatim, all case-insensitive) and
   /// [kSpecStructuralContract] enumerates it to the specify agent — so the
   /// fence can never ban a token the brief never named. Before bead `pow-77g`
   /// the brief named three of these seven, and the four it omitted are ordinary
   /// English an architect writes without thinking: a good plan parked on a rule
   /// nobody stated.
   const List<String> kSpecPlaceholderTokens = [
     'TBD',
     'TODO',
     'implement later',
     'fill in later',
     'as needed',
     'appropriate error handling',
     'similar to step',
   ];

   /// [kSpecPlaceholderTokens] compiled — single words word-bounded, phrases
   /// verbatim, all case-insensitive. Matched against [_proseOnly] output, so a
   /// token inside a markdown quotation context (quoted code, a cited clause) is
   /// evidence, not deferral, and never trips.
   final List<RegExp> _placeholderPatterns = [
     for (final token in kSpecPlaceholderTokens)
       RegExp(
         token.contains(' ')
             ? RegExp.escape(token)
             : '\\b${RegExp.escape(token)}\\b',
         caseSensitive: false,
       ),
   ];
   ```

   This is byte-equivalent to the seven hand-written patterns it replaces
   (`\btbd\b`, `\btodo\b`, and the five verbatim phrases), so every existing
   placeholder test stays green — the change is that the list is now readable by
   the brief.

   Test: `cd packages/grid_assets && dart test test/spec_committee_test.dart` →
   expect `All tests passed!`.
   Commit: `refactor(grid_assets): derive the spec placeholder fence from one exported token list`

2. **Recognize BOTH ordinal shapes, scope the check to the plan body, and read
   structure from PROSE.** Three defects in one function: the gate accepts only
   `1.`/`1)` list items (it F's `pow-kzx`'s A-graded heading form); it scans the
   WHOLE design for the ordinal, so a step-less plan passes whenever any `1.`
   appears in another section (a real gap it fails to bite); and it finds its
   `## ` headings by raw substring, so a heading quoted inside a fenced block
   counts as a section. The ordinal stays MANDATORY throughout — a bulleted or
   prose-only plan, whose steps are neither ordered nor addressable, still fails
   LOUD. That is the bead's fix (b) taken only as far as its tight-contract
   caveat allows.

   In `packages/grid_assets/lib/src/code/specify.dart`, insert this recognizer
   immediately above `specStructuralFindings` (currently line 714):

   ```dart
   /// A NUMBERED step's opening line inside `## Implementation Plan` — the two
   /// shapes a real plan takes, BOTH carrying an explicit ordinal:
   ///
   ///   * an ordered-list item — `1. …` / `1) …`
   ///   * an ordinal heading or bold lead-in — `### Step 1 — …`, `### 1. …`,
   ///     `**Step 1:** …`
   ///
   /// The heading form is what a plan with a fenced Dart block per step must
   /// take (a `1.` list item has to indent every following block to stay inside
   /// the item) and it is what the specify agent writes when left to itself:
   /// bead `pow-kzx`'s 1226-line plan, graded **A** by the `plan-completeness`
   /// critic, carried `### Step 1 — …` headings and not one `1.`-led line, and
   /// F'd here on FORMAT alone (bead `pow-77g`).
   ///
   /// Recognizing it is not a loosening — the ordinal is still MANDATORY, so a
   /// bulleted or prose-only plan (steps neither ordered nor addressable) still
   /// fails LOUD. In a heading or bold lead-in a bare ordinal IS the step number,
   /// so no trailing `.`/`)` is required there; in running prose one is, which is
   /// why `2026-07-11 …` and `3.5x faster` do not match.
   final RegExp _numberedStep = RegExp(
     r'^[ \t]*(?:'
     r'\d+[.)]\s' // 1. …  /  1) …
     r'|#{1,6}[ \t]*(?:step[ \t]*)?\d+\b' // ### Step 1 — …  /  ### 1. …
     r'|\*\*[ \t]*(?:step[ \t]*)?\d+\b' // **Step 1:** …  /  **1.** …
     r')',
     multiLine: true,
     caseSensitive: false,
   );
   ```

   Then replace the body of `specStructuralFindings` (currently lines 719-761,
   from `List<String> specStructuralFindings(Bead bead) {` through its closing
   `}`) with:

   ```dart
   List<String> specStructuralFindings(Bead bead) {
     final findings = <String>[];
     final acceptance = bead.acceptanceCriteria;
     final design = bead.design;
     // The SHAPE is read from PROSE, the same way the placeholder fence is
     // (A13(10)): a `## ` heading or a step ordinal quoted inside a fenced block
     // — this pack's own spec exemplar quotes all four headings verbatim — is
     // evidence, not structure.
     final structure = _proseOnly(design);

     // Testable acceptance: at least one `- [ ]` checkbox criterion.
     if (!RegExp(
       r'^\s*-\s*\[[ xX]\]\s*\S',
       multiLine: true,
     ).hasMatch(acceptance)) {
       findings.add('acceptance: no testable `- [ ]` checkbox criteria');
     }

     // The four design sections.
     final planAt = structure.indexOf('## Implementation Plan');
     if (planAt < 0) {
       findings.add('design: no `## Implementation Plan` section');
     } else if (!_numberedStep.hasMatch(_sectionBody(structure, planAt))) {
       findings.add(
         'design: `## Implementation Plan` has no numbered steps — every step '
         'must open with an ordinal (`1.` / `1)` list items, or `### Step 1 — '
         '…` headings)',
       );
     }
     if (!structure.contains('## Touches')) {
       findings.add('design: no `## Touches` section');
     }
     if (!structure.contains('## ADR Alignment')) {
       findings.add('design: no `## ADR Alignment` section');
     }
     final validationAt = structure.indexOf('## Validation Plan');
     if (validationAt < 0) {
       findings.add('design: no `## Validation Plan` section');
     } else {
       final body = _sectionBody(structure, validationAt);
       if (!RegExp(r'^\s*-\s*\S', multiLine: true).hasMatch(body)) {
         findings.add('design: `## Validation Plan` has no items');
       }
     }

     // Placeholder tokens anywhere in the spec's PROSE — quotation contexts
     // (quoted code, cited clauses) are evidence, not deferral, and never trip.
     final prose = _proseOnly('$acceptance\n$design');
     for (final pattern in _placeholderPatterns) {
       final match = pattern.firstMatch(prose);
       if (match != null) {
         findings.add(
           'placeholder: "${match.group(0)}" — not implementation-ready',
         );
       }
     }
     return findings;
   }
   ```

   The finding string still contains `has no numbered steps`, which the existing
   assertion at `test/spec_committee_test.dart:274` matches, so that test needs
   no edit — it now proves the ordinal-free plan case rather than the
   wrong-dialect case.

   Also correct the two doc comments that state the old contract, both in the
   same file: in `SpecValidationCapability`'s doc (line 653) change
   `` (`## Implementation Plan` with numbered steps, `## Touches`, `` to
   `` (`## Implementation Plan` with ordinal-led steps, `## Touches`, ``; and
   extend the "reads the spec's PROSE only" paragraph (lines 661-665) with the
   sentence: `The same strip governs the STRUCTURE check — a `## ` heading or a
   step ordinal quoted inside a fence is evidence, not structure.`

   Test: `cd packages/grid_assets && dart test test/spec_committee_test.dart` →
   expect `All tests passed!`.
   Commit: `fix(grid_assets): spec-validation accepts ordinal-heading steps, scopes the check to the plan body, reads structure from prose (pow-77g)`

3. **Ship the contract + a round-trip exemplar as ONE exported string the brief
   renders verbatim.** A gate whose contract the brief does not state is a trap;
   a brief that states a contract the gate does not enforce is a lie. Make them
   one string, and prove it with an exemplar that the gate itself grades clean.

   In `packages/grid_assets/lib/src/code/specify.dart`, insert this block
   immediately after the `kSpecCommitteeRubrics` declaration (currently ends line
   107) and before `kSpecReviewCircuit`:

   ````dart
   /// A structurally WHOLE spec — the acceptance half of the exemplar the specify
   /// brief ships. Round-tripped through [specStructuralFindings] in test: what
   /// the architect is told to copy is PROVEN to pass the gate that grades it.
   const String kSpecExemplarAcceptance = '''
   - [ ] `Heartbeat` parses a well-formed peer frame
   - [ ] A malformed peer frame is refused LOUDLY (throws, never returns null)''';

   /// The design half of that exemplar — one complete step in the ordinal-heading
   /// shape, all four sections, every element the four LLM lanes look for.
   const String kSpecExemplarDesign = '''
   ## Implementation Plan

   ### Step 1 — Add the `Heartbeat` frame

   Create `packages/grid_assets/lib/src/bus/heartbeat.dart`:

   ```dart
   /// One peer heartbeat frame.
   class Heartbeat {
     /// Parses [frame]; throws [FormatException] on a malformed frame.
     factory Heartbeat.parse(String frame) => frame.isEmpty
         ? throw const FormatException('empty heartbeat frame')
         : Heartbeat(frame);

     /// Creates a heartbeat from [peerId].
     const Heartbeat(this.peerId);

     /// The peer that sent it.
     final String peerId;
   }
   ```

   Test: `cd packages/grid_assets && dart test test/heartbeat_test.dart` → expect
   `All tests passed!`.
   Commit: `feat(bus): add the peer heartbeat frame`

   ## Touches
   - `packages/grid_assets/lib/src/bus/heartbeat.dart` — created;
     `lib/src/bus/heartbeat.dart:Heartbeat`

   Re-validated against the live tree: `Heartbeat` has no caller yet and no
   sibling bead adds one.

   ## ADR Alignment
   No ADR applies — verified via grep on `heartbeat`, `bus`, `frame`.

   ## Validation Plan
   - [ ] `Heartbeat` parses a well-formed peer frame → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`
   - [ ] A malformed peer frame is refused LOUDLY → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`''';

   /// [kSpecPlaceholderTokens] as one backticked line — the brief names EVERY
   /// token the fence bans.
   final String _bannedTokenLine = kSpecPlaceholderTokens
       .map((token) => '`$token`')
       .join(', ');

   /// The EXACT structural contract the deterministic `spec-validation` lane
   /// enforces ([specStructuralFindings]), in the words the specify agent reads.
   /// [buildSpecifyBrief] renders it VERBATIM, so the gate's contract and the
   /// architect's instructions are literally ONE string.
   ///
   /// Bead `pow-77g`: `pow-kzx`'s plan was graded **A** by `plan-completeness`
   /// and **F** here, for lacking a step FORMAT the brief never named. A gate
   /// whose contract the brief does not state is a trap. The round-trip fence in
   /// test — the exemplar below PASSES [specStructuralFindings] — is what keeps
   /// the two honest as either side moves.
   final String kSpecStructuralContract =
       '''
   ### The structural contract (a DETERMINISTIC gate, run before any critic reads your spec)

   `spec-validation` is not a critic and holds no opinion: it greps the bead you
   write and hard-blocks the build on any miss. It checks EXACTLY this, and
   nothing else:

   1. **Acceptance** carries at least one `- [ ]` checkbox line.
   2. **The design carries all four `## ` headings**, spelled exactly:
      `## Implementation Plan`, `## Touches`, `## ADR Alignment`,
      `## Validation Plan`.
   3. **`## Implementation Plan` carries NUMBERED steps.** Every step opens with
      an ordinal — an ordered-list item (`1. …` / `1) …`) or an ordinal heading
      (`### Step 1 — …` / `### 1. …`). A bulleted or prose-only plan has no
      ordinal and FAILS however complete it is. Steps carrying fenced code read
      best as `### Step N — …` headings.
   4. **`## Validation Plan` carries at least one `- ` item.**
   5. **No placeholder token in PROSE.** These exact tokens, case-insensitively:
      $_bannedTokenLine.

   Headings and ordinals are read from PROSE, and so are those tokens: markdown
   QUOTATION is exempt (fenced blocks, `inline code` spans, `>` blockquote
   lines). A token you QUOTE as evidence — a comment your plan deletes, a gate
   note cited verbatim — points at work rather than deferring it, so backtick any
   banned token you must name. The same cuts the other way: a `## Touches`
   heading that exists only inside a code block is evidence, not a section.

   Below is a COMPLETE spec that passes this gate. Copy its SHAPE.

   `````markdown
   $kSpecExemplarAcceptance

   $kSpecExemplarDesign
   `````''';
   ````

   Then wire it into the brief. In `buildSpecifyBrief`, replace the tail of the
   `**## Implementation Plan**` bullet (currently lines 383-385) — the sentence
   beginning `No placeholders — ` through `F-gates.',` — with:

   ```dart
         'No placeholders: the structural contract below enumerates every '
         'banned token, and a spec that defers its own content is F-gated.',
   ```

   and insert the contract after the `**## Validation Plan**` bullet (currently
   ends line 412), immediately before the `### 3. The machine gate` line:

   ```dart
       ..writeln()
       ..writeln(kSpecStructuralContract)
   ```

   Test: `cd packages/grid_assets && dart test test/specify_stage_test.dart` →
   expect `All tests passed!`.
   Commit: `feat(grid_assets): the specify brief ships the gate's EXACT structural contract + a round-tripped exemplar (pow-77g)`

4. **Restate the rubric doc to the contract the code enforces.** The pack's
   `spec-validation.md` is the portable mirror of the lane; it says "with
   numbered steps" and lists the tokens loosely. Replace its `## What it checks`
   section in
   `packages/grid_assets/extension/rubrics/spec-validation.md` (the section
   heading through the blank line before `## Bands`) with:

   ```markdown
   ## What it checks

   - **Acceptance criteria** — at least one testable `- [ ]` checkbox criterion in
     the bead's acceptance field.
   - **The design carries all four sections** — `## Implementation Plan`,
     `## Touches`, `## ADR Alignment`, and `## Validation Plan` (with at least
     one `- ` item).
   - **`## Implementation Plan` carries ORDINAL-LED steps.** Every step opens with
     an ordinal: an ordered-list item (`1. …` / `1) …`) or an ordinal heading
     (`### Step 1 — …` / `### 1. …` / `**Step 1:** …`). Both are ordered and
     addressable; a bulleted or prose-only plan is neither and fails, however
     complete it is. The check reads the `## Implementation Plan` section's own
     body — an ordinal in another section does not stand in for a step.
   - **No placeholder token in PROSE** — `TBD`, `TODO`, `implement later`,
     `fill in later`, `as needed`, `appropriate error handling`,
     `similar to step`. A spec that defers its own content is not
     implementation-ready.
   - Structure and tokens are read from PROSE alike: markdown QUOTATION contexts
     (fenced code blocks, `inline code` spans, `>` blockquote lines) are stripped
     before matching. A spec that QUOTES a token as evidence — a comment its plan
     deletes, an ADR clause cited verbatim — points at work rather than deferring
     it; and a heading that exists only inside a code block is evidence, not a
     section.

   The contract is not this lane's secret: `kSpecStructuralContract` states it
   verbatim in the specify agent's own brief, and the exemplar the brief ships is
   round-tripped through this check in test. A spec F'd here failed a rule it was
   told.
   ```

   Nothing else in the file changes — `# spec-validation [GATING]`, the `## Bands`
   section, and the `hard block` / `gated` sentences stay, so the pack fences in
   `test/spec_rubric_pack_test.dart` (self-naming, `GATING`, `hard block`,
   `gated`, and the source-residue grep) hold.

   Test: `cd packages/grid_assets && dart test test/spec_rubric_pack_test.dart` →
   expect `All tests passed!`.
   Commit: `docs(grid_assets): the spec-validation rubric states the contract the lane enforces (pow-77g)`

5. **Fence it — the round trip, the two ordinal shapes, and the three real gaps
   that must still bite.** Append this group to
   `packages/grid_assets/test/spec_committee_test.dart`, inside the existing
   top-level `main()`, immediately after the
   `group('specStructuralFindings — each defect is a named, LOUD finding', …)`
   group's closing `});` (currently line 364) and before the closing `});` of its
   parent group:

   ```dart
   group('the brief ↔ gate ROUND TRIP (`pow-77g`)', () {
     test('the exemplar the brief SHIPS passes the gate that grades it — the '
         'contract is one string, not two', () {
       final exemplar = bead('tg-1').copyWith(
         acceptanceCriteria: kSpecExemplarAcceptance,
         design: kSpecExemplarDesign,
       );
       expect(specStructuralFindings(exemplar), isEmpty);
     });

     test('an ORDINAL-HEADING plan grades A — the `pow-kzx` shape the '
         'plan-completeness critic graded A and this lane F\'d on format', () {
       final headed = _specced().copyWith(
         design: _specced().design.replaceFirst(
           '1. Add `Heartbeat` — `lib/src/heartbeat.dart`',
           '### Step 1 — Add `Heartbeat` in `lib/src/heartbeat.dart`',
         ),
       );
       expect(specStructuralFindings(headed), isEmpty);
     });

     test('a BULLETED plan still F\'s — the ordinal stays MANDATORY', () {
       final bulleted = _specced().copyWith(
         design: _specced().design.replaceFirst('1. Add', '- Add'),
       );
       expect(
         specStructuralFindings(bulleted).single,
         contains('has no numbered steps'),
       );
     });

     test('an ordinal OUTSIDE the plan section no longer rescues a step-less '
         'plan — the check reads the `## Implementation Plan` body', () {
       final elsewhere = _specced().copyWith(
         design: _specced().design
             .replaceFirst('1. Add', '- Add')
             .replaceFirst(
               '## Validation Plan\n',
               '## Validation Plan\n1. run the suite\n',
             ),
       );
       expect(
         specStructuralFindings(elsewhere).single,
         contains('has no numbered steps'),
       );
     });

     test('a heading quoted inside a fenced block is evidence, not a section',
         () {
       final quotedOnly = _specced().copyWith(
         design: _specced().design.replaceFirst(
           '## Touches\n',
           '```markdown\n## Touches\n```\n',
         ),
       );
       expect(
         specStructuralFindings(quotedOnly).single,
         contains('no `## Touches` section'),
       );
     });

     test('every banned token is DERIVED from one list: each trips the fence '
         'in prose, and the brief names all seven', () {
       final rendered = buildSpecifyBrief(
         _specced(),
         testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
       ).render();
       for (final token in kSpecPlaceholderTokens) {
         final tripped = _specced().copyWith(
           design: '${_specced().design}\nThe loader handles $token.\n',
         );
         expect(
           specStructuralFindings(tripped).single,
           contains('placeholder:'),
           reason: '$token must trip the fence in prose',
         );
         expect(
           rendered,
           contains('`$token`'),
           reason: 'the brief must NAME $token — a token the fence bans and '
               'the brief omits is a silent F',
         );
       }
     });
   });
   ```

   And append this test to `test/specify_stage_test.dart`, inside the existing
   `group('buildSpecifyBrief — the spec contract', …)` (after the working-agreement
   test, before the group's closing `});` at line 184):

   ```dart
   test('renders the DETERMINISTIC structural contract + the round-tripped '
       'exemplar, so the gate\'s rules and the architect\'s brief are one '
       'string (`pow-77g`)', () {
     expect(rendered, contains(kSpecStructuralContract));
     expect(rendered, contains(kSpecExemplarDesign));
     expect(rendered, contains('DETERMINISTIC'));
     // Both accepted ordinal shapes are NAMED — the format-only F this bead
     // closes was an agent writing the heading form the brief never mentioned.
     expect(rendered, contains('1. …'));
     expect(rendered, contains('### Step 1 — …'));
   });
   ```

   Test: `cd packages/grid_assets && dart pub get && dart analyze && dart test` →
   expect `No issues found!` then `All tests passed!`.
   Commit: `test(grid_assets): fence the brief ↔ gate round trip, both ordinal shapes, and the gaps that must still bite (pow-77g)`

6. **Register the autonomous decisions.** Append amendment `A16` to
   `docs/adr/ADR-0000-ai-decision-register.md` (after `A15`, at the end of the
   file), following the file's exact `## A<n> (date) — bead: <headline>` +
   `**Decision:**` / `**Why:**` / `**Affects (if promoted):**` / `**Status:**
   pending.` shape. It registers four calls: (1) the structural contract becomes
   ONE exported string (`kSpecStructuralContract`) rendered verbatim into the
   specify brief, with a shipped exemplar round-tripped through
   `specStructuralFindings` in test — a gate whose contract the brief does not
   state is a trap; (2) the gate recognizes ordinal HEADINGS as numbered steps —
   the bead's fix (b) taken only as far as its tight-contract caveat allows, since
   the ordinal stays mandatory and a bulleted plan still F's; (3) the numbered-step
   check is SCOPED to the `## Implementation Plan` section body and section lookup
   moves to `_proseOnly` output, extending A13(10)'s prose-not-quotation principle
   from the placeholder fence to the structure check and closing a false negative
   (a step-less plan passed whenever any `1.` appeared elsewhere in the design);
   (4) `_placeholderPatterns` is derived from the exported
   `kSpecPlaceholderTokens`, so the banned list and the stated list cannot drift.
   Note that A13(2)'s posture is preserved exactly — the lane stays a deterministic
   `ServiceCapability`, still names every missing element (guards LOUD), and a
   structural F is still the hard block A14(3) leaves to a human.

   Test: `cd packages/grid_assets && dart test` → expect `All tests passed!` (the
   register is prose; no test reads it).
   Commit: `docs(adr): A16 — the spec structural contract is ONE string the brief renders and the gate enforces (pow-77g)`

## Touches

**Files:**
- `packages/grid_assets/lib/src/code/specify.dart` — modified (steps 1-3).
- `packages/grid_assets/extension/rubrics/spec-validation.md` — modified (step 4).
- `packages/grid_assets/test/spec_committee_test.dart` — modified (step 5).
- `packages/grid_assets/test/specify_stage_test.dart` — modified (step 5).
- `docs/adr/ADR-0000-ai-decision-register.md` — modified (step 6).

**Public symbols added** (all reach the pack's API through the existing
`export 'src/code/specify.dart';` in `lib/grid_assets.dart` — no export edit):
- `lib/src/code/specify.dart:kSpecPlaceholderTokens` — the seven banned tokens.
- `lib/src/code/specify.dart:kSpecExemplarAcceptance` — the exemplar's acceptance.
- `lib/src/code/specify.dart:kSpecExemplarDesign` — the exemplar's design.
- `lib/src/code/specify.dart:kSpecStructuralContract` — the contract the brief renders.

**Public symbols changed:** none. `specStructuralFindings`, `buildSpecifyBrief`,
`SpecValidationCapability`, `kSpecGatingRubric` keep their signatures; only the
numbered-step finding's message text changes (it still contains
`has no numbered steps`, which is what `spec_committee_test.dart:274` asserts).

**Private symbols added:** `_numberedStep`, `_bannedTokenLine`.

Re-validated against the live tree: greps for the four new public symbols and for
`_numberedStep` / `_bannedTokenLine` return zero hits (no collision); the only
callers of `specStructuralFindings` are `SpecValidationCapability.run`
(`specify.dart:686`) and `spec_committee_test.dart` (7 call sites, all migrated or
unaffected by step 5); `buildSpecifyBrief`'s callers are `SpecifyCapability.spawn`
(`specify.dart:256`), `specify_stage_test.dart`, and
`track_e_reference_inflation_test.dart:232` (which asserts no bead-stamped path
reaches the brief — the contract interpolates only compile-time constants, so it
holds); `_placeholderPatterns` / `_proseOnly` / `_sectionBody` are private to
`specify.dart` with no other reader. `bd dep list pow-77g` → no dependencies, so
there is no sibling Touches to cross-check. The acceptance suite's real-kernel
structural gate grades a spec-LESS `bead('tg-1')` (no design at all), so it is
unaffected by every change here.

## ADR Alignment

Verified via `ls docs/adr/` (one file: `ADR-0000-ai-decision-register.md`) and
`grep -li "spec-validation\|structural\|specify\|numbered\|brief" docs/adr/*.md`
(one hit: the same file). ADR-0008/ADR-0011 are cited by this repo's `CLAUDE.md`
but live in the sibling `the_grid` register; the D-H clause below is quoted from
`CLAUDE.md` itself.

- `docs/adr/ADR-0000-ai-decision-register.md` A13(2) — "the gating
  `spec-validation` lane is a deterministic `ServiceCapability` … not an LLM
  critic … a spec-less / placeholder / section-less bead grades F with every
  missing element NAMED (guards LOUD)." The plan preserves this posture exactly:
  the lane stays deterministic and model-free, still returns
  `{'grade','transport':'structural','rationale'}`, and step 2's new finding NAMES
  the two shapes it wanted. What changes is WHICH structures count as whole, not
  who decides.
- `docs/adr/ADR-0000-ai-decision-register.md` A13(10) — "the placeholder fence
  reads PROSE, not QUOTATION — `specStructuralFindings` strips the spec's markdown
  quotation contexts … before matching the banned tokens: a spec that QUOTES a
  token as evidence … is pointing at work, not deferring it." Step 2 extends that
  same principle, and the same `_proseOnly` helper, to the STRUCTURE check: a
  heading or ordinal quoted inside a fence is evidence, not structure. This is the
  completion of A13(10), not a departure — and it is load-bearing for this pack,
  whose own specs quote all four headings verbatim.
- `docs/adr/ADR-0000-ai-decision-register.md` A13(6) — "The specify brief also
  sets the bead's `validation_plan` metadata … The stage is READ-ONLY on the tree."
  The brief is where the spec's contract is stated, so step 3 extends exactly this
  surface; `validation_plan` and the read-only posture are untouched.
- `docs/adr/ADR-0000-ai-decision-register.md` A14(3) — "The deterministic
  `spec-validation` F (A13(2)) stays a hard block to a human, unchanged." The plan
  does not touch `decideSpecRoute` or `SpecRouteCapability`: a structural F still
  escalates rather than auto-respecs. It removes the manufactured F's, so the
  escalation arm fires only on real ones.
- `docs/adr/ADR-0000-ai-decision-register.md` A15(1) — "`specify` is FOLDED into
  `kSpecReviewCircuit` as the head step." The plan changes the brief's CONTENT, not
  the circuit: `kSpecReviewCircuit`, `kSpecifyStep`, and every node path stay
  byte-identical.
- `CLAUDE.md` (the D-H genesis_tree doctrine, ADR-0008) — "**Guards LOUD or
  GONE** — a guard exists only if it protects a NAMED invariant and is loud
  (throws/refuses) when violated." This bead is that clause applied to the gate
  itself: the numbered-step guard was loud but its invariant was never NAMED to
  the agent it judged. Step 3 names it (in the brief the agent reads), step 2
  makes the guard bite the real invariant (steps are ordered and addressable)
  rather than a markdown dialect, and step 5's three negative fences prove it is
  still loud. The other D-H clauses do not bind: the plan adds no tree state, no
  `StateNotifier`, and no new ambient read — `SpecValidationCapability.run` keeps
  its existing `getInheritedSeedOfExactType<Bead>()`, the correct non-binding
  EFFECT verb at a capability's `run` edge (ADR-0008 D3).

## Validation Plan

- [ ] A plan whose steps are ordinal HEADINGS grades A → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name "an ORDINAL-HEADING plan grades A"` → `All tests passed!`
- [ ] Round-trip: the exemplar the brief ships passes the gate → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name "the exemplar the brief SHIPS passes the gate"` → `All tests passed!`
- [ ] The brief renders the contract, both ordinal shapes, and all seven tokens → `cd packages/grid_assets && dart test test/specify_stage_test.dart` → `All tests passed!`
- [ ] The gate still bites real gaps (bulleted / step-less / ordinal-elsewhere) → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name "the brief ↔ gate ROUND TRIP"` → `All tests passed!`
- [ ] A heading quoted inside a fenced block is not a section → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name "a heading quoted inside a fenced block is evidence, not a section"` → `All tests passed!`
- [ ] Every banned token is derived from one list and trips the fence in prose → `cd packages/grid_assets && dart test test/spec_committee_test.dart --plain-name "every banned token is DERIVED from one list"` → `All tests passed!`
- [ ] The rubric doc states the enforced contract and stays residue-clean → `cd packages/grid_assets && dart test test/spec_rubric_pack_test.dart` → `All tests passed!`
- [ ] The pack stays green end to end → `cd packages/grid_assets && dart pub get && dart analyze && dart test` → `No issues found!` then `All tests passed!`