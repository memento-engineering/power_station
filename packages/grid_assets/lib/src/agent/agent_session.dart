import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'captured_output.dart';
import 'permission_policy.dart';
import 'usage_report.dart';

part 'agent_session.freezed.dart';
part 'agent_session.g.dart';

/// One harness-owned protocol event decoded into the grid-side vocabulary.
@freezed
sealed class AgentProtocolEvent with _$AgentProtocolEvent {
  /// Reports non-terminal harness progress.
  const factory AgentProtocolEvent.progress({
    @Default(<String, String>{}) Map<String, String> fields,
  }) = AgentProtocolProgress;

  /// Reports harness completion with structured result and usage.
  const factory AgentProtocolEvent.completed({
    required Map<String, String> result,
    required UsageReport usage,
  }) = AgentProtocolCompleted;

  /// Reports a harness protocol failure.
  const factory AgentProtocolEvent.failed({required String reason}) =
      AgentProtocolFailed;

  /// Reports that the harness bound a protocol session for [attemptId].
  ///
  /// NON-TERMINAL. It is what makes an authorization addressable: every later
  /// permission ask names [protocolSessionId], and a reconnect re-binds, so a
  /// request from the superseded session is stale on arrival.
  const factory AgentProtocolEvent.sessionBound({
    required String attemptId,
    required String protocolSessionId,
  }) = AgentProtocolSessionBound;

  /// Reports one mid-turn permission ask awaiting the STATION's answer.
  ///
  /// NON-TERMINAL, and normalized: [request] carries identities and offered
  /// answers only — never the harness's tool title, input, output or labels.
  const factory AgentProtocolEvent.permissionRequested({
    required AgentPermissionRequest request,
  }) = AgentProtocolPermissionRequested;

  /// Reports an authorization the CHANNEL itself already settled — always a
  /// cancellation, never a grant.
  ///
  /// NON-TERMINAL. The bridge answers the harness locally when the station's
  /// decision could not be applied (no answer, a mismatched one, a timeout, a
  /// cancellation); this carries that record up so the one durable audit trail
  /// still sees it. Nothing is written back for it.
  const factory AgentProtocolEvent.permissionFallback({
    required AgentPermissionDecision decision,
  }) = AgentProtocolPermissionFallback;
}

/// The OPTIONAL authorization half of an [AgentSessionAdapter].
///
/// An adapter implements it when its protocol has a permission handshake; one
/// that does not is answered nothing at all, which is fail-closed — the harness
/// never receives a grant it was not given.
abstract interface class AgentAuthorizationAdapter {
  /// Encodes one station [decision] for delivery over the channel.
  List<int> encodePermissionDecision(AgentPermissionDecision decision);
}

/// The out-of-band flare every policy-produced authorization is recorded on.
///
/// It rides the SAME emit-only [ExplorationTransport] the orphan observation
/// uses (D-8) — the station's existing durable carrier, no new store. Unlike
/// that observation, though, its absence is not benign: with no carrier there
/// is no record, and [decideAgentPermission] refuses rather than granting
/// something nobody could read back.
const String kAgentAuthorizationDecisionFlare = 'agent.authorizationDecision';

/// Per-harness launch, encoding, and decoding behavior.
abstract interface class AgentSessionAdapter {
  /// Stable registry identity for this adapter.
  String get id;

  /// Describes a long-lived launch without access to the brief.
  ///
  /// [usageOut] is the workspace-relative FT-2 telemetry path
  /// ([usageReportPath]) this incarnation's usage envelope must land at. The
  /// argv transport gets this through its `sh -c` wrapper; a channel harness
  /// has no wrapper, so the adapter carries it to whatever writes the
  /// envelope. An adapter with no telemetry surface IGNORES it.
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  });

  /// Encodes the initial brief for delivery over the channel.
  List<int> encodeBrief(AgentBrief brief);

  /// Encodes one mid-run steer for delivery over the channel.
  List<int> encodeSteer(String text);

  /// Decodes raw stdout into protocol observations.
  Stream<AgentProtocolEvent> decode(Stream<List<int>> stdout);
}

/// Immutable adapter implementations injected at station composition.
class AgentSessionAdapterRegistry {
  /// Creates a registry over [adapters].
  const AgentSessionAdapterRegistry([
    Map<String, AgentSessionAdapter> adapters =
        const <String, AgentSessionAdapter>{},
  ]) : _adapters = adapters;

