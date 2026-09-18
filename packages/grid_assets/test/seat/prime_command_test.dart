// The `prime --hook-json` verb (beads `pow-lv6t`, `pow-5zpe`, `pow-d5ol`):
// orient the session in the STATION — identity, invocation, every verb by name,
// the decision register, the seat disc and the wake mechanism — then the
// tracker's own reference, then ONE handoff: the body the LAUNCHER consumed for
// this occupancy when it declared one, and otherwise whatever survived on the
// disc, which is the hand-started session. Exit 0 always, bounded always.
//
// Offline: a Fake BdRunner, a real temp disc, no harness and no `bd` process.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A `bd` that returns exactly what it was handed (Fakes, not mocks).
final class _FakeBd implements BdRunner {
  _FakeBd(this.stdout, {this.exitCode = 0});
  final String stdout;
  final int exitCode;
  final calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    return BdResult(exitCode: exitCode, stdout: stdout, stderr: '');
  }
}

/// A missing or unstartable `bd` executable.
final class _ThrowingBd implements BdRunner {
  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async => throw StateError('bd is missing');
}

/// A verb a STATION composes — the thing prime must name without this package
/// ever having heard of it.
final class _StationVerb extends Command<int> {
  _StationVerb(this.name, {this.aliases = const <String>[]});

  @override
  final String name;

  @override
  final List<String> aliases;

  @override
  final String description =
      'A verb composed by the station, with a contract only its own help '
      'carries: it takes a target, it writes a receipt, and it refuses when '
      'the store is unreachable.';

  @override
  int run() => 0;
}

String _hook(String context) => jsonEncode({
  'hookSpecificOutput': {
    'hookEventName': 'SessionStart',
    'additionalContext': context,
  },
});

const String _startup = '{"hook_event_name":"SessionStart","source":"startup"}';

/// Every UTF-8 byte of [sink], the trailing newline included.
int _bytes(StringBuffer sink) => utf8.encode(sink.toString()).length;

