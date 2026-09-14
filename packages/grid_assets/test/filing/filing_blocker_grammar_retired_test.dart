// AC-3 — the PACKAGE-WIDE fence behind the 2026-09-13 ruling (Nico, under
// `the_grid#the-grid-is-a-beads-controller`): bead text is never parsed for
// blockers again anywhere in `grid_assets`, and the filing library reads no
// link bead.
//
// A source scan, because that is what the ruling actually forbids: the
// behaviour it kills has no call site left to assert against once the grammar
// is gone, so the only durable proof is that no source in this package can
// express it. The same shape as `butane_grid_assets`'s pin on the retired
// `BurnRunCommand`.
//
// Pure-Dart, offline (reads files; no live anything).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// Every `.dart` file under this package's `lib`, keyed by its path relative
/// to `lib` so a failure NAMES the offending file.
Map<String, String> _librarySources() {
  final libDir = Directory(p.join(packageRoot(), 'lib'));
  return {
    for (final file in libDir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        p.relative(file.path, from: libDir.path): file.readAsStringSync(),
  };
}

void main() {
  final sources = _librarySources();

  test('no source parses the retired prose declaration grammar', () {
    // The grammar is an English PHRASE: `blocked`/`depends` and `by`/`on`
    // joined by a separator that is not an identifier character — a space in a
    // string literal, a `\s` class in a pattern, a hyphen in the spelling that
    // cost the round. bd's own wire key `depends_on_id` and the circuit field
    // `dependsOn` join with identifier characters and are not this grammar.
    final grammar = RegExp(
      r'(?:blocked|depends)(?:\\s|[^a-zA-Z0-9_]){1,12}(?:by|on)'
      r'(?![a-zA-Z0-9_])',
      caseSensitive: false,
    );

    // The fence PROVES itself: the exact pattern this bead retired must match,
    // or an empty result would mean nothing.
    expect(
      grammar.hasMatch(
        r'^[\s>*#-]*(?:\d+[.)]\s*)?(?:blocked\s+(?:by|on)|depends\s+on)\b',
      ),
      isTrue,
      reason: 'the scan must recognize the retired pattern it replaces',
    );
    expect(grammar.hasMatch("'Blocked-by: pow-x'"), isTrue);
    expect(grammar.hasMatch("'Depends on pow-x'"), isTrue);
    // …and must not fire on the two identifiers that legitimately survive.
    expect(grammar.hasMatch("dependsOn: {'review'}"), isFalse);
    expect(grammar.hasMatch("@JsonKey(name: 'depends_on_id')"), isFalse);

    final offenders = <String>[];
    sources.forEach((path, source) {
      for (final line in source.split('\n')) {
        final code = line.trimLeft();
        // Doc and line comments are PROSE by the ruling's own words: "a
        // `Blocked by` sentence is prose". Only executable source counts.
        if (code.startsWith('//')) continue;
        if (grammar.hasMatch(line)) offenders.add('$path: ${line.trim()}');
      }
    });
    expect(
      offenders,
      isEmpty,
      reason:
          'the prose blocker grammar is RETIRED — a blocker is a declaration '
          'bd holds, read through DependencyProjection',
    );
  });

  test('the filing library reads no link bead', () {
    final filing = {
      for (final entry in sources.entries)
        if (p.split(entry.key).contains('filing')) entry.key: entry.value,
    };
    expect(filing, isNotEmpty, reason: 'the filing library must exist');

    for (final entry in filing.entries) {
      expect(
        entry.value,
        isNot(contains('projectCrossLinks')),
        reason: '${entry.key} reads link beads',
      );
      expect(
        entry.value,
        isNot(contains('GridIssueTypes.link')),
        reason: '${entry.key} reads link beads',
      );
      expect(
        entry.value,
        isNot(contains('CrossLinkBlockerSource')),
        reason: '${entry.key} names the retired link-bead source',
      );
    }
  });

  test('the retired symbols are gone from the whole package', () {
    for (final symbol in const [
      'CrossLinkBlockerSource',
      'kUnconsultedCrossStoreDetail',
      'linkedBlockers',
    ]) {
      final offenders = [
        for (final entry in sources.entries)
          if (entry.value.contains(symbol)) entry.key,
      ];
      expect(
        offenders,
        isEmpty,
        reason: '$symbol is retired — the hard cut leaves no compatibility arm',
      );
    }
  });
}
