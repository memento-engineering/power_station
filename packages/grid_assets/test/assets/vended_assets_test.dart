// `kVendedSkills` and `kOperatorSkills` are GONE; both views derive from the
// generated pack, and no hand-maintained const id list may take their place.
// Also pins the audience doctrine's verbatim survival in the `grid:` block.
// Offline; reads this package's own sources.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (Directory(p.join(dir.path, 'extension', 'rubrics')).existsSync()) {
      return dir.path;
    }
    final nested = Directory(p.join(dir.path, 'packages', 'grid_assets'));
    if (nested.existsSync()) return nested.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_assets from ${Directory.current.path}');
}

void main() {
  final root = _packageRoot();

  test('the derived views reproduce the retired constants exactly', () {
    expect(vendedSkillIds, const [
      'asset-author',
      'discover',
      'gate-medicine',
      'handoff',
      'harvest-review',
      'intake-refinement',
      'release',
      'station-operations',
    ]);
    expect(operatorSkillIds, const [
      'asset-author',
      'gate-medicine',
      'handoff',
      'harvest-review',
      'intake-refinement',
      'release',
      'station-operations',
    ]);
    expect(operatorSkillIds, isNot(contains('discover')));
  });

  test('no hand-maintained const skill-id list survives anywhere in lib/', () {
    final declaration = RegExp(r'const\s+List<String>\s+k\w*Skills\b');
    final offenders = <String>[];
    for (final entity in Directory(
      p.join(root, 'lib'),
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final relative = p.relative(entity.path, from: root);
      for (final banned in const [
        'kVendedSkills',
        'kOperatorSkills',
        'kAgentSkills',
      ]) {
        if (source.contains(banned)) offenders.add('$relative: $banned');
      }
      if (declaration.hasMatch(source)) offenders.add('$relative: const list');
    }
    expect(offenders, isEmpty);
  });

  test('the audience doctrine survives VERBATIM on the block audience field', () {
    final pubspec = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
    for (final sentence in const [
      'The split is load-bearing, not cosmetic.',
      'Offering a build agent a skill that contradicts its working',
      'A DENY-list, not an allow-list of agent skills',
      'Only a DECLARED operator',
    ]) {
      expect(pubspec, contains(sentence), reason: 'verbatim: $sentence');
    }
  });
}
