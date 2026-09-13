// The handoff's WRITE edge — the constraint that makes a handoff working
// memory rather than a running log.
//
// The defect it closes, measured 2026-09-12 by counting commits per handoff
// file: the governor's `handoff-20260912t042326z-epoch-69-first-night.md` was
// rewritten across THIRTY commits between 23:25 and 08:45 — nine hours — while
// every refiner handoff carried exactly two (one create, one delete-on-consume,
// the correct lifecycle). The asymmetry was structural: CONSUMING a handoff was
// already a verb and already enforced, while WRITING one was a skill — prose an
// agent may follow or not — and nothing refused a second write.
//
// Pins the acceptance:
//   - AC-1 the first write lands; a second is refused loudly, names the live
//     note, and says to consume it through succession before writing a new one;
//   - AC-2 no note kind is added — a `kind: journal` candidate is refused and
//     creates no file;
//   - AC-3 the stamped note keeps its bytes AND its modification time through a
//     refused later write, so the stamp in its own file name cannot go stale;
//   - AC-4 `seat`, `prime` and `succession --no-destructive` each render how
//     long an unconsumed handoff has sat there, with no threshold behind it;
//   - AC-6 the composed `succession <seat> --write-handoff <file>` surface
//     writes once from stdin and exits 1 on the second invocation.
//
// Offline: system-temporary discs, real `CommandRunner` invocations, and Fakes
// only for the injected stdin, process, git and clock seams. No harness, no
// `bd`, no network.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The live governor note this bead was filed on — the file whose own UTC stamp
/// was falsified by nine hours of amendment.
const String kEpoch69 = 'handoff-20260912t042326z-epoch-69-first-night.md';

/// The instant that file name claims, as a local wall clock: what its stamp
/// would have meant if it had been written once.
final DateTime kEpoch69Stamped = DateTime(2026, 9, 11, 23, 25);

/// The last write that note actually took: 08:45 the next morning, nine hours
/// after it was named. Every AC-4 reader is fixed here.
final DateTime kNineHoursOn = kEpoch69Stamped.add(const Duration(hours: 9));

/// A harness process that never runs: records the plan and returns 0.
final class _RecordingSeatRunner {
  final launches = <SeatLaunch>[];

  Future<int> call(SeatLaunch launch) async {
    launches.add(launch);
    return 0;
  }
}

/// The one TTY environment the seat probes occupy.
const _declared = AgentEnvironment(
  command: 'harness',
  argsAppend: ['--kept'],
  promptMode: PromptMode.flag,
  promptFlag: '-p',
  roleAsset: '.roles/$kSeatHole.md',
  roleArgs: ['--role', kSeatHole],
  memoryDirArgs: ['--memory', kMemoryDirHole],
  // Prompt priming, so the handoff BODY is observable in the plan: the age
  // diagnostic must sit beside the note, never in place of it.
  primeMode: SeatPrimeMode.prompt,
);

const _registry = EnvironmentRegistry(custom: {'declared': _declared});

/// A `bd` that answers with a fixed hook object (Fakes, not mocks).
final class _FakeBd implements BdRunner {
  _FakeBd(this.stdout);
  final String stdout;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async => BdResult(exitCode: 0, stdout: stdout, stderr: '');
}

/// A `git` that reports a CLEAN work-tree root and answers every proof — so
/// `--no-destructive` reaches its preview without a real repository, and the
/// probe measures the diagnostic rather than git.
final class _CleanGitRunner implements GitRunner {
  final calls = <List<String>>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    return switch (args.first) {
      'rev-parse' => GitRunResult(exitCode: 0, output: '$workingDirectory\n\n'),
      _ => const GitRunResult(exitCode: 0, output: ''),
    };
  }
}

