// The TWO RUNTIMES a station has, proved where a station actually binds them:
// through the REAL `assets install` Command, the REAL install service and the
// REAL materializer, onto a temp repo root.
//
// `boot_runner_hole_test.dart` pins the RENDERING — that the vended
// station-operations source spells its boot sites from `{{bootRunner}}`. It
// cannot see the seam: it calls `renderOverlayTemplate` directly, so it passes
// whether or not a station can SET the two holes differently. This suite is the
// one that fails when the split is inert.
//
// Offline: fake delegate, static facts over the live pack's own checkout,
// injected source ref (so no git subprocess), captured sinks.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_resolution_fixture.dart';

/// The composing station's resident-station context, rooted at [root].
class _StationDelegate extends sdk.GridDelegate {
  _StationDelegate(this.root);

  @override
  final String root;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(root: root, assets: const []);
}

/// The harness heads the station-operations skill lands under — BOTH, because a
/// boot spelled from the wrong runtime on one of them is the same defect.
const List<String> _targetHeads = <String>['.claude', '.agents'];

void main() {
  late Directory temp;
  late String gridHome;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-assets-boot-runner-');
    // FIXED across every install in a test: the grid home is rendered into
    // other assets, so varying it would make a byte comparison meaningless.
    gridHome = p.join(temp.path, 'grid-home');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// Installs the LIVE pack onto [targetRoot] through the real Command.
  Future<int?> install({
    required String targetRoot,
    required String runnerInvocation,
    String? bootRunner,
    required StringBuffer err,
  }) {
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        AssetsInstallCommand(
          delegate: () => _StationDelegate(gridHome),
          registry: sdk.GridAssetRegistry(<sdk.GridAssetPackDefinition>[
            GridAssetsPack.definition,
          ]),
          factsRepository: ({required roots, required registry}) =>
              StaticSubstationFactsRepository(
                SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
                  kGridHomeSubstation: SubstationFacts(
                    root: roots[kGridHomeSubstation]!,
                    dartPackages: const <String>['grid_assets', 'grid_sdk'],
                    packageRoots: <String, String>{
                      'grid_assets': liveAssetPackageRoot(),
                    },
                  ),
                }),
              ),
          runnerInvocation: runnerInvocation,
          bootRunner: bootRunner,
          sourceRef: (_) => 'testref',
          out: StringBuffer(),
          err: err,
        ),
      );
    return runner.run(<String>['install', '--no-diff', '--root', targetRoot]);
  }

  Directory root(String name) =>
      Directory(p.join(temp.path, name))..createSync(recursive: true);

  String installedStationOperations(Directory target, String head) => File(
    p.join(target.path, head, 'skills', 'station-operations', 'SKILL.md'),
  ).readAsStringSync();

  group('the resident boot and the seat verbs, through the real install', () {
    test(
      'a station whose two runtimes differ installs them differently',
      () async {
        final err = StringBuffer();
        final target = root('two-runtimes');

        final code = await install(
          targetRoot: target.path,
          runnerInvocation: 'VERB_SENTINEL',
          bootRunner: 'BOOT_SENTINEL',
          err: err,
        );

        expect(code, 0, reason: err.toString());
        for (final head in _targetHeads) {
          final installed = installedStationOperations(target, head);
          // The RESIDENT boot: the JIT run form, which is what carries
          // `--enable-vm-service` and therefore hot reload, `reload` and the
          // leonard attach.
          expect(installed, contains('BOOT_SENTINEL up'));
          expect(installed, contains('`BOOT_SENTINEL` station JIT'));
          expect(
            installed,
            isNot(contains('VERB_SENTINEL up')),
            reason:
                '$head: a boot spelled from the verb runtime tells an operator '
                'to start the resident with a runtime carrying no VM service',
          );
          expect(
            installed,
            isNot(contains('`VERB_SENTINEL` station JIT')),
            reason:
                '$head: the JIT restart instruction is a resident boot as much '
                'as `up` is',
          );
          // …and every SEAT verb, which has to be reachable from a substation
          // worktree where `dart run <station>:<station>` resolves nothing.
          expect(installed, contains('VERB_SENTINEL seat governor'));
          expect(installed, contains('VERB_SENTINEL status'));
          expect(installed, contains('VERB_SENTINEL down'));
          // The provenance line the materializer stamps names the verb the
          // operator re-runs — a seat verb, not a boot.
          expect(installed, contains('VERB_SENTINEL assets install'));
        }
      },
    );

    test('omitted bootRunner installs byte-identically to explicit equal '
        'runtimes', () async {
      final err = StringBuffer();
      final omitted = root('omitted');
      final explicit = root('explicit');

      expect(
        await install(
          targetRoot: omitted.path,
          runnerInvocation: 'ONE_RUNTIME',
          err: err,
        ),
        0,
        reason: err.toString(),
      );
      expect(
        await install(
          targetRoot: explicit.path,
          runnerInvocation: 'ONE_RUNTIME',
          bootRunner: 'ONE_RUNTIME',
          err: err,
        ),
        0,
        reason: err.toString(),
      );

      for (final head in _targetHeads) {
        expect(
          installedStationOperations(explicit, head),
          installedStationOperations(omitted, head),
          reason:
              '$head: an omitted bootRunner adds NO key, so the hole keeps its '
              'runner-derived default — a one-runtime station installs the '
              'same bytes it installed before the split existed',
        );
      }
    });
  });
}
