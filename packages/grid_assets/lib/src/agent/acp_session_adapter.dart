/// ACP agent-session transport behind the grid's protocol-neutral session seam.
///
/// This deliberately does not reuse the federation bus's ACP-inspired envelope:
/// that codec carries grid federation methods over MQTT, while this adapter
/// speaks ACP's agent-session surface over a child process's stdio.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:acp_dart/acp_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'agent_session.dart';
import 'permission_policy.dart';
import 'usage_report.dart';

/// Stable registry identity for the ACP session adapter.
const String kAcpSessionAdapterId = 'acp';

/// ACP major protocol version spoken by the bridge.
const int kAcpProtocolVersion = 1;

/// Private environment handoff from the adapter launch to the bridge.
const String kAcpBridgeSpecEnvironment = 'GRID_ACP_BRIDGE_SPEC';

/// Removes a codex-acp reasoning-effort suffix from [id].
String baseAcpModelId(String id) {
  final bracket = id.indexOf('[');
  return bracket == -1 ? id : id.substring(0, bracket);
}

/// Resolves an environment pin against the model ids offered by an ACP agent.
///
/// Exact wins first. A qualified current model with the requested base wins
/// next so the agent's own effort default survives. A sole remaining variant
/// is unambiguous; absent and ambiguous catalogs refuse by returning null.
String? resolveAcpModelId({
  required String want,
  required List<String> available,
  String? current,
}) {
  if (available.contains(want)) return want;
  final variants = available
      .where((id) => baseAcpModelId(id) == want)
      .toList(growable: false);
  if (current != null && baseAcpModelId(current) == want) return current;
  return variants.length == 1 ? variants.single : null;
}

/// Serializable description of one ACP-compatible agent child.
///
/// Harness identity remains data: adding another ACP agent is another command,
/// args, and environment value, never an adapter branch.
class AcpBridgeSpec {
  /// Creates an agent child description.
  const AcpBridgeSpec({
    required this.command,
    required this.args,
    required this.env,
    required this.cwd,
    this.model,
    this.usageOut,
  });

  /// Agent executable.
  final String command;

  /// Agent argv.
  final List<String> args;

  /// Environment layered over the bridge process environment.
  final Map<String, String> env;

  /// ACP session and child working directory.
  final String cwd;

  /// Optional environment-owned model pin.
  final String? model;

  /// Workspace-relative FT-2 telemetry path the bridge writes its usage
  /// envelope to ([usageReportPath]); null ⇒ this launch captures no usage.
  final String? usageOut;

  /// Encodes the bridge handoff.
  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'args': args,
    'env': env,
    'cwd': cwd,
    if (model case final model?) 'model': model,
    if (usageOut case final usageOut?) 'usageOut': usageOut,
  };

  /// Decodes the bridge handoff.
  factory AcpBridgeSpec.fromJson(Map<String, Object?> json) => AcpBridgeSpec(
    command: json['command']! as String,
    args: (json['args']! as List<Object?>).cast<String>(),
    env: (json['env']! as Map<String, Object?>).map(
      (key, value) => MapEntry(key, value! as String),
    ),
    cwd: json['cwd']! as String,
    model: json['model'] as String?,
    usageOut: json['usageOut'] as String?,
  );
}

/// How long the bridge waits for the STATION's answer to one permission ask
/// before cancelling it locally.
///
/// BOUNDED on purpose: the decision is made in the parent grid process, so the
/// round trip is milliseconds. An answer that never arrives — a wedged parent,
/// a closed control stream — must cancel the ask rather than hold the harness's
/// turn open forever.
const Duration kAcpPermissionDecisionTimeout = Duration(seconds: 30);

/// Asks the station to decide one normalized permission [request].
///
/// Returns null when the station produced no usable answer at all, which the
/// bridge treats as a cancellation. It is never the bridge's job to invent one.
typedef AgentPermissionDecider =
    Future<AgentPermissionDecision?> Function(AgentPermissionRequest request);

/// Records one BRIDGE-LOCAL cancellation — an authorization the station never
/// produced, so nothing upstream has recorded it yet.
typedef AgentPermissionAuditSink =
    void Function(AgentPermissionDecision decision);

/// Normalizes an ACP tool kind onto the grid's permission vocabulary.
///
/// An absent kind and [ToolKind.other] both normalize to
/// [AgentPermissionCapability.unknown]: an action the harness would not name is
/// one no policy can scope, and it is never grantable.
AgentPermissionCapability acpPermissionCapability(ToolKind? kind) =>
    switch (kind) {
      null => AgentPermissionCapability.unknown,
      ToolKind.read => AgentPermissionCapability.read,
      ToolKind.edit => AgentPermissionCapability.edit,
      ToolKind.delete => AgentPermissionCapability.delete,
      ToolKind.move => AgentPermissionCapability.move,
      ToolKind.search => AgentPermissionCapability.search,
      ToolKind.execute => AgentPermissionCapability.execute,
      ToolKind.think => AgentPermissionCapability.think,
      ToolKind.fetch => AgentPermissionCapability.fetch,
      ToolKind.switchMode => AgentPermissionCapability.switchMode,
      ToolKind.other => AgentPermissionCapability.unknown,
    };

