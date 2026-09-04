// The DESCRIBE MANIFEST — the bounded, deterministic facts the describe pass
// hands the model in place of the raw patch. Pure: no I/O.
import 'dart:convert';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The facts a small, ordinary branch produces.
DescribeManifest _small() => DescribeManifest(
  beadId: 'tg-1',
  beadTitle: 'better titles',
  baseBranch: 'main',
  intent: '- [ ] it works',
  commits: const ['feat(x): do a thing\n\nbecause reasons\n\nRefs: tg-1'],
  files: changedFilesFrom(
    nameStatus: 'M\x00lib/x.dart\x00A\x00test/x_test.dart\x00',
    numstat: '2\t1\tlib/x.dart\x0030\t0\ttest/x_test.dart\x00',
  ),
  shortstat: ' 2 files changed, 32 insertions(+), 1 deletion(-)',
  receipts: const [
    DescribeReceipt(
      label: 'validation',
      nodePath: 'tg-1/land/revalidate',
      result: {'rc': '0'},
    ),
    DescribeReceipt(
      label: 'committee',
      nodePath: 'tg-1/review/route',
      result: {'grades': 'A,A,B', 'spread': '1'},
    ),
  ],
);

void main() {
  group('changedFilesFrom — the git FACTS, never the patch', () {
    test('joins name-status with numstat, sorted, renames whole', () {
      final files = changedFilesFrom(
        nameStatus:
            'M\x00lib/b.dart\x00A\x00lib/a.dart\x00'
            'R096\x00lib/old.dart\x00lib/new.dart\x00D\x00lib/gone.dart\x00',
        numstat:
            '12\t3\tlib/b.dart\x0040\t0\tlib/a.dart\x00'
            '1\t1\t\x00lib/old.dart\x00lib/new.dart\x000\t9\tlib/gone.dart\x00',
      );
      expect(files.map((f) => f.path).toList(), [
        'lib/a.dart',
        'lib/b.dart',
        'lib/gone.dart',
        'lib/new.dart',
      ]);
      expect(files[1].status, 'M');
      expect(files[1].insertions, 12);
      expect(files[1].deletions, 3);
      expect(files[3].status, 'R');
      expect(files[3].fromPath, 'lib/old.dart');
      expect(files[3].insertions, 1);
    });

    test('a BINARY file reports null counts, never a fabricated zero', () {
      final files = changedFilesFrom(
        nameStatus: 'M\x00assets/logo.png\x00',
        numstat: '-\t-\tassets/logo.png\x00',
      );
      expect(files.single.insertions, isNull);
      expect(files.single.deletions, isNull);
    });

    test('a test file is recognized deterministically', () {
      final files = changedFilesFrom(
        nameStatus: 'A\x00test/x_test.dart\x00M\x00lib/x.dart\x00',
        numstat: '',
      );
      expect(files.where((f) => f.isTest).map((f) => f.path), [
        'test/x_test.dart',
      ]);
      expect(files.first.area, 'lib');
    });
  });

  group('buildDescribeManifest — stable, bounded, hunk-free', () {
    test('renders the five sections in a FIXED order, with counts and '
        'receipt provenance', () {
      final text = buildDescribeManifest(_small());
      final one = text.indexOf('## 1.');
      final two = text.indexOf('## 2.');
      final three = text.indexOf('## 3.');
      final four = text.indexOf('## 4.');
      final five = text.indexOf('## 5.');
      expect([
        one,
        two,
        three,
        four,
        five,
      ], everyElement(greaterThanOrEqualTo(0)));
      expect(one < two && two < three && three < four && four < five, isTrue);
      expect(text, contains('## 2. Commits — 1 total, in git order'));
      expect(text, contains('## 3. Files — 2 changed'));
      expect(
        text,
        contains(
          '- diffstat: 2 files changed, 32 insertions(+), 1 deletion(-)',
        ),
      );
      expect(text, contains('- M lib/x.dart +2 -1'));
      expect(text, contains('- A test/x_test.dart +30 -0'));
      expect(text, contains('- observed (git): 2 changed files (1 test)'));
      expect(text, contains('- areas (2 total): lib, test'));
      expect(
        text,
        contains('- validation: rc=0 [from `tg-1/land/revalidate`]'),
      );
      expect(
        text,
        contains(
          '- committee: grades=A,A,B spread=1 [from `tg-1/review/route`]',
        ),
      );
    });

    test('the SAME facts render byte-identically', () {
      expect(buildDescribeManifest(_small()), buildDescribeManifest(_small()));
    });

    test('carries NO raw diff and NO patch hunk', () {
      final text = buildDescribeManifest(_small());
      expect(text, isNot(contains('@@')));
      expect(text, isNot(contains('diff --git')));
      expect(text, isNot(contains('\n+++')));
      expect(text, isNot(contains('\n+the change')));
    });

    test('an absent receipt is SAID, never invented', () {
      final text = buildDescribeManifest(
        const DescribeManifest(
          beadId: 'tg-1',
          beadTitle: 'no receipts yet',
          baseBranch: 'main',
        ),
      );
      expect(text, contains('- (no receipts available)'));
      expect(text, contains('- diffstat: (none reported)'));
      expect(text, contains('- acceptance: (none recorded)'));
    });

    test('a VERY LARGE branch truncates at record boundaries under 16 KiB, '
        'and every REQUIRED line survives', () {
      final nameStatus = StringBuffer();
      final numstat = StringBuffer();
      for (var i = 0; i < 900; i++) {
        nameStatus.write('M\x00packages/grid_assets/lib/src/code/f$i.dart\x00');
        numstat.write('$i\t$i\tpackages/grid_assets/lib/src/code/f$i.dart\x00');
      }
      final text = buildDescribeManifest(
        DescribeManifest(
          beadId: 'tg-1',
          beadTitle: 'huge',
          baseBranch: 'main',
          commits: [
            for (var i = 0; i < 400; i++)
              'feat(x): commit number $i\n\n${'body ' * 80}',
          ],
          files: changedFilesFrom(
            nameStatus: nameStatus.toString(),
            numstat: numstat.toString(),
          ),
          shortstat: ' 900 files changed, 1 insertion(+)',
          receipts: const [
            DescribeReceipt(
              label: 'committee',
              nodePath: 'tg-1/review/route',
              result: {'grades': 'A'},
            ),
          ],
        ),
      );
      expect(utf8.encode(text).length, lessThanOrEqualTo(16 * 1024));
      // The counts survive truncation, and say how much was dropped.
      expect(text, contains('## 2. Commits — 400 total, in git order'));
      expect(text, contains('## 3. Files — 900 changed'));
      expect(text, contains('- diffstat: 900 files changed, 1 insertion(+)'));
      expect(text, matches(RegExp(r'… \d+ of 400 commit records omitted')));
      expect(text, matches(RegExp(r'… \d+ of 900 file records omitted')));
      expect(text, contains('- observed (git): 900 changed files (0 test)'));
      expect(
        text,
        contains('- committee: grades=A [from `tg-1/review/route`]'),
      );
      // Record boundary: every admitted file line is a WHOLE record —
      // `- <status> <path> +N -N` (or `(binary)`). A record cut mid-way by
      // the byte budget could not match.
      final record = RegExp(r'^- M \S+ (\+\d+ -\d+|\(binary\))$');
      for (final line in const LineSplitter().convert(text)) {
        if (!line.startsWith('- M packages/')) continue;
        expect(line, matches(record));
      }
    });

    test('REQUIRED lines alone over the ceiling still clamp to 16 KiB', () {
      final text = buildDescribeManifest(
        DescribeManifest(
          beadId: 'tg-1',
          beadTitle: 'huge headers',
          baseBranch: 'main',
          receipts: [
            for (var i = 0; i < 400; i++)
              DescribeReceipt(
                label: 'receipt-$i',
                nodePath: 'tg-1/node/$i',
                result: {for (var k = 0; k < 12; k++) 'key$k': 'v' * 120},
              ),
          ],
        ),
      );
      expect(utf8.encode(text).length, lessThanOrEqualTo(16 * 1024));
    });
  });
}