  final Map<String, AgentSessionAdapter> _adapters;

  /// Resolves [id] or refuses loudly.
  AgentSessionAdapter require(String id) =>
      _adapters[id] ??
      (throw StateError('No AgentSessionAdapter registered for "$id"'));
}

/// Work-bead metadata key containing one JSON-encoded fenced steer.
const String kAgentSteerMetadataKey = 'grid.agent.steer.v1';

/// Typed decode shape for the durable steer metadata value.
@freezed
abstract class FencedAgentSteer with _$FencedAgentSteer {
  /// Creates an attempt- and instance-fenced steer.
  const factory FencedAgentSteer({
    required String commandId,
    required String attemptId,
    required String instanceFence,
    required String text,
  }) = _FencedAgentSteer;

  /// Decodes a fenced steer from metadata JSON.
  factory FencedAgentSteer.fromJson(Map<String, Object?> json) =>
      _$FencedAgentSteerFromJson(json);
}

/// Read-only source of bead-routed commands for one work bead.
abstract interface class AgentSteerSource {
  /// Watches commands addressed to [workBeadId].
  Stream<ProcessSessionCommand> watch(String workBeadId);
}

/// Empty source used when a composition has no command observer.
class NoAgentSteerSource implements AgentSteerSource {
  /// Creates an empty command source.
  const NoAgentSteerSource();

  @override
  Stream<ProcessSessionCommand> watch(String workBeadId) =>
      const Stream<ProcessSessionCommand>.empty();
}

/// Projects fenced commands from the existing live bead event surface.
class BeadRoutedAgentSteerSource implements AgentSteerSource {
  /// Creates a read-only command projection over [_source].
  const BeadRoutedAgentSteerSource(this._source);

  final ReadyWorkSource _source;

