// Track B — the meaningfulness half of the opinion-free-engine fence.
//
// grid_engine/test/structural_test.dart asserts the engine names NONE of the
// opinion literals. That assertion would be vacuously true if the opinions
// existed NOWHERE. This test proves they DO live in `grid_assets`: the `code`
// asset's capabilities spawn `claude` (the coding agent + the LLM committee
// critics). Pure-Dart, offline (reads files; no live anything).
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `lib` directory, walking up from the test's working
/// dir to find `packages/grid_assets/lib` (robust whether the suite runs from
/// the repo root or the package dir).
Directory _libDir() {
  final candidates = <String>['lib', p.join('packages', 'grid_assets', 'lib')];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          File(p.join(probe.path, 'grid_assets.dart')).existsSync()) {
        return probe;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/lib from ${Directory.current.path}',
  );
}

Directory _packageLib(String packageName) {
  var current = Directory.current;
  File? configFile;
  while (true) {
    final candidate = File(
      p.join(current.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) {
      configFile = candidate;
      break;
    }
    if (current.parent.path == current.path) {
      fail('package_config.json missing; run dart pub get first');
    }
    current = current.parent;
  }
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packages = config['packages']! as List<Object?>;
  final entry = packages.cast<Map<String, Object?>>().singleWhere(
    (candidate) => candidate['name'] == packageName,
    orElse: () => fail('package $packageName is not resolved'),
  );
  final root = configFile.uri.resolve(entry['rootUri']! as String);
  return Directory.fromUri(
    Directory.fromUri(root).uri.resolve(entry['packageUri']! as String),
  );
}

String _dartSourceUnder(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .map((file) => file.readAsStringSync())
    .join('\n');

void main() {
  group('the opinions DO live in grid_assets (the fence is meaningful)', () {
    final libDir = _libDir();
    final allSource = _dartSourceUnder(libDir);

    test('the `code` asset spawns `claude` (the coding agent + the committee '
        'critics)', () {
      // The compiled `code` asset's capabilities spawn `claude` — both the
      // coding agent and the three LLM committee critics — so the literal exists
      // SOMEWHERE, proving grid_engine's engine-is-clean assertion (the engine
      // names NONE of it) is not vacuously true. (The toy `melos` verify is gone
      // — `verify` is now the committee whose gating lane runs the bead's own
      // Validation Plan, naming no fixed build tool.)
      expect(allSource, contains('claude'));
    });

    test('mount clauses remain assets-owned', () {
      final engineSource = _dartSourceUnder(_packageLib('grid_engine'));
      for (final clause in const [
        'validation_plan',
        'grid.approved',
        'grid.approval.actor',
      ]) {
        expect(engineSource, isNot(contains(clause)));
      }
      expect(allSource, contains('validation_plan'));
      expect(allSource, contains('grid.approved'));
    });
  });

  group('ONE resolution defines availability and both writers', () {
    final libDir = _libDir();

    String source(String relative) =>
        File(p.join(libDir.path, relative)).readAsStringSync();

    test('one resolver defines tree availability and both writer file sets', () {
      final materializer = source('src/assets/overlay_materializer.dart');
      final install = source('src/assets/overlay_install.dart');

      // The WRITER takes a resolution and has no source-roster vocabulary left.
      expect(materializer, contains('required GridAssetResolution resolution'));
      for (final retired in const [
        'overlayRoots',
        'overlaySources',
        'StationOverlaySource',
        '_mappedRelativePath',
        'listSync(recursive: true)',
      ]) {
        expect(
          materializer,
          isNot(contains(retired)),
          reason: 'the writer enumerates no source tree: $retired',
        );
      }
      // Runtime extension discovery is RETIRED from installation (this updates
      // A24(1) — `power_station#one-asset-resolution-defines-tree-and-writers`).
      for (final retired in const [
        'extension_discovery',
        'findExtensions',
        'resolveStationOverlay',
      ]) {
        expect(install, isNot(contains(retired)), reason: retired);
      }
      expect(
        File(p.join(libDir.parent.path, 'pubspec.yaml')).readAsStringSync(),
        isNot(contains('extension_discovery')),
        reason: 'the retired discovery dependency is gone from the pubspec too',
      );

      // Every consumer answers through the SAME function.
      for (final path in const [
        'src/assets/assets_command.dart',
        'src/code/code_capabilities.dart',
        'src/code/landing.dart',
      ]) {
        expect(source(path), contains('resolveGridAssets('), reason: path);
      }
      final substationSeed = File(
        p.join(
          _packageLib('github_grid_assets').path,
          'src',
          'assets',
          'substation_seed.dart',
        ),
      ).readAsStringSync();
      expect(substationSeed, contains('resolveGridAssets('));

      // ONE compatibility seam, three consumers. Every reader of the ambient
      // facts goes through `ambientAssetFactsOrFlare`, so a station that has
      // not mounted the projection yet degrades the SAME way everywhere and no
      // fourth migration path can drift in
      // (`power_station#one-asset-resolution-defines-tree-and-writers`).
      for (final consumer in <MapEntry<String, String>>[
        MapEntry(
          'src/code/code_capabilities.dart',
          source('src/code/code_capabilities.dart'),
        ),
        MapEntry('src/code/landing.dart', source('src/code/landing.dart')),
        MapEntry('substation_seed.dart', substationSeed),
      ]) {
        expect(
          consumer.value,
          contains('ambientAssetFactsOrFlare('),
          reason: consumer.key,
        );
      }
      final resolution = source('src/assets/asset_resolution.dart');
      expect(
        resolution,
        contains('dependOnInheritedSeedOfExactType<SubstationFactsSnapshot>'),
        reason:
            'the helper WATCHES when a build hands it an aspect (ADR-0008 D3)',
      );
      // The two verbs live in the helper and nowhere else: a consumer that
      // reached for the tree itself would be the drift this pins shut.
      for (final consumer in <String>[
        'src/code/code_capabilities.dart',
        'src/code/landing.dart',
      ]) {
        expect(
          source(consumer),
          isNot(contains('InheritedSeedOfExactType<SubstationFactsSnapshot>')),
          reason: 'the ambient read belongs to the helper: $consumer',
        );
      }
      expect(
        substationSeed,
        isNot(contains('InheritedSeedOfExactType<SubstationFactsSnapshot>')),
        reason: 'the ambient read belongs to the helper: substation_seed.dart',
      );

      // ONE writer, ONE observer: the stamped write and the package-config read
      // each live in exactly one production file of this feature.
      final writers = <String>[
        for (final file
            in libDir
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart')))
          if (file.readAsStringSync().contains('writeAsStringSync(stamped)'))
            p.relative(file.path, from: libDir.path),
      ];
      expect(writers, ['src/assets/overlay_materializer.dart']);
      final observers = <String>[
        for (final file
            in libDir
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart')))
          if (file.readAsStringSync().contains('PackageConfig.parseString'))
            p.relative(file.path, from: libDir.path),
      ];
      expect(
        observers,
        containsAll(<String>['src/assets/asset_resolution.dart']),
        reason:
            'the facts repository is this feature\'s only package-graph read',
      );
      expect(
        observers,
        isNot(contains('src/assets/overlay_install.dart')),
        reason: 'no writer observes a package graph of its own',
      );
    });

    test('the accepted decision names its human maker and the compatibility '
        'posture it ratified', () {
      final decision = File(
        p.join(
          libDir.parent.parent.parent.path,
          'docs',
          'decisions',
          '2026-09-04-one-asset-resolution-defines-tree-and-writers.md',
        ),
      ).readAsStringSync();
      expect(
        decision,
        contains('decision-makers: ["Nico Spencer"]'),
        reason: 'an accepted register entry has a HUMAN maker, never "agent"',
      );
      expect(
        decision,
        contains('`consumer: substation`'),
        reason:
            'the record carries the substation BUILD degrade, not just the '
            'two process edges',
      );
    });
  });

  group(
    'bead `pow-hxme` cites its OWN amendment (A37), never the stale A35',
    () {
      final libDir = _libDir();

      /// The three `lib` files carrying the verdict-owner mechanism.
      const ownerSources = <String>[
        'src/code/committee.dart',
        'src/code/respec.dart',
        'src/code/specify.dart',
      ];

      test('every owner-mechanism file names the bead and cites A37', () {
        for (final relative in ownerSources) {
          final text = File(p.join(libDir.path, relative)).readAsStringSync();
          expect(text, contains('pow-hxme'), reason: relative);
          expect(
            text,
            contains('A37'),
            reason: '$relative must cite pow-hxme\'s amendment by number',
          );
          expect(
            text,
            isNot(contains('A35')),
            reason:
                '$relative miscites A35 — that number is pow-n6n.1\'s '
                'typed-environment amendment, not pow-hxme\'s',
          );
        }
      });

      test('A37 is exactly one register entry, and it names pow-hxme', () {
        final register = File(
          p.join(
            libDir.parent.parent.parent.path,
            'docs',
            'adr',
            'ADR-0000-ai-decision-register.md',
          ),
        ).readAsStringSync();
        final headings = RegExp(
          r'^## A37 .*$',
          multiLine: true,
        ).allMatches(register).map((match) => match.group(0)!).toList();
        expect(headings, hasLength(1));
        expect(headings.single, contains('pow-hxme'));
      });
    },
  );
}