/// Projects the KINDS an ACP request offers, dropping its option ids and its
/// human-facing labels — the station decides on shape, never on prose.
List<AgentPermissionOutcome> acpOfferedOutcomes(
  List<PermissionOption> options,
) {
  final offered = <AgentPermissionOutcome>[];
  for (final option in options) {
    final outcome = switch (option.kind) {
      PermissionOptionKind.allowOnce => AgentPermissionOutcome.allowOnce,
      PermissionOptionKind.allowAlways => AgentPermissionOutcome.allowAlways,
      PermissionOptionKind.rejectOnce => AgentPermissionOutcome.rejectOnce,
      PermissionOptionKind.rejectAlways => AgentPermissionOutcome.rejectAlways,
    };
    if (!offered.contains(outcome)) offered.add(outcome);
  }
  return List<AgentPermissionOutcome>.unmodifiable(offered);
}

/// ACP client posture for a grid agent doing real work in its worktree.
///
/// The harness owns its filesystem and terminal tools, so this client
/// advertises none of its own.
///
/// **Permission asks are the STATION's call, not this client's** (bead
/// `pow-ed1c`). The predecessor answered every ask with the widest grant the
/// harness offered, so an agent acquired whatever standing permission it asked
/// for. This one normalizes the ask, hands it to [decide], and applies EXACTLY
/// the answer that comes back: it never ranks options, never prefers a durable
/// grant, and has no allow path of its own. Anything else — no answer, an
/// answer for a different ask, a decision timeout, a kind the harness did not
/// offer — is a [CancelledOutcome], recorded through [audit] first.
class GridPolicyAcpClient implements Client {
  /// Creates the client for the incarnation admitted under [attemptId].
  GridPolicyAcpClient({
    required this.attemptId,
    required this.onUpdate,
    required this.decide,
    required this.audit,
    this.timeout = kAcpPermissionDecisionTimeout,
  });

  /// The admitted attempt this bridge was spawned under; stamped onto every
  /// ask so the station can refuse one that is not its own.
  final String attemptId;

  /// Receives every ACP session update.
  final void Function(SessionUpdate update) onUpdate;

  /// The one asynchronous station-decision exchange.
  final AgentPermissionDecider decide;

  /// Records a cancellation this client produced locally.
  final AgentPermissionAuditSink audit;

  /// The bound on [decide].
  final Duration timeout;

  int _asks = 0;

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    final request = AgentPermissionRequest(
      requestId: 'acp-permission-${++_asks}',
      attemptId: attemptId,
      sessionId: params.sessionId,
      // NORMALIZED, and nothing else crosses: not the tool title, its raw
      // input or output, its metadata, nor any option label.
      capability: acpPermissionCapability(params.toolCall.kind),
      offered: acpOfferedOutcomes(params.options),
    );
    AgentPermissionDecision? decision;
    try {
      decision = await decide(request).timeout(timeout);
    } on Object {
      // A failed exchange, a closed control stream, a bounded timeout: all the
      // same fact — no authorization exists. Never an inferred one.
      decision = null;
    }
    if (decision == null) {
      return _cancel(request, 'the station returned no authorization');
    }
    if (decision.requestId != request.requestId ||
        decision.attemptId != request.attemptId ||
        decision.sessionId != request.sessionId ||
        decision.capability != request.capability) {
      return _cancel(request, 'the station answered a different request');
    }
    final kind = switch (decision.outcome) {
      AgentPermissionOutcome.allowOnce => PermissionOptionKind.allowOnce,
      AgentPermissionOutcome.allowAlways => PermissionOptionKind.allowAlways,
      AgentPermissionOutcome.rejectOnce => PermissionOptionKind.rejectOnce,
      AgentPermissionOutcome.rejectAlways => PermissionOptionKind.rejectAlways,
      // The station itself cancelled — already recorded upstream, so this must
      // not write a second record of the same decision.
      AgentPermissionOutcome.cancelled => null,
    };
    if (kind == null) {
      return RequestPermissionResponse(outcome: CancelledOutcome());
    }
    for (final option in params.options) {
      if (option.kind == kind) {
        return RequestPermissionResponse(
          outcome: SelectedOutcome(optionId: option.optionId),
        );
      }
    }
    // The authorized kind is not on offer. NARROWING here would be this client
    // deciding, which is exactly what it must not do.
    return _cancel(
      request,
      'the harness offered no option of the authorized kind',
    );
  }

  RequestPermissionResponse _cancel(
    AgentPermissionRequest request,
    String reason,
  ) {
    audit(
      AgentPermissionDecision.cancelled(
        request: request,
        policyId: '',
        reason: reason,
      ),
    );
    return RequestPermissionResponse(outcome: CancelledOutcome());
  }

  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    onUpdate(params.update);
  }

  @override
  Future<WriteTextFileResponse>? writeTextFile(WriteTextFileRequest params) =>
      null;

  @override
  Future<ReadTextFileResponse>? readTextFile(ReadTextFileRequest params) =>
      null;

  @override
  Future<CreateTerminalResponse>? createTerminal(
    CreateTerminalRequest params,
  ) => null;

  @override
  Future<TerminalOutputResponse>? terminalOutput(
    TerminalOutputRequest params,
  ) => null;

  @override
  Future<ReleaseTerminalResponse?>? releaseTerminal(
    ReleaseTerminalRequest params,
  ) => null;

  @override
  Future<WaitForTerminalExitResponse>? waitForTerminalExit(
    WaitForTerminalExitRequest params,
  ) => null;

  @override
  Future<KillTerminalCommandResponse?>? killTerminal(
    KillTerminalCommandRequest params,
  ) => null;

  @override
  Future<Map<String, dynamic>>? extMethod(
    String method,
    Map<String, dynamic> params,
  ) => null;

  @override
  Future<void>? extNotification(String method, Map<String, dynamic> params) =>
      null;
}

