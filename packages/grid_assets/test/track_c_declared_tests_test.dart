import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _tg1ni0Design = '''
Test: `dart test test/commands/rework_command_test.dart`
Create `test/commands/gate_command_test.dart`.
Modify `test/commands/link_command_test.dart`.
''';

const _tg1ni0Diff = '''
diff --git a/test/commands/bead_command_test.dart b/test/commands/bead_command_test.dart
--- a/test/commands/bead_command_test.dart
+++ b/test/commands/bead_command_test.dart
@@ -1 +1 @@
-old
+new
''';

/// A canned [GitRunner] whose `ls-tree` answers the PINNED BASE's file list —
/// the declared-tests gate's only git read (Fakes, not mocks). Every other
/// argv answers empty + ok, and [ok] makes the base probe FAIL so the
/// fail-closed posture is provable.
class _BaseTreeGitRunner implements GitRunner {
  _BaseTreeGitRunner(this.baseFiles, {this.ok = true});

  final List<String> baseFiles;
  final bool ok;

  /// Every argv, in call order.
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.of(args));
    if (args.isNotEmpty && args.first == 'ls-tree') {
      return ok
          ? GitRunResult(exitCode: 0, output: baseFiles.join('\n'))
          : const GitRunResult(
              exitCode: 128,
              output: 'fatal: not a valid object name: origin/main',
            );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

/// Drives the gate over a temp workspace. [existingFiles] are the files present
/// at the PINNED BASE: written to disk (realism) and answered by the fake
/// `ls-tree`. [runner] overrides that fake outright (argv assertions, probe
/// failure).
Future<Ok> _runGate({
  required String design,
  required String diff,
  Iterable<String> existingFiles = const [],
  _BaseTreeGitRunner? runner,
}) async {
  final dir = Directory.systemTemp.createTempSync('declared-tests-');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final path in existingFiles) {
    final file = File(p.join(dir.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('pre-existing');
  }
  final pinned = File(pinnedDiffPath(dir.path));
  pinned.parent.createSync(recursive: true);
  pinned.writeAsStringSync(diff);
  final outcome =
      await DeclaredTestsCapability(
        runner: runner ?? _BaseTreeGitRunner(existingFiles.toList()),
      ).run(
        FakeTreeContext(
          values: {
            Bead: workBead('tg-1').copyWith(design: design),
            Workspace: testWorkspace('tg-1', workspaceDir: dir.path),
          },
        ),
        stepArgs('tg-1/review/$kDeclaredTestsRubric'),
      );
  expect(outcome, isA<Ok>());
  return outcome as Ok;
}

String _diffFor(Iterable<String> paths) => paths
    .map((path) => 'diff --git a/$path b/$path\n--- a/$path\n+++ b/$path')
    .join('\n');

String _fixtureTestPath(String stem) =>
    'test/${stem}_${String.fromCharCode(116)}est.dart';

void main() {
  test('missing declared files fail loudly', () async {
    final outcome = await _runGate(
      design: 'Create `test/one_test.dart`. Modify `test/two_test.dart`.',
      diff: _diffFor(['test/one_test.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale':
          'Design-declared test files missing from pinned diff: test/two_test.dart',
    });
  });

  test('all declared files present passes', () async {
    final outcome = await _runGate(
      design: 'Create `test/one_test.dart`. Modify `test/two_test.dart`.',
      diff: _diffFor(['test/one_test.dart', 'test/two_test.dart']),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test(
    'pow-1gs package-relative declarations match repo-relative diff',
    () async {
      const design = '''
Test: cd packages/grid_assets && dart test test/committee_verdict_race_test.dart
Test: cd packages/grid_assets && dart test test/readiness_test.dart
Test: cd packages/grid_assets && dart test test/respec_test.dart
Modify `packages/grid_assets/test/respec_test.dart`.
Test: cd packages/grid_assets && dart test test/specify_stage_test.dart
Test: cd packages/grid_assets && dart test test/verdict_transport_test.dart
''';
      final outcome = await _runGate(
        design: design,
        diff: _diffFor([
          'packages/grid_assets/test/committee_verdict_race_test.dart',
          'packages/grid_assets/test/readiness_test.dart',
          'packages/grid_assets/test/respec_test.dart',
          'packages/grid_assets/test/specify_stage_test.dart',
          'packages/grid_assets/test/verdict_transport_test.dart',
        ]),
      );
      expect(outcome.payload?['grade'], 'A');
    },
  );

  test('an absent package-relative declaration still fails', () async {
    final outcome = await _runGate(
      design: 'Create `test/absent_test.dart`.',
      diff: _diffFor(['packages/grid_assets/test/present_test.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale':
          'Design-declared test files missing from pinned diff: test/absent_test.dart',
    });
  });

  test('suffix matching requires a path-component boundary', () async {
    final outcome = await _runGate(
      design: 'Modify `test/respec_test.dart`.',
      diff: _diffFor(['packages/grid_assets/test/prespec_test.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale':
          'Design-declared test files missing from pinned diff: test/respec_test.dart',
    });
  });

  test('an ambiguous suffix match counts as present', () async {
    final outcome = await _runGate(
      design: 'Modify `test/shared_test.dart`.',
      diff: _diffFor([
        'packages/alpha/test/shared_test.dart',
        'packages/beta/test/shared_test.dart',
      ]),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('no declared test files passes', () async {
    final outcome = await _runGate(
      design: 'Change the production implementation.',
      diff: _diffFor(['lib/implementation.dart']),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('run-only references in a full design are not declarations', () async {
    final path = _fixtureTestPath('asset_pack');
    final design =
        '''
## Touches
- `lib/asset_pack.dart` — modified.

## Validation Plan
- Existing acceptance: `dart test $path --name "packs assets"`
Test: dart test `$path` --name "packs assets"
''';
    expect(declaredTestFiles(design), isEmpty);
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/asset_pack.dart']),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('pre-existing unchanged prose is not a declaration', () async {
    const design = '''
Re-validated against the live tree: `test/track_c_route_test.dart` is a
pre-existing unchanged main test.
''';
    expect(declaredTestFiles(design), isEmpty);
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/route.dart']),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('restore-to-baseline prose is not a declaration', () async {
    const design = '''
Restore `test/commands/rework_command_test.dart` to baseline; the file is
unchanged after the revert.
''';
    expect(declaredTestFiles(design), isEmpty);
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/rework.dart']),
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('declared new test absent from pinned diff fails', () async {
    const design = '''
## Declared Tests
- `test/new_gate_test.dart` — create as authored coverage.
''';
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/gate.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale':
          'Design-declared test files missing from pinned diff: test/new_gate_test.dart',
    });
  });

  test('authored pre-existing untouched test fails', () async {
    const path = 'test/existing_gate_test.dart';
    final outcome = await _runGate(
      design: 'Modify `$path` with new regression coverage.',
      diff: _diffFor(['lib/gate.dart']),
      existingFiles: const [path],
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('shared markdown primitives bound declaration sections', () {
    const design = '''
```markdown
## Touches
- `test/fenced_test.dart` — modified
```
> Modify `test/quoted_test.dart`.
## Files Touched
- `test/authored_test.dart` — modified
## Touches
- `test/second_authored_test.dart` — modified
''';
    expect(declaredTestFiles(design), {
      'test/authored_test.dart',
      'test/second_authored_test.dart',
    });
  });

  test('ambiguous paths are ignored', () async {
    const design = r'''
`/test/absolute_test.dart`
`../test/traversal_test.dart`
`test/*_test.dart`
`test/not_a_test.dart.extra`
create test/unquoted_test.dart
`dart test test/shell_command_test.dart`
`packages/grid_assets/basename_test.dart`
''';
    expect(declaredTestFiles(design), isEmpty);
    final outcome = await _runGate(design: design, diff: '');
    expect(outcome.payload?['grade'], 'A');
  });

  test('authored marker beats exclusion words in one statement', () async {
    final path = _fixtureTestPath('restored_coverage');
    final design = 'Modify `$path`, which restores prior coverage.';
    expect(declaredTestFiles(design), {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/gate.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('bare Test directive remains a fail-closed fallback', () async {
    final path = _fixtureTestPath('historical_fallback');
    final design = 'Test: dart test $path';
    expect(declaredTestFiles(design), {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/gate.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('multiline authored statements remain declarations', () async {
    final path = _fixtureTestPath('multiline_authored');
    final design =
        '''
Modify the authored regression test at
`$path`.
''';
    expect(declaredTestFiles(design), {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['lib/gate.dart']),
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('tg-1ni0 round 4', () async {
    final fallbackPath = _fixtureTestPath('commands/rework_command');
    expect(
      missingDeclaredTestFiles(
        design: _tg1ni0Design,
        changedFiles: changedFilesIn(_tg1ni0Diff),
      ),
      [
        _fixtureTestPath('commands/gate_command'),
        _fixtureTestPath('commands/link_command'),
        fallbackPath,
      ],
    );
    final outcome = await _runGate(design: _tg1ni0Design, diff: _tg1ni0Diff);
    expect(outcome.payload?['grade'], 'F');
    final rationale = outcome.payload!['rationale']!;
    expect(rationale, contains(_fixtureTestPath('commands/gate_command')));
    expect(rationale, contains(_fixtureTestPath('commands/link_command')));
    expect(rationale, contains(fallbackPath));
    expect(rationale, isNot(contains('bead_command')));
  });

  test(
    'pow-0jc a Test line running a base file is not a declaration',
    () async {
      final path = _fixtureTestPath('up_agent_scope');
      final basePath = 'apps/space/$path';
      final design = 'Test: cd apps/space && dart test $path';
      expect(declaredTestFiles(design), {path});
      expect(declaredTestFiles(design, baseFiles: {basePath}), isEmpty);
      final outcome = await _runGate(
        design: design,
        diff: _diffFor(['apps/space/lib/up_agent_scope.dart']),
        existingFiles: [basePath, 'apps/space/lib/up_agent_scope.dart'],
      );
      expect(outcome.payload?['grade'], 'A');
    },
  );

  test('pow-0jc a Test line naming a file absent at the base blocks', () async {
    final path = _fixtureTestPath('new_scope');
    final design = 'Test: cd apps/space && dart test $path';
    expect(
      declaredTestFiles(design, baseFiles: const {'apps/space/lib/scope.dart'}),
      {path},
    );
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['apps/space/lib/scope.dart']),
      existingFiles: const ['apps/space/lib/scope.dart'],
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('pow-0jc an unreadable base stays fail-closed', () async {
    final path = _fixtureTestPath('unreadable_base');
    final runner = _BaseTreeGitRunner(const [], ok: false);
    final outcome = await _runGate(
      design: 'Test: dart test $path',
      diff: _diffFor(['lib/gate.dart']),
      runner: runner,
    );
    expect(outcome.payload?['grade'], 'F');
    expect(runner.calls.single, [
      'ls-tree',
      '-r',
      '--name-only',
      'origin/main',
    ]);
  });

  test('pow-0jc a declaration section never probes the base', () async {
    final path = _fixtureTestPath('section_authored');
    final runner = _BaseTreeGitRunner(const []);
    final outcome = await _runGate(
      design: '## Touches\n- `$path` — modified\n',
      diff: _diffFor([path]),
      runner: runner,
    );
    expect(outcome.payload?['grade'], 'A');
    expect(runner.calls, isEmpty);
  });

  test('pow-aoa a prose mention of a base file is not a declaration', () async {
    final path = _fixtureTestPath('widget/transcript_wiring');
    final basePath = 'packages/panel/$path';
    final design =
        '''
## Touches
- `lib/prompt_panel.dart` — modified.

Re-validated against the live tree: the two other tests that tap `prompt.start`
(`$path`) both have a non-null `_modelId`, so step 2 does not break them.
''';
    expect(declaredTestFiles(design), {path});
    expect(declaredTestFiles(design, baseFiles: {basePath}), isEmpty);
    final runner = _BaseTreeGitRunner([basePath]);
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['packages/panel/lib/prompt_panel.dart']),
      runner: runner,
    );
    expect(outcome.payload?['grade'], 'A');
    expect(runner.calls.single, [
      'ls-tree',
      '-r',
      '--name-only',
      'origin/main',
    ]);
  });

  test('pow-aoa a prose mention absent at the base still blocks', () async {
    final path = _fixtureTestPath('widget/new_transcript_wiring');
    const baseLib = 'packages/panel/lib/prompt_panel.dart';
    final design =
        '''
## Touches
- `lib/prompt_panel.dart` — modified.

Re-validated against the live tree: the fallback-link coverage lives in
(`$path`), which step 2 keeps green.
''';
    expect(declaredTestFiles(design, baseFiles: const {baseLib}), {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor([baseLib]),
      existingFiles: const [baseLib],
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('pow-aoa an authored marker on a base file still declares', () async {
    final path = _fixtureTestPath('authored_over_base');
    final basePath = 'packages/panel/$path';
    final design = 'Modify `$path` with the regression case.';
    expect(testDeclarations(design).authored, {path});
    expect(declaredTestFiles(design, baseFiles: {basePath}), {path});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['packages/panel/lib/prompt_panel.dart']),
      existingFiles: [basePath, 'packages/panel/lib/prompt_panel.dart'],
    );
    expect(outcome.payload, {
      'grade': 'F',
      'transport': 'structural',
      'rationale': 'Design-declared test files missing from pinned diff: $path',
    });
  });

  test('pow-26dd tg-5kb a pattern file cited beside a created test', () async {
    const created = 'packages/grid_engine/test/work_list_pause_test.dart';
    const pattern =
        'packages/grid_engine/test/track_a_concurrency_governor_test.dart';
    const design = '''
Create `packages/grid_engine/test/work_list_pause_test.dart`, built on the
harness `packages/grid_engine/test/track_a_concurrency_governor_test.dart`
already uses (its _FakeSessionResolver and _FakeClock are file-private there,
so they are reproduced below).
''';
    final declarations = testDeclarations(design);
    expect(declarations.authored, {created});
    expect(declarations.mentioned, isEmpty);
    expect(declaredTestFiles(design, baseFiles: const {pattern}), {created});
    final outcome = await _runGate(
      design: design,
      diff: _diffFor([created]),
      existingFiles: const [pattern],
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('pow-26dd space-fvg a package-relative pattern citation', () async {
    const cited = 'test/link_composition_test.dart';
    const second = 'test/memento_roster_test.dart';
    const baseCited = 'packages/spec_committee/test/link_composition_test.dart';
    const baseSecond = 'packages/spec_committee/test/memento_roster_test.dart';
    const design = '''
## Touches
- `lib/link.dart` — modified.

Add the downstream fake as the `_DownstreamDelegate` shape already used in
`test/link_composition_test.dart` and `test/memento_roster_test.dart`.
''';
    final declarations = testDeclarations(design);
    expect(declarations.authored, isEmpty);
    expect(declarations.mentioned, {cited, second});
    // pow-qev's fail-closed posture: an unknown base declares both.
    expect(declaredTestFiles(design), {cited, second});
    expect(
      declaredTestFiles(design, baseFiles: const {baseCited, baseSecond}),
      isEmpty,
    );
    final outcome = await _runGate(
      design: design,
      diff: _diffFor(['packages/spec_committee/lib/link.dart']),
      existingFiles: const [baseCited, baseSecond],
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('pow-26dd tg-czsf a must-stay-green file cited in prose', () async {
    const created = 'test/overlay_scope_test.dart';
    const design = '''
Create `test/overlay_scope_test.dart`, mirroring
`test/overlay_delivery_test.dart`, which must stay green.
''';
    final declarations = testDeclarations(design);
    expect(declarations.authored, {created});
    expect(declarations.mentioned, isEmpty);
    final outcome = await _runGate(
      design: design,
      diff: _diffFor([created]),
      existingFiles: const [
        'packages/grid_assets/test/overlay_delivery_test.dart',
      ],
    );
    expect(outcome.payload?['grade'], 'A');
  });

  test('pow-26dd a reference cue that follows the path demotes it', () async {
    const cited = 'test/lane_pattern_test.dart';
    const authored = 'test/lane_probe_test.dart';
    const design = '''
## Touches
- `lib/lane.dart` — modified.

The downstream fake the harness `test/lane_pattern_test.dart` already uses is
copied inline, and add `test/lane_probe_test.dart`.
''';
    final declarations = testDeclarations(design);
    expect(declarations.authored, {authored});
    expect(declarations.mentioned, {cited});
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {'packages/lane/test/lane_pattern_test.dart'},
      ),
      {authored},
    );
  });

  test('pow-26dd an ambiguous base suffix stays declared', () {
    const cited = 'test/roster_test.dart';
    const design = '''
## Touches
- `lib/roster.dart` — modified.

The fake mirrors the shape already used in `test/roster_test.dart`.
''';
    expect(testDeclarations(design).mentioned, {cited});
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {
          'packages/alpha/test/roster_test.dart',
          'packages/beta/test/roster_test.dart',
        },
      ),
      {cited},
    );
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {'packages/alpha/test/roster_test.dart'},
      ),
      isEmpty,
    );
  });

  test('pow-26dd two authored paths in one sentence both declare', () {
    const design =
        'Modify `test/gate_shape_test.dart` and add `test/gate_route_test.dart`.';
    expect(declaredTestFiles(design), {
      'test/gate_shape_test.dart',
      'test/gate_route_test.dart',
    });
  });

  test('pow-26dd an unchanged sibling is not declared', () {
    const design =
        'Create `test/new_lane_test.dart`. `test/old_lane_test.dart` is unchanged.';
    expect(declaredTestFiles(design), {'test/new_lane_test.dart'});
  });

  test('pow-26dd a cue after the path leaves the path authored', () {
    const design =
        'Create `test/pause_lane_test.dart`, built on the existing harness.';
    expect(testDeclarations(design).authored, {'test/pause_lane_test.dart'});
    expect(
      declaredTestFiles(
        design,
        baseFiles: const {'packages/p/test/pause_lane_test.dart'},
      ),
      {'test/pause_lane_test.dart'},
    );
  });

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
    const design =
        'Create `test/pair_x_test.dart` and `test/pair_y_test.dart`.';
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
}
