import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'captured_output.dart';
import 'lane_environment_health.dart';
import 'model_tier.dart';
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

  /// Reports a harness protocol failure, and WHY it failed.
  ///
  /// [kind] is the engine's own failure vocabulary, carried from wherever the
  /// fact is actually known — a harness that ends its turn on a provider
  /// refusal produced NO usable result, and only the adapter watching that
  /// terminal can say so. It defaults to [CapabilityFailureKind.work], the
  /// historical untyped meaning, so an adapter that cannot tell reports
  /// exactly what it reported before.
  ///
  /// [fields] is the adapter's STRUCTURED evidence about this failure — the
  /// phase it happened in ([kAgentFailurePhaseField]) and, for a setup refusal,
  /// the pin, the offered catalog and the resolver's verdict. A reader consumes
  /// these KEYS; nothing downstream parses [reason] prose. It defaults EMPTY,
  /// so every adapter and every frame written before this seam existed reports
  /// exactly what it reported before.
  const factory AgentProtocolEvent.failed({
    required String reason,
    @Default(CapabilityFailureKind.work) CapabilityFailureKind kind,
    @Default(<String, String>{}) Map<String, String> fields,
  }) = AgentProtocolFailed;

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

/// The engine's allocation-env key naming the attempt an incarnation was
/// ADMITTED under.
///
/// The engine mints it once per mount and layers it over the spawn's
/// environment, so a supervised child can stamp its own asks with the attempt
/// the grid already knows it by. ABSENT means unknown, never "any".
const String kGridAttemptEnvironment = 'GRID_ATTEMPT_ID';

/// The [AgentProtocolEvent.failed] field naming WHICH phase of the session a
/// failure happened in.
///
/// Its only declared value is [kAgentSetupPhase]. An ABSENT phase is the
/// ordinary mid-turn failure every adapter has always reported — never a
/// silently-assumed setup.
const String kAgentFailurePhaseField = 'phase';

/// The [kAgentFailurePhaseField] value for a failure BEFORE the first turn:
/// the handshake, the session open, the model selection.
///
/// A setup refusal produced no work, could not have, and says nothing about
/// the bead — so it is the environment's fault by construction, and the reason
/// `declared process-session non-results are infra` applies to it.
const String kAgentSetupPhase = 'setup';

/// The [AgentProtocolEvent.failed] field carrying the model pin a setup
/// refusal named.
const String kAgentFailurePinField = 'pin';

/// The [AgentProtocolEvent.failed] field carrying the model ids the agent
/// offered, JSON-encoded ([encodeOfferedField] / [decodeOfferedField]).
///
/// JSON, not a joined string: a model id is free text on the agent's side, and
/// a separator convention is exactly the kind of thing a vendor breaks.
const String kAgentFailureOfferedField = 'offered';

/// The [AgentProtocolEvent.failed] field carrying the resolver's own verdict
/// on the pin against the offered catalog.
const String kAgentFailureResolverVerdictField = 'resolverVerdict';

/// Encodes [offered] for [kAgentFailureOfferedField].
String encodeOfferedField(List<String> offered) => jsonEncode(offered);

