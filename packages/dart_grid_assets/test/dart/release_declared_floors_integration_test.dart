// The declared-floors leg against LIVE pub.dev — the regression the release
// scrub gate exists for: a candidate consuming `StepFailureClass.noResult`
// (which only exists from grid_trajectory 0.2.0-rc.4) while declaring a floor
// of rc.3. Its local workspace sibling exposes the member, so path resolution
// stays green exactly as it did in the shipped wave; the scrub verb copies the
// candidate out of the workspace and resolves the exact declared floor from
// pub.dev, where the truth shows up.
//
// Tagged `integration`: it resolves the network, so the offline suite
// (`dart test -x integration`) excludes it.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'release scrub fails at grid_trajectory rc.3 and passes at rc.4',
    () async {
      final low = _writeFloorFixture('^0.2.0-rc.3');
      final raised = _writeFloorFixture('^0.2.0-rc.4');
      addTearDown(() => low.root.delete(recursive: true));
      addTearDown(() => raised.root.delete(recursive: true));

      final lowResult = await _runScrub(low.candidate);
      final lowFloors =
          lowResult.json['declaredFloors'] as Map<String, dynamic>;
      expect(lowResult.code, 1);
      expect(lowResult.json['clean'], isFalse);
      expect(lowFloors['passed'], isFalse);
      expect(lowFloors['message'], contains('noResult'));
      expect(lowFloors['message'], contains('grid_trajectory'));
      expect(lowFloors['message'], contains('0.2.0-rc.3'));

      final raisedResult = await _runScrub(raised.candidate);
      final raisedFloors =
          raisedResult.json['declaredFloors'] as Map<String, dynamic>;
      expect(raisedResult.code, 0);
      expect(raisedResult.json['clean'], isTrue);
      expect(raisedFloors['passed'], isTrue);
      expect(raisedFloors['pins'], [
        {
          'package': 'grid_trajectory',
          'declaredConstraint': '^0.2.0-rc.4',
          'floor': '0.2.0-rc.4',
        },
      ]);
    },
    tags: const <String>['integration'],
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<({int code, Map<String, dynamic> json})> _runScrub(
  Directory candidate,
) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = CommandRunner<int>('t', 'test')
    ..addCommand(ReleaseCommand(out: out, err: err));
  final code = await runner.run([
    'release',
    'scrub',
    '--dir',
    candidate.path,
    '--json',
  ]);
  expect(err.toString(), isEmpty);
  return (
    code: code!,
    json: jsonDecode(out.toString()) as Map<String, dynamic>,
  );
}

/// Writes a two-member pub workspace whose candidate uses a member that only
/// exists above [floor]'s published version, with a LOCAL sibling that has it —
/// the shape that resolves green by path and red at the declared floor.
({Directory root, Directory candidate}) _writeFloorFixture(String floor) {
  final root = Directory.systemTemp.createTempSync(
    'declared-floor-integration-',
  );
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: declared_floor_fixture_workspace\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'workspace:\n'
    '  - packages/candidate\n'
    '  - packages/grid_trajectory\n',
  );

  final sibling = Directory(p.join(root.path, 'packages', 'grid_trajectory'))
    ..createSync(recursive: true);
  File(p.join(sibling.path, 'pubspec.yaml')).writeAsStringSync(
    'name: grid_trajectory\n'
    'version: 0.2.0-rc.4\n'
    'resolution: workspace\n'
    'environment:\n'
    '  sdk: ^3.11.0\n',
  );
  final siblingLib = Directory(p.join(sibling.path, 'lib'))
    ..createSync(recursive: true);
  File(p.join(siblingLib.path, 'grid_trajectory.dart')).writeAsStringSync(
    'enum StepFailureClass { work, noResult, invalidResult }\n',
  );

  final candidate = Directory(p.join(root.path, 'packages', 'candidate'))
    ..createSync(recursive: true);
  File(p.join(candidate.path, 'pubspec.yaml')).writeAsStringSync(
    'name: declared_floor_candidate\n'
    'version: 0.1.0\n'
    'publish_to: none\n'
    'resolution: workspace\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'dependencies:\n'
    '  grid_trajectory: $floor\n',
  );
  final candidateLib = Directory(p.join(candidate.path, 'lib'))
    ..createSync(recursive: true);
  File(p.join(candidateLib.path, 'candidate.dart')).writeAsStringSync(
    "import 'package:grid_trajectory/grid_trajectory.dart';\n\n"
    'StepFailureClass classify() => StepFailureClass.noResult;\n',
  );
  return (root: root, candidate: candidate);
}
