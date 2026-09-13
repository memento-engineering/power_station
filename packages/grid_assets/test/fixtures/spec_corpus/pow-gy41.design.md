## Implementation Plan

### Step 1 — Bootstrap the worktree's pub linkage (idempotent; skip if already present)

The station provisions dev linkage at spawn time (A1), but a worktree cut without it
has no `pubspec_overrides.yaml` and no `.dart_tool/`. The checked-in shape uses
RELATIVE paths (`../the_grid/...`) which do not resolve from a `.grid/worktrees/`
root, so the worktree needs ABSOLUTE ones. Run this from the worktree root; if
`pubspec_overrides.yaml` already exists, this step is a no-op and you skip straight
to `dart pub get`:

```sh
test -f pubspec_overrides.yaml || cat > pubspec_overrides.yaml <<'YAML'
# Dev-time linkage (machine-local; gitignored) — absolute paths, because a
# `.grid/worktrees/` root cannot reach `../the_grid`.
dependency_overrides:
  beads_dart:
    path: /Users/nico/development/engineering.memento/the_grid/packages/beads_dart
  grid_cli:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_cli
  grid_diagnostics_contract:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_diagnostics_contract
  grid_engine:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_engine
  grid_exploration:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_exploration
  grid_runtime:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_runtime
  grid_sdk:
    path: /Users/nico/development/engineering.memento/the_grid/packages/grid_sdk
YAML
dart pub get
```

`pubspec_overrides.yaml` is line 11 of `.gitignore`, so it never enters the diff.

Test: `cd packages/grid_assets && dart test test/landing_circuit_test.dart` → expect
`All tests passed!` (the suite is green BEFORE any edit; this proves the seat works).
Commit: none — this step writes only a gitignored file.

### Step 2 — Add the pub-advice filter and the tail budget beside `landReasonTail`

In `packages/grid_assets/lib/src/code/landing.dart`, INSERT the following
immediately after the existing `landReasonTail` function (which ends at line 388,
just before the `_validationPlan` doc comment). `landReasonTail` itself is
UNCHANGED — this step only adds its two new neighbours:

