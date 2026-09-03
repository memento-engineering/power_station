// The SPEC SEAT on a CHANNEL harness (bead `pow-39tl`) — the offline proof that
// a codex-driven specify delivers its brief, produces a structurally valid
// spec, and fails LOUDLY (exit-code-led, tail-first, adapter-named) when the
// declared completion artifact is missing.
//
// Before this bead the seat called the argv spawn renderer directly: the codex
// environment declares `PromptMode.none`, so the brief rendered to an EMPTY
// argv segment and the ACP server was spawned as a one-turn process that saw
// EOF and exited 0. Every live attempt (tg-1n4y, tg-2zao, tg-gmkt, tg-mbeh,
// pow-1409 — 2026-09-03) produced no spec and no telemetry.
//
// The real `AcpSessionAdapter` codec drives this suite with only its LAUNCH
// faked, so nothing about the protocol's frame shape is invented here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// The real ACP codec with only its LAUNCH faked: the frame decoder, the brief
/// encoder and the adapter id are [AcpSessionAdapter]'s own, so this records
/// delivery without re-implementing the protocol.
class _RecordedCodexAdapter extends AcpSessionAdapter {
  _RecordedCodexAdapter();

  /// Every brief the capability encoded, rendered.
  final List<String> briefs = <String>[];

  /// The telemetry path the capability handed the adapter.
  String? capturedUsageOut;

  @override
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  }) {
    capturedUsageOut = usageOut;
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: 'npx',
      lifecycle: Lifecycle.longLived,
    );
  }

  @override
  List<int> encodeBrief(AgentBrief brief) {
    briefs.add(brief.render());
    return super.encodeBrief(brief);
  }
}

/// A minimal supervised-runtime fake: it accepts writes once started and
/// replays a recorded session's stdout frames on demand.
class _Runtime implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final StreamController<List<int>> _output = StreamController<List<int>>();
  final List<List<int>> writes = <List<int>>[];
  bool running = false;

  void emitFrame(Map<String, Object?> frame) =>
      _output.add(utf8.encode('${jsonEncode(frame)}\n'));

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
  List<String> listRunning(String prefix) =>
      running ? const <String>['session'] : const <String>[];

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeEvent? terminalOf(String name) => null;

  @override
  ({int pid, int? pgid})? identityOf(String name) =>
      running ? (pid: 1, pgid: 1) : null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> dispose() async {
    // `close()` on a single-subscription controller with NO listener never
    // completes, so it is fired and forgotten — same posture as the sibling
    // channel suites' runtime fake.
    if (!_output.isClosed) unawaited(_output.close());
    await _events.close();
  }
}

/// The spec seat armed with the builtin `codex` environment — the base every
/// codex ladder rung composes. A station's own named ladders stay in that
/// station's package, so they are deliberately not referenced here.
({FakeTreeContext context, StepArgs args}) _codexSeat(String workspaceDir) => (
  context: FakeTreeContext(
    values: <Type, Object>{
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
      SpecAgentEnvironment: SpecAgentEnvironment([
        kBuiltinEnvironments['codex']!,
      ]),
    },
  ),
  args: stepArgs('tg-1/spec_review/specify'),
);

