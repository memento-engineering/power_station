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
}