```dart
/// The tail budget for the captured Validation-Plan log a revalidate
/// [Escalate] carries (bead `pow-gy41`). Wide enough to hold a whole
/// `dart test` failure block — the failing test's name, its expected/actual,
/// and the `Some tests failed.` trailer — and well inside the gate bead's
/// metadata budget.
const int kRevalidateReasonTailChars = 1500;

/// One `dart pub get` line of pure UPGRADE ADVICE — `analyzer 10.2.0 (14.3.0
/// available)`. Anchored at both ends: a line that merely MENTIONS an
/// available version mid-sentence is not advice and survives.
final RegExp _pubVersionAdvice = RegExp(
  r'^\s*[a-z_][a-z0-9_]*\s+\S+\s+\(\S+\s+available\)\s*$',
);

/// The two trailers pub prints after that block — the `N packages have newer
/// versions incompatible with dependency constraints.` count and the
/// ``Try `dart pub outdated` for more information.`` nudge.
final RegExp _pubOutdatedSummary = RegExp(
  r'^\s*(\d+\s+packages?\s+(have|has)\s+newer\s+versions\s+incompatible\s+'
  r'with\s+dependency\s+constraints\.'
  r'|Try\s+`(dart|flutter)\s+pub\s+outdated`.*)\s*$',
);

/// [output] with pub's upgrade-ADVICE lines dropped (bead `pow-gy41`).
///
/// A Dart Validation Plan opens with `dart pub get`, and on a seat with an
/// outdated lockfile its advisory block runs past 2000 characters on its own —
/// burying the fatal line, which comes LAST. This is never the failure, so it
/// is never the diagnosis.
///
/// Pure and line-wise: every line that is not advice is returned
/// BYTE-IDENTICAL, in order; advice-free input is returned unchanged. Applied
/// BEFORE [landReasonTail] so the tail budget is spent on signal.
String planOutputWithoutPubAdvice(String output) => output
    .split('\n')
    .where(
      (line) =>
          !_pubVersionAdvice.hasMatch(line) &&
          !_pubOutdatedSummary.hasMatch(line),
    )
    .join('\n');
```

Both symbols reach consumers through the existing barrel line
`export 'src/code/landing.dart';` (`packages/grid_assets/lib/grid_assets.dart:171`)
— no barrel edit.

Test: `cd packages/grid_assets && dart analyze` → expect `No issues found!`.
Commit: `feat(landing): strip pub upgrade advice from captured plan output (pow-gy41)`

### Step 3 — Rebuild `RevalidateCapability`'s Escalate reason; delete `_truncate`

In `packages/grid_assets/lib/src/code/landing.dart`, REPLACE lines 232-234 —
exactly this text:

```dart
    final diagnostic = pathCheckDiagnostic(plan, result.exitCode);
    final suffix = diagnostic == null ? '' : '; $diagnostic';
    return Escalate('revalidate failed: ${_truncate(result.output)}$suffix');
```

with:

```dart
    final diagnostic = pathCheckDiagnostic(plan, result.exitCode);
    final suffix = diagnostic == null ? '' : '; $diagnostic';
    // The exit code LEADS (the class of failure), then the PATH diagnostic,
    // then the log — advice-stripped and TAIL-cut, because the fatal line is
    // LAST and the old head truncation cut exactly it (bead `pow-gy41`).
    final log = landReasonTail(
      planOutputWithoutPubAdvice(result.output),
      kRevalidateReasonTailChars,
    );
    return Escalate('revalidate failed (exit ${result.exitCode})$suffix: $log');
```

Then DELETE the now-callerless `_truncate` — the whole block at lines 401-408 of the
pre-edit file, doc comment included:

```dart
/// Caps captured process output embedded in an [Escalate] reason — a runaway
/// Validation Plan log must not blow up a gate bead's metadata.
String _truncate(String s, [int max = 2000]) {
  final trimmed = s.trim();
  return trimmed.length <= max
      ? trimmed
      : '${trimmed.substring(0, max)}\n… (truncated)';
}
```

`grep -rn "_truncate" packages/grid_assets/lib/src/code/landing.dart` returned only
its definition and the single call site being replaced, so deleting it is mandatory,
not optional: left in place `dart analyze` reports `unused_element`. The identically
named private helpers in `pr_composition.dart:653` and
`conventional_commit.dart:239` are DIFFERENT functions in different libraries and
are left alone.

Test: `cd packages/grid_assets && dart analyze` → expect `No issues found!`.
Commit: `fix(landing): escalate revalidate with the exit code and the output TAIL (pow-gy41)`

### Step 4 — Migrate the two existing revalidate reason assertions

The reason shape changed, so two assertions in
`packages/grid_assets/test/landing_circuit_test.dart` must move with it.

At line 277, replace:

```dart
      expect((outcome as Escalate).reason, 'revalidate failed: ');
```

with:

```dart
      expect((outcome as Escalate).reason, 'revalidate failed (exit 1): ');
```

At lines 293-297, replace:

```dart
      expect(
        (outcome as Escalate).reason,
        'revalidate failed: sh: rg: not found; '
        'exit 127 — candidate missing commands: rg',
      );
```

with:

```dart
      expect(
        (outcome as Escalate).reason,
        'revalidate failed (exit 127); '
        'exit 127 — candidate missing commands: rg: '
        'sh: rg: not found',
      );
```

The `pathCheckDiagnostic` suffix keeps its meaning and its position immediately after
the exit code; the log follows the colon. `pathCheckDiagnostic` itself is UNTOUCHED
(`packages/grid_assets/lib/src/agent/path_check.dart:52`), so its own suite
`test/agent/path_check_test.dart` and its second caller `committee.dart:1528` are
unaffected.

Test: `cd packages/grid_assets && dart test test/landing_circuit_test.dart` → expect
`All tests passed!`.
Commit: `test(landing): migrate the revalidate reason assertions to the exit-code shape (pow-gy41)`

### Step 5 — Add the three new tests

In `packages/grid_assets/test/landing_circuit_test.dart`, add these two top-level
fixtures immediately after the `_FixedShellRunner` class (which ends at line 82,
before `void main()`):

```dart
/// A `dart pub get` preamble on a seat with an outdated lockfile — the block
/// that buried the real failure in bead `pow-gy41`'s live receipt.
/// Deliberately longer than 3000 characters on its own.
String _pubAdviceBlock({int packages = 70}) {
  final buffer = StringBuffer()
    ..writeln('Resolving dependencies in `/w/tg-1`...')
    ..writeln('Downloading packages...');
  for (var i = 0; i < packages; i++) {
    buffer.writeln('  outdated_package_number_$i 1.0.$i (2.0.$i available)');
  }
  buffer
    ..writeln('Got 120 dependencies!')
    ..writeln(
      '$packages packages have newer versions incompatible with dependency '
      'constraints.',
    )
    ..writeln('Try `dart pub outdated` for more information.');
  return buffer.toString();
}

/// What `dart test` prints when it fails — the part an operator actually needs,
/// and the part the old HEAD truncation threw away.
const _dartTestFailure = '''
00:02 +512 -1: test/foo_test.dart: renders the widget [E]
  Expected: <42>
    Actual: <41>
  package:test_api                     expect
  test/foo_test.dart 88:7              main.<fn>

00:02 +512 -1: Some tests failed.''';
```

Then add these two tests INSIDE the existing `group('RevalidateCapability', ...)`,
after the `exit 127 retains output and appends candidate commands` test (which ends
at line 299, just before that group's closing `});`):

```dart
    test('the pub advisory block is stripped and the TAIL kept — the fatal '
        'line survives exactly where the old HEAD truncation cut it '
        '(pow-gy41)', () async {
      final noise = _pubAdviceBlock();
      expect(noise.length, greaterThan(3000), reason: 'the receipt shape');
      final runner = _FixedShellRunner(
        ShellRunResult(exitCode: 1, output: '$noise$_dartTestFailure'),
      );
      final richBead = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'dart pub get && dart test'},
      );
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      final reason = (outcome as Escalate).reason;
      expect(reason, startsWith('revalidate failed (exit 1): '));
      expect(reason, contains('test/foo_test.dart: renders the widget [E]'));
      expect(reason, contains('Some tests failed.'));
      expect(reason, isNot(contains(' available)')));
      expect(reason, isNot(contains('… (truncated)')));
      expect(reason.length, lessThanOrEqualTo(1600));
    });

    test('output still over the tail budget after stripping is cut at the '
        'START — landReasonTail\'s leading …, never the head (pow-gy41)',
        () async {
      final long = '${'noise line\n' * 400}FATAL: the real error';
      final runner = _FixedShellRunner(
        ShellRunResult(exitCode: 2, output: long),
      );
      final richBead = bead(
        'tg-1',
      ).copyWith(metadata: const {'validation_plan': 'dart test'});
      final c = _capCtx(delivery: _FakeDelivery(), beadOverride: richBead);
      final outcome = await RevalidateCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      final reason = (outcome as Escalate).reason;
      expect(reason, startsWith('revalidate failed (exit 2): …'));
      expect(reason, endsWith('FATAL: the real error'));
      expect(
        reason.length,
        kRevalidateReasonTailChars + 29,
        reason: 'the 28-char prefix + the … cut marker + the last 1500 chars',
      );
    });
