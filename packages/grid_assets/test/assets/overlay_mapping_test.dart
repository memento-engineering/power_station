import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory source;
  late Directory target;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('overlay_mapping_');
    source = Directory(p.join(temp.path, 'source'))..createSync();
    target = Directory(p.join(temp.path, 'target'))..createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('maps the first segment and leaves unmapped paths verbatim', () {
    File(p.join(source.path, 'claude', 'skills', 'x', 'SKILL.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('---\nname: x\n---\nskill\n');
    File(p.join(source.path, 'other', 'readme.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('---\nname: other\n---\nother\n');

    const OverlayMaterializer().materializeSync(
      overlaySources:
          [
                StationOverlaySource(
                  root: '',
                  mappings: kDefaultStationOverlayMappings,
                ),
              ]
              .map(
                (item) => StationOverlaySource(
                  root: source.path,
                  mappings: item.mappings,
                ),
              )
              .toList(),
      targetRoot: target.path,
      sourceRef: 'test',
    );

    expect(
      File(
        p.join(target.path, '.claude', 'skills', 'x', 'SKILL.md'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(target.path, 'other', 'readme.md')).existsSync(),
      isTrue,
    );
  });

  test('manifest override redirects a mapping and mapped subtree scopes', () {
    File(p.join(source.path, 'claude', 'skills', 'x', 'SKILL.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('---\nname: x\n---\nskill\n');
    final report = const OverlayMaterializer().materializeSync(
      overlaySources:
          [
                StationOverlaySource(
                  root: '',
                  mappings: {'claude': 'tools/claude'},
                ),
              ]
              .map(
                (item) => StationOverlaySource(
                  root: source.path,
                  mappings: item.mappings,
                ),
              )
              .toList(),
      targetRoot: target.path,
      sourceRef: 'test',
      subtrees: const ['tools/claude/skills'],
    );
    expect(
      report.written.single.relativePath,
      p.join('tools', 'claude', 'skills', 'x', 'SKILL.md'),
    );
  });

  test(
    'warns for hidden source directories without refusing legacy content',
    () {
      File(p.join(source.path, '.claude', 'settings.json'))
        ..createSync(recursive: true)
      ..writeAsStringSync('{\n  "enabled": true\n}\n');
      final report = const OverlayMaterializer().materializeSync(
        overlayRoots: [source.path],
        targetRoot: target.path,
        sourceRef: 'test',
      );
      expect(report.warnings.single.relativePath, '.claude');
      expect(report.written, hasLength(1));
    },
  );
}