/// Launches the package-resolved ACP bridge and normalizes its event stream.
///
/// It also carries the AUTHORIZATION half ([AgentAuthorizationAdapter]): ACP
/// has a permission handshake, so the station's decision has a wire form to go
/// back over.
class AcpSessionAdapter
    implements AgentSessionAdapter, AgentAuthorizationAdapter {
  /// Creates the stateless adapter.
  const AcpSessionAdapter();

  @override
  String get id => kAcpSessionAdapterId;

  @override
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  }) {
    final command = environment.command;
    if (command == null || command.isEmpty) {
      throw StateError('ACP environment is not spawnable: no command resolved');
    }
    final bridge = Isolate.resolvePackageUriSync(
      Uri.parse('package:grid_assets/src/agent/acp_bridge.dart'),
    );
    final packages = Isolate.packageConfigSync;
    if (bridge == null || !bridge.isScheme('file') || packages == null) {
      throw StateError('ACP bridge requires file-backed package resolution');
    }
    final spec = AcpBridgeSpec(
      command: command,
      args: <String>[...?environment.args, ...environment.argsAppend],
      env: agentProcessEnvironment(
        environment: environment,
        endpoint: endpoint,
      ),
      cwd: workspace.workspaceDir,
      model: environment.model == null ? null : model ?? environment.model,
      usageOut: usageOut,
    );
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: Platform.resolvedExecutable,
      args: <String>[
        '--packages=${packages.toFilePath()}',
        bridge.toFilePath(),
      ],
      env: <String, String>{
        kAcpBridgeSpecEnvironment: jsonEncode(spec.toJson()),
      },
      lifecycle: Lifecycle.longLived,
    );
  }

  @override
  List<int> encodeBrief(AgentBrief brief) => _input('brief', brief.render());

  @override
  List<int> encodeSteer(String text) => _input('steer', text);

  @override
  List<int> encodePermissionDecision(AgentPermissionDecision decision) =>
      _frame(<String, Object?>{
        'kind': 'permission_decision',
        'decision': decision.toJson(),
      });

  List<int> _input(String kind, String text) =>
      _frame(<String, Object?>{'kind': kind, 'text': text});

  List<int> _frame(Map<String, Object?> frame) =>
      utf8.encode('${jsonEncode(frame)}\n');

  @override
  Stream<AgentProtocolEvent> decode(Stream<List<int>> stdout) => stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map(_decodeLine);

  AgentProtocolEvent _decodeLine(String line) {
    final frame = jsonDecode(line) as Map<String, dynamic>;
    return switch (frame['kind']) {
      'progress' => AgentProtocolEvent.progress(
        fields: (frame['fields'] as Map<String, dynamic>)
            .cast<String, String>(),
      ),
      'completed' => AgentProtocolEvent.completed(
        result: (frame['result'] as Map<String, dynamic>)
            .cast<String, String>(),
        usage: UsageReport(
          tokensIn: frame['tokensIn'] as int?,
          tokensOut: frame['tokensOut'] as int?,
          numTurns: frame['numTurns'] as int?,
          model: frame['model'] as String?,
        ),
      ),
      'failed' => AgentProtocolEvent.failed(reason: frame['reason']! as String),
      // The AUTHORIZATION frames (bead `pow-ed1c`), all non-terminal.
      'session_bound' => AgentProtocolEvent.sessionBound(
        attemptId: frame['attemptId']! as String,
        protocolSessionId: frame['sessionId']! as String,
      ),
      'permission_request' => AgentProtocolEvent.permissionRequested(
        request: AgentPermissionRequest.fromJson(
          (frame['request']! as Map<String, dynamic>).cast<String, Object?>(),
        ),
      ),
      'permission_fallback' => AgentProtocolEvent.permissionFallback(
        decision: AgentPermissionDecision.fromJson(
          (frame['decision']! as Map<String, dynamic>).cast<String, Object?>(),
        ),
      ),
      _ => throw FormatException('unknown ACP bridge frame: $frame'),
    };
  }
}

/// Station-default session adapter implementations.
const AgentSessionAdapterRegistry kBuiltinAgentSessionAdapters =
    AgentSessionAdapterRegistry(<String, AgentSessionAdapter>{
      kAcpSessionAdapterId: AcpSessionAdapter(),
    });