```

Finally add this NEW top-level group immediately after the closing `});` of
`group('rework-aware delivery helpers (tg-w3c)', ...)` (the group that ends at line
389, just before `main`'s closing brace):

```dart
  group('planOutputWithoutPubAdvice (pow-gy41)', () {
    test('drops pub\'s version-advice lines and both of its trailers', () {
      const input =
          'Resolving dependencies in `/w/tg-1`...\n'
          'Downloading packages...\n'
          '  _fe_analyzer_shared 96.0.0 (107.0.0 available)\n'
          '  analyzer 10.2.0 (14.3.0 available)\n'
          'Got 120 dependencies!\n'
          '44 packages have newer versions incompatible with dependency '
          'constraints.\n'
          'Try `dart pub outdated` for more information.\n'
          'Some tests failed.';
      expect(
        planOutputWithoutPubAdvice(input),
        'Resolving dependencies in `/w/tg-1`...\n'
        'Downloading packages...\n'
        'Got 120 dependencies!\n'
        'Some tests failed.',
      );
    });

    test('leaves every non-advisory line BYTE-IDENTICAL — a lookalike that '
        'merely CONTAINS " available)" mid-line survives whole', () {
      const input =
          'Expected: <42>\n'
          '  analyzer 10.2.0 (14.3.0 available) — cited inside a failure\n'
          '\n'
          '  test/foo_test.dart 88:7  main.<fn>\n'
          'Some tests failed.';
      expect(planOutputWithoutPubAdvice(input), input);
    });

    test('empty output stays empty', () {
      expect(planOutputWithoutPubAdvice(''), '');
    });
  });