/// The verb-pointer records of [context] — the lines under `Verbs:`, up to the
/// blank line that closes the section.
List<String> _verbRecords(String context) {
  final lines = const LineSplitter().convert(context);
  final start = lines.indexOf('Verbs:');
  if (start == -1) fail('no Verbs: section in\n$context');
  final records = <String>[];
  for (var i = start + 1; i < lines.length && lines[i].isNotEmpty; i++) {
    records.add(lines[i]);
  }
  return records;
}

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('prime-'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  void writeNote(
    String seat,
    String file,
    String body, {
    String kind = 'handoff',
  }) {
    File(p.join(home.path, '.grid', 'seats', seat, file))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '---\nname: ${p.basenameWithoutExtension(file)}\nseat: $seat\n'
        'date: 2026-09-03\nkind: $kind\n---\n$body\n',
      );
  }

  /// A composed station: the runner a real one builds, with `prime` attached
  /// exactly the way `..addCommand(...)` attaches it.
  CommandRunner<int> station({
    required StringBuffer out,
    String bdStdout = '',
    int bdExitCode = 0,
    BdRunner? bd,
    Map<String, String> environment = const {},
    String payload = _startup,
    String executableName = 'space',
    String runnerInvocation = '',
    String description = 'The power station CLI.',
  }) => CommandRunner<int>(executableName, description)
    ..addCommand(
      PrimeCommand(
        runnerInvocation: runnerInvocation,
        runnerFor: (_) => bd ?? _FakeBd(bdStdout, exitCode: bdExitCode),
        environment: () => environment,
        cwd: () => home.path,
        readStdin: () async => payload,
        out: out,
      ),
    );

  Future<Map<String, Object?>> prime({
    required String bdStdout,
    int bdExitCode = 0,
    BdRunner? bd,
    Map<String, String> environment = const {},
    String payload = _startup,
  }) async {
    final out = StringBuffer();
    final code = await station(
      out: out,
      bdStdout: bdStdout,
      bdExitCode: bdExitCode,
      bd: bd,
      environment: environment,
      payload: payload,
    ).run(['prime', '--hook-json']);
    expect(code, 0, reason: 'a hook that fails must not fail a session');
    return jsonDecode(out.toString().trim()) as Map<String, Object?>;
  }

  String contextOf(Map<String, Object?> hook) =>
      ((hook['hookSpecificOutput']!
              as Map<String, Object?>)['additionalContext']!)
          as String;

  group('the STATION answers for itself', () {
    test('station identity, invocation, and every exposed verb', () async {
      final out = StringBuffer();
      final runner = station(out: out, bdStdout: _hook('BD'))
        ..addCommand(_StationVerb('land'))
        ..addCommand(_StationVerb('search'));

      expect(await runner.run(['prime']), 0);

      final context = out.toString();
      expect(context, startsWith('Station: space — The power station CLI.\n'));
      expect(context, contains('\nInvoke: space prime [--hook-json]\n'));

      // EXACTLY one pointer record per exposed key — no key unnamed, and no
      // record that is not a key.
      expect(_verbRecords(context), [
        for (final key in runner.commands.keys.toList()..sort())
          '- $key — space help $key',
      ]);
      expect(_verbRecords(context), contains('- land — space help land'));
      expect(_verbRecords(context), contains('- search — space help search'));
    });

    test(
      'configured runner invocation renders every prime command pointer',
      () async {
        final out = StringBuffer();
        // A JIT station: `dart run lunar:lunar` is the verb that reaches THIS
        // checkout, while the bare `lunar` resolves to whatever global
        // snapshot was last activated — which nothing refreshes.
        final runner =
            station(
                out: out,
                bdStdout: _hook('BD'),
                executableName: 'lunar',
                runnerInvocation: 'dart run lunar:lunar',
              )
              ..addCommand(_StationVerb('land'))
              ..addCommand(_StationVerb('search'));

        expect(await runner.run(['prime']), 0);

        final context = out.toString();
        expect(
          context,
          contains('\nInvoke: dart run lunar:lunar prime [--hook-json]\n'),
        );
        expect(_verbRecords(context), [
          for (final key in runner.commands.keys.toList()..sort())
            '- $key — dart run lunar:lunar help $key',
        ]);
        expect(
          context,
          contains(
            'Search with dart run lunar:lunar search; usage: dart run '
            'lunar:lunar help search.',
          ),
        );
        // The station's IDENTITY is still its name — it is the executable that
        // stops being a POINTER, not the station.
        expect(context, startsWith('Station: lunar — '));
        expect(
          _verbRecords(context),
          isNot(contains('- land — lunar help land')),
          reason: 'no pointer survives at the bare executable',
        );
      },
    );

    test('blank runner invocation falls back to executableName', () async {
      final out = StringBuffer();
      // A station that composed no invocation of its own: the attached
      // runner's executable is all there is to point at, and whitespace is
      // not an invocation.
      final runner = station(
        out: out,
        bdStdout: _hook('BD'),
        runnerInvocation: '   ',
      )..addCommand(_StationVerb('land'));

      expect(await runner.run(['prime']), 0);

      final context = out.toString();
      expect(context, contains('\nInvoke: space prime [--hook-json]\n'));
      expect(_verbRecords(context), contains('- land — space help land'));
      expect(
        context,
        contains('Search with space search; usage: space help search.'),
      );
    });

    test('late-added command derives into prime', () async {
      final out = StringBuffer();
      // `prime` is attached FIRST, the way a station composes it, and the verb
      // arrives afterwards. Nothing is handed to prime: it reads the runner.
      final runner = station(out: out, bdStdout: _hook('BD'))
        ..addCommand(_StationVerb('board', aliases: const ['b']));

      expect(await runner.run(['prime']), 0);

      final records = _verbRecords(out.toString());
      expect(records, contains('- board — space help board'));
      expect(
        records,
        contains('- b — space help b'),
        reason: 'an alias is an exposed key, so it is a reachable verb',
      );
    });

    test('decision register and search pointer', () async {
      final out = StringBuffer();
      final runner = station(out: out, bdStdout: _hook('BD'))
        ..addCommand(_StationVerb('search'));

      expect(await runner.run(['prime']), 0);

      expect(
        out.toString(),
        contains(
          'Decisions: docs/decisions/ in every mounted substation; ratified '
          'decisions bind. Search with space search; usage: space help '
          'search.',
        ),
      );
    });

    test('Agent Disc and fenced wake pointer', () async {
      const wake =
          'Wake: the resident station evaluates the seat wake predicate on '
          'the existing fenced service tick; a seat adds no second wake '
          'mechanism.';

      final seated = StringBuffer();
      expect(
        await station(
          out: seated,
          bdStdout: _hook('BD'),
          environment: {'GRID_SEAT': 'governor', 'GRID_HOME': home.path},
        ).run(['prime']),
        0,
      );
      expect(
        seated.toString(),
        contains(
          'Agent Disc: ${p.join(home.path, '.grid', 'seats', 'governor')}.',
        ),
      );
      expect(seated.toString(), contains(wake));

      final bare = StringBuffer();
      expect(await station(out: bare, bdStdout: _hook('BD')).run(['prime']), 0);
      expect(
        bare.toString(),
        contains('Agent Disc: <grid home>/.grid/seats/<seat>/.'),
        reason: 'with no seat the disc is named as a TEMPLATE, never guessed',
      );
      expect(bare.toString(), contains(wake));
    });

    test('verb pointers are shorter than command help', () async {
      final out = StringBuffer();
      final runner = station(out: out, bdStdout: _hook('BD'))
        ..addCommand(_StationVerb('land'))
        ..addCommand(_StationVerb('board', aliases: const ['b']));

      expect(await runner.run(['prime']), 0);

      final records = _verbRecords(out.toString());
      for (final entry in runner.commands.entries) {
        final pointer = '- ${entry.key} — space help ${entry.key}';
        // The record is the pointer and NOTHING else: no summary, no
        // description, no option list — whatever the verb's help answers,
        // prime must not duplicate.
        expect(records, contains(pointer), reason: entry.key);
        expect(
          utf8.encode(pointer).length,
          lessThan(utf8.encode(entry.value.usage).length),
          reason: entry.key,
        );
      }
    });
  });

  group('no seat', () {
    test(
      'carries bd prime under its own heading, and is not only it',
      () async {
        final context = contextOf(await prime(bdStdout: _hook('BD SAYS THIS')));
        expect(
          context,
          contains('Tracker reference (bd prime):\nBD SAYS THIS'),
        );
        expect(context, startsWith('Station: '));
      },
    );

    test('an unreadable tracker still POINTS at bd prime', () async {
      expect(
        contextOf(await prime(bdStdout: _hook(''))),
        contains(
          'Tracker reference (bd prime):\nUnavailable here; run bd '
          'prime.',
        ),
      );
    });

    test('a disc with a handoff is IGNORED without GRID_SEAT', () async {
      writeNote('governor', 'handoff.md', 'RESUME BODY');
      expect(
        contextOf(await prime(bdStdout: _hook(''))),
        isNot(contains('RESUME BODY')),
      );
    });
  });

  group('with a seat', () {
    const env = {'GRID_SEAT': 'governor'};

    test(
      'appends ONE naming line and the handoff BODY, front matter stripped',
      () async {
        writeNote('governor', 'handoff.md', 'RESUME BODY');
        final context = contextOf(
          await prime(
            bdStdout: _hook('BD'),
            environment: {...env, 'GRID_HOME': home.path},
          ),
        );
        expect(context, contains('Tracker reference (bd prime):\nBD\n\n'));
        expect(
          context,
          contains(
            'Handoff ${p.join('.grid', 'seats', 'governor', 'handoff.md')} — '
            'still on the disc, so no launcher consumed it. Act on Resume '
            'here, then run the succession verb to archive and delete it.',
          ),
        );
        expect(context, endsWith('RESUME BODY'));
        expect(context, isNot(contains('kind: handoff')));
      },
    );

    test('preserves every bd context byte before the handoff separator', () {
      const handoff = SeatHandoff(
        path: '/grid/h.md',
        relativePath: '.grid/seats/governor/h.md',
        body: 'BODY',
      );
      expect(
        composePrimeContext(
          bdContext: 'BD \n',
          handoff: PrimeHandoff.unconsumed(handoff),
        ),
        'BD \n\n'
        'Handoff .grid/seats/governor/h.md — still on the disc, so no launcher '
        'consumed it. Act on Resume here, then run the succession verb to '
        'archive and delete it.\n\nBODY',
      );
    });

    test(
      'startup, clear and compact inject identically; resume echoes bd only',
      () async {
        writeNote('governor', 'handoff.md', 'RESUME BODY');
        final freshContexts = <String>[];
        for (final source in ['startup', 'clear', 'compact']) {
          freshContexts.add(
            contextOf(
              await prime(
                bdStdout: _hook('BD \n'),
                environment: {...env, 'GRID_HOME': home.path},
                payload:
                    '{"hook_event_name":"SessionStart","source":"$source"}',
              ),
            ),
          );
        }
        expect(freshContexts.toSet(), hasLength(1));
        expect(freshContexts.first, contains('BD \n'));
        expect(freshContexts.first, endsWith('RESUME BODY'));

        final resumed = contextOf(
          await prime(
            bdStdout: _hook('BD \n'),
            environment: {...env, 'GRID_HOME': home.path},
            payload: '{"hook_event_name":"SessionStart","source":"resume"}',
          ),
        );
        expect(resumed, contains('Tracker reference (bd prime):\nBD \n'));
        expect(resumed, isNot(contains('RESUME BODY')));
      },
    );

    test(
      'injects NOTHING else from the disc — no lesson, no MEMORY.md',
      () async {
        writeNote('governor', 'a-lesson.md', 'LESSON BODY', kind: 'lesson');
        File(p.join(home.path, '.grid', 'seats', 'governor', 'MEMORY.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('- [A](a-lesson.md) — hook\n');
        final context = contextOf(
          await prime(
            bdStdout: _hook('BD'),
            environment: {...env, 'GRID_HOME': home.path},
          ),
        );
        expect(context, endsWith('BD'));
        expect(context, isNot(contains('LESSON BODY')));
      },
    );

    // mtimes land on whole seconds, so the two notes are dated explicitly
    // rather than raced apart by a sleep.
    test('the NEWEST handoff wins', () async {
      writeNote('governor', 'old.md', 'OLD');
      writeNote('governor', 'new.md', 'NEW');
      File(
        p.join(home.path, '.grid', 'seats', 'governor', 'old.md'),
      ).setLastModifiedSync(DateTime(2026, 9, 3, 10));
      File(
        p.join(home.path, '.grid', 'seats', 'governor', 'new.md'),
      ).setLastModifiedSync(DateTime(2026, 9, 3, 11));
      final context = contextOf(
        await prime(
          bdStdout: _hook(''),
          environment: {...env, 'GRID_HOME': home.path},
        ),
      );
      expect(context, endsWith('NEW'));
    });

    test('GRID_HOME absent falls back to the cwd', () async {
      writeNote('governor', 'handoff.md', 'RESUME BODY');
      expect(
        contextOf(await prime(bdStdout: _hook(''), environment: env)),
        endsWith('RESUME BODY'),
      );
    });
  });

  // pow-d5ol: on a hook-primed harness the launcher has ALREADY consumed the
  // note by the time this hook runs — the disc is empty and the body arrives in
  // the process environment. A hook that only read the disc would leave every
  // `claude`-env successor unprimed, which is the whole defect class.
  group('the LAUNCHER\'s consumed handoff is the priming (pow-d5ol)', () {
    const seated = {'GRID_SEAT': 'governor'};
    // The grid-home-relative archived copy the launcher declares beside the
    // body — the shape a LOCAL archive writes.
    final archived = p.join(
      '.grid',
      'seats',
      'governor',
      '.archive',
      '20260915t101500z',
      'handoff-20260915t101500z.md',
    );

    test('an EMPTY disc still primes the successor — the shape the launcher '
        'leaves behind', () async {
      // Exactly the live state after a consume: the disc directory exists and
      // holds no handoff at all.
      Directory(
        p.join(home.path, '.grid', 'seats', 'governor'),
      ).createSync(recursive: true);
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': 'CONSUMED BODY',
          },
        ),
      );
      expect(
        context,
        endsWith('CONSUMED BODY'),
        reason:
            'a hook-primed successor takes no prompt segment, so this IS its '
            'priming',
      );
    });

    test('the declared body is injected, named as consumed, and owes no '
        'verb', () async {
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': 'CONSUMED BODY',
            'GRID_SEAT_HANDOFF_ARCHIVE': archived,
          },
        ),
      );
      expect(context, endsWith('CONSUMED BODY'));
      expect(
        context,
        contains(
          'Handoff — CONSUMED by the launcher before this session started: the '
          'note was archived at $archived, then its live copy and index line '
          'were deleted. Act on Resume here; no succession verb is owed.',
        ),
      );
      expect(
        context,
        isNot(contains('run the succession verb')),
        reason: 'the note the verb would consume no longer exists',
      );
      expect(
        context,
        isNot(contains('unconsumed handoff')),
        reason: 'a note consumed at this launch has no age to report',
      );
    });

    test('the declaration WINS over anything left on the disc', () async {
      writeNote('governor', 'handoff.md', 'DISC BODY');
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': 'CONSUMED BODY',
          },
        ),
      );
      expect(context, endsWith('CONSUMED BODY'));
      expect(context, isNot(contains('DISC BODY')));
    });

    test('an EMPTY declaration falls back to the disc — the hand-started '
        'session, which IS owed the verb', () async {
      writeNote('governor', 'handoff.md', 'DISC BODY');
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': '   ',
          },
        ),
      );
      expect(context, endsWith('DISC BODY'));
      expect(context, contains('still on the disc'));
      expect(context, contains('run the succession verb'));
    });

    test('a resume source injects neither', () async {
      writeNote('governor', 'handoff.md', 'DISC BODY');
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': 'CONSUMED BODY',
          },
          payload: '{"hook_event_name":"SessionStart","source":"resume"}',
        ),
      );
      expect(context, isNot(contains('CONSUMED BODY')));
      expect(context, isNot(contains('DISC BODY')));
    });

    test('a withheld consumed body points at its ARCHIVED copy, one read '
        'away', () {
      final consumed = PrimeHandoff.consumed('BODY', archivePath: archived);
      final withheld = consumed.withheld(4);
      expect(
        withheld.body,
        'Withheld: 4 handoff-body bytes; read $archived from the Agent Disc.',
      );
      expect(
        withheld.body,
        isNot(contains('names the archive')),
        reason: 'the pointer IS the path — it never defers to another line',
      );
      expect(
        withheld.namingLine,
        consumed.namingLine,
        reason: 'the fact that a handoff exists is never the cut',
      );
    });

    test('a withheld consumed body with no archive path says the path is '
        'unknown rather than claiming it is named', () {
      final withheld = PrimeHandoff.consumed('BODY').withheld(4);
      expect(
        withheld.body,
        'Withheld: 4 handoff-body bytes; the archive path is unknown.',
      );
      expect(withheld.body, isNot(contains('names the archive')));
      expect(withheld.body, isNot(contains('from the Agent Disc')));
    });

    // The measured defect: every governor handoff runs 9.5–10.8 KB, so the
    // body can never fit the 8000-byte bound. The naming line is what
    // survives, and it must be enough to reach the body in ONE read.
    test('an oversized consumed handoff keeps its archive path in the naming '
        'line while the body is withheld', () async {
      final body = List.filled(
        300,
        'Resume here — the governor brief, line after line.',
      ).join('\n');
      final bodyBytes = utf8.encode(body).length;
      expect(bodyBytes, greaterThan(10000));
      final out = StringBuffer();
      expect(
        await station(
          out: out,
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF': body,
            'GRID_SEAT_HANDOFF_ARCHIVE': '  $archived\n',
          },
        ).run(['prime', '--hook-json']),
        0,
      );
      expect(_bytes(out), lessThanOrEqualTo(kBoundedOutputCapBytes));
      final context = contextOf(
        jsonDecode(out.toString().trim()) as Map<String, Object?>,
      );

      expect(
        context,
        contains(
          'Handoff — CONSUMED by the launcher before this session started: the '
          'note was archived at $archived, then its live copy and index line '
          'were deleted. Act on Resume here; no succession verb is owed.',
        ),
      );
      expect(
        context,
        endsWith(
          'Withheld: $bodyBytes handoff-body bytes; read $archived from the '
          'Agent Disc.',
        ),
      );
      expect(context, isNot(contains('Resume here — the governor brief')));
      expect(context, isNot(contains('names the archive')));
    });

    test('a consumed handoff with no archive declaration says its archive '
        'path is unknown', () async {
      // Absent, and declared blank: neither names a path.
      for (final declaration in <String?>[null, '   ']) {
        final context = contextOf(
          await prime(
            bdStdout: _hook('BD'),
            environment: {
              ...seated,
              'GRID_HOME': home.path,
              'GRID_SEAT_HANDOFF': 'CONSUMED BODY',
              'GRID_SEAT_HANDOFF_ARCHIVE': ?declaration,
            },
          ),
        );
        expect(
          context,
          contains(
            'Handoff — CONSUMED by the launcher before this session started: '
            'the note was archived, but the archive path is unknown; its live '
            'copy and index line were deleted. Act on Resume here; no '
            'succession verb is owed.',
          ),
          reason: '$declaration',
        );
        expect(context, isNot(contains('archived at')), reason: '$declaration');
        expect(context, endsWith('CONSUMED BODY'), reason: '$declaration');
      }
    });

    test('an archive declaration WITHOUT a consumed body cannot displace the '
        'disc', () async {
      writeNote('governor', 'handoff.md', 'DISC BODY');
      final context = contextOf(
        await prime(
          bdStdout: _hook('BD'),
          environment: {
            ...seated,
            'GRID_HOME': home.path,
            'GRID_SEAT_HANDOFF_ARCHIVE': archived,
          },
        ),
      );
      expect(context, endsWith('DISC BODY'));
      expect(context, contains('still on the disc'));
      expect(context, isNot(contains('CONSUMED')));
      expect(context, isNot(contains(archived)));
    });
  });

  group('a hook NEVER fails a session', () {
    test('SessionStart behavior remains', () async {
      writeNote('governor', 'handoff.md', 'RESUME BODY');
      const seated = {'GRID_SEAT': 'governor'};

      // A valid hook object, exit 0, on every source.
      for (final source in ['startup', 'clear', 'compact']) {
        final hook = await prime(
          bdStdout: _hook('BD'),
          environment: seated,
          payload: '{"hook_event_name":"SessionStart","source":"$source"}',
        );
        expect(
          (hook['hookSpecificOutput']!
              as Map<String, Object?>)['hookEventName'],
          'SessionStart',
        );
        expect(contextOf(hook), endsWith('RESUME BODY'), reason: source);
      }
      for (final source in ['resume', 'teleported']) {
        expect(
          contextOf(
            await prime(
              bdStdout: _hook('BD'),
              environment: seated,
              payload: '{"hook_event_name":"SessionStart","source":"$source"}',
            ),
          ),
          isNot(contains('RESUME BODY')),
          reason: source,
        );
      }

      // A dependency failure degrades to its own value and never to a failed
      // session: the station still answers for itself.
      for (final broken in [
        await prime(bdStdout: 'not json', environment: seated),
        await prime(bdStdout: _hook('X'), bdExitCode: 9, environment: seated),
        await prime(bdStdout: '', bd: _ThrowingBd(), environment: seated),
      ]) {
        final context = contextOf(broken);
        expect(context, startsWith('Station: '));
        expect(context, contains('Unavailable here; run bd prime.'));
        expect(context, endsWith('RESUME BODY'));
      }
      expect(
        contextOf(
          await prime(
            bdStdout: _hook('X'),
            environment: seated,
            payload: '<<<',
          ),
        ),
        allOf(
          contains('Tracker reference (bd prime):\nX'),
          isNot(contains('RESUME BODY')),
        ),
        reason: 'a malformed payload names no source, so nothing is injected',
      );
    });

    test('tracker reference remains reachable', () async {
      // bd's own context survives BYTE FOR BYTE under its own heading, and it
      // is no longer the whole answer.
      const body = 'BD LINE ONE\n\n  indented two\ntrailing spaces  ';
      final context = contextOf(await prime(bdStdout: _hook(body)));

      expect(context, contains('\nTracker reference (bd prime):\n$body'));
      expect(context, contains('Station: space — The power station CLI.'));
      expect(
        context.indexOf('Station: '),
        lessThan(context.indexOf('Tracker reference')),
        reason: 'the station answers first; the tracker is subordinate',
      );
    });

    test('the BD_JSON_ENVELOPE wrapper is unwrapped', () {
      expect(
        extractBdAdditionalContext(
          jsonEncode({'data': jsonDecode(_hook('W'))}),
        ),
        'W',
      );
    });

    test('an absent disc directory injects nothing', () async {
      expect(
        contextOf(
          await prime(
            bdStdout: _hook('BD'),
            environment: {'GRID_SEAT': 'nobody', 'GRID_HOME': home.path},
          ),
        ),
        endsWith('Tracker reference (bd prime):\nBD'),
      );
    });
  });

  group('AC-8 — the answer is bounded, and every cut is NAMED', () {
    // Multibyte in both bodies, each far over the cap on its own.
    final trackerBody = '日本語の文脈・' * 5000;
    final handoffBody = 'ハンドオフ本文' * 2000;

    test(
      'plain and hook output are bounded with explicit withholding',
      () async {
        writeNote('governor', 'handoff.md', handoffBody);
        const environment = {'GRID_SEAT': 'governor'};
        final relative = p.join('.grid', 'seats', 'governor', 'handoff.md');

        // PLAIN: there is no hook payload, so no handoff is due. The oversized
        // tracker body is the one cut, and it names exactly what it cost.
        final plain = StringBuffer();
        expect(
          await station(
            out: plain,
            bdStdout: _hook(trackerBody),
            environment: environment,
          ).run(['prime']),
          0,
        );
        expect(_bytes(plain), lessThanOrEqualTo(kBoundedOutputCapBytes));
        expect(plain.toString(), startsWith('Station: '));
        expect(
          plain.toString(),
          endsWith(
            'Withheld: ${utf8.encode(trackerBody).length} tracker-reference '
            'bytes; run bd prime.\n',
          ),
        );

        // HOOK: both bodies are over, and each is replaced by its own count.
        // This rendering is the larger of the two, so a bound measured only on
        // the plain text would ship it over the cap.
        final hook = StringBuffer();
        expect(
          await station(
            out: hook,
            bdStdout: _hook(trackerBody),
            environment: environment,
          ).run(['prime', '--hook-json']),
          0,
        );
        expect(_bytes(hook), lessThanOrEqualTo(kBoundedOutputCapBytes));
        final decoded = jsonDecode(hook.toString()) as Map<String, Object?>;
        final context =
            (decoded['hookSpecificOutput']!
                    as Map<String, Object?>)['additionalContext']!
                as String;
        expect(
          context,
          contains(
            'Withheld: ${utf8.encode(trackerBody).length} tracker-reference '
            'bytes; run bd prime.',
          ),
        );
        expect(
          context,
          endsWith(
            'Withheld: ${utf8.encode(handoffBody).length} handoff-body bytes; '
            'read $relative from the Agent Disc.',
          ),
        );
        // What is withheld is the BODY, never the fact that a handoff exists.
        expect(context, contains('Handoff $relative — still on the disc'));
        expect(context, startsWith('Station: '));
        expect(context, isNot(contains('�')));
      },
    );

    test(
      'verb pointers are dropped WHOLE, with the count and the bytes',
      () async {
        final out = StringBuffer();
        final runner = station(out: out, bdStdout: _hook('BD'));
        // More verb pointers than the cap can hold, each with a multibyte name.
        for (var i = 0; i < 100; i++) {
          runner.addCommand(_StationVerb('verb-日本語の長い動詞の名前-$i'));
        }
        final expected = [
          for (final key in runner.commands.keys.toList()..sort())
            '- $key — space help $key',
        ];

        expect(await runner.run(['prime']), 0);
        expect(_bytes(out), lessThanOrEqualTo(kBoundedOutputCapBytes));

        final records = _verbRecords(out.toString());
        final note = records.last;
        final kept = records.take(records.length - 1).toList();
        // Every surviving record is a COMPLETE record — a leading prefix of the
        // list, never a sliced line and never half a rune.
        expect(kept, isNotEmpty);
        expect(kept, expected.take(kept.length));
        expect(
          note,
          'Withheld: ${expected.length - kept.length} verb-pointer records '
          '(${expected.skip(kept.length).fold(0, (sum, record) => sum + utf8.encode(record).length)} '
          'bytes); run space help.',
        );
      },
    );

    test(
      'an oversized station orientation falls back to its own count',
      () async {
        final out = StringBuffer();
        // A station whose own description cannot fit the cap: nothing but the
        // floor is renderable, and the floor still POINTS.
        final runner = station(
          out: out,
          bdStdout: 'not json',
          description: 'サブステーションの説明' * 800,
        );

        expect(await runner.run(['prime']), 0);
        expect(_bytes(out), lessThanOrEqualTo(kBoundedOutputCapBytes));
        expect(
          out.toString(),
          matches(
            RegExp(
              r'^Withheld: [0-9]+ station-orientation bytes; run the station '
              r'executable with help\.\n',
            ),
          ),
        );
        expect(
          out.toString(),
          endsWith(
            'Tracker reference (bd prime):\nUnavailable here; run bd '
            'prime.\n',
          ),
        );
      },
    );
  });
}
