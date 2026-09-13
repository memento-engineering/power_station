// The seat disc's INDEX INVARIANT — `MEMORY.md` covers the notes beside it.
//
// The defect it closes, with the receipt: on 2026-09-12 at 06:24 CDT the
// governor seat banked ONE lesson and its index went from 77 pointer lines to
// 1 (commit 72d4d92 in the lunar_station grid home: 1 insertion, 78 deletions,
// @@ -1,79 +1,2 @@). The seat rewrote its OWN index wholesale while appending
// one entry — replace where append was meant, the failure the house already
// knows from `bd --notes` versus `--append-notes`, on a different surface. The
// note FILES survived: the disc held 81 markdown files and the index named 2.
// Seventy-nine banked lessons were on disk and unreachable, because the index
// is the only thing that makes a disc note findable. Nothing failed, nothing
// warned, and it was found by accident four hours later.
//
// Pins the acceptance:
//   - AC-1 omitted and multiply-indexed persistent notes are ALL named, never
//     just the first;
//   - AC-2 a pointer target that is no file on the disc is named structurally
//     and in prose;
//   - AC-3 the 77-plus-1 fixture ends with 78 pointer lines, not 1;
//   - AC-4 `kind: handoff` is exempt — a consumed note is indexed for exactly
//     one succession, and `succession_command_test.dart` is what pins that half;
//   - AC-5 the check is READ-ONLY: byte snapshots of a clean and a failing disc
//     survive it unchanged, and the disc API grew no writer;
//   - AC-6 every fixture is its own system-temporary grid home.
//
// Pure-Dart, offline: files in a temp dir and one source read. No git, no cwd.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// A disc under its OWN temporary grid home, deleted with the test (AC-6).
///
/// Never a real `.grid/seats/` path: this suite reads and writes discs, and a
/// live station's disc is the operator's memory.
SeatDisc _disc({String seat = 'governor'}) {
  final home = Directory.systemTemp.createTempSync('seat-disc-integrity-');
  addTearDown(() => home.deleteSync(recursive: true));
  final disc = SeatDisc(
    directory: seatDiscPath(home.path, seat),
    gridHome: home.path,
  );
  disc.ensure();
  return disc;
}

/// Writes one disc note of [kind] — the shape
/// `the_grid#agent-disc-file-shape-and-home` fixes.
void _note(SeatDisc disc, String name, {String kind = 'lesson'}) {
  File(p.join(disc.directory, name)).writeAsStringSync(
    '---\n'
    'name: ${p.basenameWithoutExtension(name)}\n'
    'description: one banked fact\n'
    'seat: governor\n'
    'date: 2026-09-12\n'
    'kind: $kind\n'
    '---\n'
    '\n'
    'The fact.\n',
  );
}

/// Writes the index: its title line, then one pointer line per entry of
/// [targets] — `- [Title](file.md) — hook`.
void _index(SeatDisc disc, Iterable<String> targets) {
  File(p.join(disc.directory, kSeatMemoryFileName)).writeAsStringSync(
    <String>[
      '# Governor disc',
      '',
      for (final target in targets) '- [$target]($target) — a hook',
      '',
    ].join('\n'),
  );
}

