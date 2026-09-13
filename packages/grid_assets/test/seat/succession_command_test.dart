// The `succession` verb — the successor's half of the handoff ritual.
//
// The defect it closes: the disc doctrine licenses deleting a consumed handoff
// on "the disc is tracked, so git history is the archive", and NOTHING enforced
// the tracked half. A seat whose disc had never been `git add`ed deleted its
// handoff into nothing, in the same turn that read it.
//
// Pins the acceptance:
//   - AC-1 a dirty disc is archived in a PATH-SCOPED commit before consume, and
//     unrelated staged paths stay staged and outside that commit;
//   - AC-2 two live handoffs — including a sibling written during the commit
//     window — refuse with exit 1, name both, and delete nothing;
//   - AC-3 exactly the one MEMORY.md pointer line whose link target is the
//     consumed basename is removed; every other byte survives;
//   - AC-4 --no-destructive still archives, exits 0, mutates nothing, and names
//     what it WOULD have deleted;
//   - AC-5 a disc with no handoff is a named no-op that never invokes git.
//
//   - AC-6 (pow-d5ol) an IGNORED disc archives LOCALLY instead — a
//     `.archive/<utc-stamp>/` directory under the disc holding both consumed
//     files byte-identical — and `git add -f` is never invoked on any path;
//   - RULING 2026-09-13 (governor) a second succession inside one UTC second
//     takes the next ORDINAL (`-2`, `-3`) instead of refusing, and every
//     succession PRUNES the local archives past the newest
//     `kSeatArchiveRetention` — names it did not write are never candidates,
//     and a prune that fails is reported without failing the succession.
//
// The archive/HEAD/unrelated-staging probes run against a REAL temporary git
// repository (nothing else can prove a path-scoped commit); the race, failure
// and no-call probes ride a recording Fake GitRunner (Fakes, not mocks).
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart' show GitRunner, SystemGitRunner;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/recording_git_runner.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('succession-');
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// The seat's disc directory, created on demand.
  Directory disc(String seat) =>
      Directory(p.join(home.path, '.grid', 'seats', seat))
        ..createSync(recursive: true);

  /// Writes one `kind: handoff` note and returns its file.
  File writeHandoff(String seat, String name, {String body = 'RESUME HERE'}) {
    final file = File(p.join(disc(seat).path, name));
    file.writeAsStringSync('---\nkind: handoff\nseat: $seat\n---\n\n$body\n');
    return file;
  }

  /// Writes the disc index.
  File writeMemory(String seat, String contents) =>
      File(p.join(disc(seat).path, 'MEMORY.md'))..writeAsStringSync(contents);

  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: home.path);
    expect(
      result.exitCode,
      0,
      reason: 'git ${args.join(' ')}: ${result.stderr}',
    );
  }

  /// A real repository at [home] with one commit, so `HEAD` resolves.
  Future<void> initRepository() async {
    await git(const ['init', '-q', '.']);
    await git(const ['config', 'user.email', 'succession@test']);
    await git(const ['config', 'user.name', 'Succession Test']);
    await git(const ['config', 'commit.gpgsign', 'false']);
    File(p.join(home.path, 'README.md')).writeAsStringSync('base\n');
    await git(const ['add', 'README.md']);
    await git(const ['commit', '-qm', 'base']);
  }

  Future<String> headTree() async {
    final result = await Process.run('git', const [
      'ls-tree',
      '-r',
      '--name-only',
      'HEAD',
    ], workingDirectory: home.path);
    return result.stdout as String;
  }

  Future<String> porcelain() async {
    final result = await Process.run('git', const [
      'status',
      '--porcelain',
    ], workingDirectory: home.path);
    return result.stdout as String;
  }

  /// Runs the verb through the real [CommandRunner] so argv parsing, the exit
  /// code and the rendered report are all under test.
  Future<({int code, String out, String err})> succession(
    List<String> argv, {
    GitRunner? runner,
    DateTime? archivedAt,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final command = CommandRunner<int>('space', 'test')
      ..addCommand(
        SuccessionCommand(
          service: SeatSuccessionService(
            runner: runner ?? SystemGitRunner(),
            now: () => archivedAt ?? DateTime.utc(2026, 9, 13, 17, 45, 1),
          ),
          out: out,
          err: err,
        ),
      );
    final code = await command.run(<String>['succession', ...argv]) ?? 0;
    return (code: code, out: out.toString(), err: err.toString());
  }

  group('AC-1 the disc is ARCHIVED before anything is destroyed', () {
    test('archives the dirty disc before deleting the handoff', () async {
      await initRepository();
      // The observed trap: the whole disc is UNTRACKED, live handoff included.
      final handoff = writeHandoff('refiner', 'handoff-a.md');
      writeMemory(
        'refiner',
        '# Memory index\n\n- [Handoff a](handoff-a.md) — hook\n',
      );
      // An unrelated staged path, which the scoped commit must not sweep up.
      File(p.join(home.path, 'unrelated.txt')).writeAsStringSync('mine\n');
      await git(const ['add', 'unrelated.txt']);

      final result = await succession(['refiner', '--grid-home', home.path]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('COMMITTED'));
      expect(
        result.out,
        contains(
          'DELETED ${p.join('.grid', 'seats', 'refiner', 'handoff-a.md')} AND '
          'MEMORY.md POINTER',
        ),
      );

      // The archive EXISTS: the deleted handoff is in HEAD.
      expect(await headTree(), contains('.grid/seats/refiner/handoff-a.md'));
      expect(handoff.existsSync(), isFalse);
      // …and the operator's unrelated work is still staged, still uncommitted.
      expect(await headTree(), isNot(contains('unrelated.txt')));
      expect(await porcelain(), contains('A  unrelated.txt'));
    });

    test('refuses when the archive cannot be proved at HEAD', () async {
      await initRepository();
      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [Handoff a](handoff-a.md) — hook\n');
      // A runner that reports a dirty tree, stages, then FAILS the commit —
      // exactly the shape of a rejecting pre-commit hook.
      final runner = RecordingGitRunner(
        statusOutput: '?? .grid/\n',
        fail: const {'commit', 'cat-file'},
      );

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: runner);

      expect(result.code, 1);
      expect(result.err, contains('REFUSED'));
      expect(result.err, contains('is not in HEAD'));
      expect(result.err, contains('staged: yes, committed: no'));
      expect(
        File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
        isTrue,
        reason: 'a run that cannot prove the archive destroys nothing',
      );
    });
  });

  group('AC-2 two live handoffs REFUSE and name both', () {
    test(
      'refuses two live handoffs and a newer commit-window sibling',
      () async {
        // (a) Two on the disc from the start: refused before any git call.
        writeHandoff('refiner', 'handoff-a.md');
        writeHandoff('refiner', 'handoff-b.md');
        writeMemory(
          'refiner',
          '- [a](handoff-a.md) — h\n- [b](handoff-b.md) — h\n',
        );
        final quiet = RecordingGitRunner();

        final two = await succession([
          'refiner',
          '--grid-home',
          home.path,
        ], runner: quiet);

        expect(two.code, 1);
        expect(two.err, contains('REFUSED'));
        expect(two.err, contains('2 live handoffs'));
        expect(
          two.err,
          contains(p.join('.grid', 'seats', 'refiner', 'handoff-a.md')),
        );
        expect(
          two.err,
          contains(p.join('.grid', 'seats', 'refiner', 'handoff-b.md')),
        );
        expect(quiet.calls, isEmpty, reason: 'refused before any git call');
        expect(
          File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(disc('refiner').path, 'handoff-b.md')).existsSync(),
          isTrue,
        );

        // (b) One on the disc, a sibling written DURING the commit window.
        File(p.join(disc('refiner').path, 'handoff-b.md')).deleteSync();
        writeMemory('refiner', '- [a](handoff-a.md) — h\n');
        final racing = RecordingGitRunner(
          statusOutput: '?? .grid/\n',
          duringCommit: () => writeHandoff('refiner', 'handoff-c.md'),
        );

        final raced = await succession([
          'refiner',
          '--grid-home',
          home.path,
        ], runner: racing);

        expect(raced.code, 1);
        expect(raced.err, contains('REFUSED'));
        expect(raced.err, contains('changed while it was being archived'));
        expect(
          raced.err,
          contains(p.join('.grid', 'seats', 'refiner', 'handoff-a.md')),
        );
        expect(
          raced.err,
          contains(p.join('.grid', 'seats', 'refiner', 'handoff-c.md')),
        );
        expect(
          File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(disc('refiner').path, 'handoff-c.md')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
          '- [a](handoff-a.md) — h\n',
        );
      },
    );
  });

  group('AC-3 only the matching MEMORY pointer line goes', () {
    test('removes only the matching MEMORY pointer line', () async {
      await initRepository();
      writeHandoff('governor', 'handoff-a.md');
      const memory =
          '# Memory index\n'
          '\n'
          '- [Lesson](lesson-x.md) — keep me\n'
          '- [Old](old-handoff-a.md) — a DIFFERENT target, keep me\n'
          '- [Handoff a](handoff-a.md) — take me\n'
          '- [Receipt](receipt-y.md) — keep me too\n';
      writeMemory('governor', memory);

      final result = await succession(['governor', '--grid-home', home.path]);

      expect(result.code, 0, reason: result.err);
      expect(
        File(p.join(disc('governor').path, 'MEMORY.md')).readAsStringSync(),
        '# Memory index\n'
        '\n'
        '- [Lesson](lesson-x.md) — keep me\n'
        '- [Old](old-handoff-a.md) — a DIFFERENT target, keep me\n'
        '- [Receipt](receipt-y.md) — keep me too\n',
        reason: 'every remaining byte survives, including a near-miss target',
      );
    });

    test('refuses when the index names the handoff zero or twice', () async {
      await initRepository();
      writeHandoff('governor', 'handoff-a.md');
      writeMemory(
        'governor',
        '# Memory index\n\n- [Lesson](lesson-x.md) — x\n',
      );

      final orphan = await succession(['governor', '--grid-home', home.path]);
      expect(orphan.code, 1);
      expect(orphan.err, contains('0 pointer lines'));

      writeMemory(
        'governor',
        '- [a](handoff-a.md) — one\n- [a again](handoff-a.md) — two\n',
      );
      final doubled = await succession(['governor', '--grid-home', home.path]);
      expect(doubled.code, 1);
      expect(doubled.err, contains('2 pointer lines'));
      expect(
        File(p.join(disc('governor').path, 'handoff-a.md')).existsSync(),
        isTrue,
      );
    });
  });

  group('AC-4 --no-destructive archives and NAMES, but destroys nothing', () {
    test('no-destructive commits and reports without deleting', () async {
      await initRepository();
      writeHandoff('refiner', 'handoff-a.md');
      const memory = '# Memory index\n\n- [Handoff a](handoff-a.md) — hook\n';
      writeMemory('refiner', memory);

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
        '--no-destructive',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('COMMITTED'));
      expect(
        result.out,
        contains(
          'WOULD DELETE ${p.join('.grid', 'seats', 'refiner', 'handoff-a.md')}',
        ),
      );
      expect(result.out, isNot(contains('DELETED ')));

      // Archived — and byte-identical.
      expect(await headTree(), contains('.grid/seats/refiner/handoff-a.md'));
      expect(
        File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
        memory,
      );
    });

    test('an already-archived disc reports ALREADY ARCHIVED', () async {
      await initRepository();
      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [a](handoff-a.md) — hook\n');
      await git(const ['add', '-A']);
      await git(const ['commit', '-qm', 'archive the disc by hand']);

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
        '--no-destructive',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('ALREADY ARCHIVED'));
      expect(result.out, isNot(contains('COMMITTED')));
    });
  });

  group('AC-5 an empty disc is a named no-op', () {
    test('no handoff is a clean no-op', () async {
      disc('refiner');
      writeMemory('refiner', '# Memory index\n');
      final runner = RecordingGitRunner();

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: runner);

      expect(result.code, 0, reason: result.err);
      expect(result.out.trim(), 'succession: refiner — NO HANDOFF');
      expect(runner.calls, isEmpty, reason: 'a no-op invokes no git');
      expect(
        File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
        '# Memory index\n',
      );
    });

    test(
      'a degraded git status is fail-closed, never an invented answer',
      () async {
        writeHandoff('refiner', 'handoff-a.md');
        writeMemory('refiner', '- [a](handoff-a.md) — hook\n');
        final warned = RecordingGitRunner(
          statusStderr:
              'warning: could not open directory: Permission denied\n',
        );

        final result = await succession([
          'refiner',
          '--grid-home',
          home.path,
        ], runner: warned);

        expect(result.code, 1);
        expect(result.err, contains('git work-tree gate would not clear'));
        expect(result.err, contains('staged: no, committed: no'));
        expect(
          warned.calls.first,
          const ['check-ignore', '-q', '--', '.grid/seats/refiner'],
          reason:
              'the archive SINK is resolved first: which archive this run '
              'would delete into decides whether git is touched at all',
        );
        expect(
          warned.calls[1],
          const ['rev-parse', '--show-toplevel', '--show-prefix'],
          reason:
              "GitOps' work-tree-ROOT guard runs before any other git MUTATION "
              '— a command run from a non-checkout would commit to the '
              'enclosing repository',
        );
        expect(
          File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('AC-6 an IGNORED disc archives LOCALLY, never with `git add -f`', () {
    // Measured 2026-09-13 on the live station: lunar_station 7b225e8 gitignored
    // `.grid/seats` for the PII a disc accretes, and every succession after it
    // refused — `could not stage the disc … The following paths are ignored`.
    // The archive moves under the ignore rather than forcing past it.
    test('copies both consumed files under .archive/<stamp>/ and deletes '
        'without one git mutation', () async {
      final note = writeHandoff('refiner', 'handoff-a.md');
      const memory = '# Memory index\n\n- [Handoff a](handoff-a.md) — hook\n';
      final noteBytes = note.readAsBytesSync();
      writeMemory('refiner', memory);
      final runner = RecordingGitRunner(ignored: true);

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: runner);

      expect(result.code, 0, reason: result.err);
      final stamp = p.join(
        '.grid',
        'seats',
        'refiner',
        '.archive',
        '20260913t174501z',
      );
      expect(result.out, contains('ARCHIVED-LOCAL $stamp'));
      expect(result.out, isNot(contains('COMMITTED')));
      expect(
        result.out,
        contains(
          'DELETED ${p.join('.grid', 'seats', 'refiner', 'handoff-a.md')} AND '
          'MEMORY.md POINTER',
        ),
      );

      // The archive holds BOTH files, byte-identical to what was destroyed.
      final archive = p.join(home.path, stamp);
      expect(
        File(p.join(archive, 'handoff-a.md')).readAsBytesSync(),
        noteBytes,
      );
      expect(File(p.join(archive, 'MEMORY.md')).readAsStringSync(), memory);

      // …and the disc no longer carries either.
      expect(note.existsSync(), isFalse);
      expect(
        File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
        '# Memory index\n\n',
      );

      // The ONLY git call is the fork probe: no add, no commit, and no force.
      expect(runner.calls.map((argv) => argv.first).toSet(), {'check-ignore'});
      expect(
        runner.calls.any(
          (argv) => argv.contains('-f') || argv.contains('--force'),
        ),
        isFalse,
        reason: 'git add -f would re-commit the PII the ignore exists for',
      );
      // The archived copies are in a SUBDIRECTORY, so the disc scan cannot see
      // them as a second live handoff.
      expect(
        SeatDisc(
          directory: disc('refiner').path,
          gridHome: home.path,
        ).handoffs(),
        isEmpty,
      );
    });

    test('--no-destructive archives locally and destroys nothing', () async {
      writeHandoff('refiner', 'handoff-a.md');
      const memory = '- [Handoff a](handoff-a.md) — hook\n';
      writeMemory('refiner', memory);

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
        '--no-destructive',
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('ARCHIVED-LOCAL'));
      expect(result.out, contains('WOULD DELETE'));
      expect(
        File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
        memory,
      );
    });

    // RULING 2026-09-13 (governor): a second succession inside one UTC second
    // takes an ORDINAL rather than refusing. Refusing stranded the seat on a
    // clock tick, and the launcher's relaunch loop is not paced by a human.
    test('a taken stamp takes the next ordinal, and both archives stay '
        'whole', () async {
      final taken = Directory(
        p.join(disc('refiner').path, '.archive', '20260913t174501z'),
      )..createSync(recursive: true);
      File(p.join(taken.path, 'handoff-a.md')).writeAsStringSync('FIRST\n');

      writeHandoff('refiner', 'handoff-b.md', body: 'SECOND');
      writeMemory('refiner', '- [b](handoff-b.md) — hook\n');

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('ARCHIVED-LOCAL'));
      expect(
        result.out,
        contains(
          p.join('.grid', 'seats', 'refiner', '.archive', '20260913t174501z-2'),
        ),
      );
      // The archive that was already there is untouched…
      expect(
        File(p.join(taken.path, 'handoff-a.md')).readAsStringSync(),
        'FIRST\n',
      );
      // …and the second one holds this run's note.
      expect(
        File(
          p.join(
            disc('refiner').path,
            '.archive',
            '20260913t174501z-2',
            'handoff-b.md',
          ),
        ).readAsStringSync(),
        contains('SECOND'),
      );
      expect(
        File(p.join(disc('refiner').path, 'handoff-b.md')).existsSync(),
        isFalse,
      );
    });

    test('a THIRD succession in the same second takes -3', () async {
      for (final name in const ['20260913t174501z', '20260913t174501z-2']) {
        Directory(
          p.join(disc('refiner').path, '.archive', name),
        ).createSync(recursive: true);
      }
      writeHandoff('refiner', 'handoff-c.md');
      writeMemory('refiner', '- [c](handoff-c.md) — hook\n');

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('20260913t174501z-3'));
    });
    test('a check-ignore that answers neither 0 nor 1 refuses', () async {
      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [a](handoff-a.md) — hook\n');
      final runner = RecordingGitRunner(checkIgnoreExitCode: 128);

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: runner);

      expect(result.code, 1);
      expect(result.err, contains('whether this disc is tracked is UNKNOWN'));
      expect(runner.calls.map((argv) => argv.first).toSet(), {'check-ignore'});
      expect(
        File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
        isTrue,
      );
    });
  });

  // RULING 2026-09-13 (governor): keep the newest ten, prune the rest on every
  // succession. Git history folds an archive away; a directory does not, and
  // the disc that earns this sink is the one a station ignored for PII.
  group('RETENTION keeps the newest ten local archives', () {
    /// Writes [count] archive directories, oldest first, each holding one
    /// file so a prune has something real to remove.
    List<String> seed(String seat, int count) {
      final names = <String>[
        for (var i = 0; i < count; i++)
          '202609${(10 + i ~/ 24).toString().padLeft(2, '0')}t'
              '${(i % 24).toString().padLeft(2, '0')}0000z',
      ];
      for (final name in names) {
        final directory = Directory(p.join(disc(seat).path, '.archive', name))
          ..createSync(recursive: true);
        File(p.join(directory.path, 'MEMORY.md')).writeAsStringSync(name);
      }
      return names;
    }

    test('a succession past the retention prunes the OLDEST and names '
        'them', () async {
      // Ten already there + the one this run writes = eleven, so exactly one
      // falls out.
      final seeded = seed('refiner', kSeatArchiveRetention);
      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [a](handoff-a.md) — hook\n');

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: result.err);
      expect(
        result.out,
        contains(
          'PRUNED 1 expired archive (keeping the newest '
          '$kSeatArchiveRetention): ${seeded.first}',
        ),
      );
      final archives = Directory(
        p.join(disc('refiner').path, '.archive'),
      ).listSync().map((entry) => p.basename(entry.path)).toSet();
      expect(archives.length, kSeatArchiveRetention);
      expect(archives, isNot(contains(seeded.first)));
      expect(archives, contains(seeded.last));
      expect(archives, contains('20260913t174501z'));
    });

    test(
      'a disc under the retention prunes nothing and says nothing',
      () async {
        seed('refiner', 3);
        writeHandoff('refiner', 'handoff-a.md');
        writeMemory('refiner', '- [a](handoff-a.md) — hook\n');

        final result = await succession([
          'refiner',
          '--grid-home',
          home.path,
        ], runner: RecordingGitRunner(ignored: true));

        expect(result.code, 0, reason: result.err);
        expect(result.out, isNot(contains('PRUNED')));
        expect(
          Directory(p.join(disc('refiner').path, '.archive')).listSync().length,
          4,
        );
      },
    );

    test('a directory this station did not write is never pruned', () async {
      seed('refiner', kSeatArchiveRetention);
      Directory(
        p.join(disc('refiner').path, '.archive', 'operator-notes'),
      ).createSync(recursive: true);
      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [a](handoff-a.md) — hook\n');

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: result.err);
      expect(
        Directory(
          p.join(disc('refiner').path, '.archive', 'operator-notes'),
        ).existsSync(),
        isTrue,
        reason: 'retention deletes only the names it wrote',
      );
    });

    test('a prune that FAILS is reported and does not fail the '
        'succession', () async {
      final seeded = seed('refiner', kSeatArchiveRetention);
      // The oldest archive is the one about to be pruned; a read-only
      // directory cannot have its child removed, so the recursive delete
      // fails while everything above it has already succeeded.
      final blocked = p.join(disc('refiner').path, '.archive', seeded.first);
      final chmod = await Process.run('chmod', ['500', blocked]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
      addTearDown(() => Process.run('chmod', ['700', blocked]));

      writeHandoff('refiner', 'handoff-a.md');
      writeMemory('refiner', '- [a](handoff-a.md) — hook\n');

      final result = await succession([
        'refiner',
        '--grid-home',
        home.path,
      ], runner: RecordingGitRunner(ignored: true));

      expect(result.code, 0, reason: 'housekeeping never fails a succession');
      expect(result.err, contains('PRUNE INCOMPLETE'));
      expect(result.err, contains(seeded.first));
      // The succession itself completed: the note and its pointer are gone.
      expect(
        File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(disc('refiner').path, 'MEMORY.md')).readAsStringSync(),
        isNot(contains('handoff-a.md')),
      );
    });
  });

  group('the argv adapter is thin and loud', () {
    test('a missing or extra seat name is a usage error', () async {
      final none = await succession(const <String>[]);
      expect(none.code, 64);
      expect(none.err, contains('exactly one seat name is required'));
      expect(none.err, contains('space succession <seat>'));

      final two = await succession(const ['a', 'b']);
      expect(two.code, 64);
    });

    test('--grid-home must be ABSOLUTE', () async {
      await expectLater(
        succession(const ['refiner', '--grid-home', 'relative/home']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('must be an ABSOLUTE path'),
          ),
        ),
      );
    });
  });

  group('the pointer-line composers are PURE', () {
    test('a pointer matches its EXACT link target only', () {
      const memory =
          '- [a](handoff-a.md)\n'
          '- [b](old-handoff-a.md)\n'
          '- [c](handoff-a.md.bak)\n'
          '- [d] (handoff-a.md)\n';
      expect(memoryPointerLines(memory: memory, target: 'handoff-a.md'), [0]);
    });

    test('removing a line disturbs no other byte', () {
      const memory = 'one\ntwo\nthree';
      expect(removeMemoryLine(memory: memory, index: 1), 'one\nthree');
      expect(removeMemoryLine(memory: memory, index: 2), 'one\ntwo\n');
      expect(removeMemoryLine(memory: memory, index: 9), memory);
    });
  });
}
