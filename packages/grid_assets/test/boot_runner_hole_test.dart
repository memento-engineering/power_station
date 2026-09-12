import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';

/// The vended skill source for [target], read from the pack itself.
///
/// Anchored on the package root, never on the process working directory: that
/// is a process property and `dart test` runs suites in concurrent isolates.
String stationOperationsSource(String target) => File(
  p.join(
    packageRoot(),
    'extension',
    'station_overlay',
    target,
    'skills',
    'station-operations',
    'SKILL.md',
  ),
).readAsStringSync();

/// The two runtimes a station has, and the two holes that name them.
///
/// `{{runner}}` is the VERB invocation — reachable from a substation worktree.
/// `{{bootRunner}}` is what starts the RESIDENT, which today needs the JIT run
/// form because that is what carries `--enable-vm-service`.
void main() {
  group('the boot hole', () {
    test('defaults to the verb runner, so a station that sets only runner '
        'renders exactly as before', () {
      final rendered = renderOverlayTemplate(
        '{{runner}} status and {{bootRunner}} up',
        const {'runner': 'space'},
      );
      expect(rendered, 'space status and space up');
    });

    test('a station whose runtimes differ spells them differently', () {
      final rendered = renderOverlayTemplate(
        '{{runner}} status and {{bootRunner}} up',
        const {'runner': 'lunar', 'bootRunner': 'dart run lunar:lunar'},
      );
      expect(rendered, 'lunar status and dart run lunar:lunar up');
    });

    test('a station value wins over the default', () {
      final rendered = renderOverlayTemplate('{{bootRunner}}', const {
        'runner': 'space',
        'bootRunner': 'dart run space:space',
      });
      expect(rendered, 'dart run space:space');
    });
  });

  group('the vended station-operations skill', () {
    test('renders its BOOT commands from the boot hole and never from the '
        'verb hole', () {
      for (final target in ['claude', 'agents']) {
        final source = stationOperationsSource(target);
        final rendered = renderOverlayTemplate(source, const {
          'runner': 'VERB_SENTINEL',
          'bootRunner': 'BOOT_SENTINEL',
        });
        // Every `up` invocation is a resident boot.
        expect(
          rendered,
          isNot(contains('VERB_SENTINEL up')),
          reason:
              '$target: a boot rendered from the verb hole would tell an '
              'operator to start the resident with a runtime that carries no '
              'VM service',
        );
        expect(rendered, contains('BOOT_SENTINEL up'));
        // …and the non-boot verbs still ride the verb hole.
        expect(rendered, contains('VERB_SENTINEL status'));
        expect(rendered, contains('VERB_SENTINEL down'));
      }
    });

    test('leaves no unrendered hole', () {
      for (final target in ['claude', 'agents']) {
        final rendered = renderOverlayTemplate(
          stationOperationsSource(target),
          const {'runner': 'space'},
        );
        expect(
          RegExp(r'\{\{\w+\}\}').firstMatch(rendered),
          isNull,
          reason: '$target: an unrendered hole is REFUSED at install',
        );
      }
    });
  });
}
