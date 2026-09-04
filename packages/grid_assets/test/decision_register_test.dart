// The DECISION-LOOKUP surface — a pure RENDERING contract.
//
// The lookup used to be a shell loop this suite executed against temp
// `docs/adr`/`docs/decisions` trees. It is now the composing station's
// roster-mode `decisions index` verb, whose grid adapter resolves the live
// mounted-substation roster; this library renders its argv and runs nothing,
// so the suite is a unit test over the rendered text.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart' show kLocalOnlyTokens;

void main() {
  group('rosterDecisionIndexCommand renders the roster-mode verb', () {
    test('the bare form asks for the whole union', () {
      expect(rosterDecisionIndexCommand(), 'space decisions index');
    });

    test('a surface is passed by --surface, roster-qualified', () {
      expect(
        rosterDecisionIndexCommand(surface: 'the_grid/lib/src/a.dart'),
        'space decisions index --surface the_grid/lib/src/a.dart',
      );
    });

    test('the composing station\'s runner is substitutable — a MULTI-TOKEN '
        'downstream invocation renders verbatim', () {
      expect(
        rosterDecisionIndexCommand(
          surface: 'x/y.dart',
          runner: 'dart run lunar:lunar',
        ),
        'dart run lunar:lunar decisions index --surface x/y.dart',
      );
    });

    test('NO register-directory argument is ever rendered — the omission is '
        'what resolves the roster', () {
      for (final command in [
        rosterDecisionIndexCommand(),
        rosterDecisionIndexCommand(surface: 'a/b.dart'),
      ]) {
        expect(command, isNot(contains('docs/adr')));
        expect(command, isNot(contains('docs/decisions')));
        for (final token in kLocalOnlyTokens) {
          expect(command, isNot(contains(token)));
        }
      }
    });
  });

  group('rosterDecisionLookupBlock is one command per surface', () {
    test('every surface gets its own line, in order', () {
      expect(
        rosterDecisionLookupBlock(const ['a/b.dart', 'c/d.dart']),
        'space decisions index --surface a/b.dart\n'
        'space decisions index --surface c/d.dart',
      );
    });

    test('an empty surface list renders the TEMPLATE form, so a PRE-SPECIFY '
        'brief still names the verb', () {
      expect(
        rosterDecisionLookupBlock(const []),
        'space decisions index '
        '--surface $kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
      );
    });

    test('surfaces derived from a spec dedupe in document order', () {
      const design = '''
## Touches
- `lib/a.dart` — modified; `lib/a.dart:Alpha`
- `lib/b.dart` — created
- `lib/a.dart` — the duplicate collapses

## Validation Plan
- [ ] proven by `dart test`
''';
      expect(
        rosterDecisionLookupBlock(
          rosterQualifiedSurfaces(design: design, substation: 'power_station'),
        ),
        'space decisions index --surface power_station/lib/a.dart\n'
        'space decisions index --surface power_station/lib/b.dart',
      );
    });

    test('only the `## Touches` section is read — a path named elsewhere in '
        'the spec is not a queried surface', () {
      const design = '''
## Implementation Plan
Read `lib/elsewhere.dart` first.

## Touches
- `lib/a.dart` — modified

## Validation Plan
- [ ] `test/a_test.dart` passes
''';
      expect(
        rosterQualifiedSurfaces(design: design, substation: 'power_station'),
        ['power_station/lib/a.dart'],
      );
    });
  });

  group('rosterQualifiedPaths is the ONE qualifier both lookups share', () {
    test('the PRE-specify gather and the POST-specify spec qualify a path '
        'identically — same order, same dedupe, same prefix', () {
      const design =
          '## Touches\n'
          '- `lib/a.dart` — modified; `lib/a.dart:Alpha`\n'
          '- `lib/b.dart` — created\n'
          '- `lib/a.dart` — the duplicate collapses\n';
      final fromSpec = rosterQualifiedSurfaces(
        design: design,
        substation: 'power_station',
      );
      final fromGather = rosterQualifiedPaths(
        paths: const [
          'lib/a.dart',
          'lib/a.dart:Alpha',
          'lib/b.dart',
          'lib/a.dart',
        ],
        substation: 'power_station',
      );
      expect(fromSpec, [
        'power_station/lib/a.dart',
        'power_station/lib/b.dart',
      ]);
      expect(fromGather, fromSpec);
    });

    test('an empty substation falls back to the placeholder prefix, and prose '
        'is never a surface', () {
      expect(
        rosterQualifiedPaths(
          paths: const ['lib/a.dart', 'Alpha', 'a b/c.dart', ''],
          substation: '  ',
        ),
        ['$kUnknownSubstationPrefix/lib/a.dart'],
      );
    });
  });

  group('the WRITE rule is unchanged by the roster move', () {
    test('it names its four load-bearing tokens', () {
      for (final token in [
        'docs/decisions/',
        '.claude/skills/decide/SKILL.md',
        'BINDS ON WRITE',
        'READ-ONLY LEGACY',
      ]) {
        expect(kDecisionWriteRule, contains(token));
      }
    });
  });
}