```

Every number above was executed against a standalone Dart harness before this spec
was written: the block is 4025 chars, the assembled reason is 334 chars and carries
both the failing test line and `Some tests failed.`, and the over-budget reason is
exactly 1529 chars (`28 + 1 + 1500`).

Test: `cd packages/grid_assets && dart test test/landing_circuit_test.dart` → expect
`All tests passed!`.
Commit: `test(landing): pin the advice-stripped, tail-cut revalidate reason (pow-gy41)`

### Step 6 — Record the decision

Create `docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md`
with exactly this content:

```markdown
---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: captured-process-output-escalates-tail-first
  surfaces:
    - "packages/grid_assets/lib/src/code/landing.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-gy41
  legacy-id: null
---
## Captured process output escalates TAIL-first, advice-stripped, exit-code-led (2026-09-02) — bead `pow-gy41`

**Decision (AI; MECHANISM only).** Every `Escalate` reason in the landing
circuit that embeds CAPTURED PROCESS OUTPUT is assembled the same way:
`'<verb> failed (exit N)<diagnostic-suffix>: <tail>'`, where the tail is
`landReasonTail(planOutputWithoutPubAdvice(output), kRevalidateReasonTailChars)`.
`RevalidateCapability.route` is the first caller;
`packages/grid_assets/lib/src/code/landing.dart`'s private `_truncate`, which
kept the HEAD of the output at a 2000-char cap, is DELETED with its only caller.

**Why the tail, not the head.** `landReasonTail`'s own doc comment already
stated the rule for git/gh output — "the useful line is at the END … taking the
tail keeps the diagnosis, not the noise" — and a Validation Plan's output has
the same shape: `dart pub get`'s advisory block first, the fatal line last. The
live receipt on gate `tranquility-ajfh6r` (node `tg-lohr/land/revalidate`)
carried 2000 characters of `(<version> available)` lines and nothing else, so
the governor had to re-run the plan blind. The rule was already owned; it was
simply not applied to plan output.

**Why strip advice as well as cutting.** A tail alone would spend its budget on
advisory lines when the failure is short. `planOutputWithoutPubAdvice` is a pure,
line-wise filter over two anchored shapes — `<pkg> <ver> (<ver> available)` and
pub's two `outdated` trailers — and is byte-identical on everything else, so it
can never eat a diagnosis. It is public so delivery can reuse it.

**Why the exit code LEADS.** An operator reads the CLASS of failure before the
log; `pathCheckDiagnostic`'s suffix (which only fires on exit 127) keeps its
meaning and sits immediately after the code, before the log.

