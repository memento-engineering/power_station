// The provenance stamp — format-aware, round-tripping, and LOUD on a file type
// it cannot stamp. The stamp is what lets a vended asset be COMMITTED rather
// than gitignored: it tells a generated file from a hand-authored one.
import 'dart:convert';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

const _skill = '---\nname: discover\n---\n\n# Discover\n\nbody\n';
const _settings = '{\n  "hooks": {\n    "SessionStart": []\n  }\n}\n';

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
}
