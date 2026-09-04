## Implementation Plan

The whole change is two files: one test file loses a guard and gains a corrected
header, and one decision entry records why. No `lib/` file, no overlay content,
no mapping, no CHANGELOG.

### Step 1 — Rewrite the header of `overlay_codex_leg_test.dart`

In `packages/grid_assets/test/assets/overlay_codex_leg_test.dart`, replace lines
6-10 — the paragraph that states the retired rule — leaving lines 1-5 and the
`// Offline only` line exactly as they are.

DELETE exactly this block:

```dart
// The SKILL.md + frontmatter format is shared by every harness the station
// arms — only the root dir differs — so the codex leg is a COPY of the claude
// leg, never a translation. Nothing enforces that at runtime: this file is the
// enforcement. A drifted copy is the one failure mode the copy-based design
// admits, so it is pinned byte-for-byte here.
```

WRITE exactly this block in its place:

```dart
// The agents leg is an INDEPENDENT instruction source for the codex-style
// harnesses the station arms. It started life as a copy of the claude leg and
// MAY diverge from it: a harness may carry its own instructions (Nico,
// 2026-09-03), so a difference between the two legs is a harness-specific
// instruction, not drift. Identical content is permitted, never required —
// nothing here reads a SKILL.md's bytes.
//
// What this file DOES pin is STRUCTURE, which is harness-independent: both
// legs vend the same skill IDS (a skill present for one harness and absent
// for the other is a vending gap, not an instruction difference), the leg
// carries SKILL.md files and nothing else, and no copilot leg exists.
```

The result — the file's first 17 lines — reads:

```dart
// The CODEX leg of the vended overlay:
// `extension/station_overlay/agents/skills/<id>/SKILL.md`, mapped to
// `.agents/skills/<id>/SKILL.md` at install by the `agents -> .agents` head
// already in `kDefaultStationOverlayMappings`.
//
// The agents leg is an INDEPENDENT instruction source for the codex-style
// harnesses the station arms. It started life as a copy of the claude leg and
// MAY diverge from it: a harness may carry its own instructions (Nico,
// 2026-09-03), so a difference between the two legs is a harness-specific
// instruction, not drift. Identical content is permitted, never required —
// nothing here reads a SKILL.md's bytes.
//
// What this file DOES pin is STRUCTURE, which is harness-independent: both
// legs vend the same skill IDS (a skill present for one harness and absent
// for the other is a vending gap, not an instruction difference), the leg
// carries SKILL.md files and nothing else, and no copilot leg exists.
//
// Offline only — reads the bundled `extension/` files.
```

Test: `cd packages/grid_assets && dart analyze test/assets/overlay_codex_leg_test.dart`
→ expect `No issues found!` (the header is a comment; this only proves nothing
was broken while editing).
Commit (shared with Step 2): `test(overlay): retire the byte-identical twin pin on the codex leg (pow-emxf)`

### Step 2 — Delete the byte-identity test

In the same file, `packages/grid_assets/test/assets/overlay_codex_leg_test.dart`,
DELETE exactly this whole `test(...)` call plus the blank line that follows it
(currently lines 63-77):

```dart
  test('every agents-leg SKILL.md is BYTE-IDENTICAL to its claude twin — the '
      'format is shared across harnesses, so a divergent copy is drift, never '
      'a translation', () {
    for (final id in kVendedSkills) {
      final claude = File(p.join(claudeSkills, id, 'SKILL.md'));
      final agents = File(p.join(agentsSkills, id, 'SKILL.md'));
      expect(agents.existsSync(), isTrue, reason: '$id is vended for codex');
      expect(
        agents.readAsBytesSync(),
        claude.readAsBytesSync(),
        reason: '$id drifted from the claude leg',
      );
    }
  });
```

Delete NOTHING else. In particular:

- `final claudeSkills = p.join(overlay, 'claude', 'skills');` STAYS — the
  surviving id-parity test reads it (`expect(skillIdsIn(agentsSkills),
  skillIdsIn(claudeSkills))`), so the local is still used and `dart analyze`
  stays clean.
- The `skillIdsIn` helper, the `_extensionDir()` walk, and the three surviving
  tests keep their current bodies and their current names verbatim:
  `'the agents leg vends EXACTLY the claude leg skill ids'`,
  `'the agents leg carries SKILL.md files and nothing else — no operator seat asset, no loose file'`,
  and the `'no copilot leg is authored and no AGENTS.md is vended — …'` test.
- The `import 'dart:io';` STAYS: the surviving tests construct `Directory` and
  `File`.
- `kVendedSkills` STAYS imported and used by the two surviving tests.

