import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _Runtime implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final StreamController<List<int>> _output = StreamController<List<int>>();
  final List<List<int>> writes = <List<int>>[];
  bool running = false;
  RuntimeEvent? terminal;

  void emitRuntime(RuntimeEvent event) {
    if (event is Exited || event is Died) terminal = event;
    _events.add(event);
  }

  void emitOutput(String line) => _output.add(utf8.encode('$line\n'));

  Future<void> closeOutput() => _output.close();

  @override
  String exitOutputOf(String name) => '';

  @override
  Future<void> start(String name, RuntimeConfig config) async => running = true;

  @override
  Future<void> stop(String name) async => running = false;

  @override
  Future<void> interrupt(String name) async {}

  @override
  Future<void> write(String name, List<int> bytes) async {
    if (!running) throw SessionNotWritable(name, 'not running');
    writes.add(List<int>.unmodifiable(bytes));
  }

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  Stream<List<int>> interactionOutput(String name) => _output.stream;

  @override
  bool isRunning(String name) => running;

  @override
  bool processAlive(String name) => running;

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) => running ? const ['session'] : [];

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeEvent? terminalOf(String name) => terminal;

  @override
  ({int pid, int? pgid})? identityOf(String name) =>
      running ? (pid: 1, pgid: 1) : null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() async {
    if (!_output.isClosed) unawaited(_output.close());
    await _events.close();
  }
}

class _JsonAdapter implements AgentSessionAdapter {
  bool decoderCancelled = false;

  @override
  String get id => 'json-test';

  @override
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  }) => RuntimeConfig(
    workDir: workspace.workspaceDir,
    command: 'probe',
    lifecycle: Lifecycle.longLived,
  );

  @override
  List<int> encodeBrief(AgentBrief brief) => utf8.encode(
    '${jsonEncode(<String, Object?>{'type': 'brief', 'brief': brief.render()})}\n',
  );

  @override
  List<int> encodeSteer(String text) => utf8.encode(
    '${jsonEncode(<String, Object?>{'type': 'steer', 'text': text})}\n',
  );

  @override
  Stream<AgentProtocolEvent> decode(Stream<List<int>> stdout) {
    final decoded = stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(_decodeLine);
    late final StreamController<AgentProtocolEvent> controller;
    late final StreamSubscription<AgentProtocolEvent> subscription;
    controller = StreamController<AgentProtocolEvent>(
      onListen: () {
        subscription = decoded.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        decoderCancelled = true;
        return subscription.cancel();
      },
    );
    return controller.stream;
  }

  AgentProtocolEvent _decodeLine(String line) {
    final frame = jsonDecode(line) as Map<String, dynamic>;
    return switch (frame['type']) {
      'progress' => const AgentProtocolEvent.progress(),
      'completed' => AgentProtocolEvent.completed(
        result: (frame['result'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, value as String),
        ),
        usage: const UsageReport(
          tokensIn: 21,
          tokensOut: 8,
          numTurns: 2,
          model: 'probe-model',
        ),
      ),
      'failed' => AgentProtocolEvent.failed(reason: frame['reason'] as String),
      _ => throw FormatException('unknown protocol frame: $frame'),
    };
  }
}

class _ReadySource implements ReadyWorkSource {
  _ReadySource(this.current);

  Bead current;
  final StreamController<GraphEvent> controller =
      StreamController<GraphEvent>.broadcast();

  @override
  Stream<GraphEvent> get events => controller.stream;

  @override
  List<Bead> get readyBeads => [current];

  @override
  Bead? bead(String id) => current.id == id ? current : null;
}

String _steerJson({
  required String commandId,
  required String attemptId,
  required String instanceFence,
  required String text,
}) => jsonEncode(<String, Object?>{
  'commandId': commandId,
  'attemptId': attemptId,
  'instanceFence': instanceFence,
  'text': text,
});

