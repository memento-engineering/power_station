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

    test('a bound GRID HOME qualifies the verb with its cwd — the station\'s '
        'JIT verb resolves only from there', () {
      expect(
        rosterDecisionIndexCommand(
          surface: '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
          runner: 'dart run lunar:lunar',
          gridHome: '/grid/lunar',
        ),
        "cd '/grid/lunar' && dart run lunar:lunar decisions index "
        '--surface <repo>/<path>',
      );
      expect(
        rosterDecisionIndexCommand(gridHome: '/grid/lunar'),
        "cd '/grid/lunar' && space decisions index",
      );
    });

    test('a grid home is SHELL-QUOTED — a space or an apostrophe still renders '
        'ONE argument', () {
      expect(
        rosterDecisionIndexCommand(gridHome: '/grid homes/lunar'),
        "cd '/grid homes/lunar' && space decisions index",
      );
      expect(
        rosterDecisionIndexCommand(gridHome: "/nico's grid"),
        'cd \'/nico\'"\'"\'s grid\' && space decisions index',
      );
    });

    test('an ABSENT or blank grid home keeps the BARE verb — the executing '
        'gather binds its own working directory', () {
      for (final home in [null, '', '   ']) {
        expect(
          rosterDecisionIndexCommand(surface: 'a/b.dart', gridHome: home),
          'space decisions index --surface a/b.dart',
        );
      }
    });

    test('NO register-directory argument is ever rendered — the omission is '
        'what resolves the roster', () {
      for (final command in [
        rosterDecisionIndexCommand(),
        rosterDecisionIndexCommand(surface: 'a/b.dart'),
        rosterDecisionIndexCommand(surface: 'a/b.dart', gridHome: '/g'),
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
    test('every surface gets its own line, in order, each cwd-qualified', () {
      expect(
        rosterDecisionLookupBlock(const [
          'a/b.dart',
          'c/d.dart',
        ], gridHome: '/grid/lunar'),
        "cd '/grid/lunar' && space decisions index --surface a/b.dart\n"
        "cd '/grid/lunar' && space decisions index --surface c/d.dart",
      );
    });

    test('an empty surface list renders the TEMPLATE form, so a PRE-SPECIFY '
        'brief still names the verb', () {
      expect(
        rosterDecisionLookupBlock(const [], gridHome: '/grid/lunar'),
        "cd '/grid/lunar' && space decisions index "
        '--surface $kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
      );
    });

    test('an UNBOUND grid home renders NOTHING — a prompt names no command it '
        'cannot run from where it stands', () {
      for (final home in [null, '', '  ']) {
        expect(
          rosterDecisionLookupBlock(const ['a/b.dart'], gridHome: home),
          isEmpty,
        );
        expect(rosterDecisionLookupBlock(const [], gridHome: home), isEmpty);
      }
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
          gridHome: '/grid/lunar',
        ),
        "cd '/grid/lunar' && space decisions index "
        '--surface power_station/lib/a.dart\n'
        "cd '/grid/lunar' && space decisions index "
        '--surface power_station/lib/b.dart',
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

  group('decisionLookupRule states the lookup it can actually name', () {
    test('BOUND: it renders the cwd-qualified verb and says why the cwd is '
        'there, keeping every roster clause', () {
      final rule = decisionLookupRule(
        runner: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      );
      expect(
        rule,
        contains(
          "cd '/grid/lunar' && dart run lunar:lunar decisions index "
          '--surface <repo>/<path>',
        ),
      );
      expect(rule, contains('Could not find package'));
      for (final token in [
        'UNION',
        'LOAD-BEARING',
        'originRegister',
        '<repo>#<slug>',
        'register.legacy-id',
        'real result, not an error',
        'never grade a crashed index clean',
      ]) {
        expect(rule, contains(token));
      }
      expect(rule, isNot(contains('docs/adr')));
    });

    test('UNBOUND: it names NO invocation and sends the lane to every mounted '
        'register — the honest form, and the exported default', () {
      for (final home in [null, '', '   ']) {
        final rule = decisionLookupRule(
          runner: 'dart run lunar:lunar',
          gridHome: home,
        );
        expect(rule, kDecisionLookupRule);
        expect(rule, contains('composing grid home is bound'));
        expect(rule, contains('docs/decisions/'));
        expect(rule, contains('EVERY mounted register'));
        // The FORCE clauses survive the loss of the command.
        for (final token in [
          'UNION',
          'LOAD-BEARING',
          '<repo>#<slug>',
          'register.legacy-id',
          'real result, not an error',
        ]) {
          expect(rule, contains(token));
        }
        expect(rule, isNot(contains('decisions index --surface')));
        expect(rule, isNot(contains('lunar decisions index')));
      }
    });
  });

  group('the narrative sentences follow the same binding', () {
    test('BOUND: both quote the cwd-qualified verb under their parsed '
        'prefixes', () {
      const home = '/grid/lunar';
      final empty = noGoverningDecisionSentence(gridHome: home);
      final failed = failedDecisionLookupSentence(gridHome: home);
      expect(empty, startsWith(kNoGoverningDecisionPrefix));
      expect(failed, startsWith(kFailedDecisionLookupPrefix));
      for (final sentence in [empty, failed]) {
        expect(
          sentence,
          contains("cd '/grid/lunar' && space decisions index --surface"),
        );
      }
    });

    test('UNBOUND: both name the direct register read instead, and keep the '
        'prefixes the spec gate parses', () {
      expect(
        kNoGoverningDecisionSentence,
        startsWith(kNoGoverningDecisionPrefix),
      );
      expect(
        kFailedDecisionLookupSentence,
        startsWith(kFailedDecisionLookupPrefix),
      );
      for (final sentence in [
        kNoGoverningDecisionSentence,
        kFailedDecisionLookupSentence,
      ]) {
        expect(sentence, contains('every mounted decision register'));
        expect(sentence, isNot(contains('decisions index')));
        // A backticked register PATH here would parse as a citation
        // (`isResolvableDecisionReference`), so the sentence that declares
        // the union empty must not carry one.
        expect(sentence, isNot(contains('docs/decisions/')));
      }
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
