// Conventional Commits v1.0.0 (bead pow-8dx) — the grammar, the sanitizer, the
// lint, the trailer composer. Pure: zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('ConventionalSubject.format', () {
    test('renders <type>[(scope)][!]: <description>', () {
      expect(
        const ConventionalSubject(
          type: 'feat',
          description: 'do a thing',
        ).format(),
        'feat: do a thing',
      );
      expect(
        const ConventionalSubject(
          type: 'fix',
          scope: 'landing',
          breaking: true,
          description: 'drop the legacy title',
        ).format(),
        'fix(landing)!: drop the legacy title',
      );
    });
  });

  group('lintConventionalSubject — the policy, machine-checked', () {
    test('a compliant subject has NO violations', () {
      expect(
        lintConventionalSubject(
          'feat(landing): infer the pr title from the branch diff',
          foreignRef: 'pow-8dx',
        ),
        isEmpty,
      );
    });

    test(
      'the legacy `grid: <bead>` shape is NOT conventional — an unknown type '
      'AND a foreign reference in the subject',
      () {
        final faults = lintConventionalSubject(
          'grid: tg-1',
          foreignRef: 'tg-1',
        );
        expect(faults, hasLength(2));
        expect(faults.first, contains('unknown type "grid"'));
        expect(faults.last, contains('foreign reference "tg-1"'));
      },
    );

    test('the inline `<type>(scope): <bead> — …` shape agents write today is a '
        'foreign-reference violation', () {
      expect(
        lintConventionalSubject(
          'feat(grid_assets): pow-8dx — add the thing',
          foreignRef: 'pow-8dx',
        ),
        contains(predicate<String>((f) => f.contains('foreign reference'))),
      );
    });

    test(
      'an uppercase description, a trailing period, and an over-long subject '
      'each violate',
      () {
        expect(
          lintConventionalSubject('feat: Add the thing.'),
          containsAll(<Matcher>[
            predicate<String>((f) => f.contains('not lowercase')),
            predicate<String>((f) => f.contains('ends with a period')),
          ]),
        );
        expect(
          lintConventionalSubject('feat: ${'x' * 80}'),
          contains(
            predicate<String>((f) => f.contains('max $kMaxSubjectChars')),
          ),
        );
      },
    );

    test('a subject that is not <type>: <description> at all fails whole', () {
      expect(lintConventionalSubject('just some prose'), hasLength(1));
      expect(
        lintConventionalSubject('just some prose').single,
        contains('not a conventional-commit subject'),
      );
    });
  });

  group('sanitizeConventionalSubject — compliant BY CONSTRUCTION', () {
    ConventionalSubject sanitize(String description, {String type = 'feat'}) =>
        sanitizeConventionalSubject(
          type: type,
          scope: 'landing',
          description: description,
          foreignRef: 'pow-8dx',
        );

    test('strips the bead id AND the separator it orphans', () {
      expect(
        sanitize('pow-8dx — infer the pr title').format(),
        'feat(landing): infer the pr title',
      );
      expect(
        sanitize('add pow-8dx#r2 support for x').description,
        'add support for x',
      );
    });

    test('lower-cases the description and drops a trailing period', () {
      expect(sanitize('Infer the pr title.').description, 'infer the pr title');
    });

    test(
      'ONLY the first letter is lower-cased — an acronym or an identifier '
      'mid-description keeps its case (`infer the PR title`, never `pr`)',
      () {
        final subject = sanitize('Infer the PR title from the branch diff.');
        expect(subject.description, 'infer the PR title from the branch diff');
        // Still compliant: the lint only forbids an UPPERCASE first letter.
        expect(
          lintConventionalSubject(subject.format(), foreignRef: 'pow-8dx'),
          isEmpty,
        );
      },
    );

    test('an unknown type falls back (never throws, never emits it)', () {
      expect(sanitize('do a thing', type: 'grid').type, 'chore');
      expect(
        sanitizeConventionalSubject(
          type: 'nonsense',
          description: 'do a thing',
          foreignRef: '',
          fallbackType: 'fix',
        ).type,
        'fix',
      );
    });

    test(
      'a long description is truncated at a WORD boundary so the whole subject '
      'fits kMaxSubjectChars',
      () {
        final subject = sanitize(
          'add a very long and rambling description that runs well past the '
          'seventy-two character subject budget git conventions expect',
        );
        expect(subject.format().length, lessThanOrEqualTo(kMaxSubjectChars));
        expect(subject.description, isNot(endsWith('-')));
        expect(
          lintConventionalSubject(subject.format(), foreignRef: 'pow-8dx'),
          isEmpty,
        );
      },
    );

    test('a description that sanitizes to NOTHING falls back, id-free', () {
      expect(sanitize('pow-8dx').description, kFallbackDescription);
    });

    test('every sanitized subject passes its own lint (the invariant)', () {
      for (final raw in const [
        'pow-8dx — Add a thing.',
        'GRID: do stuff',
        '   ',
        'pow-8dx',
        'Fix pow-8dx#r2, the regression.',
      ]) {
        final subject = sanitize(raw);
        expect(
          lintConventionalSubject(subject.format(), foreignRef: 'pow-8dx'),
          isEmpty,
          reason: 'sanitizing "$raw" must yield a compliant subject',
        );
      }
    });
  });

  group('composeCommitMessage + hasTrailer — the git-trailer policy', () {
    test('subject, body, BREAKING CHANGE, then the trailer — blank-line '
        'separated, footers LAST', () {
      final message = composeCommitMessage(
        subject: const ConventionalSubject(
          type: 'feat',
          scope: 'landing',
          breaking: true,
          description: 'infer the pr title',
        ),
        body: 'What changed and why.',
        breakingChange: 'the land commit message shape changed',
        trailers: const {'Refs': 'pow-8dx'},
      );
      expect(message, '''
feat(landing)!: infer the pr title

What changed and why.

BREAKING CHANGE: the land commit message shape changed
Refs: pow-8dx''');
      expect(hasTrailer(message), isTrue);
      expect(hasTrailer(message, token: 'Bead'), isFalse);
    });

    test('a bare subject + trailer (the land commit shape)', () {
      expect(
        composeCommitMessage(
          subject: const ConventionalSubject(
            type: 'chore',
            description: 'commit residual review changes',
          ),
          trailers: const {'Refs': 'tg-1'},
        ),
        'chore: commit residual review changes\n\nRefs: tg-1',
      );
    });

    test('a blank trailer value is dropped (never a dangling `Refs:`)', () {
      expect(
        composeCommitMessage(
          subject: const ConventionalSubject(type: 'chore', description: 'x'),
          trailers: const {'Refs': '  '},
        ),
        'chore: x',
      );
    });
  });
}