/// A complete disc note — front matter then prose — of [kind].
String note({
  required String name,
  required String seat,
  String kind = 'handoff',
  String body = '## 9. Resume here\n\n1. Read the board.\n',
}) =>
    '---\n'
    'name: ${p.basenameWithoutExtension(name)}\n'
    'description: one line, the recall key\n'
    'seat: $seat\n'
    'date: 2026-09-12\n'
    'kind: $kind\n'
    '---\n'
    '\n'
    '$body';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('handoff-write-'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// The disc value under test, over [seat]'s home-relative disc directory.
  SeatDisc discOf(String seat) =>
      SeatDisc(directory: seatDiscPath(home.path, seat), gridHome: home.path);

  /// [seat]'s disc-local path for [name].
  String discFile(String seat, String name) =>
      p.join(seatDiscPath(home.path, seat), name);

  /// What the diagnostic and every report call a disc note.
  String relative(String seat, String name) =>
      p.join('.grid', 'seats', seat, name);

  group('AC-1 the second write is REFUSED, never an amendment', () {
    test('the first write lands, the second names the live note and the '
        'remedy, and the first file is byte-for-byte untouched', () {
      final disc = discOf('governor')..ensure();
      final first = note(name: kEpoch69, seat: 'governor');

      final written = disc.writeHandoffOnce(
        fileName: kEpoch69,
        contents: first,
      );

      expect(written.relativePath, relative('governor', kEpoch69));
      expect(
        written.body,
        '## 9. Resume here\n\n1. Read the board.',
        reason: 'the parsed value is the note, front matter stripped',
      );
      expect(File(discFile('governor', kEpoch69)).readAsStringSync(), first);

      // The amendment: a SECOND note, at a second name, two minutes later.
      final thrown = _refusalOf(
        () => disc.writeHandoffOnce(
          fileName: 'handoff-20260912t042500z-still-going.md',
          contents: note(
            name: 'handoff-20260912t042500z-still-going.md',
            seat: 'governor',
            body: 'the board moved again\n',
          ),
        ),
      );
      expect(thrown.fileName, 'handoff-20260912t042500z-still-going.md');
      expect(thrown.existingHandoffs, [relative('governor', kEpoch69)]);
      expect(thrown.detail, contains('already carries 1 live handoff,'));
      expect(thrown.detail, contains('written ONCE at a boundary'));
      expect(thrown.detail, contains('never amended'));
      expect(
        thrown.detail,
        contains(
          'consume the existing handoff with succession, then write a new '
          'handoff',
        ),
        reason: 'the remedy is the VERB, never a hand edit and never a delete',
      );
      expect(
        thrown.toString(),
        contains(relative('governor', kEpoch69)),
        reason: 'the exception itself names the note, not only its fields',
      );
      expect(
        () => thrown.existingHandoffs.add('x'),
        throwsUnsupportedError,
        reason: 'a report cannot be edited by whoever catches it',
      );

      // Nothing was written, and the first note is exactly as authored.
      expect(
        File(
          discFile('governor', 'handoff-20260912t042500z-still-going.md'),
        ).existsSync(),
        isFalse,
      );
      expect(File(discFile('governor', kEpoch69)).readAsStringSync(), first);
      expect(
        Directory(
          seatDiscPath(home.path, 'governor'),
        ).listSync().whereType<File>().map((f) => p.basename(f.path)).toList(),
        [kEpoch69],
        reason: 'one live handoff on the disc, and no index written for it',
      );
    });

    test('a write to the SAME name is refused, never a truncation', () {
      final disc = discOf('refiner')..ensure();
      const name = 'handoff-20260912t100000z-one-boundary.md';
      final first = note(
        name: name,
        seat: 'refiner',
        body: 'FIRST AUTHORING\n',
      );
      disc.writeHandoffOnce(fileName: name, contents: first);

      expect(
        () => disc.writeHandoffOnce(
          fileName: name,
          contents: note(name: name, seat: 'refiner', body: 'SECOND\n'),
        ),
        throwsA(isA<SeatHandoffWriteException>()),
      );
      expect(File(discFile('refiner', name)).readAsStringSync(), first);
    });

    test('a name that is not one disc-local .md basename is refused', () {
      final disc = discOf('refiner')..ensure();
      for (final bad in const <String>[
        '',
        '   ',
        'sub/handoff-a.md',
        '../handoff-a.md',
        'handoff-a.txt',
        'MEMORY.md',
      ]) {
        expect(
          () => disc.writeHandoffOnce(
            fileName: bad,
            contents: note(name: 'handoff-a.md', seat: 'refiner'),
          ),
          throwsA(isA<SeatHandoffWriteException>()),
          reason: 'refused: "$bad"',
        );
      }
      expect(
        Directory(seatDiscPath(home.path, 'refiner')).listSync(),
        isEmpty,
        reason: 'a refused name creates nothing at all',
      );
    });
  });

  group('AC-2 no note kind is added — the checkpoint IS a handoff', () {
    test('a kind: journal candidate is refused and creates no file', () {
      final disc = discOf('governor')..ensure();
      const name = 'journal-20260912t050000z-mid-shift.md';

      final thrown = _refusalOf(
        () => disc.writeHandoffOnce(
          fileName: name,
          contents: note(
            name: name,
            seat: 'governor',
            kind: 'journal',
            body: 'a checkpoint that wants a channel of its own\n',
          ),
        ),
      );

      expect(thrown.detail, contains('kind: handoff'));
      expect(thrown.existingHandoffs, isEmpty);
      expect(File(discFile('governor', name)).existsSync(), isFalse);
      expect(
        Directory(seatDiscPath(home.path, 'governor')).listSync(),
        isEmpty,
      );
    });

    test('every OTHER disc kind is refused here too, and a handoff whose '
        'name does not say "handoff" is still a handoff', () {
      final disc = discOf('governor')..ensure();
      for (final kind in const ['lesson', 'receipt', 'observation']) {
        expect(
          () => disc.writeHandoffOnce(
            fileName: '$kind-x.md',
            contents: note(name: '$kind-x.md', seat: 'governor', kind: kind),
          ),
          throwsA(isA<SeatHandoffWriteException>()),
          reason: 'the write-once gate is the HANDOFF writer only: $kind',
        );
      }
      // The constraint keys on front matter, not on a file-name pattern.
      disc.writeHandoffOnce(
        fileName: 'board-20260912t060000z.md',
        contents: note(name: 'board-20260912t060000z.md', seat: 'governor'),
      );
      expect(
        () => disc.writeHandoffOnce(
          fileName: kEpoch69,
          contents: note(name: kEpoch69, seat: 'governor'),
        ),
        throwsA(isA<SeatHandoffWriteException>()),
        reason: 'the live note declares the kind, whatever it is called',
      );
    });

    test('an incomplete or unfenced candidate is refused', () {
      final disc = discOf('refiner')..ensure();
      for (final contents in const <String>[
        '',
        'no front matter at all\n',
        '---\nkind: handoff\nseat: refiner\n',
        'kind: handoff\n',
      ]) {
        expect(
          () => disc.writeHandoffOnce(
            fileName: 'handoff-a.md',
            contents: contents,
          ),
          throwsA(isA<SeatHandoffWriteException>()),
          reason: 'a half-written note is not a boundary',
        );
      }
      expect(File(discFile('refiner', 'handoff-a.md')).existsSync(), isFalse);
    });
  });

  group('AC-3 the stamped note cannot go stale through amendment', () {
    test('the bytes and the modification time survive a refused later '
        'write', () {
      final disc = discOf('governor')..ensure();
      final authored = note(name: kEpoch69, seat: 'governor');
      disc.writeHandoffOnce(fileName: kEpoch69, contents: authored);

      final file = File(discFile('governor', kEpoch69));
      // mtimes land on whole seconds, so both writes in this test would tie.
      // Pinning the file to the instant its own NAME claims is what makes the
      // assertion below non-vacuous: an overwrite bumps it to now.
      file.setLastModifiedSync(kEpoch69Stamped);
      final bytes = file.readAsBytesSync();

      // Eight hours of "still going", the shape of the observed defect.
      for (var amendment = 0; amendment < 8; amendment++) {
        expect(
          () => disc.writeHandoffOnce(
            fileName: kEpoch69,
            contents: '$authored\nAMENDMENT $amendment\n',
          ),
          throwsA(isA<SeatHandoffWriteException>()),
          reason: 'amendment $amendment',
        );
      }

      expect(file.readAsBytesSync(), bytes);
      expect(
        file.lastModifiedSync(),
        kEpoch69Stamped,
        reason:
            'the stamp in the file name is TRUE: the note has exactly one '
            'author moment',
      );
    });
  });

  group('AC-4 an unconsumed handoff is visible as an AGE', () {
    const seat = 'governor';

    /// A live handoff on [seat]'s disc, dated to the instant its own name
    /// claims, plus the one index pointer line the succession preview needs.
    void stampedDisc() {
      discOf(seat)
        ..ensure()
        ..writeHandoffOnce(
          fileName: kEpoch69,
          contents: note(name: kEpoch69, seat: seat, body: 'RESUME BODY\n'),
        );
      File(discFile(seat, kEpoch69)).setLastModifiedSync(kEpoch69Stamped);
      File(
        p.join(seatDiscPath(home.path, seat), 'MEMORY.md'),
      ).writeAsStringSync(
        '# Memory index\n\n- [Handoff epoch 69]($kEpoch69) — first night\n',
      );
    }

    /// What all three readers must say, nine hours on.
    String expected() =>
        'Agent Seat "$seat" has unconsumed handoff '
        '${relative(seat, kEpoch69)} on its Agent Disc — age 9h 0m.';

    test('the seat launcher names it before every launch, and launches '
        'with the note anyway', () async {
      stampedDisc();
      File(p.join(home.path, '.roles', '$seat.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nname: $seat\n---\nrole\n');
      final out = StringBuffer();
      final harness = _RecordingSeatRunner();

      final code =
          await (CommandRunner<int>('space', 'test')..addCommand(
                SeatCommand(
                  registry: _registry,
                  runner: harness.call,
                  gridHomeDefault: () => home.path,
                  now: () => kNineHoursOn,
                  out: out,
                  err: StringBuffer(),
                ),
              ))
              .run(['seat', seat, '--env', 'declared', '--once']);

      expect(code, 0);
      expect(out.toString(), contains(expected()));
      expect(
        (harness.launches.single as SeatTtyLaunch).args,
        contains('RESUME BODY'),
        reason: 'the age REPORTS — it never withholds the handoff',
      );
      expect(File(discFile(seat, kEpoch69)).existsSync(), isTrue);
    });

    test('prime carries it between the naming line and the body', () async {
      stampedDisc();
      final out = StringBuffer();

      final code =
          await (CommandRunner<int>('space', 'test')..addCommand(
                PrimeCommand(
                  runnerFor: (_) => _FakeBd(
                    jsonEncode({
                      'hookSpecificOutput': {
                        'hookEventName': 'SessionStart',
                        'additionalContext': 'BD',
                      },
                    }),
                  ),
                  environment: () => {
                    'GRID_SEAT': seat,
                    'GRID_HOME': home.path,
                  },
                  cwd: () => home.path,
                  readStdin: () async =>
                      '{"hook_event_name":"SessionStart","source":"startup"}',
                  now: () => kNineHoursOn,
                  out: out,
                ),
              ))
              .run(['prime', '--hook-json']);

      expect(code, 0);
      final context =
          ((jsonDecode(out.toString().trim())
                      as Map<String, Object?>)['hookSpecificOutput']!
                  as Map<String, Object?>)['additionalContext']!
              as String;
      expect(
        context,
        endsWith(
          '${handoffNamingLine(SeatHandoff(path: discFile(seat, kEpoch69), relativePath: relative(seat, kEpoch69), body: ''))}\n'
          '${expected()}\n'
          '\n'
          'RESUME BODY',
        ),
        reason: 'age is read BEFORE the board it describes',
      );
      expect(File(discFile(seat, kEpoch69)).existsSync(), isTrue);
    });

    test('the safe succession preview names it and still destroys '
        'nothing', () async {
      stampedDisc();
      final memory = File(
        p.join(seatDiscPath(home.path, seat), 'MEMORY.md'),
      ).readAsStringSync();
      final bytes = File(discFile(seat, kEpoch69)).readAsBytesSync();

      final run = await succession(
        home: home,
        argv: [seat, '--grid-home', home.path, '--no-destructive'],
        now: () => kNineHoursOn,
        gitRunner: _CleanGitRunner(),
      );

      expect(run.code, 0, reason: run.err);
      expect(run.out, contains(expected()));
      expect(run.out, contains('WOULD DELETE ${relative(seat, kEpoch69)}'));
      expect(File(discFile(seat, kEpoch69)).readAsBytesSync(), bytes);
      expect(
        File(
          p.join(seatDiscPath(home.path, seat), 'MEMORY.md'),
        ).readAsStringSync(),
        memory,
      );
    });

    test('the write refusal names the age of what it refused on', () async {
      stampedDisc();
      const second = 'handoff-20260912t084500z-still-going.md';

      final run = await succession(
        home: home,
        argv: [seat, '--grid-home', home.path, '--write-handoff', second],
        stdinNote: note(name: second, seat: seat),
        now: () => kNineHoursOn,
      );

      expect(run.code, 1);
      expect(
        run.out,
        contains(expected()),
        reason: 'nine hours IS the diagnosis of the refused amendment',
      );
      expect(run.err, contains('REFUSED'));
    });

    test('the formatter keeps hours and minutes, names days, and refuses '
        'to conceal clock skew', () {
      const handoff = SeatHandoff(
        path: '/grid/.grid/seats/governor/h.md',
        relativePath: '.grid/seats/governor/h.md',
        body: 'BODY',
      );
      final authored = DateTime(2026, 9, 11, 23, 25);
      String age(Duration elapsed) => seatHandoffAgeDiagnostic(
        seat: 'governor',
        handoff: handoff,
        authoredAt: authored,
        now: authored.add(elapsed),
      );
      const head =
          'Agent Seat "governor" has unconsumed handoff '
          '.grid/seats/governor/h.md on its Agent Disc — ';

      expect(age(const Duration(hours: 9)), '${head}age 9h 0m.');
      expect(age(Duration.zero), '${head}age 0h 0m.');
      expect(age(const Duration(minutes: 7)), '${head}age 0h 7m.');
      expect(
        age(const Duration(hours: 33, minutes: 12)),
        '${head}age 1d 9h 12m.',
      );
      expect(
        age(const Duration(minutes: -4)),
        '${head}age unavailable: authored time is 4m in the future.',
        reason: 'a future mtime is a broken clock, never a fresh handoff',
      );
    });

    test('NO threshold: forty days old still only reports', () async {
      stampedDisc();
      final run = await succession(
        home: home,
        argv: [seat, '--grid-home', home.path, '--no-destructive'],
        now: () => kEpoch69Stamped.add(const Duration(days: 40, hours: 2)),
        gitRunner: _CleanGitRunner(),
      );

      expect(run.code, 0, reason: run.err);
      expect(run.out, contains('age 40d 2h 0m.'));
      expect(
        run.out,
        isNot(contains('EXPIRED')),
        reason: 'there is no expiry — the age is evidence, not a verdict',
      );
      expect(File(discFile(seat, kEpoch69)).existsSync(), isTrue);
    });
  });

  group('AC-6 the composed surface writes once', () {
    test(
      'succession --write-handoff writes from stdin, then refuses',
      () async {
        const seat = 'governor';
        final first = await succession(
          home: home,
          argv: [seat, '--grid-home', home.path, '--write-handoff', kEpoch69],
          stdinNote: note(name: kEpoch69, seat: seat),
        );

        expect(first.code, 0, reason: first.err);
        expect(
          first.out,
          contains(
            'succession: $seat — HANDOFF WRITTEN ${relative(seat, kEpoch69)}',
          ),
        );
        expect(File(discFile(seat, kEpoch69)).existsSync(), isTrue);
        expect(
          File(p.join(seatDiscPath(home.path, seat), 'MEMORY.md')).existsSync(),
          isFalse,
          reason:
              'the verb writes the NOTE; the index line is the caller\'s step',
        );

        const second = 'handoff-20260912t084500z-still-going.md';
        final refused = await succession(
          home: home,
          argv: [seat, '--grid-home', home.path, '--write-handoff', second],
          stdinNote: note(name: second, seat: seat),
        );

        expect(refused.code, 1);
        expect(refused.err, contains('REFUSED'));
        expect(refused.err, contains(relative(seat, kEpoch69)));
        expect(
          refused.err,
          contains(
            'consume the existing handoff with succession, then write a new '
            'handoff',
          ),
        );
        expect(File(discFile(seat, second)).existsSync(), isFalse);
      },
    );

    test('--write-handoff and --no-destructive name no coherent run', () async {
      await expectLater(
        succession(
          home: home,
          argv: [
            'governor',
            '--grid-home',
            home.path,
            '--write-handoff',
            kEpoch69,
            '--no-destructive',
          ],
          stdinNote: note(name: kEpoch69, seat: 'governor'),
        ),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('ask for one run, not both'),
          ),
        ),
      );
      expect(
        Directory(seatDiscPath(home.path, 'governor')).existsSync(),
        isFalse,
        reason: 'a usage refusal reaches no disc',
      );
    });

    test('a refused write leaves the exit code and the disc alone', () async {
      final run = await succession(
        home: home,
        argv: [
          'refiner',
          '--grid-home',
          home.path,
          '--write-handoff',
          'notes.txt',
        ],
        stdinNote: note(name: 'notes.txt', seat: 'refiner'),
      );
      expect(run.code, 1);
      expect(run.err, contains('ends in ".md"'));
      expect(run.out, isEmpty);
    });
  });
}

/// The [SeatHandoffWriteException] [body] throws, or a failure naming what it
/// did instead.
SeatHandoffWriteException _refusalOf(void Function() body) {
  try {
    body();
  } on SeatHandoffWriteException catch (refusal) {
    return refusal;
  }
  fail('expected a SeatHandoffWriteException; the write was ALLOWED');
}

/// Runs the real composed verb: argv parsing, the exit code and both rendered
/// sinks are all under test.
Future<({int code, String out, String err})> succession({
  required Directory home,
  required List<String> argv,
  String stdinNote = '',
  DateTime Function()? now,
  GitRunner? gitRunner,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final command = CommandRunner<int>('space', 'test')
    ..addCommand(
      SuccessionCommand(
        service: gitRunner == null
            ? const SeatSuccessionService()
            : SeatSuccessionService(runner: gitRunner),
        gridHomeDefault: () => home.path,
        readStdin: () async => stdinNote,
        now: now ?? DateTime.now,
        out: out,
        err: err,
      ),
    );
  final code = await command.run(<String>['succession', ...argv]) ?? 0;
  return (code: code, out: out.toString(), err: err.toString());
}
