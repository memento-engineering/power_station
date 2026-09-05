// The `seat <name>` launcher (bead `pow-lv6t`): harness-neutral, refusing,
// relaunching. Offline — an injected process runner, a real temp grid home, no
// harness spawned.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
  },
);

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('seat-'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  void authorSeat(String seat) => File(p.join(home.path, '.roles', '$seat.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync('---\nname: $seat\n---\nrole\n');

  void writeHandoff(String seat, String file, String body) =>
      File(p.join(home.path, '.grid', 'seats', seat, file))
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nname: h\nkind: handoff\n---\n$body\n');

  Future<({int code, _RecordingRunner runner, String err})> occupy(
    List<String> argv, {
    void Function(int call)? onLaunch,
    int childExitCode = 0,
    DateTime Function()? now,
  }) async {
    final runner = _RecordingRunner(
      onLaunch: onLaunch,
      exitCode: childExitCode,
    );
    final err = StringBuffer();
    final code =
        await (CommandRunner<int>('space', 'test')..addCommand(
              SeatCommand(
                registry: _registry,
                runner: runner.call,
                gridHomeDefault: () => home.path,
                now: now ?? DateTime.now,
                out: StringBuffer(),
                err: err,
              ),
            ))
            .run(['seat', ...argv]);
    return (code: code ?? 0, runner: runner, err: err.toString());
  }

  test('it carries NO vendor flag literal — the whole point of the rework', () {
    String read(String rel) {
      final local = File('lib/src/seat/$rel');
      return (local.existsSync()
              ? local
              : File('packages/grid_assets/lib/src/seat/$rel'))
          .readAsStringSync();
    }

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

  test('a hook-primed harness takes no prompt segment; a prompt-primed one '
      'takes the handoff body', () async {
    authorSeat('governor');
    writeHandoff('governor', 'h.md', 'RESUME BODY');
    final hooked = await occupy(['governor', '--env', 'declared', '--once']);
    expect(
      (hooked.runner.launches.single as SeatTtyLaunch).args,
      isNot(contains('RESUME BODY')),
    );
    final prompted = await occupy(['governor', '--env', 'bare', '--once']);
    expect((prompted.runner.launches.single as SeatTtyLaunch).args, [
      '-p',
      'RESUME BODY',
    ]);
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

  test('it relaunches iff a handoff NEWER than the launch exists', () async {
    authorSeat('governor');
    final run = await occupy(
      ['governor', '--env', 'declared'],
      now: () => DateTime.fromMillisecondsSinceEpoch(0),
      onLaunch: (call) {
        final file = File(
          p.join(home.path, '.grid', 'seats', 'governor', 'h.md'),
        );
        if (call == 1) {
          writeHandoff('governor', 'h.md', 'RESUME BODY');
        } else {
          file.deleteSync();
        }
      },
    );
    expect(run.code, 0);
    expect(run.runner.launches, hasLength(2));
  });

  test('a handoff older than the launch does not relaunch', () async {
    authorSeat('governor');
    writeHandoff('governor', 'old.md', 'OLD');
    final run = await occupy([
      'governor',
      '--env',
      'declared',
    ], now: () => DateTime(2100));
    expect(run.code, 0);
    expect(run.runner.launches, hasLength(1));
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

  test(
    'an unknown environment and a missing seat name refuse loudly',
    () async {
      authorSeat('governor');
      expect((await occupy(['governor', '--env', 'nope', '--once'])).code, 1);
      expect((await occupy(['--env', 'declared', '--once'])).code, 64);
    },
  );
}
