// The provenance stamp — format-aware, round-tripping, and LOUD on a file type
// it cannot stamp. The stamp is what lets a vended asset be COMMITTED rather
// than gitignored: it tells a generated file from a hand-authored one.
import 'dart:convert';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

const _skill = '---\nname: discover\n---\n\n# Discover\n\nbody\n';
const _settings = '{\n  "hooks": {\n    "SessionStart": []\n  }\n}\n';
const _instructions = '# Doctrine\n\nthe org rule\n';

/// [body] stamped as the owned root block, the way an install writes it.
String _rootBlock(String body, {String ref = 'abc1234'}) => stampProvenance(
  body,
  relativePath: kAgentsRootRelativePath,
  sourceRef: ref,
  runner: 'space',
);

void main() {
  group('stampProvenance', () {
    test(
      'a frontmatter-led .md keeps `---` on line 1 and carries a YAML comment '
      'on line 2 — the harness still parses the frontmatter',
      () {
        final stamped = stampProvenance(
          _skill,
          relativePath: '.claude/skills/discover/SKILL.md',
          sourceRef: 'abc1234',
          runner: 'space',
        );

        final lines = stamped.split('\n');
        expect(lines.first, '---');
        expect(lines[1], startsWith('# $kProvenanceMarker'));
        expect(lines[1], contains('abc1234'));
        expect(lines[1], contains('`space assets install`'));
        expect(lines[2], 'name: discover');
      },
    );

    test(
      'a JSON object carries a top-level field, stays VALID JSON, and preserves '
      "the operator's formatting byte-for-byte below it",
      () {
        final stamped = stampProvenance(
          _settings,
          relativePath: '.claude/settings.json',
          sourceRef: 'abc1234',
          runner: 'space',
        );

        final lines = stamped.split('\n');
        expect(lines.first, '{');
        expect(lines[1], startsWith(r'  "$generated": "'));
        expect(lines[1], endsWith('",'));
        expect(lines[2], '  "hooks": {');
        expect(
          (jsonDecode(stamped) as Map<String, dynamic>)[r'$generated'],
          contains('abc1234'),
        );
      },
    );

    test('stripProvenance is the exact inverse — the body round-trips', () {
      for (final (path, body) in const [
        ('.claude/skills/discover/SKILL.md', _skill),
        ('.claude/settings.json', _settings),
      ]) {
        final stamped = stampProvenance(
          body,
          relativePath: path,
          sourceRef: 'abc1234',
          runner: 'space',
        );
        expect(hasProvenance(stamped), isTrue);
        expect(stripProvenance(stamped), body, reason: '$path round-trips');
      }
    });

    test('an unstamped file has no provenance and strips to itself', () {
      expect(hasProvenance(_skill), isFalse);
      expect(stripProvenance(_skill), _skill);
    });

    test(
      'only the BODY decides drift — the same body under a DIFFERENT source ref '
      'strips to the same bytes, so a re-stamp never churns the tree',
      () {
        String strippedAt(String ref) => stripProvenance(
          stampProvenance(
            _skill,
            relativePath: '.claude/skills/discover/SKILL.md',
            sourceRef: ref,
            runner: 'space',
          ),
        );

        expect(strippedAt('ref1'), strippedAt('ref2'));
      },
    );
  });

  group('provenanceSyntaxFor — LOUD on an unstampable file', () {
    test('a file type with no provenance syntax THROWS, naming the path', () {
      expect(
        () => provenanceSyntaxFor('.claude/notes.txt', 'plain'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('no provenance syntax'), contains('notes.txt')),
          ),
        ),
      );
    });

    test(
      'a .md with NO frontmatter is refused too — a `#` line would read as a '
      'markdown heading, not a comment',
      () {
        expect(
          () => provenanceSyntaxFor('.claude/agents/x.md', '# Title\n'),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'a JSON shape the textual insertion cannot handle is refused rather than '
      'silently emitting invalid JSON',
      () {
        expect(
          () => stampProvenance(
            '{}\n',
            relativePath: '.claude/settings.json',
            sourceRef: 'abc1234',
            runner: 'space',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('would not leave valid JSON'),
            ),
          ),
        );
      },
    );
  });

  group('resolveOverlaySourceRefSync', () {
    test(
      'a dir that is not a git checkout resolves to the unknown ref, never a '
      'throw — an un-probable ref is not a packaging bug',
      () {
        expect(
          resolveOverlaySourceRefSync('/nonexistent-overlay-root'),
          kUnknownSourceRef,
        );
      },
    );
  });

  group('MarkedBlockProvenance root AGENTS.md only', () {
    test('the root file selects the marked syntax whatever its body opens on, '
        'and no other path does', () {
      for (final body in [_instructions, _skill, 'plain\n']) {
        expect(
          provenanceSyntaxFor(kAgentsRootRelativePath, body),
          isA<MarkedBlockProvenance>(),
        );
      }
      expect(
        provenanceSyntaxFor('.claude/skills/discover/SKILL.md', _skill),
        isA<YamlFrontmatterProvenance>(),
      );
      expect(
        provenanceSyntaxFor('.claude/settings.json', _settings),
        isA<JsonObjectProvenance>(),
      );
      expect(
        () => provenanceSyntaxFor('docs/AGENTS.md', _instructions),
        throwsA(isA<StateError>()),
        reason: 'the departure is bounded to the ROOT file',
      );
      expect(
        () => provenanceSyntaxFor('.agents/skills/x/NOTES.md', _instructions),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no provenance syntax'),
          ),
        ),
        reason: 'every OTHER plain markdown path is still refused',
      );
    });

    test('the owned block is the exact boundary lines, with the stamp as its '
        'FIRST interior line and the vended body below', () {
      final block = _rootBlock(_instructions);

      final lines = block.split('\n');
      expect(lines.first, kGeneratedBlockBegin);
      expect(lines[1], startsWith('<!-- $kProvenanceMarker'));
      expect(lines[1], contains('abc1234'));
      expect(lines[1], contains('`space assets install`'));
      expect(lines[1], endsWith('-->'));
      expect(lines[2], '# Doctrine');
      expect(lines[lines.length - 2], kGeneratedBlockEnd);
      expect(block, endsWith('$kGeneratedBlockEnd\n'));
      expect(hasProvenance(block), isTrue);
    });

    test('the vended body round-trips — through stripProvenance and through '
        'bodyOf, under any source ref', () {
      const marked = MarkedBlockProvenance();

      expect(stripProvenance(_rootBlock(_instructions)), _instructions);
      expect(marked.bodyOf(_rootBlock(_instructions)), _instructions);
      expect(
        stripProvenance(_rootBlock(_instructions, ref: 'ref1')),
        stripProvenance(_rootBlock(_instructions, ref: 'ref2')),
        reason: 'only the BODY decides drift',
      );
    });

    test('bodyOf claims ONE well-formed stamped block and refuses every other '
        'shape', () {
      const marked = MarkedBlockProvenance();
      final block = _rootBlock(_instructions);

      expect(
        marked.bodyOf('# theirs\n\n$block\ntail\n'),
        _instructions,
        reason: 'the block is claimed from inside a larger composed file',
      );
      expect(marked.bodyOf('# theirs\n'), isNull);
      expect(marked.bodyOf('$block$block'), isNull, reason: 'duplicated');
      expect(
        marked.bodyOf(
          '$kGeneratedBlockEnd\n$_instructions'
          '$kGeneratedBlockBegin\n',
        ),
        isNull,
        reason: 'out of order',
      );
      expect(
        marked.bodyOf(
          '$kGeneratedBlockBegin\n$_instructions$kGeneratedBlockEnd\n',
        ),
        isNull,
        reason: 'a hand-typed imitation carries no stamp on its first line',
      );
      expect(
        marked.bodyOf('$kGeneratedBlockBegin\n$kGeneratedBlockEnd\n'),
        isNull,
        reason: 'an empty block vended nothing',
      );
      expect(
        marked.bodyOf(
          'prefix $kGeneratedBlockBegin\nx\n'
          '$kGeneratedBlockEnd\n',
        ),
        isNull,
        reason: 'a marker that does not own its line is not ours',
      );
      expect(marked.containsAnyMarker('# theirs\n'), isFalse);
      expect(
        marked.containsAnyMarker('prefix $kGeneratedBlockBegin inline\n'),
        isTrue,
        reason: 'detection is LOOSER than ownership, so a trace is refusable',
      );
    });

    test('merge replaces only the owned span and preserves every byte around '
        'it, or appends when there is none', () {
      const marked = MarkedBlockProvenance();
      const prefix = '# Their doc\r\n\r\nkeep me\r\n';
      const suffix = '\n## after\n\ntail\n';
      final block = _rootBlock(_instructions);
      final next = _rootBlock('# Doctrine\n\nthe NEW rule\n');

      final replaced = marked.merge('$prefix$block$suffix', block: next);
      expect(replaced, '$prefix$next$suffix');
      expect(marked.bodyOf(replaced), '# Doctrine\n\nthe NEW rule\n');

      expect(marked.merge(prefix, block: block), '$prefix\n$block');
      expect(marked.merge('no newline', block: block), 'no newline\n\n$block');
      expect(marked.merge('spaced\n\n', block: block), 'spaced\n\n$block');
      expect(marked.merge('', block: block), block);
    });
  });
}
