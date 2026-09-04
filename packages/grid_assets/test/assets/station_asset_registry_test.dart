import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolved closure', () {
    late Directory temp;
    late _StationFixture fixture;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('station-registry-');
      fixture = _StationFixture(temp);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('resolved closure includes transitive and workspace packs', () {
      fixture
        ..addPackage('direct_grid_assets', dependency: 'direct main')
        ..addPackage('serenity', dependency: 'transitive')
        ..addPackage('station_craft', workspace: true)
        ..addPackage('extension_only', grid: false, extensionOnly: true)
        ..writeGraph();

      final packs = resolveStationGridAssetPacks(stationRoot: temp.path);
      expect(packs.map((pack) => pack.name), <String>[
        'direct_grid_assets',
        'serenity',
        'station_craft',
      ]);
      expect(packs.map((pack) => pack.version).toSet(), <String>{'1.0.0'});
      expect(packs.every((pack) => p.isAbsolute(pack.root)), isTrue);
      expect(packs.map((pack) => pack.publicLibraryUri.toString()), <String>[
        'package:direct_grid_assets/direct_grid_assets.dart',
        'package:serenity/serenity.dart',
        'package:station_craft/station_craft.dart',
      ]);
      expect(packs.every((pack) => pack.assets.length == 1), isTrue);
    });

    test('grid key presence is the only membership rule', () {
      fixture
        ..addPackage('serenity', dependency: 'transitive')
        ..addPackage('extension_only', grid: false, extensionOnly: true)
        ..writeGraph();

      expect(
        resolveStationGridAssetPacks(
          stationRoot: temp.path,
        ).map((pack) => pack.name),
        <String>['serenity'],
      );
    });

    test('stale lock refuses with every missing package and no output', () {
      fixture
        ..addPackage('serenity', dependency: 'transitive')
        ..addLockOnlyPackage('zeta_missing')
        ..addLockOnlyPackage('alpha_missing')
        ..writeGraph();
      final output = File(p.join(temp.path, 'lib', 'registry.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('sentinel');

      expect(
        () => runStationAssetRegistryGenerator(
          stationRoot: temp.path,
          outputPath: output.path,
          out: StringBuffer(),
        ),
        throwsA(
          isA<StalePackageGraphException>().having(
            (error) => error.packageNames,
            'packageNames',
            <String>['alpha_missing', 'zeta_missing'],
          ),
        ),
      );
      expect(output.readAsStringSync(), 'sentinel');
    });

    test('render is a static deterministic registrant', () {
      fixture
        ..addPackage('zest', dependency: 'transitive')
        ..addPackage('serenity', dependency: 'direct main')
        ..writeGraph();
      final packs = resolveStationGridAssetPacks(stationRoot: temp.path);
      final source = renderStationAssetRegistryLibrary(packs.reversed);

      expect(source, contains(kStationAssetRegistryGeneratedMarker));
      expect(
        source,
        contains('ignore_for_file: depend_on_referenced_packages'),
      );
      expect(
        source.indexOf('package:serenity/serenity.dart'),
        lessThan(source.indexOf('package:zest/zest.dart')),
      );
      expect(
        source,
        contains('serenity_grid_asset_pack.GridAssetsPack.definition'),
      );
      expect(source, contains('static final GridAssetRegistry registry'));
      expect(source, isNot(contains('static const GridAssetRegistry')));
      expect(source, isNot(contains('GridAssetDefinition(')));
      expect(source, renderStationAssetRegistryLibrary(packs));
    });

    test('duplicate identities refuse before output changes', () {
      fixture
        ..addPackage('serenity', dependency: 'direct main')
        ..writeGraph();
      final pack = resolveStationGridAssetPacks(stationRoot: temp.path).single;
      expect(
        () => renderStationAssetRegistryLibrary(<ResolvedGridAssetPack>[
          pack,
          pack,
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('duplicate AssetKey'),
          ),
        ),
      );

      final duplicateArtifacts =
          'grid:\n'
          '  assets:\n'
          '    - id: probe\n'
          '      kind: rubric\n'
          '      description: "Probe."\n'
          '      artifacts:\n'
          '        - target: mcp\n'
          '          path: extension/rubrics/probe.md\n'
          '        - target: mcp\n'
          '          path: extension/rubrics/probe.md\n';
      final second = _StationFixture(temp)
        ..addPackage(
          'serenity',
          dependency: 'direct main',
          gridBody: duplicateArtifacts,
        )
        ..writeGraph();
      final output = File(p.join(temp.path, 'lib', 'registry.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('sentinel');
      expect(
        () => runStationAssetRegistryGenerator(
          stationRoot: second.root.path,
          outputPath: output.path,
          out: StringBuffer(),
        ),
        throwsA(
          isA<GridBlockException>().having(
            (error) => error.message,
            'message',
            contains('duplicate delivery target'),
          ),
        ),
      );
      expect(output.readAsStringSync(), 'sentinel');
    });

    test('write and check are atomic and emit no aggregate config', () {
      fixture
        ..addPackage('serenity', dependency: 'direct main')
        ..writeGraph();
      final output = File(p.join(temp.path, 'lib', 'registry.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      final mcp = File(
        p.join(
          temp.path,
          'packages',
          'serenity',
          'extension',
          'mcp',
          'config.yaml',
        ),
      )..createSync(recursive: true);
      mcp.writeAsStringSync('sentinel mcp\n');

      expect(
        runStationAssetRegistryGenerator(
          stationRoot: temp.path,
          outputPath: output.path,
          check: true,
          out: StringBuffer(),
        ),
        1,
      );
      expect(output.readAsStringSync(), 'stale');

      expect(
        runStationAssetRegistryGenerator(
          stationRoot: temp.path,
          outputPath: output.path,
          out: StringBuffer(),
        ),
        0,
      );
      final generated = output.readAsStringSync();
      expect(
        runStationAssetRegistryGenerator(
          stationRoot: temp.path,
          outputPath: output.path,
          check: true,
          out: StringBuffer(),
        ),
        0,
      );
      expect(
        runStationAssetRegistryGenerator(
          stationRoot: temp.path,
          outputPath: output.path,
          out: StringBuffer(),
        ),
        0,
      );
      expect(output.readAsStringSync(), generated);
      expect(mcp.readAsStringSync(), 'sentinel mcp\n');
      expect(
        File(p.join(temp.path, 'station_asset_registry.yaml')).existsSync(),
        isFalse,
      );
    });

    test('checked-in registrant constructs offline', () {
      final registry = GeneratedGridAssetRegistrant.registry;
      expect(registry.packs, <GridAssetPackDefinition>[
        GridAssetsPack.definition,
      ]);
      expect(
        identical(registry.packs.single, GridAssetsPack.definition),
        isTrue,
      );
      expect(registry.assets, hasLength(28));

      final source = File(
        p.join(Directory.current.path, 'lib', 'station_asset_registry.dart'),
      ).readAsStringSync();
      for (final forbidden in <String>[
        'dart:io',
        'package:yaml',
        'package:package_config',
        'parseGridBlock(',
        'findExtensions(',
        'Service',
        'reflect',
      ]) {
        expect(source, isNot(contains(forbidden)));
      }
    });
  });
}

final class _StationFixture {
  _StationFixture(this.root);

  final Directory root;
  final List<Map<String, Object?>> _packages = <Map<String, Object?>>[];
  final Map<String, String> _locked = <String, String>{};

  void addPackage(
    String name, {
    String dependency = 'transitive',
    bool grid = true,
    bool extensionOnly = false,
    bool workspace = false,
    String? gridBody,
  }) {
    final packageRoot = Directory(p.join(root.path, 'packages', name))
      ..createSync(recursive: true);
    final artifact = File(
      p.join(packageRoot.path, 'extension', 'rubrics', 'probe.md'),
    )..createSync(recursive: true);
    artifact.writeAsStringSync('probe\n');
    final library = File(p.join(packageRoot.path, 'lib', '$name.dart'))
      ..createSync(recursive: true);
    library.writeAsStringSync("export 'src/assets/grid_asset_pack.dart';\n");
    if (extensionOnly) {
      File(p.join(packageRoot.path, 'extension', 'mcp', 'config.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('resources: []\n');
    }
    final block = grid
        ? gridBody ??
              'grid:\n'
                  '  assets:\n'
                  '    - id: probe\n'
                  '      kind: rubric\n'
                  '      description: "Probe."\n'
                  '      artifacts:\n'
                  '        - target: mcp\n'
                  '          path: extension/rubrics/probe.md\n'
        : '';
    File(
      p.join(packageRoot.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: $name\nversion: 1.0.0\n$block');
    _packages.add(<String, Object?>{
      'name': name,
      'rootUri': packageRoot.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.11',
    });
    if (!workspace) _locked[name] = dependency;
  }

  void addLockOnlyPackage(String name) {
    _locked[name] = 'transitive';
  }

  void writeGraph() {
    final config = File(p.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true);
    config.writeAsStringSync(
      jsonEncode(<String, Object?>{'configVersion': 2, 'packages': _packages}),
    );
    final lock = StringBuffer('packages:\n');
    for (final entry in _locked.entries) {
      lock
        ..writeln('  ${entry.key}:')
        ..writeln('    dependency: ${entry.value}')
        ..writeln('    description:')
        ..writeln('      name: ${entry.key}')
        ..writeln('    source: hosted')
        ..writeln('    version: "1.0.0"');
    }
    File(p.join(root.path, 'pubspec.lock')).writeAsStringSync(lock.toString());
  }
}
