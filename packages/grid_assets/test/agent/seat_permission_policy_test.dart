// The ARMED SEAT is a channel's admitted identity (bead `pow-ed1c`).
//
// The station boundary that replaced the blanket ACP grant is only half a
// boundary if every seat lands on the floor: the two production channels — the
// build agent and the spec architect — must still AUTHORIZE their own work when
// the station armed them, and must still refuse when it did not. This suite
// fences both halves.
//
// The real `AcpSessionAdapter` codec and the real `GridPolicyAcpClient` drive
// it, with only the supervised process faked: the bridge's loopback (publish the
// ask, wait for the station's answer, complete on the encoded
// `permission_decision`) is reproduced in memory, so nothing about the protocol
// or the decision path is invented here. No wall clock, no subprocess.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// The ACP protocol session every armed channel binds to.
const String _protocolSession = 'acp-session-1';

/// The attempt this incarnation is admitted under.
const String _attempt = 'attempt-1';

const String _rejectOption = 'opt-reject-once';
const String _allowAlwaysOption = 'opt-allow-always';

/// The codex builtin — the ACP-backed environment lunar's coded arming puts on
/// both seats, so the seats under test are the ones that actually ship.
AgentEnvironment get _codex => kBuiltinEnvironments['codex']!;

/// Ends every probe tree (the `typed_environment_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Runs [read] once, at build, over the mounted context.
class _Probe extends StatelessSeed {
  const _Probe(this.read);
  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}

/// A minimal supervised-runtime Fake: it accepts writes once started, replays
/// frames on demand, and — standing in for the bridge's control stream — routes
/// an encoded `permission_decision` back to the ask waiting for it.
class _Runtime implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final StreamController<List<int>> _output = StreamController<List<int>>();

  /// Every frame the session wrote, decoded.
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];

  /// Every authorization the session wrote back, in order.
  final List<AgentPermissionDecision> decisions = <AgentPermissionDecision>[];

  /// The bridge's `answerPermission`, injected.
  void Function(AgentPermissionDecision decision)? onDecision;

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
    final frame = (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
        .cast<String, Object?>();
    writes.add(frame);
    if (frame['kind'] != 'permission_decision') return;
    final decision = AgentPermissionDecision.fromJson(
      (frame['decision']! as Map<String, dynamic>).cast<String, Object?>(),
    );
    decisions.add(decision);
    onDecision?.call(decision);
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
    // completes, so it is fired and forgotten — the sibling channel suites'
    // posture.
    if (!_output.isClosed) unawaited(_output.close());
    await _events.close();
  }
}

/// The BRIDGE's permission loopback, in memory: the real
/// [GridPolicyAcpClient] asking, [_Runtime] carrying the ask out as a
/// `permission_request` frame, and the station's encoded `permission_decision`
/// completing it — exactly `_AcpBridgeDriver.askStation`/`answerPermission`.
class _AcpLoopback {
  _AcpLoopback(this._runtime) {
    client = GridPolicyAcpClient(
      attemptId: _attempt,
      onUpdate: (_) {},
      decide: _ask,
      // The bridge-LOCAL cancellations, which an admitted happy path never
      // produces.
      audit: fallbacks.add,
    );
    _runtime.onDecision = _answer;
  }

  final _Runtime _runtime;
  final Map<String, Completer<AgentPermissionDecision?>> _pending =
      <String, Completer<AgentPermissionDecision?>>{};

  /// The client under test, with the PRODUCTION decision timeout.
  late final GridPolicyAcpClient client;

  /// Every cancellation the client produced on its own.
  final List<AgentPermissionDecision> fallbacks = <AgentPermissionDecision>[];

  Future<AgentPermissionDecision?> _ask(AgentPermissionRequest request) {
    final completer = Completer<AgentPermissionDecision?>();
    _pending[request.requestId] = completer;
    _runtime.emitFrame(<String, Object?>{
      'kind': 'permission_request',
      'request': request.toJson(),
    });
    return completer.future;
  }

  void _answer(AgentPermissionDecision decision) {
    final pending = _pending.remove(decision.requestId);
    if (pending == null || pending.isCompleted) return;
    pending.complete(decision);
  }