AgentSession _session({
  required _Runtime runtime,
  required _JsonAdapter adapter,
  Stream<ProcessSessionCommand> commands =
      const Stream<ProcessSessionCommand>.empty(),
  ExplorationTransport? transport,
}) => AgentSession(
  runtime: runtime,
  name: 'session',
  adapter: adapter,
  brief: const AgentBrief(task: 'secret brief'),
  commands: commands,
  attemptId: 'attempt-live',
  instanceFence: 'fence-live',
  transport: transport,
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('an orphaned session is OBSERVED, stays live, and still dies on the '
      'terminal that follows', () async {
    final runtime = _Runtime();
    final transport = RecordingExplorationTransport();
    await runtime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'probe'),
    );
    final session = _session(
      runtime: runtime,
      adapter: _JsonAdapter(),
      transport: transport,
    );
    final updates = <ProcessSessionUpdate>[];
    final updateSub = session.updates.listen(updates.add);
    await session.start();
    await _pump();

    session.onRuntimeEvent(
      const RuntimeEvent.sessionOrphaned(
        name: 'session',
        pgid: 4242,
        memberCount: 3,
        pid: 99,
      ),
    );
    await _pump();

    // OBSERVED, never a state change: one flare, and NO protocol update (so
    // `driveProcessSession` cannot settle and no respawn is scheduled).
    final flare = transport.named('agent.sessionOrphaned').single;
    expect(flare.data, containsPair('sessionId', 'session'));
    expect(flare.data, containsPair('pgid', '4242'));
    expect(flare.data, containsPair('memberCount', '3'));
    expect(updates, isEmpty);

    // Still LIVE and supervised: a correctly fenced steer is still delivered,
    // so the session was not latched terminal by the observation.
    expect(
      await session.send(
        const ProcessSessionCommand(
          commandId: 'steer-after-orphan',
          attemptId: 'attempt-live',
          instanceFence: 'fence-live',
          body: 'keep going',
        ),
      ),
      ProcessCommandDisposition.delivered,
    );

    // The TERMINAL after the provider's bounded grace still ends the session.
    session.onRuntimeEvent(
      const RuntimeEvent.died(name: 'session', reason: 'group reaped'),
    );
    await _pump();
    expect(updates.single, isA<ProcessSessionFailed>());
    expect(transport.named('agent.sessionOrphaned'), hasLength(1));

    await updateSub.cancel();
    await session.close();
    await runtime.close();
  });

  test('clean exit and exit zero before protocol completion fail', () async {
    final exitRuntime = _Runtime();
    await exitRuntime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'probe'),
    );
    final exitDone = driveProcessSession(
      session: _session(runtime: exitRuntime, adapter: _JsonAdapter()),
      runtimeEvents: exitRuntime.events,
    );
    await _pump();
    exitRuntime.emitRuntime(
      const RuntimeEvent.exited(name: 'session', exitCode: 0),
    );
    final exitUpdate = await exitDone;
    expect(exitUpdate, isA<ProcessSessionFailed>());
    expect(exitUpdate, isNot(isA<ProcessSessionCompleted>()));
    await exitRuntime.close();

    final closeRuntime = _Runtime();
    await closeRuntime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'probe'),
    );
    final closeDone = driveProcessSession(
      session: _session(runtime: closeRuntime, adapter: _JsonAdapter()),
      runtimeEvents: closeRuntime.events,
    );
    await _pump();
    await closeRuntime.closeOutput();
    final closeUpdate = await closeDone;
    expect(closeUpdate, isA<ProcessSessionFailed>());
    expect(closeUpdate, isNot(isA<ProcessSessionCompleted>()));
    await closeRuntime.close();
  });

  test(
    'bead-routed steer is fenced deduplicated and terminal-latched',
    () async {
      final initial = Bead(
        id: 'work-1',
        metadata: {
          kAgentSteerMetadataKey: _steerJson(
            commandId: 'matching',
            attemptId: 'attempt-live',
            instanceFence: 'fence-live',
            text: 'correct course',
          ),
        },
      );
      final source = _ReadySource(initial);
      final runtime = _Runtime();
      final adapter = _JsonAdapter();
      await runtime.start(
        'session',
        const RuntimeConfig(workDir: '/tmp', command: 'probe'),
      );
      final session = _session(
        runtime: runtime,
        adapter: adapter,
        commands: BeadRoutedAgentSteerSource(source).watch('work-1'),
      );
      final updates = <ProcessSessionUpdate>[];
      final updateSub = session.updates.listen(updates.add);
      await session.start();
      await _pump();

      expect(
        await session.send(
          const ProcessSessionCommand(
            commandId: 'stale',
            attemptId: 'attempt-old',
            instanceFence: 'fence-live',
            body: 'stale',
          ),
        ),
        ProcessCommandDisposition.staleAttempt,
      );
      expect(
        await session.send(
          const ProcessSessionCommand(
            commandId: 'wrong',
            attemptId: 'attempt-live',
            instanceFence: 'fence-old',
            body: 'wrong',
          ),
        ),
        ProcessCommandDisposition.wrongFence,
      );
      expect(
        await session.send(
          const ProcessSessionCommand(
            commandId: 'matching',
            attemptId: 'attempt-live',
            instanceFence: 'fence-live',
            body: 'duplicate',
          ),
        ),
        ProcessCommandDisposition.duplicate,
      );

      runtime.emitOutput(
        jsonEncode(<String, Object?>{
          'type': 'completed',
          'result': <String, String>{'answer': 'done'},
        }),
      );
      await _pump();
      expect(
        await session.send(
          const ProcessSessionCommand(
            commandId: 'late',
            attemptId: 'attempt-live',
            instanceFence: 'fence-live',
            body: 'late',
          ),
        ),
        ProcessCommandDisposition.terminal,
      );

      expect(runtime.writes, hasLength(2));
      expect(utf8.decode(runtime.writes[0]), contains('secret brief'));
      expect(utf8.decode(runtime.writes[1]), contains('correct course'));
      expect(updates.whereType<ProcessSessionCompleted>(), hasLength(1));
      await session.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw StateError('session close timed out'),
      );
      await updateSub.cancel();
      await source.controller.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw StateError('source close timed out'),
      );
      await runtime.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw StateError('runtime close timed out'),
      );
    },
  );

  // A `sessionOrphaned` observation means the LEADER is gone while its owned
  // process group still has live members — supervision evidence, not a
  // terminal (`the_grid#pgid-liveness-is-supervision-evidence` D3). Exhaustive
  // matching alone would not prove this: routing it into `_fail` also
  // analyzes clean.
  test('a sessionOrphaned observation is NOT terminal — the harness is still '
      'working and can still finish its protocol', () async {
    final runtime = _Runtime();
    await runtime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'probe'),
    );
    final done = driveProcessSession(
      session: _session(runtime: runtime, adapter: _JsonAdapter()),
      runtimeEvents: runtime.events,
    );
    var settled = false;
    unawaited(done.then((_) => settled = true));
    await _pump();
    runtime.emitRuntime(
      const RuntimeEvent.sessionOrphaned(
        name: 'session',
        pgid: 4242,
        memberCount: 2,
      ),
    );
    await _pump();
    expect(settled, isFalse, reason: 'an orphaned session must not settle');
    runtime.emitOutput(
      jsonEncode(<String, Object?>{
        'type': 'completed',
        'result': <String, String>{'text': 'wrote it'},
      }),
    );
    expect(await done, isA<ProcessSessionCompleted>());
    await runtime.close();
  });

  // The engine fences an artifact-durability completion in its PROCESS
  // dispatcher, which a session-driven step never reaches — the lease vendor
  // returns the session's terminal verbatim. So the capability re-applies its
  // own declared contract here (bead `pow-39tl`).
  group('ArtifactFencedSession', () {
    test(
      'a clean protocol completion with NO artifact fails tail-first',
      () async {
        final runtime = _Runtime();
        await runtime.start(
          'session',
          const RuntimeConfig(workDir: '/tmp', command: 'probe'),
        );
        final transcript =
            'HEAD-OF-TRANSCRIPT\n${'y' * 4000}\n'
            'I could not run bd: command not found';
        final done = driveProcessSession(
          session: ArtifactFencedSession(
            inner: _session(runtime: runtime, adapter: _JsonAdapter()),
            probe: () async => GateOutcome.present,
            resultFields: () async => const <String, String>{},
            verb: 'specify',
            adapter: 'acp',
          ),
          runtimeEvents: runtime.events,
        );
        await _pump();
        runtime.emitOutput(
          jsonEncode(<String, Object?>{
            'type': 'completed',
            'result': <String, String>{'text': transcript},
          }),
        );
        final update = await done;
        expect(update, isA<ProcessSessionFailed>());
        final reason = (update as ProcessSessionFailed).reason;
        expect(reason, startsWith('specify failed (exit 0) [acp]: '));
        expect(
          reason,
          contains('declared completion artifact is not durable — …'),
        );
        // The harness's own last words are the diagnosis; its opening is not.
        expect(reason, contains('I could not run bd: command not found'));
        expect(reason, isNot(contains('HEAD-OF-TRANSCRIPT')));
        await runtime.close();
      },
    );

    test('a failed probe is refused too, never a silent pass', () async {
      final runtime = _Runtime();
      await runtime.start(
        'session',
        const RuntimeConfig(workDir: '/tmp', command: 'probe'),
      );
      final done = driveProcessSession(
        session: ArtifactFencedSession(
          inner: _session(runtime: runtime, adapter: _JsonAdapter()),
          probe: () async => throw StateError('bd query blew up'),
          resultFields: () async => const <String, String>{},
          verb: 'specify',
          adapter: 'acp',
        ),
        runtimeEvents: runtime.events,
      );
      await _pump();
      runtime.emitOutput(
        jsonEncode(<String, Object?>{
          'type': 'completed',
          'result': <String, String>{'text': 'I think I wrote it'},
        }),
      );
      final update = await done;
      expect(update, isA<ProcessSessionFailed>());
      expect(
        (update as ProcessSessionFailed).reason,
        'specify failed (exit 0) [acp]: '
        'completion artifact probe failed — I think I wrote it',
      );
      await runtime.close();
    });

    test(
      'a proven artifact completes and merges the capability result fields',
      () async {
        final runtime = _Runtime();
        await runtime.start(
          'session',
          const RuntimeConfig(workDir: '/tmp', command: 'probe'),
        );
        final done = driveProcessSession(
          session: ArtifactFencedSession(
            inner: _session(runtime: runtime, adapter: _JsonAdapter()),
            probe: () async => GateOutcome.clear,
            resultFields: () async => const <String, String>{
              'specAcceptance': '- [ ] a',
            },
            verb: 'specify',
            adapter: 'acp',
          ),
          runtimeEvents: runtime.events,
        );
        await _pump();
        runtime.emitOutput(
          jsonEncode(<String, Object?>{
            'type': 'completed',
            'result': <String, String>{'text': 'wrote it'},
          }),
        );
        final update = await done;
        expect(update, isA<ProcessSessionCompleted>());
        // The protocol result, the inner session's usage merge, AND the
        // capability's own `result()` contribution — which the engine's session
        // dispatch never calls.
        expect((update as ProcessSessionCompleted).result, {
          'text': 'wrote it',
          'tokensIn': '21',
          'tokensOut': '8',
          'numTurns': '2',
          'model': 'probe-model',
          'specAcceptance': '- [ ] a',
        });
        await runtime.close();
      },
    );

    test(
      'a harness FAILURE is forwarded verbatim — the probe never runs',
      () async {
        final runtime = _Runtime();
        await runtime.start(
          'session',
          const RuntimeConfig(workDir: '/tmp', command: 'probe'),
        );
        var probed = false;
        final done = driveProcessSession(
          session: ArtifactFencedSession(
            inner: _session(runtime: runtime, adapter: _JsonAdapter()),
            probe: () async {
              probed = true;
              return GateOutcome.clear;
            },
            resultFields: () async => const <String, String>{},
            verb: 'specify',
            adapter: 'acp',
          ),
          runtimeEvents: runtime.events,
        );
        await _pump();
        runtime.emitOutput(
          jsonEncode(<String, Object?>{
            'type': 'failed',
            'reason': 'acp agent failed (exit 3) [acp]: boom',
          }),
        );
        final update = await done;
        expect(
          (update as ProcessSessionFailed).reason,
          'acp agent failed (exit 3) [acp]: boom',
        );
        expect(probed, isFalse);
        await runtime.close();
      },
    );
  });

  test('malformed protocol frame fails and cancels decoder', () async {
    final runtime = _Runtime();
    final adapter = _JsonAdapter();
    await runtime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'probe'),
    );
    final done = driveProcessSession(
      session: _session(runtime: runtime, adapter: adapter),
      runtimeEvents: runtime.events,
    );
    await _pump();
    runtime.emitOutput('{not-json');
    final update = await done;

    expect(update, isA<ProcessSessionFailed>());
    expect((update as ProcessSessionFailed).reason, contains('malformed'));
    expect(update.reason, isNot(contains('tokensIn')));
    expect(adapter.decoderCancelled, isTrue);
    await runtime.close();
  });
}
