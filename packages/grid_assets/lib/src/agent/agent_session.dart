import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
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
}

/// Per-harness launch, encoding, and decoding behavior.
abstract interface class AgentSessionAdapter {
  /// Stable registry identity for this adapter.
  String get id;

  /// Describes a long-lived launch without access to the brief.
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
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

  final StreamController<ProcessSessionUpdate> _updates =
      StreamController<ProcessSessionUpdate>();
  final Set<String> _seen = <String>{};
  StreamSubscription<AgentProtocolEvent>? _decoderSub;
  StreamSubscription<ProcessSessionCommand>? _commandSub;
  bool _terminal = false;

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