  /// Asks to EXECUTE, offering a narrow refusal and a durable grant — the
  /// widest thing a codex tool call puts on the table.
  Future<RequestPermissionResponse> requestExecute({
    String sessionId = _protocolSession,
  }) => client.requestPermission(
    RequestPermissionRequest(
      sessionId: sessionId,
      toolCall: ToolCallUpdate(
        toolCallId: 'tool-1',
        kind: ToolKind.execute,
        title: 'rm -rf the-secret-worktree',
        rawInput: const <String, dynamic>{'command': 'rm -rf .'},
      ),
      options: <PermissionOption>[
        PermissionOption(
          optionId: _rejectOption,
          name: 'Reject',
          kind: PermissionOptionKind.rejectOnce,
        ),
        PermissionOption(
          optionId: _allowAlwaysOption,
          name: 'Always allow',
          kind: PermissionOptionKind.allowAlways,
        ),
      ],
    ),
  );
}

/// Which production channel a seat opens.
enum _Which { build, spec }

typedef _Seat = ({
  ProcessSession session,
  _Runtime runtime,
  _AcpLoopback acp,
  RecordingExplorationTransport transport,
  List<ProcessSessionUpdate> updates,
});

/// Opens one production channel over the Fake runtime, exactly as the engine
/// does: `createSession` at the capability's effect edge, `start()`, then the
/// binding announcement that makes a later ask addressable.
Future<_Seat> _openSeat(
  _Which which, {
  BuildAgentEnvironment? build,
  SpecAgentEnvironment? spec,
  ModelPreference? generic,
  AgentPermissionPolicy? policy,
}) async {
  final transport = RecordingExplorationTransport();
  final context = FakeTreeContext(
    values: <Type, Object>{
      Bead: bead('tg-1'),
      // A workspace dir that was never materialized: an offline/dry-run seat,
      // so nothing in this suite touches a filesystem.
      Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
      ServiceBundle: ServiceBundle(transport: transport),
      if (build != null) BuildAgentEnvironment: build,
      if (spec != null) SpecAgentEnvironment: spec,
      if (generic != null) ModelPreference: generic,
      if (policy != null) AgentPermissionPolicy: policy,
    },
  );
  final args = stepArgs(
    which == _Which.build ? 'tg-1/code/agent' : 'tg-1/spec_review/specify',
  );
  final runtime = _Runtime();
  addTearDown(runtime.dispose);
  final session = switch (which) {
    _Which.build => const AgentCapability().createSession(
      runtime: runtime,
      name: 'session',
      attemptId: _attempt,
      instanceFence: 'fence-1',
      context: context,
      args: args,
    ),
    _Which.spec =>
      SpecifyCapability(
        // The durable read-back seam, faked: this suite never completes a
        // session, so the runner is here only to keep a process off the path.
        runnerFor: (_) => SpecifyReadbackBdRunner(beads: <Bead>[bead('tg-1')]),
      ).createSession(
        runtime: runtime,
        name: 'session',
        attemptId: _attempt,
        instanceFence: 'fence-1',
        context: context,
        args: args,
      ),
  };
  expect(session, isNotNull, reason: 'the codex builtin is a CHANNEL seat');
  final updates = <ProcessSessionUpdate>[];
  final subscription = session!.updates.listen(updates.add);
  addTearDown(subscription.cancel);
  addTearDown(session.close);
  await runtime.start(
    'session',
    const RuntimeConfig(workDir: '/w/tg-1', command: 'npx'),
  );
  await session.start();
  await pumpEventQueue();
  runtime.emitFrame(<String, Object?>{
    'kind': 'session_bound',
    'attemptId': _attempt,
    'sessionId': _protocolSession,
  });
  await pumpEventQueue();
  return (
    session: session,
    runtime: runtime,
    acp: _AcpLoopback(runtime),
    transport: transport,
    updates: updates,
  );
}

/// The option kind the client selected, or null when it cancelled.
PermissionOptionKind? _selected(RequestPermissionResponse response) =>
    switch (response.outcome) {
      SelectedOutcome(:final optionId) when optionId == _allowAlwaysOption =>
        PermissionOptionKind.allowAlways,
      SelectedOutcome(:final optionId) when optionId == _rejectOption =>
        PermissionOptionKind.rejectOnce,
      SelectedOutcome(:final optionId) => fail('unknown option $optionId'),
      _ => null,
    };

