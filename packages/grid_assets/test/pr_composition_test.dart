// The PR title/body composition (bead pow-8dx) — the inferred conventional
// title, the section-composed body, the bead-id-as-trailer policy, and the
// configurable knob. Pure: zero I/O.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const PrDescription _inferred = PrDescription(
  type: 'feat',
  scope: 'landing',
  description: 'Infer the pr title from the branch diff.',
  summary:
      'The land step now reads the branch delta and describes it. '
      'Titles were terse and templated off the tracker.',
);

PrCompositionContext _context({
  Bead? bead,
  SiblingView siblings = const SiblingView(),
  PrDescription? description,
  CommitLintReport commits = const CommitLintReport(),
  String titleSource = 'fallback',
}) {
  final work = bead ?? const Bead(id: 'tg-1');
  return PrCompositionContext(
    beadId: work.id,
    bead: work,
    siblings: siblings,
    description: description,
    commits: commits,
    titleSource: titleSource,
  );
}

void main() {
  group('the TITLE is inferred, conventional, and id-free (pow-8dx)', () {
    test('an inferred description renders a sanitized v1.0.0 subject — the '
        "model's raw string never reaches GitHub", () {
      final title = const PrComposition().titleOf(
        _context(description: _inferred, titleSource: 'inference'),
      );
      expect(title, 'feat(landing): infer the pr title from the branch diff');
      expect(lintConventionalSubject(title, foreignRef: 'tg-1'), isEmpty);
    });

    test('an inferred subject that smuggles the bead id in is STRIPPED', () {
      final title = const PrComposition().titleOf(
        _context(
          description: const PrDescription(
            type: 'feat',
            description: 'tg-1 — add the thing',
          ),
          titleSource: 'inference',
        ),
      );
      expect(title, 'feat: add the thing');
      expect(title, isNot(contains('tg-1')));
    });

    test(
      'NO inference ⇒ the deterministic fallback: type from issueType, scope '
      'from metadata.rig, description from the id-stripped title — never the '
      'legacy `grid: <id>`',
      () {
        expect(
          const PrComposition().titleOf(
            _context(
              bead: const Bead(
                id: 'pow-8dx',
                title: 'pow-8dx: Better PR titles.',
                issueType: IssueType.feature,
                metadata: {'rig': 'power_station'},
              ),
            ),
          ),
          'feat(power_station): better PR titles',
        );
        expect(
          const PrComposition().titleOf(_context()),
          'chore: $kFallbackDescription',
        );
      },
    );

    test(
      'the fallback type maps the OPEN IssueType set (bug→fix, epic/story→feat, '
      'anything unknown→chore, never a throw)',
      () {
        expect(conventionalTypeFor(IssueType.bug), 'fix');
        expect(conventionalTypeFor(IssueType.epic), 'feat');
        expect(conventionalTypeFor(IssueType.story), 'feat');
        expect(conventionalTypeFor(IssueType.task), 'chore');
        expect(conventionalTypeFor(const IssueType('mystery')), 'chore');
      },
    );

    test("BREAKING: `!` and the footer imply each other (Nico's rule)", () {
      const composition = PrComposition();
      final flagOnly = _context(
        description: const PrDescription(
          type: 'feat',
          breaking: true,
          description: 'drop the legacy title',
        ),
        titleSource: 'inference',
      );
      expect(composition.titleOf(flagOnly), 'feat!: drop the legacy title');
      expect(
        composition.bodyOf(flagOnly),
        contains('BREAKING CHANGE: drop the legacy title'),
      );

      final footerOnly = _context(
        description: const PrDescription(
          type: 'feat',
          description: 'drop the legacy title',
          breakingChange: 'the PR title shape changed',
        ),
        titleSource: 'inference',
      );
      expect(composition.subjectOf(footerOnly).breaking, isTrue);
      expect(
        composition.bodyOf(footerOnly),
        contains('BREAKING CHANGE: the PR title shape changed'),
      );
    });
  });

  group('PrDescription.parse — the LAST JSON object wins (pow-8dx)', () {
    test('parses the answer object out of a chatty stdout, ignoring an echoed '
        'template preamble', () {
      final parsed = PrDescription.parse(
        'Here is the shape: {"type":"feat","description":"<the description>"}\n'
        'And my answer:\n'
        '{"type":"fix","scope":"land","breaking":false,'
        '"description":"stop clobbering the design note","body":"prose",'
        '"breakingChange":""}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.type, 'fix');
      expect(parsed.scope, 'land');
      expect(parsed.description, 'stop clobbering the design note');
      // The LEGACY `body` key still yields a digest — a model answering in the
      // shape it half-remembers must not lose its prose.
      expect(parsed.summary, 'prose');
    });

    test('reads the `summary` key — the digest the prompt now asks for', () {
      final parsed = PrDescription.parse(
        '{"type":"fix","description":"stop the clobber",'
        '"summary":"The receipt no longer writes the body."}',
      );
      expect(parsed!.summary, 'The receipt no longer writes the body.');
    });

    test(
      'null for absent / blank / unparseable output, and for an object with no '
      'description (fail-safe — never a throw)',
      () {
        expect(PrDescription.parse(null), isNull);
        expect(PrDescription.parse('   '), isNull);
        expect(PrDescription.parse('I could not do it.'), isNull);
        expect(PrDescription.parse('{"type":"feat"}'), isNull);
        expect(PrDescription.parse('{not json'), isNull);
      },
    );
  });

  group('the BODY composes; absent data OMITS a section (pow-8dx / pow-yny)', () {
    const siblings = SiblingView(
      results: {
        'tg-1/review/route': {
          'grades': 'code-validation=A',
          'spread': '0',
          'rule': 'all-approve',
        },
        'tg-1/land/rebase': {'outcome': 'clean'},
        'tg-1/land/revalidate': {'outcome': 'passed'},
      },
    );

    test(
      'the default body: summary → receipt → committee → validation → trailers, '
      'in order — the inferred prose is COMPOSED with the receipt, never '
      'clobbered by it',
      () {
        final body = const PrComposition().bodyOf(
          _context(
            bead: const Bead(
              id: 'tg-1',
              metadata: {'validation_plan': 'dart test'},
            ),
            siblings: siblings,
            description: _inferred,
            commits: const CommitLintReport(
              total: 2,
              compliant: 2,
              trailered: 2,
            ),
            titleSource: 'inference',
          ),
        );
        final order = [
          body.indexOf('## Summary'),
          body.indexOf(
            'The land step now reads the branch delta and describes',
          ),
          body.indexOf('## Circuit receipt'),
          body.indexOf('## Committee'),
          body.indexOf('## Validation'),
          body.indexOf('Refs: tg-1'),
        ];
        expect(order, everyElement(greaterThanOrEqualTo(0)));
        expect(order, orderedEquals([...order]..sort()));
        // The receipt carries the landing circuit's own provenance + this bead's.
        expect(body, contains('- rebase: clean'));
        expect(body, contains('- revalidate: passed'));
        expect(body, contains('- description: inference'));
        expect(body, contains('- commits: 2 (2 conventional, 2 trailered)'));
        expect(
          body,
          contains(
            '- review: grades=code-validation=A spread=0 rule=all-approve',
          ),
        );
        expect(body, contains('- plan: `dart test`'));
        // THE POLICY: the bead id appears EXACTLY once — on the trailer line.
        expect('tg-1'.allMatches(body).length, 1);
        expect(body.trimRight(), endsWith('Refs: tg-1'));
      },
    );

    test(
      'a bare bead: no summary, no committee, no validation — but always the '
      'receipt and the trailer (no bare headings)',
      () {
        final body = const PrComposition().bodyOf(_context());
        expect(body, contains('## Circuit receipt'));
        expect(body, contains('- description: fallback'));
        expect(body, isNot(contains('## Committee')));
        expect(body, isNot(contains('## Validation')));
        expect(body, isNot(contains('- commits:')));
        expect(body.trimRight(), endsWith('Refs: tg-1'));
      },
    );

    test('off-policy branch commits are NAMED in the receipt (the build-agent '
        'commit lint, directive item 5)', () {
      final report = lintCommitSubjects(const [
        'feat(landing): infer the pr title\n\nRefs: tg-1',
        'feat(x): tg-1 — do a thing',
        'wip',
      ], foreignRef: 'tg-1');
      expect(report.total, 3);
      expect(report.compliant, 1);
      expect(report.trailered, 1);
      expect(report.violations, hasLength(2));
      final body = const PrComposition().bodyOf(_context(commits: report));
      expect(body, contains('- commits: 3 (1 conventional, 1 trailered)'));
      expect(body, contains('off-policy: `feat(x): tg-1 — do a thing`'));
      expect(body, contains('off-policy: `wip`'));
    });
  });

  // The code route's single-finding advance (bead `pow-bhm`) writes
  // `fix_in_flight` onto its route result as `<lane>=<grade>`; the PR body
  // surfaces it as ONE digest line, so a reviewer reads the open finding this
  // PR was built carrying without opening the circuit.
  group('the committee digest names the carried finding', () {
    SiblingView siblingsWith({String? carried}) => SiblingView(
      results: {
        'tg-1/review/route': {
          'grades': 'code-validation=A regression-risk=D',
          'spread': '1',
          'rule': carried == null ? 'all-approve' : 'single-finding-advance',
          if (carried != null) 'fix_in_flight': carried,
        },
      },
    );

    test('a carried finding renders `- fix in flight: <lane>=<grade>`', () {
      final body = const PrComposition().bodyOf(
        _context(siblings: siblingsWith(carried: 'regression-risk=D')),
      );
      expect(body, contains('## Committee'));
      expect(body, contains('- fix in flight: regression-risk=D'));
    });

    test('no carried finding ⇒ the committee section omits the line', () {
      final body = const PrComposition().bodyOf(
        _context(siblings: siblingsWith()),
      );
      expect(body, contains('## Committee'));
      expect(body, isNot(contains('fix in flight')));
    });

    test('an EMPTY carry value omits the line — the guard is the emptiness '
        'check, not mere presence of the key', () {
      final body = const PrComposition().bodyOf(
        _context(siblings: siblingsWith(carried: '')),
      );
      expect(body, contains('## Committee'));
      expect(body, isNot(contains('fix in flight')));
    });
  });

  group('the human DIGEST leads the body', () {
    test(
      'an inferred digest renders under `## Summary`, ABOVE the receipt — the '
      'reader meets the change before its provenance',
      () {
        final body = const PrComposition().bodyOf(
          _context(description: _inferred, titleSource: 'inference'),
        );
        expect(body, startsWith('## Summary\n\n'));
        expect(
          body,
          contains(
            'The land step now reads the branch delta and describes it.',
          ),
        );
        expect(
          body.indexOf('## Summary'),
          lessThan(body.indexOf('## Circuit receipt')),
        );
      },
    );

    test('a digest that smuggles the bead id is STRIPPED — the id rides the '
        'trailer and nothing else', () {
      final body = const PrComposition().bodyOf(
        _context(
          description: const PrDescription(
            type: 'feat',
            description: 'add the digest',
            summary:
                'tg-1 — the land step now writes a digest. '
                'Fixes tg-1 (tg-1#r2) for good.',
          ),
          titleSource: 'inference',
        ),
      );
      expect(body, contains('## Summary'));
      expect(body, contains('the land step now writes a digest.'));
      expect('tg-1'.allMatches(body).length, 1);
      expect(body.trimRight(), endsWith('Refs: tg-1'));
    });

    test(
      'NO digest ⇒ NO heading (an absent section is dropped, never bare)',
      () {
        const bare = PrComposition();
        expect(bare.bodyOf(_context()), isNot(contains('## Summary')));
        expect(
          bare.bodyOf(
            _context(
              description: const PrDescription(
                type: 'feat',
                description: 'add the thing',
              ),
              titleSource: 'inference',
            ),
          ),
          isNot(contains('## Summary')),
        );
        expect(
          bare.bodyOf(
            _context(
              description: const PrDescription(
                type: 'feat',
                description: 'add the thing',
                summary: '   \n  ',
              ),
              titleSource: 'inference',
            ),
          ),
          isNot(contains('## Summary')),
        );
      },
    );

    test(
      'a runaway digest is CAPPED (an essay must not become the PR body)',
      () {
        final long = 'word ' * (kMaxSummaryChars ~/ 2);
        final digest = sanitizeDigest(long, foreignRef: 'tg-1');
        expect(digest.length, lessThan(kMaxSummaryChars + 32));
        expect(digest, endsWith('… (truncated)'));
      },
    );

    test(
      'sanitizeDigest is pure prose surgery: paragraphs survive, the ref does '
      'not',
      () {
        expect(sanitizeDigest('', foreignRef: 'tg-1'), isEmpty);
        expect(
          sanitizeDigest('One. \n\nTwo.', foreignRef: 'tg-1'),
          'One.\n\nTwo.',
        );
        expect(
          sanitizeDigest('The tg-1 work adds x.', foreignRef: 'tg-1'),
          'The work adds x.',
        );
      },
    );
  });

  group('PrComposition — the configurable knob (pow-8dx)', () {
    test('a custom trailer token re-tokens the footer', () {
      final body = const PrComposition(trailerToken: 'Bead').bodyOf(_context());
      expect(body.trimRight(), endsWith('Bead: tg-1'));
      expect(body, isNot(contains('Refs:')));
    });

    test(
      'a custom section list is honored (a receipt-only body — no trailer)',
      () {
        final body = const PrComposition(
          sections: [PrSection.circuitReceipt],
        ).bodyOf(_context(description: _inferred, titleSource: 'inference'));
        expect(body, contains('## Circuit receipt'));
        expect(body, isNot(contains('Refs: tg-1')));
        expect(body, isNot(contains('The land step now reads')));
      },
    );

    test('the describe model is a knob (cheap by default)', () {
      expect(const PrComposition().model, kDefaultDescribeModel);
      expect(const PrComposition(model: 'sonnet').model, 'sonnet');
    });
  });

  group('buildDescribePrompt — one-shot, diff-pinned, foreign-ref-forbidden', () {
    test(
      'carries the delta + the v1.0.0 rules + the no-foreign-reference rule, '
      'and asks for NO tool use',
      () {
        final prompt = buildDescribePrompt(
          bead: const Bead(
            id: 'tg-1',
            title: 'better titles',
            description: 'why',
          ),
          beadId: 'tg-1',
          baseBranch: 'main',
          commitLog: 'feat(x): do a thing',
          diffStat: ' lib/x.dart | 2 +-',
          diff: '--- a/lib/x.dart\n+++ b/lib/x.dart\n+the change',
        );
        expect(prompt, contains('do NOT run a tool'));
        expect(prompt, contains('IMPERATIVE MOOD'));
        expect(prompt, contains('NEVER write the tracker id `tg-1`'));
        expect(prompt, contains('`Refs:` git trailer'));
        expect(prompt, contains('+the change'));
        expect(prompt, contains('lib/x.dart | 2 +-'));
        expect(prompt, contains('CONTEXT ONLY'));
      },
    );

    test(
      'asks for a 2-5 sentence human digest, prose-only, and EXEMPLIFIES it in '
      'the answer object',
      () {
        final prompt = buildDescribePrompt(
          bead: const Bead(id: 'tg-1', title: 'better titles'),
          beadId: 'tg-1',
          baseBranch: 'main',
          commitLog: 'feat(x): do a thing',
          diffStat: ' lib/x.dart | 2 +-',
          diff: '+the change',
        );
        expect(prompt, contains('HUMAN DIGEST'));
        expect(prompt, contains('2 to 5 complete sentences'));
        expect(prompt, contains('NEVER opens the diff'));
        expect(prompt, contains('no heading, no bullet list, no code fence'));
        expect(prompt, contains('"summary":"The land step now reads its own'));
        // The old, weak contract ("a short paragraph or two, or bullets") is
        // GONE — the exemplar is the contract a model actually copies.
        expect(prompt, isNot(contains('or bullets')));
      },
    );
  });
}
