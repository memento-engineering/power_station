import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
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

Future<Ok> _runGate({required String design, required String diff}) async {
  final dir = Directory.systemTemp.createTempSync('declared-tests-');
  addTearDown(() => dir.deleteSync(recursive: true));
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
      design: 'Test: dart test test/absent_test.dart',
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
      design: 'Test: dart test test/respec_test.dart',
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
      design: 'Test: dart test test/shared_test.dart',
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

  test('a test command path is extracted', () {
    expect(
      declaredTestFiles(
        'Test: dart test packages/grid_assets/test/track_c_route_test.dart',
      ),
      {'packages/grid_assets/test/track_c_route_test.dart'},
    );
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
        'test/commands/rework_command_test.dart',
      ],
    );
    final outcome = await _runGate(design: _tg1ni0Design, diff: _tg1ni0Diff);
    expect(outcome.payload?['grade'], 'F');
    final rationale = outcome.payload!['rationale']!;
    expect(rationale, contains('test/commands/gate_command_test.dart'));
    expect(rationale, contains('test/commands/link_command_test.dart'));
    expect(rationale, contains('test/commands/rework_command_test.dart'));
    expect(rationale, isNot(contains('bead_command_test.dart')));
  });
}
