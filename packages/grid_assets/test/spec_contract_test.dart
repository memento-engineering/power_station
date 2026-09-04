// The spec's line-oriented RECORD grammar — the deterministic contract one
// level below the section-presence gate.
//
// Proves: `proseOnly` preserves its input's LINE COUNT (so a record finding
// names the spec's OWN line).
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
}
