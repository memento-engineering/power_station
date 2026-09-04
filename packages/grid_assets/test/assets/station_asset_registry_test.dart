import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
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
        () => resolveStationGridAssetPacks(stationRoot: temp.path),
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