**Affects:** `packages/grid_assets/lib/src/code/landing.dart`
(`planOutputWithoutPubAdvice`, `kRevalidateReasonTailChars`,
`RevalidateCapability.route`; `_truncate` deleted),
`packages/grid_assets/test/landing_circuit_test.dart`.
```

Test: `test -f docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md && grep -q 'slug: captured-process-output-escalates-tail-first' docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md && echo RECORDED` → expect `RECORDED`.
Commit: `docs(decisions): record the tail-first captured-output escalation shape (pow-gy41)`

### Step 7 — Run the house gate

```sh
cd packages/grid_assets && dart analyze && dart test
```

Expect `No issues found!` followed by `All tests passed!`. Do NOT run
`dart format` — this machine's Dart is 3.12 against the repo's 3.11 house set and
it reformats unrelated files.

Commit: none — Step 7 only verifies Steps 2-6.

## Touches

- `packages/grid_assets/lib/src/code/landing.dart` — modified. ADDS
  `lib/src/code/landing.dart:planOutputWithoutPubAdvice` and
  `lib/src/code/landing.dart:kRevalidateReasonTailChars` (both public, exported by
  the existing `packages/grid_assets/lib/grid_assets.dart:171` barrel line); adds
  private `_pubVersionAdvice` and `_pubOutdatedSummary`; rewrites the `Escalate`
  at line 234 inside `lib/src/code/landing.dart:RevalidateCapability`; DELETES
  private `_truncate`. `landReasonTail` and `_validationPlan` are unchanged.
- `packages/grid_assets/test/landing_circuit_test.dart` — modified. Adds fixtures
  `_pubAdviceBlock` / `_dartTestFailure`, two tests in the `RevalidateCapability`
  group, one new `planOutputWithoutPubAdvice` group; migrates two existing reason
  assertions (lines 277 and 293-297).
- `docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md` —
  created.
- `pubspec_overrides.yaml` — machine-local, gitignored (`.gitignore:11`); written
  only if absent. Never part of the diff.

NOT touched: `packages/grid_assets/lib/src/agent/path_check.dart`
(`pathCheckDiagnostic` keeps its exact signature and text, so its second caller
`packages/grid_assets/lib/src/code/committee.dart:1528` and its suite
`packages/grid_assets/test/agent/path_check_test.dart` are unaffected);
`packages/github_grid_assets/lib/src/code/github_pr_delivery.dart:80` and
`github_direct_merge_delivery.dart:67,92`, which call `landReasonTail` with its
DEFAULT 400-char budget — this bead adds a wider budget for plan output rather than
changing that default, so those three call sites see no behaviour change.

Re-validated against the live tree: `grep -rn "_truncate\|landReasonTail\|revalidate failed" --include='*.dart' packages/` confirms `_truncate` in `landing.dart` has exactly one caller (line 234, the one this plan replaces) and that the only assertions on the revalidate reason string are `landing_circuit_test.dart:277` and `:293-297`, both migrated in Step 4; `bd dep list pow-gy41` reports no dependencies and `bd search revalidate` returns only this bead, so there is no sibling to carve scope from and no shared symbol to coordinate.

## ADR Alignment

Verified via grep on `revalidate`, `landReasonTail`, `truncat`, `escalate`,
`failureReason` over both registers (`docs/adr/` and `docs/decisions/`, excluding
`views/`). Two recorded decisions are load-bearing here; both are ALIGNED WITH, and
neither is overridden.

1. `docs/decisions/2026-07-13-a25-bead-pow-wbe-the-root-circuit-grows-a-flat-deliver-termi.md`
   (`power_station#a25-bead-pow-wbe-the-root-circuit-grows-a-flat-deliver-termi`,
   `register.legacy-id: A25`), clause (1): "the `land` `SubCircuitStep` is demoted to
   a PREPARATION leg (`rebase → revalidate`) and KEEPS its step id, so the
   `<bead>/land/*` cursor keys and `buildCircuitReceipt`'s reads are untouched."
   ALIGNED: this plan changes only the TEXT of the reason string
   `RevalidateCapability.route` hands to `Escalate`. `kLandingCircuit`, both step
   ids, `terminalStepId`, the `Advance` payloads (`{'outcome': 'passed'}`) and
   `buildCircuitReceipt` are untouched, so no cursor key and no frozen circuit shape
   moves. The `kLandingCircuit shape` and `buildCircuitReceipt` test groups are
   expected to stay green unmodified.

