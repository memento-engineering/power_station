import 'dart:io';

import 'package:test/test.dart';

/// The ONE file allowed to touch the process environment directly: it defines
/// `platformEnvironment()`, the default `EnvironmentReader` every other
/// production read is injected with.
const _sanctioned = 'lib/src/credentials.dart';

void main() {
  test(
    'exactly one lib file reads Platform.environment — every other production '
    'read takes an injectable EnvironmentReader',
    () {
      final offenders = <String>[];
      var sanctionedHits = 0;
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final hits = 'Platform.environment'
            .allMatches(file.readAsStringSync())
            .length;
        if (hits == 0) continue;
        if (file.path == _sanctioned) {
          sanctionedHits = hits;
        } else {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'take an EnvironmentReader (lib/src/credentials.dart) and default '
            'it to platformEnvironment() instead of reading the process '
            'environment here',
      );
      expect(
        sanctionedHits,
        1,
        reason: '$_sanctioned defines platformEnvironment() exactly once',
      );
    },
  );
}
