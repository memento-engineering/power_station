// The LOCAL archive's naming and retention arithmetic — the pure half of the
// sink an IGNORED disc archives into.
//
// The defect the sink itself closes is pinned in `succession_command_test.dart`
// (pow-d5ol AC-6). Two of its rules are arithmetic rather than filesystem, and
// the filesystem suite cannot reach their edges without staging absurd discs:
//
//   - RULING 2026-09-13 (governor) two successions inside one UTC second take
//     the next ORDINAL rather than refusing — the stamp has second resolution
//     and the launcher's relaunch loop is not paced by a human;
//   - RULING 2026-09-13 (governor) a disc keeps the newest
//     `kSeatArchiveRetention` archives and prunes the rest. The ordering that
//     decides WHICH is the newest is the edge: `<stamp>-10` sorts before
//     `<stamp>-2` as a string, so a string compare would prune the newest
//     archive on a disc that took ten successions in one second.
//
// Pure Dart: no files, no clock, no git.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('an archive directory NAME carries its stamp and its ordinal', () {
    test('ordinal 1 is the bare stamp; 2 and up take a suffix', () {
      expect(
        seatArchiveDirectoryName('20260913t174501z', 1),
        '20260913t174501z',
      );
      expect(
        seatArchiveDirectoryName('20260913t174501z', 2),
        '20260913t174501z-2',
      );
      expect(
        seatArchiveDirectoryName('20260913t174501z', 11),
        '20260913t174501z-11',
      );
      expect(
        seatArchiveDirectoryName('20260913t174501z', 0),
        '20260913t174501z',
        reason: 'a non-positive ordinal is the first archive, never "-0"',
      );
    });

    test('every name this station writes parses back to what wrote it', () {
      for (var ordinal = 1; ordinal <= 12; ordinal++) {
        final name = seatArchiveDirectoryName('20260913t174501z', ordinal);
        expect(parseSeatArchiveDirectoryName(name), (
          stamp: '20260913t174501z',
          ordinal: ordinal,
        ), reason: name);
      }
    });

    test('a name this station did NOT write parses to null — retention '
        'deletes, so an unrecognised directory is never a candidate', () {
      for (final name in const [
        'operator-notes',
        '',
        '.',
        '..',
        '20260913t174501z-0',
        '20260913t174501z-1',
        '20260913t174501z-02',
        '20260913t174501z-',
        '20260913t174501z-x',
        '20260913T174501Z',
        '2026091t174501z',
        '20260913t17450z',
        'handoff-20260913t174501z-slug.md',
      ]) {
        expect(
          parseSeatArchiveDirectoryName(name),
          isNull,
          reason: '"$name" is not a name this station wrote',
        );
      }
    });
  });

  group('RETENTION names the archives that fall outside the newest ten', () {
    /// [count] archive names, oldest first.
    List<String> stamps(int count) => <String>[
      for (var i = 0; i < count; i++)
        '2026${(9 + i ~/ 28).toString().padLeft(2, '0')}'
            '${(1 + i % 28).toString().padLeft(2, '0')}t120000z',
    ];

    test('a disc at or under the retention prunes nothing', () {
      for (var count = 0; count <= kSeatArchiveRetention; count++) {
        expect(seatArchivesToPrune(stamps(count)), isEmpty, reason: '$count');
      }
    });

    test('a disc over the retention prunes the OLDEST, oldest first', () {
      final names = stamps(kSeatArchiveRetention + 3);
      expect(seatArchivesToPrune(names), names.take(3).toList());
    });

    test('the input order does not decide the outcome', () {
      final names = stamps(kSeatArchiveRetention + 2);
      expect(
        seatArchivesToPrune(names.reversed),
        names.take(2).toList(),
        reason: 'the directory listing order is the filesystem\'s, not ours',
      );
    });

    test('ORDINALS order numerically, so ten successions in one second do '
        'not prune the newest', () {
      // The string trap: "<stamp>-10" < "<stamp>-2" lexicographically.
      final names = <String>[
        for (var ordinal = 1; ordinal <= kSeatArchiveRetention + 2; ordinal++)
          seatArchiveDirectoryName('20260913t174501z', ordinal),
      ];
      expect(seatArchivesToPrune(names), <String>[
        '20260913t174501z',
        '20260913t174501z-2',
      ]);
    });

    test('a stamp sorts before its own ordinals, and an older stamp before '
        'a newer one', () {
      expect(
        seatArchivesToPrune(const <String>[
          '20260914t090000z',
          '20260913t174501z-2',
          '20260913t174501z',
        ], keep: 1),
        const <String>['20260913t174501z', '20260913t174501z-2'],
      );
    });

    test('names it did not write are dropped, never returned', () {
      expect(
        seatArchivesToPrune(const <String>[
          'operator-notes',
          'README.md',
          '20260901t120000z',
          '20260902t120000z',
        ], keep: 1),
        const <String>['20260901t120000z'],
      );
    });

    test('keep: 0 prunes everything it recognises', () {
      final names = stamps(3);
      expect(seatArchivesToPrune(names, keep: 0), names);
    });
  });
}
