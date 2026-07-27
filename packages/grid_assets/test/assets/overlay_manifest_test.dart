import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late File manifest;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('overlay_manifest_');
    manifest = File(p.join(temp.path, 'config.yaml'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  StationOverlaySource load(String yaml) {
    manifest.writeAsStringSync(yaml);
    return loadStationOverlaySourceFromPaths(
      overlayRoot: p.join(temp.path, 'station_overlay'),
      manifestPath: manifest.path,
    );
  }

  test('provides all publish-safe defaults', () {
    expect(load('name: assets\n').mappings, kDefaultStationOverlayMappings);
  });

  test('manifest mappings override defaults', () {
    expect(
      load(
        'station_overlay:\n  mappings:\n    claude: tools/claude\n',
      ).mappings['claude'],
      p.join('tools', 'claude'),
    );
  });

  test('rejects malformed mappings', () {
    expect(
      () => load('station_overlay:\n  mappings: nope\n'),
      throwsFormatException,
    );
  });

  for (final target in ['/absolute', '../outside']) {
    test('rejects unsafe target $target', () {
      expect(
        () => load('station_overlay:\n  mappings:\n    claude: $target\n'),
        throwsFormatException,
      );
    });
  }
}
