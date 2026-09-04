// The spec's line-oriented RECORD grammar — the deterministic contract one
// level below the section-presence gate.
//
// Proves: `proseOnly` preserves its input's LINE COUNT (so a record finding
// names the spec's OWN line); the record parser is TOTAL (no throw, no repair)
// and source-located; and the two composed resolvers — repo-relativity over
// the pack's one citation-path reader, and decision-citation RESOLUTION —
// answer exactly what they claim to.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('proseOnly preserves the LINE COUNT of everything it blanks', () {
    const ticks = '\x60\x60\x60';
    final samples = <String, String>{
      'the shipped exemplar': kSpecExemplarDesign,
      'a terminated fence': 'a\n${ticks}dart\nb\nc\n$ticks\nd',
      'an unterminated fence': 'a\n${ticks}dart\nb\nc\nd',
      'two fences': 'a\n$ticks\nb\n$ticks\nc\n$ticks\nd\n$ticks\ne',
      'a blockquote': 'a\n> quoted\n> more\nb',
      'inline spans': 'a `span` b\n`other` c',
      'a fence with no trailing newline': 'a\n$ticks\nb\n$ticks',
    };
    for (final entry in samples.entries) {
      test(entry.key, () {
        expect(
          proseOnly(entry.value).split('\n').length,
          entry.value.split('\n').length,
          reason: 'a blanked region must give back its newlines',
        );
      });
    }
  });

  test('the two-space seam still LEADS every blanked region — stripping '
      'breaks a token across it and never splices one together', () {
    const ticks = '\x60\x60\x60';
    // The inline-span seam: `as`retryPolicy`needed` must not become "as needed".
    final inline = proseOnly('Frames retry as`retryPolicy`needed dictates.');
    expect(inline, isNot(contains('as needed')));
    expect(inline, contains('as  needed'));
    // The fence seam leads the padding, so the line the fence OPENED on still
    // carries it and the banned phrase is never manufactured.
    final fenced = proseOnly('as $ticks\n$ticks\nquoted\n$ticks\nneeded');
    expect(fenced, isNot(contains('as needed')));
    expect(fenced, startsWith('as  '));
  });

  test('lineOf is 1-based and clamps out-of-range offsets', () {
    const text = 'one\ntwo\nthree';
    expect(lineOf(text, 0), 1);
    expect(lineOf(text, text.indexOf('two')), 2);
    expect(lineOf(text, text.indexOf('three')), 3);
    expect(lineOf(text, text.length + 99), 3);
    expect(lineOf(text, -5), 1);
  });

  test('sectionAt locates a section AND its body; sectionBodyAt is one line '
      'over it', () {
    const design = '## A\nbody a\n## B\nbody b\n';
    final a = sectionAt(design, headingOffset(design, '## A'));
    expect(a.body, '\nbody a');
    expect(design.substring(a.start, a.start + 6), '\nbody ');
    expect(sectionBodyAt(design, headingOffset(design, '## B')), '\nbody b\n');
  });

  group('repoRelativePathOf composes the pack\'s one citation-path reader', () {
    test('a repo-relative path resolves', () {
      expect(
        repoRelativePathOf('packages/grid_assets/lib/src/code/specify.dart'),
        'packages/grid_assets/lib/src/code/specify.dart',
      );
      expect(repoRelativePathOf('docs/decisions/'), 'docs/decisions/');
    });

    test('the two guards repo-relativity adds: ABSOLUTE and `..`', () {
      expect(repoRelativePathOf('/etc/passwd.txt'), isNull);
      expect(repoRelativePathOf('../the_grid/lib/main.dart'), isNull);
      expect(repoRelativePathOf('a/../b.dart'), isNull);
    });

    test('what the citation reader already refuses stays refused', () {
      expect(repoRelativePathOf('Heartbeat'), isNull);
      expect(repoRelativePathOf('lib/**/*.dart'), isNull);
      expect(repoRelativePathOf('https://example.com/a.dart'), isNull);
      expect(repoRelativePathOf('two words/a.dart'), isNull);
    });
  });

  group('isResolvableDecisionReference answers RESOLUTION, not reading', () {
    test('the three identities the roster index can answer', () {
      expect(
        isResolvableDecisionReference('power_station#a19-the-contract'),
        isTrue,
      );
      expect(
        isResolvableDecisionReference('the_grid#admission-authority-boundary'),
        isTrue,
      );
      expect(isResolvableDecisionReference('ADR-0008'), isTrue);
      expect(
        isResolvableDecisionReference('docs/decisions/2026-09-02-a-slug.md'),
        isTrue,
      );
      expect(isResolvableDecisionReference('docs/adr/ADR-0001-x.md'), isTrue);
    });

    test('prose, a bare word, and a non-register path do not resolve', () {
      expect(isResolvableDecisionReference('the heartbeat decision'), isFalse);
      expect(isResolvableDecisionReference('ADR-8'), isFalse);
      expect(isResolvableDecisionReference('lib/src/code/specify.dart'), isFalse);
      expect(isResolvableDecisionReference('#slug'), isFalse);
    });
  });

  group('parseSpecContract is TOTAL — never throws, never repairs', () {
    test('empty fields parse to an empty projection with no findings', () {
      final parsed = parseSpecContract(acceptance: '', design: '');
      expect(parsed.findings, isEmpty);
      expect(parsed.contract.criteria, isEmpty);
      expect(parsed.contract.steps, isEmpty);
      expect(parsed.contract.validations, isEmpty);
      expect(
        parsed.contract.decisionNarrative,
        DecisionLookupNarrative.cited,
      );
    });

    test('a malformed record contributes a FINDING and nothing to the '
        'projection — no guess reaches a cross-record check', () {
      final parsed = parseSpecContract(
        acceptance: '- [ ] the peer heartbeat surfaces',
        design: '',
        only: const {SpecContractSection.acceptance},
      );
      expect(parsed.findings.single.rule, SpecContractRule.acceptanceRecord);
      expect(parsed.findings.single.field, 'acceptance');
      expect(parsed.findings.single.line, 1);
      expect(parsed.contract.criteria, isEmpty);
    });

    test('a finding renders with the field and the AUTHORED line', () {
      final parsed = parseSpecContract(
        acceptance: '- [ ] AC-1 — a real record\n- [ ] no id here',
        design: '',
        only: const {SpecContractSection.acceptance},
      );
      expect(parsed.findings.single.render(), startsWith('acceptance line 2:'));
      expect(parsed.contract.criteria.single.id, 1);
    });

    test('a FENCED region shifts no line number — the record after it is '
        'named by the line the architect wrote', () {
      const ticks = '\x60\x60\x60';
      final parsed = parseSpecContract(
        acceptance: '- [ ] AC-1 — one',
        design:
            '## Validation Plan\n'
            '${ticks}markdown\n'
            '- [ ] AC-9 -> `quoted` -> quoted\n'
            '$ticks\n'
            '- [ ] not a record\n',
        only: const {SpecContractSection.validation},
      );
      expect(parsed.findings.single.rule, SpecContractRule.validationRecord);
      expect(parsed.findings.single.line, 5);
      expect(parsed.contract.validations, isEmpty);
    });

    test('the ASCII arrow is taken for the unicode one', () {
      final parsed = parseSpecContract(
        acceptance: '- [ ] AC-1 — one',
        design:
            '## Validation Plan\n'
            '- [ ] AC-1 -> `dart test` -> All tests passed!\n',
        only: const {
          SpecContractSection.acceptance,
          SpecContractSection.validation,
        },
      );
      expect(parsed.findings, isEmpty);
      expect(parsed.contract.validations.single.command, 'dart test');
      expect(parsed.contract.validations.single.expected, 'All tests passed!');
    });
  });

  group('the `## ADR Alignment` lookup NARRATIVE is typed', () {
    ({String acceptance, String design}) spec(String body) => (
      acceptance: '- [ ] AC-1 — one',
      design: '## ADR Alignment\n$body\n',
    );

    ({SpecContract contract, List<SpecContractFinding> findings}) parse(
      String body,
    ) => parseSpecContract(
      acceptance: spec(body).acceptance,
      design: spec(body).design,
      only: const {SpecContractSection.decisions},
    );

    test('an EMPTY union is a real result — the sentence the brief dictates '
        'is the one the gate accepts', () {
      final parsed = parse(kNoGoverningDecisionSentence);
      expect(parsed.findings, isEmpty);
      expect(
        parsed.contract.decisionNarrative,
        DecisionLookupNarrative.emptyUnion,
      );
      expect(parsed.contract.citations, isEmpty);
    });

    test('a CRASHED lookup is NOT an empty union — it has its own form, and '
        'citations are not required because the union is UNKNOWN', () {
      final parsed = parse(
        '$kFailedDecisionLookupSentence\n\n'
        '> sh: space: command not found\n',
      );
      expect(parsed.findings, isEmpty);
      expect(
        parsed.contract.decisionNarrative,
        DecisionLookupNarrative.failedLookup,
      );
    });

    test('a crashed lookup that still quotes the LOCAL register keeps the '
        'crashed narrative — the union stays unknown', () {
      final parsed = parse(
        '$kFailedDecisionLookupSentence\n'
        '- `power_station#a19-the-contract` — applied: the one string rule.\n',
      );
      expect(parsed.findings, isEmpty);
      expect(
        parsed.contract.decisionNarrative,
        DecisionLookupNarrative.failedLookup,
      );
      expect(
        parsed.contract.citations.single.reference,
        'power_station#a19-the-contract',
      );
    });

    test('a SILENT section — no citation and neither outcome declared — is '
        'LOUD, because an unknown union is not an empty one', () {
      final parsed = parse('None that we could find.');
      expect(
        parsed.findings.single.rule,
        SpecContractRule.decisionSectionSilent,
      );
      expect(parsed.findings.single.line, 1);
      expect(parsed.findings.single.message, contains('unknown union'));
    });

    test('a citation without a disposition is a named deviation', () {
      final parsed = parse('- `power_station#a19-the-contract` is relevant.');
      expect(parsed.findings.single.rule, SpecContractRule.decisionRecord);
      expect(parsed.contract.citations, isEmpty);
    });
  });
}
