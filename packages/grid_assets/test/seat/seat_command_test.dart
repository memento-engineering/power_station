// The `seat <name>` launcher (bead `pow-lv6t`): harness-neutral, refusing,
// relaunching — and, since `pow-d5ol`, CONSUMING.
//
// Pins the acceptance of pow-d5ol:
//   - AC-1 an ignored Fake disc holding one handoff launches the child primed
//     with that body, and afterwards the note, its MEMORY.md pointer line and
//     nothing else are gone, with `.archive/<stamp>/` holding byte-identical
//     copies of both;
//   - AC-2 a tracked Fake disc archives in the scoped commit exactly as before;
//   - AC-3 a handoff written during the child's run relaunches once and is
//     consumed the same way;
//   - AC-4 `git add -f` is never invoked on any path.
//
// Offline — an injected process runner, an injected Fake git runner, a real
// temp grid home, no harness spawned.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';
import '../support/recording_git_runner.dart';

/// A fake harness process: records every plan and returns a programmed code.
final class _RecordingRunner {
  _RecordingRunner({this.onLaunch, this.exitCode = 0});
  final void Function(int call)? onLaunch;
  final int exitCode;
  final launches = <SeatLaunch>[];

  Future<int> call(SeatLaunch launch) async {
    launches.add(launch);
    onLaunch?.call(launches.length);
    return exitCode;
  }
}

/// A `bd` with nothing to say — `prime`'s tracker section is not under test
/// here (Fakes, not mocks).
final class _SilentBd implements BdRunner {
  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async => const BdResult(exitCode: 0, stdout: '', stderr: '');
}

/// A TTY environment with every seat declaration.
const _declared = AgentEnvironment(
  command: 'harness',
  drivenArgs: ['--driven-only'],
  argsAppend: ['--kept'],
  promptMode: PromptMode.flag,
  promptFlag: '-p',
  roleAsset: '.roles/$kSeatHole.md',
  roleArgs: ['--role', kSeatHole],
  memoryDirArgs: ['--memory', kMemoryDirHole],
  primeMode: SeatPrimeMode.hook,
);

/// A harness that declares none of them.
const _bare = AgentEnvironment(
  command: 'bare',
  roleAsset: '.roles/$kSeatHole.md',
  primeMode: SeatPrimeMode.prompt,
  promptMode: PromptMode.flag,
  promptFlag: '-p',
);

const _unoccupiable = AgentEnvironment(
  command: 'unoccupiable',
  primeMode: SeatPrimeMode.prompt,
);

/// A TTY harness that declares it wants the body in a PROMPT and that it takes
/// no prompt: there is no transport left, so a consumed handoff would reach
/// nobody.
const _mute = AgentEnvironment(
  command: 'mute',
  promptMode: PromptMode.none,
  roleAsset: '.roles/$kSeatHole.md',
  primeMode: SeatPrimeMode.prompt,
);

const _channel = AgentEnvironment(
  command: 'npx',
  args: ['-y', 'agent-acp'],
  promptMode: PromptMode.none,
  sessionAdapter: kAcpSessionAdapterId,
  roleAsset: '.roles/$kSeatHole.md',
  primeMode: SeatPrimeMode.prompt,
);

const _registry = EnvironmentRegistry(
  custom: {
    'declared': _declared,
    'bare': _bare,
    'channel': _channel,
    'unoccupiable': _unoccupiable,
    'mute': _mute,
  },
);

