// The `prime --hook-json` verb (bead `pow-lv6t`): echo bd, inject ONLY the
// seat's newest handoff, exit 0 always. Offline — a Fake BdRunner, a real temp
// disc, no harness and no `bd` process.
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

String _hook(String context) => jsonEncode({
  'hookSpecificOutput': {
    'hookEventName': 'SessionStart',
    'additionalContext': context,
  },
});

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

  Future<Map<String, Object?>> prime({
    required String bdStdout,
    int bdExitCode = 0,
    BdRunner? bd,
    Map<String, String> environment = const {},
    String payload = '{"hook_event_name":"SessionStart","source":"startup"}',
  }) async {
    final out = StringBuffer();
    final code =
        await (CommandRunner<int>('space', 'test')..addCommand(
              PrimeCommand(
                runnerFor: (_) => bd ?? _FakeBd(bdStdout, exitCode: bdExitCode),
                environment: () => environment,
                cwd: () => home.path,
                readStdin: () async => payload,
                out: out,
              ),
            ))
            .run(['prime', '--hook-json']);
    expect(code, 0, reason: 'a hook that fails must not fail a session');
    return jsonDecode(out.toString().trim()) as Map<String, Object?>;
  }

  String contextOf(Map<String, Object?> hook) =>
      ((hook['hookSpecificOutput']!
              as Map<String, Object?>)['additionalContext']!)
          as String;

  group('no seat', () {
    test("returns EXACTLY bd prime's additionalContext", () async {
      final hook = await prime(bdStdout: _hook('BD SAYS THIS'));
      expect(contextOf(hook), 'BD SAYS THIS');
    });

    test(
      'an empty bd context stays empty (the measured 79-byte payload)',
      () async {
        expect(contextOf(await prime(bdStdout: _hook(''))), '');
      },
    );

    test('a disc with a handoff is IGNORED without GRID_SEAT', () async {
      writeNote('governor', 'handoff.md', 'RESUME BODY');
      expect(contextOf(await prime(bdStdout: _hook(''))), '');
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
        expect(context, startsWith('BD\n\n'));
        expect(
          context,
          contains(
            'Handoff ${p.join('.grid', 'seats', 'governor', 'handoff.md')} — act '
            'on Resume here, then delete this file and its MEMORY.md line in this '
            'turn.',
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
        composePrimeContext(bdContext: 'BD \n', handoff: handoff),
        'BD \n\n'
        'Handoff .grid/seats/governor/h.md — act on Resume here, then delete '
        'this file and its MEMORY.md line in this turn.\n\nBODY',
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
        expect(freshContexts.first, startsWith('BD \n\n'));
        expect(freshContexts.first, endsWith('RESUME BODY'));

        final resumed = contextOf(
          await prime(
            bdStdout: _hook('BD \n'),
            environment: {...env, 'GRID_HOME': home.path},
            payload: '{"hook_event_name":"SessionStart","source":"resume"}',
          ),
        );
        expect(resumed, 'BD \n');
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
        expect(context, 'BD');
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

  group('a hook NEVER fails a session', () {
    test(
      'unparsable output, non-zero/missing bd, and junk stdin exit 0',
      () async {
        expect(contextOf(await prime(bdStdout: 'not json')), '');
        expect(contextOf(await prime(bdStdout: _hook('X'), bdExitCode: 9)), '');
        expect(contextOf(await prime(bdStdout: '', bd: _ThrowingBd())), '');
        expect(
          contextOf(await prime(bdStdout: _hook('X'), payload: '<<<')),
          'X',
        );
      },
    );

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
        'BD',
      );
    });
  });
}