Judgment call made here, so the builder makes none: the SET check stays (the
bead's design §2 keeps it, and a missing skill is a vending gap rather than a
harness-specific instruction); only the CONTENT pin goes. This is the
`CLAUDE.md` **Guards LOUD or GONE** clause applied in the GONE direction — the
guard was loud, but the invariant it named ("a divergent copy is drift") was
retired by Nico on 2026-09-03, so the guard goes with it rather than being
softened into a warning.

Test: `cd packages/grid_assets && dart test test/assets/overlay_codex_leg_test.dart`
→ expect `+3: All tests passed!` (three tests, down from four).
Divergence proof — run this exact line and expect `All tests passed!`, and
expect the working tree clean afterwards:

```sh
cd packages/grid_assets && \
  printf '\n<!-- divergence probe (pow-emxf) -->\n' \
    >> extension/station_overlay/agents/skills/discover/SKILL.md && \
  dart test test/assets/overlay_codex_leg_test.dart; \
  git checkout -- extension/station_overlay/agents/skills/discover/SKILL.md
```

Commit (with Step 1): `test(overlay): retire the byte-identical twin pin on the codex leg (pow-emxf)`

### Step 3 — Record the reversal as a new decision entry

Create `docs/decisions/2026-09-03-a-harness-may-carry-its-own-instructions.md`
with EXACTLY this content. The slug is `a-harness-may-carry-its-own-instructions`
(40 characters, within the 60-character budget). Do NOT edit
`docs/decisions/2026-09-02-the-worktree-overlay-scope-widens-to-every-skill-tree.md`
— including its `updated-by` list; the ratified entry stays byte-for-byte as it
landed, and this entry's `updates` edge is the only link written.

