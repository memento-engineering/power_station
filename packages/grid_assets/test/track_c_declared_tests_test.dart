import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
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

Future<Ok> _runGate({
  required String design,
  required String diff,
  Iterable<String> existingFiles = const [],
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
  final outcome = await const DeclaredTestsCapability().run(
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

  test('run-only references are not declarations', () async {
    const design = '''
## Validation Plan
- Existing acceptance: `dart test test/asset_pack_test.dart --name "packs assets"`
Test: dart test `test/asset_pack_test.dart` --name "packs assets"
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

  test('tg-1ni0 round 4', () async {
    expect(
      missingDeclaredTestFiles(
        design: _tg1ni0Design,
        changedFiles: changedFilesIn(_tg1ni0Diff),
      ),
      [
        'test/commands/gate_command_test.dart',
        'test/commands/link_command_test.dart',
      ],
    );
    final outcome = await _runGate(design: _tg1ni0Design, diff: _tg1ni0Diff);
    expect(outcome.payload?['grade'], 'F');
    final rationale = outcome.payload!['rationale']!;
    expect(rationale, contains('test/commands/gate_command_test.dart'));
    expect(rationale, contains('test/commands/link_command_test.dart'));
    expect(
      rationale,
      isNot(contains('test/commands/rework_command_test.dart')),
    );
    expect(rationale, isNot(contains('bead_command_test.dart')));
  });
}
