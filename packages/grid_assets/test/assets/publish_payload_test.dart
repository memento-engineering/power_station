import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

void main() {
  test('pub publish includes the complete visible overlay payload', () async {
    // The package root, and the dry run's working directory, come off the
    // shared cwd-independent anchor — never the process working directory,
    // which is a process property a concurrently scheduled suite could move out
    // from under a spawn.
    final root = packageRoot();
    final result = await Process.run(Platform.resolvedExecutable, const [
      'pub',
      'publish',
      '--dry-run',
      '--verbose',
    ], workingDirectory: root);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final output = '${result.stdout}\n${result.stderr}'.replaceAll('\\', '/');
    final expected = [
      for (final leg in const ['agents', 'claude'])
        ...Directory(p.join(root, 'extension', 'station_overlay', leg))
            .listSync(recursive: true)
            .whereType<File>()
            .map(
              (file) => p.relative(file.path, from: root).replaceAll('\\', '/'),
            ),
    ]..sort();
    expect(expected, hasLength(19));
    for (final path in expected) {
      expect(
        output,
        contains(path),
        reason: '$path missing from publish payload',
      );
    }
    expect(output, isNot(contains('extension/station_overlay/.claude/')));
    expect(output, isNot(contains('extension/station_overlay/.agents/')));
  });
}
