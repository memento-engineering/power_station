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
// The archive/HEAD/unrelated-staging probes run against a REAL temporary git
// repository (nothing else can prove a path-scoped commit); the race, failure
// and no-call probes ride a recording Fake GitRunner (Fakes, not mocks).
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GitRunResult, GitRunner, SystemGitRunner;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A [GitRunner] that RECORDS every argv and answers from canned outcomes,
/// with an optional side effect fired on a chosen subcommand — how the
/// commit-window race is staged deterministically.
class _RecordingGitRunner implements GitRunner {
  _RecordingGitRunner({
    this.fail = const <String>{},
    this.duringCommit,
    this.statusOutput = '',
    this.statusStderr = '',
  });

  /// The first argv token of every call that must answer NOT ok.
  final Set<String> fail;

  /// Fired immediately before `git commit` answers — the commit window.
  final void Function()? duringCommit;

  /// What `git status --porcelain` reports (empty ⇒ a clean tree).
  final String statusOutput;

  /// What `git status --porcelain` writes on stderr (non-empty ⇒ a degraded
  /// scan, which [GitOps.hasUncommittedWork] fails closed on).
  final String statusStderr;

  /// Every argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    if (args.first == 'commit') duringCommit?.call();
    if (fail.contains(args.first)) {
      return GitRunResult(exitCode: 1, output: 'refused: ${args.join(' ')}');
    }
    return switch (args.first) {
      'rev-parse' => GitRunResult(exitCode: 0, output: '$workingDirectory\n\n'),
      'status' => GitRunResult(
        exitCode: 0,
        output: statusOutput,
        stderr: statusStderr,
      ),
      _ => const GitRunResult(exitCode: 0, output: ''),
    };
  }
}

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
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final command = CommandRunner<int>('space', 'test')
      ..addCommand(
        SuccessionCommand(
          service: SeatSuccessionService(runner: runner ?? SystemGitRunner()),
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
      final runner = _RecordingGitRunner(
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
        final quiet = _RecordingGitRunner();

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
        final racing = _RecordingGitRunner(
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
      final runner = _RecordingGitRunner();

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
        final warned = _RecordingGitRunner(
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
          const ['rev-parse', '--show-toplevel', '--show-prefix'],
          reason:
              "GitOps' work-tree-ROOT guard runs before any other git call — a "
              'command run from a non-checkout would commit to the enclosing '
              'repository',
        );
        expect(
          File(p.join(disc('refiner').path, 'handoff-a.md')).existsSync(),
          isTrue,
        );
      },
    );
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