```markdown
---
status: accepted
date: 2026-09-03
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: a-harness-may-carry-its-own-instructions
  surfaces:
    - "packages/grid_assets/test/assets/overlay_codex_leg_test.dart"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - the-worktree-overlay-scope-widens-to-every-skill-tree
  obsoleted-by: null
  updated-by: []
  bead: pow-emxf
  legacy-id: null
---

# A harness may carry its own instructions — the per-harness overlay legs are independent instruction sources

## Context and Problem Statement

`power_station#the-worktree-overlay-scope-widens-to-every-skill-tree`
(bead `pow-99g`, PR #176) vended the codex leg of the station overlay and
recorded: "The codex leg is authored as a byte-identical COPY of the claude leg
under `extension/station_overlay/agents/skills/`, pinned by test rather than by
a mechanism". It named the cost in the same breath — "every skill edit must
land twice; the byte-identity test is what makes that loud instead of silent" —
and the cost arrived on the first collision. `pow-vwny` (PR #177) edited two
claude skills (`discover`, `intake-refinement`); the moment #176 landed ahead of
it, the merge-group run for #177 failed the twin test, the queue ejected the PR,
and the governor had to hand-copy the edited skills over their twins to
re-queue. Worse than the tax: under the pin a genuinely harness-specific
instruction — a codex-only note, a claude-only tool hint — is unrepresentable.

## Decision Outcome

Per Nico, 2026-09-03: "That is overbearing. Different harnesses can have
different instructions." Each per-harness leg of `station_overlay`
(`claude/skills`, `agents/skills`) is an INDEPENDENT instruction source.
Identical content between legs is PERMITTED and remains the common case — the
SKILL.md + frontmatter format really is shared — but it is never REQUIRED, and
nothing tests for it. `packages/grid_assets/test/assets/overlay_codex_leg_test.dart`
loses its `'every agents-leg SKILL.md is BYTE-IDENTICAL to its claude twin'`
test.

What the leg still owes is STRUCTURE, and those checks are untouched: both legs
vend exactly the `kVendedSkills` id set (a skill present for one harness and
absent for the other is a vending GAP, which is a defect in the vending rather
than an instruction difference), the agents leg carries SKILL.md files and
nothing else, and no copilot leg is authored.

This entry UPDATES the pow-99g entry on exactly one clause — the byte-identical
copy rule and the test that pinned it. Everything else pow-99g recorded stands
verbatim: the worktree overlay scope is still the SET of per-harness SKILL
trees, the per-asset-dir `.gitignore` fence still derives from that scope, the
materializer still gains no placement branching (A26's path-preserving
invariant is untouched), and no loose root file is vended. The ratified entry is
not edited.

### Consequences

* Good, because a skill edit lands on the leg it belongs to and no longer has
  to be mirrored to keep CI green; the #177 ejection class of failure is gone.
* Good, because a harness-specific instruction is now expressible at all, which
  is what a per-harness leg is for.
* Neutral, because the legs are byte-identical today and stay so until someone
  has a reason to diverge; nothing is copied, moved, or rewritten by this
  decision.
* Bad, because a copy-paste MISTAKE on one leg is no longer caught by a test —
  an unintended divergence now reads the same as an intended one. Accepted:
  under the pin the same mistake was caught only by making every deliberate
  edit expensive, and Nico ruled that trade overbearing. The id-set and
  SKILL.md-only checks still catch the failure mode that is unambiguously a
  defect — a skill missing from a harness.

### Confirmation

`cd packages/grid_assets && dart test test/assets/overlay_codex_leg_test.dart`
— three structural tests pass, and appending a line to one leg's SKILL.md
leaves them passing.
```

Test: `cd packages/grid_assets && dart test test/decision_register_test.dart`
→ expect `All tests passed!` (the register lens enumerates `docs/decisions/`
Markdown entries; a malformed new file would surface here).
Commit: `docs(decisions): a harness may carry its own instructions (pow-emxf)`

### Step 4 — Run the house gate

```sh
cd packages/grid_assets && dart analyze && dart test
```

→ expect `No issues found!` from `dart analyze` and `All tests passed!` from
`dart test`, exit code 0. Do NOT run `dart format` (the local toolchain is
3.12 against a `^3.11` house set and reflows unrelated files).

Then confirm the change is exactly two files:

```sh
git diff --name-only main...HEAD
```

→ expect exactly:

```
docs/decisions/2026-09-03-a-harness-may-carry-its-own-instructions.md
packages/grid_assets/test/assets/overlay_codex_leg_test.dart
```

No CHANGELOG edit: in this repo `packages/grid_assets/CHANGELOG.md` is written
at RELEASE time by the vended `release` skill (its step 4, "CHANGELOG entry +
version bump, committed"), and every commit touching that file is a
`chore(release):` train — `pow-99g` itself added no line. The one-line note the
bead names ("the codex leg is no longer pinned byte-identical to the claude
leg") therefore rides the commit subject and this decision entry, and the
release skill folds it into the next rc entry. This is a decision, not an
omission: adding a per-bead `## Unreleased` heading would mint a section shape
the release skill does not consume.

## Touches

- `packages/grid_assets/test/assets/overlay_codex_leg_test.dart` — modified;
  header comment rewritten (Step 1) and the test
  `'every agents-leg SKILL.md is BYTE-IDENTICAL to its claude twin …'` deleted
  (Step 2). No public symbol added, removed, or renamed — this is a test file
  and exports nothing.
- `docs/decisions/2026-09-03-a-harness-may-carry-its-own-instructions.md` —
  created (Step 3); a decision entry, no Dart symbol.

Symbols READ but not modified (no signature change, no new definition):
`kVendedSkills` (`packages/grid_assets/lib/src/assets/asset_loader.dart:47`) and
`kDefaultStationOverlayMappings`
(`packages/grid_assets/lib/src/assets/overlay_manifest.dart`) — both stay
exactly as they are; the test file's local `skillIdsIn` helper is likewise
unchanged.

Re-validated against the live tree: `grep -rn "BYTE-IDENTICAL\|readAsBytesSync" . --include='*.dart'` finds the assertion ONLY in `packages/grid_assets/test/assets/overlay_codex_leg_test.dart` (no other suite re-asserts twin equality); `grep -rn "kVendedSkills\|kDefaultStationOverlayMappings" . --include='*.dart'` shows every other caller reads them for id/mapping enumeration, not for byte comparison, so deleting the assertion migrates no caller; `overlay_golden_test.dart` asserts the `.agents/skills/**` PATH set (`kWorktreeOverlayGolden`) plus PER-FILE properties of each materialized SKILL.md (frontmatter-led, no `{{` residue, provenance-stamped, `name` matching its dir) and never compares one leg to the other, so it is unaffected by this deletion and keeps binding on both legs after a divergence; the byte-identity rule is written down in exactly two places — this test file and the pow-99g decision entry — and the entry is superseded by a new file rather than edited; `bd dep list pow-emxf` reports no dependencies and `bd search overlay` returns only two deferred, non-colliding beads (`pow-mta`, `pow-sef`), so there is no sibling to carve scope from; baseline `dart test test/assets/overlay_codex_leg_test.dart` on this worktree is `+4: All tests passed!`, and `git log main..HEAD` is empty, so the two-file diff assertion in Step 4 is exact.

## ADR Alignment

Verified via grep on `overlay`, `byte-identical`, `codex`, `harness`,
`skill tree`, `guard` over both registers with
`for register in docs/adr docs/decisions; do [ ! -d "$register" ] || find "$register" -type f -not -path '*/views/*' -name '*.md' -exec grep -li "…" {} +; done`.
Three recorded decisions govern this surface; one is departed from, by name.

1. **`power_station#the-worktree-overlay-scope-widens-to-every-skill-tree`**
   (bead `pow-99g`, `status: accepted`) — **DEPARTED FROM, on one clause, and
   the departure is RECORDED.** The load-bearing clause: "The codex leg is
   authored as a byte-identical COPY of the claude leg under
   `extension/station_overlay/agents/skills/`, pinned by test rather than by a
   mechanism", with the consequence "the byte-identity test is what makes that
   loud instead of silent." This plan RETIRES that clause on Nico's 2026-09-03
   ruling ("Different harnesses can have different instructions"). Per the
   register's write rule, the reversal is recorded as a NEW `docs/decisions/`
   slug entry (Step 3) carrying `updates:` the pow-99g slug; the ratified entry
   itself is not edited, and `docs/adr/ADR-0000-ai-decision-register.md` is not
   appended to. Every OTHER clause of that entry — the per-harness subtree set,
   the derived `.gitignore` fence, "no loose file … is materialized into a
   worktree" — is preserved by this plan, which touches no `lib/` file.

2. **`docs/decisions/2026-07-14-a26-bead-pow-hhs-the-station-overlay-becomes-a-root-relative.md`**
   (A26, legacy amendment, accepted) — **ALIGNED, untouched.** A26 makes the
   overlay path-preserving and scopes the worktree leg to SKILL trees whose
   every path sits inside an `<id>/` asset dir. This plan changes no path, no
   mapping and no materializer branch — `kDefaultStationOverlayMappings`'
   `agents -> .agents` head is read-only here — so A26's invariant is neither
   extended nor weakened.

3. **`CLAUDE.md`'s D-H doctrine clause "Guards LOUD or GONE — a guard exists
   only if it protects a NAMED invariant and is loud (throws/refuses) when
   violated; delete a silent guard"** (the local restatement of the_grid
   ADR-0008; the same clause is quoted in
   `docs/decisions/2026-07-12-a19-bead-pow-77g-the-spec-s-structural-contract-becomes-one.md`).
   **APPLIED, in the GONE direction.** The byte-identity test was a loud guard
   over a named invariant ("a divergent copy is drift"); the invariant is
   retired, so the guard is DELETED outright rather than downgraded to a
   warning or a skipped test. The three guards whose invariants survive — id
   parity, SKILL.md-only, no copilot leg — stay loud and unchanged.

The org invariants hold: no "plugin" wording is introduced (the header says
"harness" and "extension" stays the seam word), no agent-noun is minted (no new
symbol at all), and every bead mutation for this work goes through the bd CLI.

## Validation Plan

- [ ] Editing ONE leg alone leaves the suite green → `cd packages/grid_assets && printf '\n<!-- divergence probe (pow-emxf) -->\n' >> extension/station_overlay/agents/skills/discover/SKILL.md && dart test test/assets/overlay_codex_leg_test.dart; git checkout -- extension/station_overlay/agents/skills/discover/SKILL.md` → `All tests passed!`, and `git status --porcelain` afterwards shows the SKILL.md unmodified
- [ ] No byte-equality assertion remains → `grep -n 'readAsBytesSync\|BYTE-IDENTICAL' packages/grid_assets/test/assets/overlay_codex_leg_test.dart` → no output, exit status 1
- [ ] The three structural checks survive unchanged → `cd packages/grid_assets && dart test test/assets/overlay_codex_leg_test.dart` → `+3: All tests passed!` with the three test names `the agents leg vends EXACTLY the claude leg skill ids`, `the agents leg carries SKILL.md files and nothing else …`, `no copilot leg is authored and no AGENTS.md is vended …`
- [ ] The header no longer calls the agents leg a must-not-drift copy → `grep -in 'is a COPY of the claude\|pinned byte-for-byte\|drifted copy' packages/grid_assets/test/assets/overlay_codex_leg_test.dart` → no output, exit status 1; and `grep -c 'INDEPENDENT instruction source' packages/grid_assets/test/assets/overlay_codex_leg_test.dart` → `1`
- [ ] The reversal is recorded with the right frontmatter and a ≤60-character slug → `grep -n 'status: accepted\|bead: pow-emxf\|slug: a-harness-may-carry-its-own-instructions\|the-worktree-overlay-scope-widens-to-every-skill-tree' docs/decisions/2026-09-03-a-harness-may-carry-its-own-instructions.md` → four matching lines; and `printf 'a-harness-may-carry-its-own-instructions' | wc -c` → `40`
- [ ] The ratified pow-99g entry is not edited → `git diff --name-only main...HEAD -- docs/decisions/2026-09-02-the-worktree-overlay-scope-widens-to-every-skill-tree.md` → no output
- [ ] Nothing else moves (no overlay content, installer, mapping or CHANGELOG edit) → `git diff --name-only main...HEAD` → exactly the two lines `docs/decisions/2026-09-03-a-harness-may-carry-its-own-instructions.md` and `packages/grid_assets/test/assets/overlay_codex_leg_test.dart`
- [ ] House gate green → `cd packages/grid_assets && dart analyze && dart test` → `No issues found!` then `All tests passed!`, exit code 0