/// Every file under [disc], relative path to bytes — the whole disc, so a write
/// anywhere in it is visible and not merely a change to a file we thought of.
Map<String, List<int>> _snapshot(SeatDisc disc) => <String, List<int>>{
  for (final entity in Directory(disc.directory).listSync(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: disc.directory): entity.readAsBytesSync(),
};

/// The index's lines that carry a Markdown link — what the 2026-09-12 loss took
/// 78 of, counted the way a reader of the file would.
int _pointerLineCount(SeatDisc disc) => File(
  p.join(disc.directory, kSeatMemoryFileName),
).readAsLinesSync().where((line) => line.contains('](')).length;

void main() {
  group('the index must COVER the disc', () {
    test('a clean disc verifies', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'b-lesson.md');
      _index(disc, const ['a-lesson.md', 'b-lesson.md']);

      expect(disc.verifyIndexIntegrity, returnsNormally);
    });

    test('EVERY unindexed note is named, not just the first', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'b-lesson.md');
      _note(disc, 'c-lesson.md');
      _index(disc, const ['a-lesson.md']);

      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>()
              .having((e) => e.unindexedFiles, 'unindexedFiles', const <String>[
                'b-lesson.md',
                'c-lesson.md',
              ])
              .having((e) => e.missingTargets, 'missingTargets', isEmpty)
              .having(
                (e) => e.multiplyIndexedFiles,
                'multiplyIndexedFiles',
                isEmpty,
              )
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('b-lesson.md'),
                  contains('c-lesson.md'),
                  contains('NOT INDEXED'),
                ),
              ),
        ),
      );
    });

    test('a note TWO pointer lines name is reported', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _index(disc, const ['a-lesson.md', 'a-lesson.md']);

      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>()
              .having(
                (e) => e.multiplyIndexedFiles,
                'multiplyIndexedFiles',
                const <String>['a-lesson.md'],
              )
              .having((e) => e.unindexedFiles, 'unindexedFiles', isEmpty)
              .having(
                (e) => e.toString(),
                'message',
                contains('INDEXED MORE THAN ONCE'),
              ),
        ),
      );
    });

    test('a pointer at no file on the disc is named (AC-2)', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _index(disc, const ['a-lesson.md', 'deleted-lesson.md']);

      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>()
              .having((e) => e.missingTargets, 'missingTargets', const <String>[
                'deleted-lesson.md',
              ])
              .having(
                (e) => e.toString(),
                'message',
                allOf(contains('deleted-lesson.md'), contains('MISSING')),
              ),
        ),
      );
    });

    test('a pointer that leaves the disc is a pointer at no note', () {
      // The index's grammar is one disc-LOCAL file name per line, so a target
      // a reader cannot follow to a note on this disc is reported even when
      // some file of that basename exists somewhere.
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _index(disc, const <String>[]);
      File(p.join(disc.directory, kSeatMemoryFileName)).writeAsStringSync(
        '# Governor disc\n'
        '\n'
        '- [a](a-lesson.md) — the one followable line\n'
        '- [b](sub/a-lesson.md) — a directory part\n'
        '- [c](https://example.test/a-lesson.md) — off the disc entirely\n',
      );

      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>().having(
            (e) => e.missingTargets,
            'missingTargets',
            const <String>[
              'https://example.test/a-lesson.md',
              'sub/a-lesson.md',
            ],
          ),
        ),
      );
    });

    test('all three faults are collected in ONE scan', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'b-lesson.md');
      _note(disc, 'c-lesson.md');
      _index(disc, const [
        'a-lesson.md',
        'a-lesson.md',
        'b-lesson.md',
        'gone-lesson.md',
      ]);

      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>()
              .having((e) => e.unindexedFiles, 'unindexedFiles', const <String>[
                'c-lesson.md',
              ])
              .having((e) => e.missingTargets, 'missingTargets', const <String>[
                'gone-lesson.md',
              ])
              .having(
                (e) => e.multiplyIndexedFiles,
                'multiplyIndexedFiles',
                const <String>['a-lesson.md'],
              ),
        ),
      );
    });

    test('the report is frozen and sorted, whatever the scan order', () {
      final thrown = SeatDiscIntegrityException(
        directory: '/tmp/disc',
        unindexedFiles: const <String>['z.md', 'a.md'],
      );
      expect(thrown.unindexedFiles, const <String>['a.md', 'z.md']);
      expect(() => thrown.unindexedFiles.add('b.md'), throwsUnsupportedError);
      expect(thrown.toString(), thrown.toString());
      expect(thrown.toString(), contains('/tmp/disc'));
    });
  });

  group('the consumed kind is exempt', () {
    test('a handoff-only disc with no index verifies (AC-4)', () {
      final disc = _disc();
      _note(disc, 'handoff-2026-09-12.md', kind: 'handoff');

      expect(disc.verifyIndexIntegrity, returnsNormally);
    });

    test('an empty disc, and one with no index at all, verify', () {
      expect(_disc().verifyIndexIntegrity, returnsNormally);

      final unindexed = _disc();
      _note(unindexed, 'a-lesson.md');
      expect(
        unindexed.verifyIndexIntegrity,
        throwsA(isA<SeatDiscIntegrityException>()),
        reason: 'an absent index is EMPTY, so a persistent note is uncovered',
      );
    });

    test('a handoff needs no pointer line while its siblings do', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'handoff-2026-09-12.md', kind: 'handoff');
      _index(disc, const ['a-lesson.md']);

      expect(disc.verifyIndexIntegrity, returnsNormally);
    });

    test('a disc that does not exist verifies rather than throwing', () {
      final home = Directory.systemTemp.createTempSync('seat-disc-absent-');
      addTearDown(() => home.deleteSync(recursive: true));
      final disc = SeatDisc(
        directory: seatDiscPath(home.path, 'never-occupied'),
        gridHome: home.path,
      );

      expect(Directory(disc.directory).existsSync(), isFalse);
      expect(disc.verifyIndexIntegrity, returnsNormally);
    });
  });

  group('the 2026-09-12 loss', () {
    test('banking one lesson leaves 78 pointer lines, not 1 (AC-3)', () {
      final disc = _disc();
      final banked = <String>[
        for (var i = 0; i < 77; i++)
          'lesson-${i.toString().padLeft(3, '0')}.md',
      ];
      for (final name in banked) {
        _note(disc, name);
      }
      _index(disc, banked);
      expect(_pointerLineCount(disc), 77);
      expect(disc.verifyIndexIntegrity, returnsNormally);

      // The bank: the note, then its pointer line APPENDED — the one motion
      // the 06:24 rewrite replaced the whole file with.
      const arrival = 'lesson-078.md';
      _note(disc, arrival);
      File(p.join(disc.directory, kSeatMemoryFileName)).writeAsStringSync(
        '- [$arrival]($arrival) — a hook\n',
        mode: FileMode.append,
      );

      expect(_pointerLineCount(disc), 78);
      final memory = File(
        p.join(disc.directory, kSeatMemoryFileName),
      ).readAsStringSync();
      expect(
        memory,
        startsWith('# Governor disc'),
        reason: 'the disc title line went with the 76 lost pointers',
      );
      for (final name in <String>[...banked, arrival]) {
        expect(memoryPointerLines(memory: memory, target: name), hasLength(1));
      }
      expect(disc.verifyIndexIntegrity, returnsNormally);
    });

    test('the wholesale rewrite itself is caught', () {
      final disc = _disc();
      final banked = <String>[
        for (var i = 0; i < 77; i++)
          'lesson-${i.toString().padLeft(3, '0')}.md',
      ];
      for (final name in banked) {
        _note(disc, name);
      }
      _index(disc, banked);

      // Exactly what commit 72d4d92 did: one entry REPLACING the index.
      const arrival = 'lesson-078.md';
      _note(disc, arrival);
      _index(disc, const [arrival]);

      expect(_pointerLineCount(disc), 1);
      expect(
        disc.verifyIndexIntegrity,
        throwsA(
          isA<SeatDiscIntegrityException>().having(
            (e) => e.unindexedFiles,
            'unindexedFiles',
            hasLength(77),
          ),
        ),
      );
    });
  });

  group('verification never writes', () {
    test('a clean disc is byte-identical after the scan (AC-5)', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'handoff-2026-09-12.md', kind: 'handoff');
      _index(disc, const ['a-lesson.md']);

      final before = _snapshot(disc);
      disc.verifyIndexIntegrity();
      expect(_snapshot(disc), before);
    });

    test('a FAILING disc is byte-identical after the scan (AC-5)', () {
      final disc = _disc();
      _note(disc, 'a-lesson.md');
      _note(disc, 'b-lesson.md');
      _index(disc, const ['gone-lesson.md']);

      final before = _snapshot(disc);
      expect(
        disc.verifyIndexIntegrity,
        throwsA(isA<SeatDiscIntegrityException>()),
      );
      expect(_snapshot(disc), before);
      expect(
        before.keys,
        containsAll(<String>[
          'a-lesson.md',
          'b-lesson.md',
          kSeatMemoryFileName,
        ]),
        reason: 'a refusal REPAIRS nothing — the drifted index is still there',
      );
    });

    test('the disc source vends NO writer beyond ensure()', () {
      // AC-5's other half, and the ruling that this ships as a CHECK: the disc
      // detects index drift and never banks, appends or repairs. A source fence
      // because a behavioural test can only prove the writers it thought of.
      final source = File(
        p.join(packageRoot(), 'lib', 'src', 'seat', 'seat_disc.dart'),
      ).readAsStringSync();

      for (final writer in const <String>[
        'writeAsString',
        'writeAsBytes',
        'openWrite',
        'FileMode.append',
        'deleteSync',
        'renameSync',
      ]) {
        expect(
          source,
          isNot(contains(writer)),
          reason: '$writer would make the disc a writer',
        );
      }
      expect(
        source.contains('createSync(recursive: true)'),
        isTrue,
        reason: 'ensure() is the ONE mutation, and this fence stays honest',
      );
    });
  });
}