void main() {
  late Directory home;
  // The LOCAL archive clock, advanced one second per archive across the whole
  // test: two archives in one test are two directories, exactly as two
  // successions a second apart are on a live disc.
  late int archiveTick;

  setUp(() {
    home = Directory.systemTemp.createTempSync('seat-');
    archiveTick = 0;
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  void authorSeat(String seat) => File(p.join(home.path, '.roles', '$seat.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync('---\nname: $seat\n---\nrole\n');

  File discFile(String seat, String file) =>
      File(p.join(home.path, '.grid', 'seats', seat, file));

  /// Writes one `kind: handoff` note AND the one `MEMORY.md` pointer line that
  /// makes it consumable — the shape the vended ritual always leaves behind.
  File writeHandoff(String seat, String file, String body) {
    final note = discFile(seat, file)
      ..createSync(recursive: true)
      ..writeAsStringSync('---\nname: h\nkind: handoff\n---\n$body\n');
    final index = discFile(seat, 'MEMORY.md');
    final existing = index.existsSync() ? index.readAsStringSync() : '';
    index.writeAsStringSync('$existing- [Handoff]($file) — hook\n');
    return note;
  }

  Future<({int code, _RecordingRunner runner, String out, String err})> occupy(
    List<String> argv, {
    void Function(int call)? onLaunch,
    int childExitCode = 0,
    DateTime Function()? now,
    RecordingGitRunner? git,
    DateTime Function()? archivedAt,
  }) async {
    final runner = _RecordingRunner(
      onLaunch: onLaunch,
      exitCode: childExitCode,
    );
    final out = StringBuffer();
    final err = StringBuffer();
    final code =
        await (CommandRunner<int>('space', 'test')..addCommand(
              SeatCommand(
                registry: _registry,
                runner: runner.call,
                // Ignored by default: a temp grid home is no repository, and a
                // launcher test must never reach the real `git`.
                succession: SeatSuccessionService(
                  runner: git ?? RecordingGitRunner(ignored: true),
                  now:
                      archivedAt ??
                      () => DateTime.utc(2026, 9, 13, 17, 45, ++archiveTick),
                ),
                gridHomeDefault: () => home.path,
                now: now ?? DateTime.now,
                out: out,
                err: err,
              ),
            ))
            .run(['seat', ...argv]);
    return (
      code: code ?? 0,
      runner: runner,
      out: out.toString(),
      err: err.toString(),
    );
  }

  /// The grid-home-relative local archive for [stamp].
  Directory archiveOf(String seat, String stamp) =>
      Directory(p.join(home.path, '.grid', 'seats', seat, '.archive', stamp));

  test('it carries NO vendor flag literal — the whole point of the rework', () {
    // Off the shared cwd-independent package root: the process working
    // directory is a process property and `dart test` runs the suites
    // concurrently, so a relative read resolved against another file's setting.
    String read(String rel) => File(
      p.join(packageRoot(), 'lib', 'src', 'seat', rel),
    ).readAsStringSync();

    final source = read('seat_command.dart') + read('seat_launch.dart');
    for (final literal in const [
      '--agent',
      '--settings',
      'autoMemoryDirectory',
      '--dangerously-skip-permissions',
    ]) {
      expect(
        source,
        isNot(contains(literal)),
        reason: 'a vendor flag lives on AgentEnvironment, or nowhere',
      );
    }
  });

  test(
    'it REFUSES when the role definition is absent — nothing is spawned',
    () async {
      final run = await occupy(['governor', '--env', 'declared', '--once']);
      expect(run.code, 1);
      expect(run.runner.launches, isEmpty);
      expect(run.err, contains('has no role definition at'));
      expect(run.err, contains(p.join(home.path, '.roles', 'governor.md')));
    },
  );

  test('it REFUSES an environment with no role-definition home', () async {
    final run = await occupy(['governor', '--env', 'unoccupiable', '--once']);
    expect(run.code, 1);
    expect(run.runner.launches, isEmpty);
    expect(run.err, contains('declares no role-definition home'));
  });

  test('it composes command + args + declarations, and drops the driven '
      'posture', () async {
    authorSeat('governor');
    final run = await occupy(['governor', '--env', 'declared', '--once']);
    expect(run.code, 0);
    final launch = run.runner.launches.single as SeatTtyLaunch;
    expect(launch.command, 'harness');
    expect(launch.args, [
      '--kept',
      '--role',
      'governor',
      '--memory',
      p.join(home.path, '.grid', 'seats', 'governor'),
    ]);
    expect(launch.args, isNot(contains('--driven-only')));
    expect(launch.processEnvironment['GRID_SEAT'], 'governor');
    expect(launch.processEnvironment['GRID_HOME'], home.path);
    expect(launch.workingDirectory, home.path);
    expect(
      Directory(p.join(home.path, '.grid', 'seats', 'governor')).existsSync(),
      isTrue,
    );
  });

  test('a hook-primed harness takes the CONSUMED body in its process '
      'environment; a prompt-primed one takes it on argv', () async {
    authorSeat('governor');
    writeHandoff('governor', 'h.md', 'RESUME BODY');
    final hooked = await occupy(['governor', '--env', 'declared', '--once']);
    final hookedLaunch = hooked.runner.launches.single as SeatTtyLaunch;
    expect(
      hookedLaunch.args,
      isNot(contains('RESUME BODY')),
      reason: 'a hook-primed harness is never handed the body on argv',
    );
    // The BLOCKER this closes: the launcher deleted the note, so the child's
    // SessionStart hook has no disc left to read it off. The body travels in
    // the environment instead, and `prime` injects it from there.
    expect(hookedLaunch.processEnvironment['GRID_SEAT_HANDOFF'], 'RESUME BODY');
    // The consume is unconditional, so the second occupancy needs its own
    // note: the first one is gone.
    expect(discFile('governor', 'h.md').existsSync(), isFalse);
    writeHandoff('governor', 'h.md', 'RESUME BODY');
    final prompted = await occupy(['governor', '--env', 'bare', '--once']);
    final promptedLaunch = prompted.runner.launches.single as SeatTtyLaunch;
    expect(promptedLaunch.args, ['-p', 'RESUME BODY']);
    expect(
      promptedLaunch.processEnvironment.containsKey('GRID_SEAT_HANDOFF'),
      isFalse,
      reason: 'one transport per launch — never the body twice',
    );
  });

  test('an UNPRIMED occupancy declares no consumed handoff at all', () async {
    authorSeat('governor');
    final run = await occupy(['governor', '--env', 'declared', '--once']);
    expect(
      (run.runner.launches.single as SeatTtyLaunch).processEnvironment
          .containsKey('GRID_SEAT_HANDOFF'),
      isFalse,
      reason: 'an empty disc consumed nothing, so nothing is declared',
    );
    expect(
      (run.runner.launches.single as SeatTtyLaunch).processEnvironment
          .containsKey('GRID_SEAT_HANDOFF_ARCHIVE'),
      isFalse,
      reason: 'no body was consumed, so no archive is named',
    );
  });

  group('a consumed handoff names its archived copy beside the body', () {
    // The LOCAL archive the first consume of a test writes: the first tick of
    // the archive clock, holding the note under its own file name.
    final archivedNote = p.join(
      '.grid',
      'seats',
      'governor',
      '.archive',
      '20260913t174501z',
      'h.md',
    );

    test('a hook-primed consumed handoff archived LOCALLY declares the exact '
        'archive-note path, and that path holds the note', () async {
      authorSeat('governor');
      final noteBytes = writeHandoff(
        'governor',
        'h.md',
        'RESUME BODY',
      ).readAsBytesSync();

      final run = await occupy(['governor', '--env', 'declared', '--once']);

      expect(run.code, 0, reason: run.err);
      final launch = run.runner.launches.single as SeatTtyLaunch;
      expect(launch.processEnvironment['GRID_SEAT_HANDOFF'], 'RESUME BODY');
      expect(
        launch.processEnvironment[kConsumedHandoffArchiveEnvironmentVariable],
        archivedNote,
      );
      // Not a plausible string — the one file a successor reads to recover a
      // withheld body.
      expect(
        File(p.join(home.path, archivedNote)).readAsBytesSync(),
        noteBytes,
      );
    });

    test('the declared path reaches prime: a consumed handoff is named by '
        'its archive', () async {
      authorSeat('governor');
      writeHandoff('governor', 'h.md', 'RESUME BODY');
      final run = await occupy(['governor', '--env', 'declared', '--once']);
      final launch = run.runner.launches.single as SeatTtyLaunch;

      // The child's own SessionStart hook, over the environment the launcher
      // handed it.
      final out = StringBuffer();
      final code =
          await (CommandRunner<int>('space', 'test')..addCommand(
                PrimeCommand(
                  runnerInvocation: '',
                  runnerFor: (_) => _SilentBd(),
                  environment: () => launch.processEnvironment,
                  cwd: () => home.path,
                  readStdin: () async =>
                      '{"hook_event_name":"SessionStart","source":"startup"}',
                  out: out,
                ),
              ))
              .run(['prime', '--hook-json']);

      expect(code, 0);
      final context =
          ((jsonDecode(out.toString())
                      as Map<String, Object?>)['hookSpecificOutput']!
                  as Map<String, Object?>)['additionalContext']!
              as String;
      expect(context, contains('the note was archived at $archivedNote,'));
      expect(context, endsWith('RESUME BODY'));
    });

    test('a consumed handoff archived in GIT declares no archive path — a '
        'commit is not a path', () async {
      authorSeat('governor');
      writeHandoff('governor', 'h.md', 'RESUME BODY');

      final run = await occupy([
        'governor',
        '--env',
        'declared',
        '--once',
      ], git: RecordingGitRunner(statusOutput: '?? .grid/\n'));

      expect(run.code, 0, reason: run.err);
      final launch = run.runner.launches.single as SeatTtyLaunch;
      expect(launch.processEnvironment['GRID_SEAT_HANDOFF'], 'RESUME BODY');
      expect(
        launch.processEnvironment.containsKey(
          kConsumedHandoffArchiveEnvironmentVariable,
        ),
        isFalse,
      );
    });

    test('a prompt-primed consumed handoff declares neither — the body is '
        'whole in its first message', () async {
      authorSeat('governor');
      writeHandoff('governor', 'h.md', 'RESUME BODY');

      final run = await occupy(['governor', '--env', 'bare', '--once']);

      final launch = run.runner.launches.single as SeatTtyLaunch;
      expect(launch.args, ['-p', 'RESUME BODY']);
      expect(launch.processEnvironment.containsKey('GRID_SEAT_HANDOFF'), false);
      expect(
        launch.processEnvironment.containsKey(
          kConsumedHandoffArchiveEnvironmentVariable,
        ),
        isFalse,
      );
    });

    test('planSeatLaunch writes an archive path only BESIDE a hook-delivered '
        'consumed handoff body', () {
      Map<String, String> planned(
        AgentEnvironment environment, {
        String? body,
        String? archive,
      }) => planSeatLaunch(
        environment: environment,
        seat: 'governor',
        gridHome: home.path,
        discDirectory: seatDiscPath(home.path, 'governor'),
        handoffBody: body,
        handoffArchivePath: archive,
      ).processEnvironment;

      expect(
        planned(_declared, body: 'B', archive: archivedNote),
        containsPair(kConsumedHandoffArchiveEnvironmentVariable, archivedNote),
      );
      for (final (label, environment) in [
        ('no body', planned(_declared, archive: archivedNote)),
        ('empty path', planned(_declared, body: 'B', archive: '')),
        ('no path', planned(_declared, body: 'B')),
        ('prompt mode', planned(_bare, body: 'B', archive: archivedNote)),
      ]) {
        expect(
          environment.containsKey(kConsumedHandoffArchiveEnvironmentVariable),
          isFalse,
          reason: label,
        );
      }
    });
  });

  test(
    'a channel harness plans through the existing session adapter',
    () async {
      authorSeat('governor');
      writeHandoff('governor', 'h.md', 'RESUME BODY');
      final run = await occupy(['governor', '--env', 'channel', '--once']);
      final launch = run.runner.launches.single as SeatChannelLaunch;
      expect(launch.adapterId, kAcpSessionAdapterId);
      expect(launch.priming, 'RESUME BODY');
    },
  );

  test('the channel terminal sends one initial brief, then steers', () {
    Map<String, Object?> frame(List<int> bytes) =>
        (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
            .cast<String, Object?>();

    final freshFrames = <List<int>>[];
    final fresh = SeatChannelClient(
      adapter: const AcpSessionAdapter(),
      write: freshFrames.add,
    );
    fresh.send('FIRST');
    fresh.send('SECOND');
    expect(frame(freshFrames[0]), {'kind': 'brief', 'text': 'FIRST'});
    expect(frame(freshFrames[1]), {'kind': 'steer', 'text': 'SECOND'});

    final primedFrames = <List<int>>[];
    final primed = SeatChannelClient(
      adapter: const AcpSessionAdapter(),
      write: primedFrames.add,
    );
    primed.prime('HANDOFF');
    primed.send('NEXT');
    expect(frame(primedFrames[0]), {'kind': 'brief', 'text': 'HANDOFF'});
    expect(frame(primedFrames[1]), {'kind': 'steer', 'text': 'NEXT'});
    expect(() => primed.prime('TWICE'), throwsStateError);
  });

  // The operator seat occupies a channel DIRECTLY: no admitted attempt stands
  // behind this terminal and no durable carrier records what it authorizes, so
  // it answers a permission request deterministically and non-authorizing
  // (bead `pow-ed1c`).
  test('unadmitted channel seat denies permission requests', () {
    Map<String, Object?> frame(List<int> bytes) =>
        (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
            .cast<String, Object?>();

    final frames = <List<int>>[];
    final diagnostics = StringBuffer();
    final client = SeatChannelClient(
      adapter: const AcpSessionAdapter(),
      write: frames.add,
      diagnostics: diagnostics,
    );
    client.prime('BRIEF');
    expect(frame(frames.single), {'kind': 'brief', 'text': 'BRIEF'});

    // The binding is TRACKED, not honoured: it writes nothing and authorizes
    // nothing — it only lets a refusal name what it refused on.
    expect(
      client.handleProtocolControl(
        const AgentProtocolEvent.sessionBound(
          attemptId: 'attempt-1',
          protocolSessionId: 'acp-1',
        ),
      ),
      isTrue,
    );
    expect(frames, hasLength(1));

    // A request is answered IMMEDIATELY with the narrowest refusal on offer,
    // and with a cancellation when the harness offers no refusal at all.
    const request = AgentPermissionRequest(
      requestId: 'req-1',
      attemptId: 'attempt-1',
      sessionId: 'acp-1',
      capability: AgentPermissionCapability.execute,
      offered: <AgentPermissionOutcome>[
        AgentPermissionOutcome.rejectOnce,
        AgentPermissionOutcome.allowOnce,
        AgentPermissionOutcome.allowAlways,
      ],
    );
    expect(
      client.handleProtocolControl(
        const AgentProtocolEvent.permissionRequested(request: request),
      ),
      isTrue,
    );
    expect(
      client.handleProtocolControl(
        const AgentProtocolEvent.permissionRequested(
          request: AgentPermissionRequest(
            requestId: 'req-2',
            attemptId: 'attempt-1',
            sessionId: 'acp-1',
            capability: AgentPermissionCapability.edit,
            offered: <AgentPermissionOutcome>[
              AgentPermissionOutcome.allowOnce,
              AgentPermissionOutcome.allowAlways,
            ],
          ),
        ),
      ),
      isTrue,
    );
    final answers = frames
        .map(frame)
        .where((f) => f['kind'] == 'permission_decision')
        .map((f) => (f['decision']! as Map<String, dynamic>))
        .toList(growable: false);
    expect(answers.map((d) => <Object?>[d['requestId'], d['outcome']]), [
      <Object?>['req-1', 'rejectOnce'],
      <Object?>['req-2', 'cancelled'],
    ]);
    expect(answers.map((d) => d['policyId']).toSet(), <String>{''});
    // The refusal names the protocol identity it refused on.
    expect(diagnostics.toString(), contains('acp-1'));

    // A channel-side cancellation is only reported; it is never answered again.
    final before = frames.length;
    expect(
      client.handleProtocolControl(
        AgentProtocolEvent.permissionFallback(
          decision: AgentPermissionDecision.cancelled(
            request: request,
            policyId: '',
            reason: 'the station returned no authorization',
          ),
        ),
      ),
      isTrue,
    );
    expect(frames, hasLength(before));
    expect(diagnostics.toString(), contains('the channel cancelled'));

    // Harness OUTPUT is not this client's business — the runner renders it.
    for (final event in <AgentProtocolEvent>[
      const AgentProtocolEvent.progress(),
      const AgentProtocolEvent.completed(
        result: <String, String>{},
        usage: UsageReport(),
      ),
      const AgentProtocolEvent.failed(reason: 'boom'),
    ]) {
      expect(client.handleProtocolControl(event), isFalse);
    }

    // And the occupancy is unchanged: the next terminal line is still a steer.
    client.send('NEXT');
    expect(frame(frames.last), {'kind': 'steer', 'text': 'NEXT'});
    // Nothing this seat wrote ever authorized anything.
    expect(
      frames
          .map(frame)
          .map((f) => f['decision'])
          .whereType<Map<String, dynamic>>()
          .map((d) => d['outcome']),
      isNot(anyElement(anyOf('allowOnce', 'allowAlways'))),
    );
  });

  test('AC-3 a handoff written during the run relaunches ONCE, consumed the '
      'same way', () async {
    authorSeat('governor');
    final git = RecordingGitRunner(ignored: true);
    final run = await occupy(
      ['governor', '--env', 'bare'],
      git: git,
      now: () => DateTime.fromMillisecondsSinceEpoch(0),
      onLaunch: (call) {
        if (call == 1) writeHandoff('governor', 'h.md', 'SECOND BOARD');
      },
    );
    expect(run.code, 0);
    expect(run.runner.launches, hasLength(2));
    // The first occupancy had nothing to be primed with; the second carries
    // the note written during the first.
    expect(
      (run.runner.launches[0] as SeatTtyLaunch).args,
      isNot(contains('-p')),
    );
    expect((run.runner.launches[1] as SeatTtyLaunch).args, [
      '-p',
      'SECOND BOARD',
    ]);
    // Consumed the SAME way: archived locally, then destroyed.
    expect(discFile('governor', 'h.md').existsSync(), isFalse);
    expect(discFile('governor', 'MEMORY.md').readAsStringSync(), '');
    expect(
      File(
        p.join(archiveOf('governor', '20260913t174501z').path, 'h.md'),
      ).readAsStringSync(),
      contains('SECOND BOARD'),
      reason: 'the first occupancy had nothing to archive; this is the first',
    );
    expect(
      git.calls.any((argv) => argv.contains('-f') || argv.contains('--force')),
      isFalse,
    );
  });

  test('a CONSUMED handoff cannot relaunch the seat', () async {
    authorSeat('governor');
    writeHandoff('governor', 'old.md', 'OLD');
    final run = await occupy([
      'governor',
      '--env',
      'bare',
    ], now: () => DateTime(2100));
    expect(run.code, 0);
    expect(run.runner.launches, hasLength(1));
    expect(discFile('governor', 'old.md').existsSync(), isFalse);
  });

  test('--once never relaunches, even with a fresh handoff', () async {
    authorSeat('governor');
    final run = await occupy(
      ['governor', '--env', 'declared', '--once'],
      childExitCode: 23,
      onLaunch: (_) => writeHandoff('governor', 'h.md', 'RESUME BODY'),
    );
    expect(run.code, 23);
    expect(run.runner.launches, hasLength(1));
  });

  group('the LAUNCHER consumes before it primes (pow-d5ol)', () {
    test('AC-1 an IGNORED disc: the child is primed with the body, and the '
        'note, its index line and only those are gone', () async {
      authorSeat('governor');
      final note = writeHandoff('governor', 'h.md', 'RESUME BODY');
      final noteBytes = note.readAsBytesSync();
      // A second, banked note the index also names: the consume touches its
      // pointer line no more than it touches the note itself.
      discFile('governor', 'lesson-x.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nkind: lesson\n---\nkeep me\n');
      final index = discFile('governor', 'MEMORY.md');
      index.writeAsStringSync(
        '${index.readAsStringSync()}- [Lesson](lesson-x.md) — keep me\n',
      );
      final memoryBefore = index.readAsStringSync();
      final git = RecordingGitRunner(ignored: true);

      final run = await occupy(
        ['governor', '--env', 'bare', '--once'],
        git: git,
        // The ORDER is the point: by the time the child exists the disc is
        // already consumed.
        onLaunch: (_) {
          expect(note.existsSync(), isFalse);
          expect(
            index.readAsStringSync(),
            '- [Lesson](lesson-x.md) — keep me\n',
          );
        },
      );

      expect(run.code, 0, reason: run.err);
      expect((run.runner.launches.single as SeatTtyLaunch).args, [
        '-p',
        'RESUME BODY',
      ]);
      expect(run.out, contains('CONSUMED'));
      expect(
        run.out,
        contains(
          'ARCHIVED-LOCAL '
          '${p.join('.grid', 'seats', 'governor', '.archive', '20260913t174501z')}',
        ),
      );

      // The archive holds BOTH consumed files, byte-identical.
      final archive = archiveOf('governor', '20260913t174501z');
      expect(File(p.join(archive.path, 'h.md')).readAsBytesSync(), noteBytes);
      expect(
        File(p.join(archive.path, 'MEMORY.md')).readAsStringSync(),
        memoryBefore,
      );
      // The banked lesson is untouched on the disc.
      expect(discFile('governor', 'lesson-x.md').existsSync(), isTrue);
      // AC-4 — and no git MUTATION at all on an ignored disc.
      expect(git.calls.map((argv) => argv.first).toSet(), {'check-ignore'});
      expect(
        git.calls.any(
          (argv) => argv.contains('-f') || argv.contains('--force'),
        ),
        isFalse,
        reason: 'git add -f would re-commit the PII the ignore exists for',
      );
    });

    test('AC-2 a TRACKED disc archives in the scoped commit, exactly as '
        'before', () async {
      authorSeat('governor');
      writeHandoff('governor', 'h.md', 'RESUME BODY');
      final git = RecordingGitRunner(statusOutput: '?? .grid/\n');

      final run = await occupy([
        'governor',
        '--env',
        'bare',
        '--once',
      ], git: git);

      expect(run.code, 0, reason: run.err);
      expect((run.runner.launches.single as SeatTtyLaunch).args, [
        '-p',
        'RESUME BODY',
      ]);
      expect(run.out, contains('COMMITTED'));
      expect(run.out, isNot(contains('ARCHIVED-LOCAL')));
      expect(
        git.calls,
        contains(orderedEquals(['add', '-A', '--', '.grid/seats/governor'])),
      );
      expect(
        git.calls,
        contains(
          orderedEquals([
            'commit',
            '--only',
            '-m',
            'chore(seat): archive governor disc',
            '--',
            '.grid/seats/governor',
          ]),
        ),
      );
      expect(
        git.calls.any(
          (argv) => argv.contains('-f') || argv.contains('--force'),
        ),
        isFalse,
      );
      // A tracked disc writes NO local archive: git history is the archive.
      expect(
        Directory(
          p.join(home.path, '.grid', 'seats', 'governor', '.archive'),
        ).existsSync(),
        isFalse,
      );
      expect(discFile('governor', 'h.md').existsSync(), isFalse);
      expect(discFile('governor', 'MEMORY.md').readAsStringSync(), '');
    });

    test(
      'an environment with NO transport refuses BEFORE the consume',
      () async {
        authorSeat('governor');
        final note = writeHandoff('governor', 'h.md', 'RESUME BODY');
        final bytes = note.readAsBytesSync();
        final index = discFile('governor', 'MEMORY.md').readAsStringSync();
        final git = RecordingGitRunner(ignored: true);

        final run = await occupy([
          'governor',
          '--env',
          'mute',
          '--once',
        ], git: git);

        expect(run.code, 1);
        expect(run.runner.launches, isEmpty);
        expect(run.err, contains('HANDOFF NOT CONSUMED'));
        expect(run.err, contains('promptMode none'));
        expect(run.err, contains('a successor cannot start unprimed'));
        // Destroying a note on the way to nobody is strictly worse than not
        // launching: the disc is untouched and no git ran.
        expect(note.readAsBytesSync(), bytes);
        expect(discFile('governor', 'MEMORY.md').readAsStringSync(), index);
        expect(git.calls, isEmpty);
      },
    );

    test('the same environment occupies an EMPTY disc freely', () async {
      authorSeat('governor');
      final run = await occupy(['governor', '--env', 'mute', '--once']);
      expect(run.code, 0, reason: run.err);
      expect(run.runner.launches, hasLength(1));
    });

    // The "couldn't tell" branch, from the launcher's side: a grid home that is
    // no repository exits 128 on `git check-ignore`, the succession refuses to
    // pick an archive blind, and the launch stops with the disc intact. Ruled
    // (the decision entry names the consequence) and pinned here so it can
    // never become accidental.
    test('a grid home that is NO repository refuses, and destroys '
        'nothing', () async {
      authorSeat('governor');
      final note = writeHandoff('governor', 'h.md', 'RESUME BODY');
      final bytes = note.readAsBytesSync();
      final git = RecordingGitRunner(checkIgnoreExitCode: 128);

      final run = await occupy([
        'governor',
        '--env',
        'bare',
        '--once',
      ], git: git);

      expect(run.code, 1);
      expect(run.runner.launches, isEmpty);
      expect(run.err, contains('HANDOFF NOT CONSUMED'));
      expect(run.err, contains('exited 128'));
      expect(note.readAsBytesSync(), bytes);
      expect(git.calls.map((argv) => argv.first).toSet(), {'check-ignore'});
    });

    test(
      'a succession that REFUSES stops the launch and destroys nothing',
      () async {
        authorSeat('governor');
        writeHandoff('governor', 'a.md', 'FIRST');
        writeHandoff('governor', 'b.md', 'SECOND');
        final git = RecordingGitRunner(ignored: true);

        final run = await occupy([
          'governor',
          '--env',
          'bare',
          '--once',
        ], git: git);

        expect(run.code, 1);
        expect(run.runner.launches, isEmpty);
        expect(run.err, contains('HANDOFF NOT CONSUMED'));
        expect(run.err, contains('2 live handoffs'));
        expect(run.err, contains('nothing was launched'));
        expect(discFile('governor', 'a.md').existsSync(), isTrue);
        expect(discFile('governor', 'b.md').existsSync(), isTrue);
        expect(git.calls, isEmpty, reason: 'refused before any git call');
      },
    );
  });

  test(
    'an unknown environment and a missing seat name refuse loudly',
    () async {
      authorSeat('governor');
      expect((await occupy(['governor', '--env', 'nope', '--once'])).code, 1);
      expect((await occupy(['--env', 'declared', '--once'])).code, 64);
    },
  );
}