/// Resolves the seat policy under a REAL [TypedEnvironmentProvider] — the same
/// seed production mounts — with an optional explicit station policy above it.
AgentPermissionPolicy _underProvider<TSeat extends ModelPreference>(
  AgentArming arming, {
  required String seatId,
  AgentPermissionPolicy? policy,
}) {
  late final AgentPermissionPolicy observed;
  final owner = TreeOwner();
  Seed tree = TypedEnvironmentProvider(
    arming: arming,
    child: _Probe(
      (context) => observed = seatChannelPolicy<TSeat>(context, seatId: seatId),
    ),
  );
  if (policy != null) {
    tree = InheritedSeed<AgentPermissionPolicy>(value: policy, child: tree);
  }
  owner.mountRoot(tree);
  owner.flush();
  owner.dispose();
  return observed;
}

String _source(String relative) {
  final local = File(relative);
  if (local.existsSync()) return local.readAsStringSync();
  return File('packages/grid_assets/$relative').readAsStringSync();
}

void main() {
  test('the seat identity comes from the typed seat arming', () {
    const arming = AgentArming(
      build: BuildAgentEnvironment(<AgentEnvironment>[]),
      spec: SpecAgentEnvironment(<AgentEnvironment>[]),
    );

    // THE EXACT TYPE IS THE IDENTITY (ADR-0006 D2): each seat derives the
    // station's trusted-headless posture under its OWN const audit id.
    expect(
      _underProvider<BuildAgentEnvironment>(
        const AgentArming(build: BuildAgentEnvironment(<AgentEnvironment>[])),
        seatId: kBuildSeatPolicyId,
      ),
      const AgentPermissionPolicy.trustedHeadless(id: kBuildSeatPolicyId),
    );
    expect(
      _underProvider<SpecAgentEnvironment>(
        const AgentArming(spec: SpecAgentEnvironment(<AgentEnvironment>[])),
        seatId: kSpecSeatPolicyId,
      ),
      const AgentPermissionPolicy.trustedHeadless(id: kSpecSeatPolicyId),
    );
    expect(kBuildSeatPolicyId, 'seat:build');
    expect(kSpecSeatPolicyId, 'seat:spec');

    // A DIFFERENT seat's arming is not this seat's identity.
    expect(
      _underProvider<SpecAgentEnvironment>(
        const AgentArming(build: BuildAgentEnvironment(<AgentEnvironment>[])),
        seatId: kSpecSeatPolicyId,
      ),
      const AgentPermissionPolicy.unavailable(),
    );

    // An EXPLICIT station policy wins outright, unchanged — including the
    // lock-down, which is how a station refuses over an armed seat.
    const scoped = AgentPermissionPolicy.scoped(
      id: 'station',
      grants: <AgentPermissionCapability, AgentPermissionGrant>{
        AgentPermissionCapability.read: AgentPermissionGrant.allowOnce,
      },
    );
    expect(
      _underProvider<BuildAgentEnvironment>(
        arming,
        seatId: kBuildSeatPolicyId,
        policy: scoped,
      ),
      scoped,
    );
    expect(
      _underProvider<BuildAgentEnvironment>(
        arming,
        seatId: kBuildSeatPolicyId,
        policy: const AgentPermissionPolicy.unavailable(),
      ),
      const AgentPermissionPolicy.unavailable(),
    );

    // The GENERIC preference is the station's model default, NOT an arming of
    // this seat: it never confers an identity, on either seat.
    final generic = FakeTreeContext(
      values: <Type, Object>{
        ModelPreference: ModelPreference([_codex]),
      },
    );
    expect(
      seatChannelPolicy<BuildAgentEnvironment>(
        generic,
        seatId: kBuildSeatPolicyId,
      ),
      const AgentPermissionPolicy.unavailable(),
    );
    expect(
      seatChannelPolicy<SpecAgentEnvironment>(
        generic,
        seatId: kSpecSeatPolicyId,
      ),
      const AgentPermissionPolicy.unavailable(),
    );
    // Nothing mounted at all is the same floor.
    expect(
      seatChannelPolicy<BuildAgentEnvironment>(
        FakeTreeContext(),
        seatId: kBuildSeatPolicyId,
      ),
      const AgentPermissionPolicy.unavailable(),
    );

    // The pure vocabulary stays pure: the resolution needs the tree, so it
    // lives at the seat rung and `permission_policy.dart` takes no context —
    // it imports no tree and declares no parameter over one.
    final policySource = _source('lib/src/agent/permission_policy.dart');
    expect(policySource, isNot(contains("import 'package:genesis_tree")));
    expect(policySource, isNot(contains('TreeContext context')));
    expect(
      _source('lib/src/agent/seat_environments.dart'),
      contains('seatChannelPolicy'),
    );
  });

  test('an armed build seat grants an ACP permission request', () async {
    final seat = await _openSeat(
      _Which.build,
      build: BuildAgentEnvironment([_codex]),
    );

    final response = await seat.acp.requestExecute();

    // The station ANSWERED, durably, and the harness got exactly that answer.
    expect(_selected(response), PermissionOptionKind.allowAlways);
    final flare = seat.transport.named(kAgentAuthorizationDecisionFlare).single;
    expect(flare.data, containsPair('policyId', kBuildSeatPolicyId));
    expect(flare.data, containsPair('outcome', 'allowAlways'));
    expect(flare.data, containsPair('capability', 'execute'));
    expect(flare.data, containsPair('attemptId', _attempt));
    expect(flare.data, containsPair('protocolSessionId', _protocolSession));
    // REDACTED: the harness's own words never reach the audit.
    expect(flare.data.values, isNot(contains(contains('rm -rf'))));
    expect(seat.acp.fallbacks, isEmpty);
    expect(seat.updates.whereType<ProcessSessionFailed>(), isEmpty);
  });

  test('an armed spec seat grants an ACP permission request', () async {
    final seat = await _openSeat(
      _Which.spec,
      spec: SpecAgentEnvironment([_codex]),
    );

    final response = await seat.acp.requestExecute();

    expect(_selected(response), PermissionOptionKind.allowAlways);
    final flare = seat.transport.named(kAgentAuthorizationDecisionFlare).single;
    expect(flare.data, containsPair('policyId', kSpecSeatPolicyId));
    expect(flare.data, containsPair('outcome', 'allowAlways'));
    expect(seat.acp.fallbacks, isEmpty);
    expect(seat.updates.whereType<ProcessSessionFailed>(), isEmpty);
  });

  test('an unarmed seat still refuses', () async {
    // A GENERIC-only channel: the ACP session exists (codex still resolves),
    // but no typed seat admitted it, so there is no identity to authorize.
    for (final which in _Which.values) {
      final seat = await _openSeat(which, generic: ModelPreference([_codex]));
      final response = await seat.acp.requestExecute();
      expect(
        _selected(response),
        PermissionOptionKind.rejectOnce,
        reason: '${which.name}: a generic default is not a seat identity',
      );
      expect(
        seat.transport
            .named(kAgentAuthorizationDecisionFlare)
            .every((flare) => flare.data['outcome'] != 'allowAlways'),
        isTrue,
        reason: which.name,
      );
    }

    // An explicit LOCK-DOWN over an ARMED seat: the station's own value wins,
    // and the seat's arming does not climb over it.
    for (final which in _Which.values) {
      final seat = await _openSeat(
        which,
        build: BuildAgentEnvironment([_codex]),
        spec: SpecAgentEnvironment([_codex]),
        policy: const AgentPermissionPolicy.unavailable(),
      );
      final response = await seat.acp.requestExecute();
      expect(
        _selected(response),
        PermissionOptionKind.rejectOnce,
        reason: '${which.name}: an explicit lock-down is not widened',
      );
      expect(
        seat.runtime.decisions.every((decision) => !decision.grants),
        isTrue,
        reason: which.name,
      );
    }
  });

  test('an armed seat answers well inside the decision timeout', () async {
    // The PRODUCTION bound, untouched: the round trip is a parent-process
    // decision, so an admitted seat settles in event-queue turns and never
    // reaches it.
    expect(kAcpPermissionDecisionTimeout, const Duration(seconds: 30));

    final seat = await _openSeat(
      _Which.build,
      build: BuildAgentEnvironment([_codex]),
    );
    expect(seat.acp.client.timeout, kAcpPermissionDecisionTimeout);

    var settled = false;
    final pending = seat.acp.requestExecute().then((response) {
      settled = true;
      return response;
    });
    // NO clock is advanced and no delay is awaited: pumping alone must settle
    // it, or the happy path was riding the timeout.
    await pumpEventQueue();
    expect(settled, isTrue);
    expect(_selected(await pending), PermissionOptionKind.allowAlways);

    // The write leg SUCCEEDED — one encoded authorization reached the harness,
    // so `_respond` never failed the session.
    expect(seat.runtime.decisions, hasLength(1));
    expect(seat.runtime.decisions.single.grants, isTrue);
    expect(seat.acp.fallbacks, isEmpty);
    expect(seat.updates.whereType<ProcessSessionFailed>(), isEmpty);
  });
}