void main() {
  test('the spec seat launches the ACP BRIDGE with its telemetry path, not a '
      'codex argv', () {
    final seat = _codexSeat('/w/tg-1');
    final cfg = const SpecifyCapability().spawn(seat.context, seat.args);
    expect(cfg.lifecycle, Lifecycle.longLived);
    expect(cfg.command, Platform.resolvedExecutable);
    final spec = AcpBridgeSpec.fromJson(
      (jsonDecode(cfg.env[kAcpBridgeSpecEnvironment]!) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    expect(spec.command, 'npx');
    expect(spec.args, contains('@agentclientprotocol/codex-acp@1.6.2'));
    expect(spec.cwd, '/w/tg-1');
    expect(
      spec.usageOut,
      '.grid/telemetry/tg-1_spec_review_specify.usage.json',
    );
  });

  test('a recorded codex session receives the BRIEF and its written spec '
      'passes spec-validation', () async {
    final dir = await Directory.systemTemp.createTemp('grid_specify_channel_');
    addTearDown(() async => dir.delete(recursive: true));
    final written = durableSpecifiedBead('tg-1');
    final adapter = _RecordedCodexAdapter();
    final runtime = _Runtime();
    addTearDown(runtime.dispose);
    final capability = SpecifyCapability(
      runnerFor: (_) => SpecifyReadbackBdRunner(beads: <Bead>[written]),
      sessionAdapters: AgentSessionAdapterRegistry(
        <String, AgentSessionAdapter>{kAcpSessionAdapterId: adapter},
      ),
    );
    final seat = _codexSeat(dir.path);
    // The engine's real order: `spawn` renders the launch, the vendor starts
    // the process, THEN `createSession` attaches the protocol.
    final cfg = capability.spawn(seat.context, seat.args);
    expect(cfg.lifecycle, Lifecycle.longLived);
    final session = capability.createSession(
      runtime: runtime,
      name: 'session',
      attemptId: 'a1',
      instanceFence: 'f1',
      context: seat.context,
      args: seat.args,
    )!;
    await runtime.start('session', cfg);
    final terminal = driveProcessSession(
      session: session,
      runtimeEvents: runtime.events,
    );

    // The DELIVERY the argv path dropped: the brief reached the channel whole.
    // `driveProcessSession` calls `start()`, which writes it, so a pump is
    // enough — no wall clock is involved.
    await pumpEventQueue();
    expect(adapter.briefs, hasLength(1));
    final brief = adapter.briefs.single;
    expect(brief, contains('bd update tg-1'));
    expect(brief, contains('## Implementation Plan'));
    expect(brief, contains('## Touches'));
    expect(brief, contains('## ADR Alignment'));
    expect(brief, contains('## Validation Plan'));
    expect(
      adapter.capturedUsageOut,
      '.grid/telemetry/tg-1_spec_review_specify.usage.json',
    );

    // The bridge's own FT-2 write, stood in for here: the channel path must
    // recover usage AND the carried spec through the identical readers.
    writeUsageEnvelope(
      workspaceDir: dir.path,
      usageOut: usageReportPath('tg-1/spec_review/specify'),
      content: usageEnvelopeJson(
        result: jsonEncode(<String, String>{
          'acceptance': written.acceptanceCriteria,
          'design': written.design,
        }),
        tokensIn: 900,
        tokensOut: 120,
        numTurns: 2,
        model: 'gpt-5.6-sol',
      ),
    );
    runtime.emitFrame(<String, Object?>{
      'kind': 'completed',
      'result': <String, Object?>{'text': 'spec written to tg-1'},
      'tokensIn': 900,
      'tokensOut': 120,
      'numTurns': 2,
      'model': 'gpt-5.6-sol',
    });

    final update = await terminal;
    expect(update, isA<ProcessSessionCompleted>());
    final result = (update as ProcessSessionCompleted).result;
    expect(result['tokensIn'], '900');
    expect(result['model'], 'gpt-5.6-sol');
    expect(result[kCarriedSpecAcceptanceKey], written.acceptanceCriteria);
    expect(result[kCarriedSpecDesignKey], written.design);

    // The declared completion artifact is STRUCTURALLY VALID — the same pure
    // check `SpecValidationCapability` grades with.
    expect(specStructuralFindings(written), isEmpty);
    expect(
      specForStructuralValidation(
        fallback: bead('tg-1'),
        specifyResult: result,
      )?.design,
      written.design,
    );
  });

  test('an artifact-less codex completion fails exit-code-led, adapter-named '
      'and tail-first', () async {
    final adapter = _RecordedCodexAdapter();
    final runtime = _Runtime();
    addTearDown(runtime.dispose);
    final capability = SpecifyCapability(
      // A bead whose spec fields are still empty — the live tg-2zao shape.
      runnerFor: (_) => SpecifyReadbackBdRunner(beads: <Bead>[bead('tg-1')]),
      sessionAdapters: AgentSessionAdapterRegistry(
        <String, AgentSessionAdapter>{kAcpSessionAdapterId: adapter},
      ),
    );
    final seat = _codexSeat('/w/tg-1');
    final session = capability.createSession(
      runtime: runtime,
      name: 'session',
      attemptId: 'a1',
      instanceFence: 'f1',
      context: seat.context,
      args: seat.args,
    )!;
    await runtime.start(
      'session',
      const RuntimeConfig(workDir: '/tmp', command: 'npx'),
    );
    final terminal = driveProcessSession(
      session: session,
      runtimeEvents: runtime.events,
    );
    await pumpEventQueue();
    final transcript =
        'HEAD-OF-TRANSCRIPT\n${'z' * 4000}\nbd: command not found';
    runtime.emitFrame(<String, Object?>{
      'kind': 'completed',
      'result': <String, Object?>{'text': transcript},
      'tokensIn': 10,
      'tokensOut': 5,
      'numTurns': 1,
      'model': 'gpt-5.6-sol',
    });

    final update = await terminal;
    expect(update, isA<ProcessSessionFailed>());
    final reason = (update as ProcessSessionFailed).reason;
    expect(reason, startsWith('specify failed (exit 0) [acp]: '));
    expect(reason, contains('declared completion artifact is not durable — …'));
    expect(reason, contains('bd: command not found'));
    expect(reason, isNot(contains('HEAD-OF-TRANSCRIPT')));
    expect(reason.length, lessThan(kRevalidateReasonTailChars + 200));
  });

  test('an ARGV environment on the same seat has no channel session — the '
      'engine\'s one-turn dispatch still owns it', () {
    final context = FakeTreeContext(
      values: <Type, Object>{
        Bead: bead('tg-1'),
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: '/w/tg-1',
          branch: 'grid/tg-1',
        ),
      },
    );
    final args = stepArgs('tg-1/spec_review/specify');
    final runtime = _Runtime();
    addTearDown(runtime.dispose);
    expect(
      const SpecifyCapability().createSession(
        runtime: runtime,
        name: 'session',
        attemptId: 'a1',
        instanceFence: 'f1',
        context: context,
        args: args,
      ),
      isNull,
    );
  });
}
