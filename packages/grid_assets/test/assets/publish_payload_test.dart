import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('pub publish includes the complete visible overlay payload', () async {
    final packageRoot = Directory.current;
    final result = await Process.run(Platform.resolvedExecutable, const [
      'pub',
      'publish',
      '--dry-run',
      '--verbose',
    ], workingDirectory: packageRoot.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final output = '${result.stdout}\n${result.stderr}'.replaceAll('\\', '/');
    final expected = [
      for (final leg in const ['agents', 'claude'])
        ...Directory(
              p.join(packageRoot.path, 'extension', 'station_overlay', leg),
            )
            .listSync(recursive: true)
            .whereType<File>()
            .map(
              (file) => p
                  .relative(file.path, from: packageRoot.path)
                  .replaceAll('\\', '/'),
            ),
    ]..sort();
    expect(expected, hasLength(18));
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