  @override
  Stream<ProcessSessionCommand> watch(String workBeadId) {
    StreamSubscription<GraphEvent>? subscription;
    late final StreamController<ProcessSessionCommand> controller;
    void emit(Bead? bead) {
      if (bead == null) return;
      try {
        final command = _decode(bead);
        if (command != null) controller.add(command);
      } on Object catch (error, stack) {
        controller.addError(error, stack);
      }
    }

    controller = StreamController<ProcessSessionCommand>(
      onListen: () {
        emit(_source.bead(workBeadId));
        subscription = _source.events.listen(
          (event) {
            final bead = switch (event) {
              BeadCreated(:final bead) when bead.id == workBeadId => bead,
              BeadUpdated(:final after) when after.id == workBeadId => after,
              SnapshotInitialized() ||
              BeadClosed() ||
              BeadReopened() ||
              BeadDeleted() ||
              DependencyAdded() ||
              DependencyRemoved() ||
              ReadySetChanged() => null,
              BeadCreated() || BeadUpdated() => null,
            };
            emit(bead);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  ProcessSessionCommand? _decode(Bead bead) {
    final raw = bead.metadata[kAgentSteerMetadataKey];
    if (raw == null) return null;
    if (raw is! String) {
      throw const FormatException('agent steer metadata must be JSON text');
    }
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) {
      throw const FormatException('agent steer metadata must be an object');
    }
    final steer = FencedAgentSteer.fromJson(json);
    return ProcessSessionCommand(
      commandId: steer.commandId,
      attemptId: steer.attemptId,
      instanceFence: steer.instanceFence,
      body: steer.text,
    );
  }
}

/// Grid-side session joining one adapter, supervised child, and steer stream.
class AgentSession implements ProcessSession {
  /// Creates a channel session for one live process incarnation.
  AgentSession({
    required this.runtime,
    required this.name,
    required this.adapter,
    required this.brief,
    required this.commands,
    required this.attemptId,
    required this.instanceFence,
    this.transport,
    this.policy = const AgentPermissionPolicy.unavailable(),
  });

  /// The sole owner of the supervised child and its byte interaction surface.
  final RuntimeProvider runtime;

  /// The runtime provider's session name.
  final String name;

  /// Harness-specific launch, frame, and decode behavior.
  final AgentSessionAdapter adapter;

  /// Initial work content sent only after protocol subscriptions attach.
  final AgentBrief brief;

  /// Live bead-routed commands addressed to this work.
  final Stream<ProcessSessionCommand> commands;

  /// Durable attempt identity accepted by [send].
  final String attemptId;

  /// Live process-incarnation fence accepted by [send].
  final String instanceFence;

  /// The out-of-band flare sink for observations that are NOT protocol updates
  /// (emit-only, D-8). Null — the composition mounted no transport — drops the
  /// observation; it is never a session failure.
  final ExplorationTransport? transport;

  /// The STATION's authorization boundary for this channel, read as a VALUE at
  /// the capability's effect edge. Defaults to
  /// [AgentPermissionPolicy.unavailable] — an unconfigured composition grants
  /// nothing, which is how the boundary can be added without trusting anything
  /// by omission.
  final AgentPermissionPolicy policy;

  final StreamController<ProcessSessionUpdate> _updates =
      StreamController<ProcessSessionUpdate>();
  final Set<String> _seen = <String>{};
  StreamSubscription<AgentProtocolEvent>? _decoderSub;
  StreamSubscription<ProcessSessionCommand>? _commandSub;
  bool _terminal = false;

  /// The harness protocol session currently bound to [attemptId]; null until a
  /// valid [AgentProtocolEvent.sessionBound] arrives, and REPLACED on a
  /// reconnect so the prior id's asks become stale.
  String? _protocolSessionId;

  @override
  Stream<ProcessSessionUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    _decoderSub = adapter
        .decode(runtime.interactionOutput(name))
        .listen(
          _onProtocol,
          onError: _onDecoderError,
          onDone: () =>
              _fail('protocol stream closed before protocol completion'),
        );
    _commandSub = commands.listen(
      (command) => unawaited(_sendObserved(command)),
      onError: _onDecoderError,
    );
    await runtime.write(name, adapter.encodeBrief(brief));
  }

  Future<void> _sendObserved(ProcessSessionCommand command) async {
    try {
      await send(command);
    } on Object catch (error, stack) {
      _onDecoderError(error, stack);
    }
  }

  void _onProtocol(AgentProtocolEvent event) {
    if (_terminal) return;
    switch (event) {
      case AgentProtocolProgress(:final fields):
        _updates.add(ProcessSessionUpdate.progress(fields: fields));
      case AgentProtocolCompleted(:final result, :final usage):
        _terminal = true;
        _updates.add(
          ProcessSessionUpdate.completed(
            result: <String, String>{...result, ...usage.toResultFields()},
          ),
        );
      case AgentProtocolFailed(:final reason):
        _fail(reason);
      case AgentProtocolSessionBound(
        attemptId: final bound,
        :final protocolSessionId,
      ):
        // ONLY the admitted attempt's binding counts. A blank or foreign
        // attempt, or a blank session id, leaves this channel UNBOUND — every
        // later ask then fails closed for want of a bound session rather than
        // being answered against a binding nobody admitted.
        if (bound.trim().isEmpty ||
            bound != attemptId ||
            protocolSessionId.trim().isEmpty) {
          return;
        }
        _protocolSessionId = protocolSessionId;
      case AgentProtocolPermissionRequested(:final request):
        _authorize(request);
      case AgentProtocolPermissionFallback(:final decision):
        // Already answered by the bridge, and always a cancellation: record it
        // and write NOTHING — a second response would race the first.
        _audit(decision);
    }
  }

  /// Decides one permission ask against the station's [policy], RECORDS the
  /// decision, then answers the harness — in that order, so no grant can reach
  /// a harness without a durable record of it existing first.
  void _authorize(AgentPermissionRequest request) {
    // The authorization half is OPTIONAL on an adapter, and the two interfaces
    // are unrelated, so the narrowing is a pattern rather than a promotion.
    final authorization = switch (adapter) {
      final AgentAuthorizationAdapter authorization => authorization,
      _ => null,
    };
    final decision = authorization != null
        ? decideAgentPermission(
            policy: policy,
            request: request,
            admittedAttemptId: attemptId,
            boundSessionId: _protocolSessionId,
            // The audit carrier IS the authorization's durability. Absent, the
            // decision function refuses; it never grants unrecorded.
            audited: transport != null,
          )
        : AgentPermissionDecision.cancelled(
            request: request,
            policyId: policy.id,
            reason: 'the channel adapter cannot answer an authorization',
          );
    _audit(decision);
    if (authorization == null) return;
    unawaited(_respond(authorization, decision));
  }

  void _audit(AgentPermissionDecision decision) => transport?.flare(
    kAgentAuthorizationDecisionFlare,
    decision.auditFields(channelSessionId: name),
  );

  Future<void> _respond(
    AgentAuthorizationAdapter authorization,
    AgentPermissionDecision decision,
  ) async {
    try {
      await runtime.write(
        name,
        authorization.encodePermissionDecision(decision),
      );
    } on Object catch (error) {
      // The answer never reached the harness: the ask stays unanswered and the
      // bridge cancels it. The channel itself is broken, so fail LOUD.
      _fail('authorization response failed: $error');
    }
  }

  void _onDecoderError(Object error, StackTrace stack) {
    _fail('malformed protocol frame: $error');
    unawaited(_decoderSub?.cancel());
  }

  @override
  void onRuntimeEvent(RuntimeEvent event) {
    if (_terminal) return;
    switch (event) {
      case Exited() || Died():
        _fail('process ended before protocol completion');
      case SessionOrphaned(:final pgid, :final memberCount):
        // NOT a terminal and NOT a state change (grid_runtime
        // `RuntimeEvent.sessionOrphaned`): the leader is gone but the OWNED
        // group still has live members, so the session stays supervised until
        // the group empties or the provider's bounded grace elapses. Record the
        // observation and leave the session exactly where it is; the
        // `Exited`/`Died` that follows IS the terminal and has its own arm.
        transport?.flare('agent.sessionOrphaned', <String, String>{
          'sessionId': event.name,
          'pgid': '$pgid',
          'memberCount': '$memberCount',
        });
        return;
      case SessionStarted() || Respawned() || ActivityChanged():
        return;
    }
  }

  @override
  Future<ProcessCommandDisposition> send(ProcessSessionCommand command) async {
    final disposition = _terminal
        ? ProcessCommandDisposition.terminal
        : command.attemptId != attemptId
        ? ProcessCommandDisposition.staleAttempt
        : command.instanceFence != instanceFence
        ? ProcessCommandDisposition.wrongFence
        : !_seen.add(command.commandId)
        ? ProcessCommandDisposition.duplicate
        : ProcessCommandDisposition.delivered;
    if (disposition == ProcessCommandDisposition.delivered) {
      await runtime.write(name, adapter.encodeSteer(command.body));
    }
    return disposition;
  }

  void _fail(String reason) {
    if (_terminal) return;
    _terminal = true;
    _updates.add(ProcessSessionUpdate.failed(reason: reason));
  }

  @override
  Future<void> close() async {
    _terminal = true;
    await _commandSub?.cancel();
    await _decoderSub?.cancel();
    if (!_updates.isClosed) await _updates.close();
  }
}

/// The HARNESS-NEUTRAL spawn (bead `pow-39tl`): one resolved [environment]
/// rendered into a process invocation, whichever transport it declares.
///
/// An environment naming an [AgentEnvironment.sessionAdapter] launches
/// LONG-LIVED through that adapter and receives its [brief] over the channel
/// once the protocol is up ([AgentSession.start]); one that does not renders
/// the brief into argv through [spawnFor]. Before this seam existed the branch
/// lived in ONE caller, and the spec seat — which called [spawnFor] directly —
/// spawned a channel harness as a one-turn process with an EMPTY prompt
/// segment (`PromptMode.none`), so the brief was never delivered at all.
///
/// GUARD, LOUD: a channel adapter that does not launch [Lifecycle.longLived]
/// throws — the brief arrives AFTER startup, so a one-turn channel launch can
/// only ever produce a briefless run.
RuntimeConfig spawnThroughSessionAdapter({
  required AgentSessionAdapterRegistry adapters,
  required AgentEnvironment environment,
  required AgentBrief brief,
  required Workspace workspace,
  String? model,
  String? usageOut,
  Uri? endpoint,
}) {
  final adapterId = environment.sessionAdapter;
  if (adapterId == null) {
    return spawnFor(
      environment: environment,
      brief: brief,
      workspace: workspace,
      model: model,
      usageOut: usageOut,
      endpoint: endpoint,
    );
  }
  final config = adapters
      .require(adapterId)
      .launch(
        environment: environment,
        workspace: workspace,
        model: model,
        endpoint: endpoint,
        usageOut: usageOut,
      );
  if (config.lifecycle != Lifecycle.longLived) {
    throw StateError('channel adapter "$adapterId" must launch longLived');
  }
  return config;
}

/// Re-applies a capability's DECLARED [CompletionContract.artifactDurability]
/// on the CHANNEL path, and contributes that capability's `result()` fields
/// (bead `pow-39tl`).
///
/// The engine fences an artifact-durability completion in its process
/// dispatcher, which a session-driven step never reaches — the vendor returns
/// the session's terminal verbatim. A channel harness that ends its turn
/// without writing the artifact therefore completed SILENTLY, and its step
/// result carried neither the FT-2 usage fields nor any transport-carried
/// payload. This decorator restores both, so ONE brief behaves identically on
/// either transport.
///
/// [probe] and [resultFields] are the composing capability's own — read at the
/// decorator's construction site, where the branch is mounted.
class ArtifactFencedSession implements ProcessSession {
  /// Wraps [inner], fencing its completion on [probe] and merging
  /// [resultFields] into the forwarded result. [verb] and [adapter] name the
  /// step and its transport in the failure reason.
  ///
  /// Subscribes to [inner] EAGERLY, in the constructor: the engine's
  /// retained-terminal path calls `onRuntimeEvent` WITHOUT ever calling
  /// `start()`, so a decorator that attached in `start()` would forward
  /// nothing and hang the dispatch.
  ArtifactFencedSession({
    required this.inner,
    required this.probe,
    required this.resultFields,
    required this.verb,
    required this.adapter,
  }) {
    _sub = inner.updates.listen(
      _onUpdate,
      onError: _updates.addError,
      onDone: () {
        if (!_terminal && !_updates.isClosed) _updates.close();
      },
    );
  }

  /// The protocol session being fenced.
  final ProcessSession inner;

  /// The composing capability's artifact probe.
  final Future<GateOutcome> Function() probe;

  /// The composing capability's result contribution.
  final Future<Map<String, String>?> Function() resultFields;

  /// The step id named in a failure reason (e.g. `specify`).
  final String verb;

  /// The session-adapter id named in a failure reason (e.g. `acp`).
  final String adapter;

  final StreamController<ProcessSessionUpdate> _updates =
      StreamController<ProcessSessionUpdate>();
  StreamSubscription<ProcessSessionUpdate>? _sub;
  bool _terminal = false;

  @override
  Stream<ProcessSessionUpdate> get updates => _updates.stream;

  @override
  Future<void> start() => inner.start();

  @override
  Future<ProcessCommandDisposition> send(ProcessSessionCommand command) =>
      inner.send(command);

  @override
  void onRuntimeEvent(RuntimeEvent event) => inner.onRuntimeEvent(event);

  void _onUpdate(ProcessSessionUpdate update) {
    if (_terminal) return;
    switch (update) {
      case ProcessSessionProgress():
        _updates.add(update);
      case ProcessSessionFailed():
        // The harness already said why — and on the ACP path that reason
        // already carries the child's exit code and stderr tail.
        _terminal = true;
        _updates.add(update);
      case ProcessSessionCompleted(:final result):
        _terminal = true;
        unawaited(_fence(result));
    }
  }

  /// Proves the artifact before letting a completion through. The captured
  /// output is the harness's OWN final text (`result['text']`), which is where
  /// a channel harness says why it could not write — and which the argv path
  /// gets from its stdout envelope.
  Future<void> _fence(Map<String, String> result) async {
    GateOutcome outcome;
    try {
      outcome = await probe();
    } on Object {
      outcome = GateOutcome.probeError;
    }
    if (_updates.isClosed) return;
    switch (outcome) {
      case GateOutcome.clear:
        Map<String, String>? extra;
        try {
          extra = await resultFields();
        } on Object {
          extra = null; // a result contribution never gates a proven artifact.
        }
        if (_updates.isClosed) return;
        _updates.add(
          ProcessSessionUpdate.completed(
            result: <String, String>{...result, ...?extra},
          ),
        );
      case GateOutcome.present:
        _updates.add(
          _refuse(result, 'declared completion artifact is not durable'),
        );
      case GateOutcome.probeError:
        _updates.add(_refuse(result, 'completion artifact probe failed'));
    }
  }

  ProcessSessionUpdate _refuse(Map<String, String> result, String diagnostic) =>
      ProcessSessionUpdate.failed(
        reason: capturedOutputReason(
          verb: verb,
          adapter: adapter,
          output: result['text'] ?? '',
          // A protocol turn that ENDED cleanly: the child said it was done, so
          // the exit code is the honest 0 and the diagnostic carries the lie.
          exitCode: 0,
          diagnostic: diagnostic,
        ),
      );

  @override
  Future<void> close() async {
    _terminal = true;
    await _sub?.cancel();
    await inner.close();
    if (!_updates.isClosed) await _updates.close();
  }
}