/// Decodes [kAgentFailureOfferedField]; an absent or unparseable value is the
/// EMPTY catalog, never a throw — diagnostic evidence may not break a failure
/// report that is already on its way to the engine.
List<String> decodeOfferedField(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(encoded);
    return decoded is List
        ? <String>[
            for (final id in decoded)
              if (id is String) id,
          ]
        : const <String>[];
  } on Object {
    return const <String>[];
  }
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
  ///
  /// [tier] is the rung the SPAWN SITE declares (`model_tier.dart`), carried
  /// here because [model] alone cannot say it: a harness may name one model per
  /// reasoning effort while a seat pins the bare id, and the effort belongs to
  /// the seat, not to the pin. An adapter whose protocol has no effort axis
  /// IGNORES it. It defaults to [AgentTier.frontier] — the rung a direct launch
  /// (a terminal occupying a seat) has always ridden.
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
    AgentTier tier = AgentTier.frontier,
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
  ///
  /// GUARD, LOUD: [laneHealth] and [laneTarget] are ALL OR NOTHING. A
  /// coordinator with nothing to diagnose would silently record nothing, and a
  /// target with no coordinator would silently diagnose nowhere — both are the
  /// exact silence this session exists to end, so half a pair refuses.
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
    this.laneHealth,
    this.laneTarget,
  }) {
    if ((laneHealth == null) != (laneTarget == null)) {
      throw ArgumentError(
        'AgentSession takes a LaneEnvironmentHealth and a '
        'LaneEnvironmentTarget together, or neither',
      );
    }
  }

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

  /// The STATION's authorization boundary for this channel, RESOLVED at the
  /// capability's effect edge (`seatChannelPolicy`) and passed in as a VALUE.
  ///
  /// Defaults to [AgentPermissionPolicy.unavailable] for a DIRECT construction
  /// — a session built without a capability, so without a seat identity to
  /// resolve from — which grants nothing. A capability's channel gets its seat's
  /// derived policy instead; nothing is ever trusted by omission.
  final AgentPermissionPolicy policy;

  /// The station's LANE-HEALTH coordinator, injected at the capability's effect
  /// edge. Null ⇒ this composition diagnoses nothing, and a setup refusal is
  /// forwarded exactly as it was before this seam existed.
  ///
  /// THE DECLARED DEPARTURE from `power_station#a38-…` clause 5 lives here: a
  /// session-edge spawn failure is a THIRD failure signal that clause scoped
  /// out, taken under Nico's recorded ruling of 2026-09-21 ("The station should
  /// be able to debug this itself"). See `lane_environment_health.dart`'s
  /// library docstring for the full statement. A38's own reason survives:
  /// [transport] is still read OUTBOUND-ONLY — it carries the flare out and is
  /// never treated as an inbound bus.
  final LaneEnvironmentHealth? laneHealth;

  /// WHICH lane this incarnation was spawned onto — required exactly when
  /// [laneHealth] is supplied.
  final LaneEnvironmentTarget? laneTarget;

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
      case AgentProtocolFailed(:final reason, :final kind, :final fields):
        final health = laneHealth;
        final target = laneTarget;
        // ONLY the bridge-authored phase counts. Nothing here reads the reason
        // prose, and nothing INFERS a setup from a fast failure: the adapter
        // that watched the handshake is the only thing that can say so.
        if (health != null &&
            target != null &&
            fields[kAgentFailurePhaseField] == kAgentSetupPhase) {
          // Claim the terminal NOW, before the await: a second protocol frame
          // or a runtime exit landing mid-diagnosis must not produce a second
          // failure update.
          _terminal = true;
          unawaited(_diagnoseThenFail(health, target, fields, reason, kind));
          return;
        }
        _fail(reason, kind: kind);
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

  /// Records the lane evidence FIRST, then forwards the harness's own declared
  /// failure to the engine.
  ///
  /// THE ORDER IS THE POINT. Supervision asks for the next spawn off this
  /// failure report, so a second correlated diagnosis must have removed the
  /// lane from the presence set BEFORE that request can be served — otherwise
  /// the station parks the lane on its third refusal instead of its second, and
  /// burns one more bead's attempt to learn what it already knew.
  ///
  /// The diagnosis is EVIDENCE, never a gate: a probe that throws or hangs
  /// leaves the harness's failure exactly as reported.
  Future<void> _diagnoseThenFail(
    LaneEnvironmentHealth health,
    LaneEnvironmentTarget target,
    Map<String, String> fields,
    String reason,
    CapabilityFailureKind kind,
  ) async {
    try {
      await health.recordSetupFailure(
        LaneEnvironmentSetupFailure(
          target: target,
          offered: decodeOfferedField(fields[kAgentFailureOfferedField]),
          pin: fields[kAgentFailurePinField],
          resolverVerdict: fields[kAgentFailureResolverVerdictField],
        ),
        // The ambient carrier, OUTBOUND-ONLY and optional: no transport means
        // no flare, never a session failure (the `_audit` posture, D-8).
        flare: transport?.flare,
      );
    } on Object {
      // Swallowed on purpose — see above.
    }
    _emitFailure(reason, kind);
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

  /// Fails the channel with [reason], carrying [kind] onto the engine's own
  /// update.
  ///
  /// Every GRID-side failure — a dead process, a malformed frame, an
  /// undeliverable authorization — keeps the default
  /// [CapabilityFailureKind.work]: this side observed a broken channel, not a
  /// harness that declared its own outcome. Only a protocol failure that
  /// carries a kind overrides it.
  void _fail(
    String reason, {
    CapabilityFailureKind kind = CapabilityFailureKind.work,
  }) {
    if (_terminal) return;
    _terminal = true;
    _emitFailure(reason, kind);
  }

  /// Publishes the failure update for a terminal ALREADY claimed.
  ///
  /// Split out for [_diagnoseThenFail], which claims the terminal before its
  /// await so nothing races it, then emits after. A closed controller — the
  /// session was disposed while the diagnosis ran — drops the update rather
  /// than throwing into a dead branch.
  void _emitFailure(String reason, CapabilityFailureKind kind) {
    if (_updates.isClosed) return;
    _updates.add(ProcessSessionUpdate.failed(reason: reason, kind: kind));
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
/// [tier] is the seat's DECLARED rung, required here rather than defaulted: a
/// spawn site already names the tier it resolves its model on, and a channel
/// adapter that selects a reasoning effort needs the same fact rather than a
/// second guess at it.
///
/// GUARD, LOUD: a channel adapter that does not launch [Lifecycle.longLived]
/// throws — the brief arrives AFTER startup, so a one-turn channel launch can
/// only ever produce a briefless run.
RuntimeConfig spawnThroughSessionAdapter({
  required AgentSessionAdapterRegistry adapters,
  required AgentEnvironment environment,
  required AgentBrief brief,
  required Workspace workspace,
  required AgentTier tier,
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
        tier: tier,
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
  /// [failureKind], [blockedDiagnostic] and [probeErrorDiagnostic] describe
  /// what THIS capability's probe proves, for a composer whose fence is not an
  /// artifact read. They default to the artifact-durability wording and to the
  /// untyped [CapabilityFailureKind.work], so every caller predating them is
  /// byte-for-byte unchanged.
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
    this.failureKind = CapabilityFailureKind.work,
    this.blockedDiagnostic = 'declared completion artifact is not durable',
    this.probeErrorDiagnostic = 'completion artifact probe failed',
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

  /// The engine failure kind a refused completion carries, so a capability can
  /// put its refusal on the retry budget it declared for that kind.
  final CapabilityFailureKind failureKind;

  /// The short cause a [GateOutcome.present] refusal opens with — the probe
  /// READ the workspace and what it promised is not there.
  final String blockedDiagnostic;

  /// The short cause a [GateOutcome.probeError] refusal opens with — the probe
  /// could not read the workspace at all.
  final String probeErrorDiagnostic;

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
        _updates.add(_refuse(result, blockedDiagnostic));
      case GateOutcome.probeError:
        _updates.add(_refuse(result, probeErrorDiagnostic));
    }
  }

  ProcessSessionUpdate _refuse(Map<String, String> result, String diagnostic) =>
      ProcessSessionUpdate.failed(
        kind: failureKind,
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