2. The same entry, clause (3): "A route's failure channel is a THROWN
   `RouteFailure` … A bare `StateError` would stamp `Bad state:` into the FT-1
   `failureReason` an operator reads; `RouteFailure` carries the reason verbatim."
   ALIGNED and EXTENDED in spirit: the clause holds that the operator-facing reason
   text is a contract worth designing, not incidental. This bead keeps the channel
   exactly as it is — an `Escalate` for a non-zero plan, a thrown `RouteFailure`
   nowhere newly introduced — and only makes the reason carry the diagnosis instead
   of pub's noise.

A `docs/decisions/` entry is RECORDED for the decision this design MAKES (the
tail-first, advice-stripped, exit-code-led shape for captured process output) —
Step 6, slug `captured-process-output-escalates-tail-first`. Nothing is appended to
`docs/adr/ADR-0000-ai-decision-register.md`, which is read-only legacy.

Org invariants checked: the seam word "extension" does not appear in this change (no
seam is added); the new public symbols `planOutputWithoutPubAdvice` and
`kRevalidateReasonTailChars` name a craft/quantity, not an agent-noun; no `bd` SQL
and no `.beads/hooks/` write occurs anywhere on this path; no `print` is added to
`lib/`.

## Validation Plan

- [ ] A revalidate failure whose plan output is a 3000+ char pub advisory block followed by a `dart test` failure produces an `Escalate` reason containing the failing test line and `Some tests failed.` → `cd packages/grid_assets && dart test test/landing_circuit_test.dart --plain-name 'the pub advisory block is stripped and the TAIL kept'` → `All tests passed!`
- [ ] That same reason contains no ` available)` line, no `… (truncated)` marker, and is at most 1600 characters → `cd packages/grid_assets && dart test test/landing_circuit_test.dart --plain-name 'the pub advisory block is stripped and the TAIL kept'` → `All tests passed!` (the same test asserts all four; it fails if any holds)
- [ ] The reason begins `revalidate failed (exit 1): ` and `pathCheckDiagnostic`'s suffix still appears for the exit-127 failure → `cd packages/grid_assets && dart test test/landing_circuit_test.dart --plain-name 'RevalidateCapability'` → `All tests passed!` (the migrated line-277 and line-293 assertions are exact string equality on both shapes)
- [ ] Advice-stripped output still over the 1500-char budget is cut at the START, `kRevalidateReasonTailChars + 29` chars long → `cd packages/grid_assets && dart test test/landing_circuit_test.dart --plain-name 'output still over the tail budget'` → `All tests passed!`
- [ ] `planOutputWithoutPubAdvice` is unit-tested alone and byte-identical on non-advisory lines → `cd packages/grid_assets && dart test test/landing_circuit_test.dart --plain-name 'planOutputWithoutPubAdvice'` → `All tests passed!` (3 tests: strips both shapes, byte-identical lookalike, empty)
- [ ] `_truncate` is deleted from `landing.dart` → `grep -q '_truncate' packages/grid_assets/lib/src/code/landing.dart && echo STILL_THERE || echo ABSENT` → `ABSENT`
- [ ] The five existing landing-circuit revalidate/helper tests stay green → `cd packages/grid_assets && dart test test/landing_circuit_test.dart` → `All tests passed!` with no test skipped or deleted (`git diff --stat packages/grid_assets/test/landing_circuit_test.dart` shows insertions plus the 2 migrated assertions, no deleted `test(` call)
- [ ] The decision entry exists with its `register` block → `test -f docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md && grep -q 'slug: captured-process-output-escalates-tail-first' docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md && echo RECORDED` → `RECORDED`
- [ ] House gate green → `cd packages/grid_assets && dart analyze && dart test` → `No issues found!` then `All tests passed!`