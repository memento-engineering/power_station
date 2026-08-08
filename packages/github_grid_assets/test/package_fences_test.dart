import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('lib stays identity-only', () async {
    final source = await allLibrarySource();
    for (final forbidden in <String>[
      'package:beads_dart',
      'PrOpener',
      'Timer.periodic',
      'webhook',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('README documents credential posture and sibling ownership', () async {
    final readme = await File('README.md').readAsString();
    for (final required in <String>[
      'GC_GITHUB_APP_KEY_PATH',
      '0600',
      'never written to disk',
      'pow-1rn.2',
      'pow-1rn.3',
      'pow-1rn.4',
      'pow-1rn.5',
      'pow-1rn.6',
    ]) {
      expect(readme, contains(required));
    }
  });
}

Future<String> allLibrarySource() async {
  final files = await Directory('lib')
      .list(recursive: true)
      .where((entity) => entity is File && entity.path.endsWith('.dart'))
      .cast<File>()
      .toList();
  return (await Future.wait(
    files.map((file) => file.readAsString()),
  )).join('\n');
}
