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

  /// Encodes the bridge handoff.
  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'args': args,
    'env': env,
    'cwd': cwd,
    if (model case final model?) 'model': model,
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
  );
}

/// ACP client posture for a grid agent doing real work in its worktree.
///
/// The harness owns its filesystem and terminal tools, so this client
/// advertises none of its own. Permission requests prefer a durable allow,
/// fall back to a one-shot allow, and never select either reject option.
class GridAllowAllAcpClient implements Client {
  /// Creates the client with a session update sink.
  GridAllowAllAcpClient({required this.onUpdate});

  /// Receives every ACP session update.
  final void Function(SessionUpdate update) onUpdate;

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    PermissionOption? selected;
    for (final kind in const <PermissionOptionKind>[
      PermissionOptionKind.allowAlways,
      PermissionOptionKind.allowOnce,
    ]) {
      for (final option in params.options) {
        if (option.kind == kind) {
          selected = option;
          break;
        }
      }
      if (selected != null) break;
    }
    return RequestPermissionResponse(
      outcome: selected == null
          ? CancelledOutcome()
          : SelectedOutcome(optionId: selected.optionId),
    );
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
class AcpSessionAdapter implements AgentSessionAdapter {
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

  List<int> _input(String kind, String text) => utf8.encode(
    '${jsonEncode(<String, Object?>{'kind': kind, 'text': text})}\n',
  );

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
      _ => throw FormatException('unknown ACP bridge frame: $frame'),
    };
  }
}

/// Station-default session adapter implementations.
const AgentSessionAdapterRegistry kBuiltinAgentSessionAdapters =
    AgentSessionAdapterRegistry(<String, AgentSessionAdapter>{
      kAcpSessionAdapterId: AcpSessionAdapter(),
    });
