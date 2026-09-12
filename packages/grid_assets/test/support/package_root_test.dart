// The cwd-independence of [packageRoot] itself — pinned the only way that does
// not reintroduce the hazard: in a CHILD process with a foreign working
// directory, so this suite never writes the cwd its siblings read.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package_root.dart';

void main() {
  test('the root resolves from a FOREIGN working directory — one no walk up '
      'from it could ever reach this package', () async {
    final foreign = await Directory.systemTemp.createTemp(
      'grid_assets_foreign_cwd_',
    );
    addTearDown(() => foreign.delete(recursive: true));

    final probe = p.join(
      packageRoot(),
      'test',
      'support',
      'package_root_probe.dart',
    );
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      probe,
    ], workingDirectory: foreign.path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, isEmpty);
    expect(result.stdout, packageRoot());
  });

  test(
    'the resolved root is THIS package — its own pubspec and this suite',
    () {
      final root = packageRoot();
      expect(p.isAbsolute(root), isTrue);
      expect(
        File(p.join(root, 'pubspec.yaml')).readAsLinesSync(),
        contains('name: grid_assets'),
      );
      expect(
        File(p.join(root, 'test', 'support', 'package_root.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(root, 'lib', 'grid_assets.dart')).readAsStringSync(),
        isNotEmpty,
      );
    },
  );
}
