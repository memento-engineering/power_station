/// Runtime-supervised ACP agent-session bridge.
///
/// ACP JSON-RPC stays between this process and the configured agent child.
/// The parent grid process sees only the normalized private frames emitted on
/// stdout; all diagnostics and child stderr stay on stderr.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';

import 'acp_session_adapter.dart';

/// Starts the bridge and converts setup errors into one normalized failure.
Future<void> main(List<String> args) => runZoned(
  () async {
    try {
      await runAcpBridge();
    } on Object catch (error, stack) {
      stderr.writeln('ACP bridge setup failed: $error\n$stack');
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'kind': 'failed',
          'reason': 'ACP bridge setup failed: $error',
        }),
      );
    }
  },
  // acp_dart 0.4.0 logs malformed protocol messages with print. Keep even
  // dependency diagnostics off the bridge's normalized stdout boundary.
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) => stderr.writeln(line),
  ),
);

/// Spawns the configured ACP agent and drives one session until parent teardown.
Future<void> runAcpBridge() async {
  final encoded = Platform.environment[kAcpBridgeSpecEnvironment];
  if (encoded == null) {
    throw StateError('$kAcpBridgeSpecEnvironment is required');
  }
  final spec = AcpBridgeSpec.fromJson(
    (jsonDecode(encoded) as Map<String, dynamic>).cast<String, Object?>(),
  );
  final childEnv = <String, String>{...Platform.environment}
    ..remove(kAcpBridgeSpecEnvironment)
    ..addAll(spec.env);
  final process = await Process.start(
    spec.command,
    spec.args,
    workingDirectory: spec.cwd,
    environment: childEnv,
    includeParentEnvironment: false,
  );
  unawaited(process.stderr.forEach(stderr.add));

  late final _AcpBridgeDriver driver;
  final client = GridAllowAllAcpClient(
    onUpdate: (update) => driver.onSessionUpdate(update),
  );
  final childOutput = process.stdout.asBroadcastStream();
  final outputClosed = childOutput.drain<void>();
  final stream = ndJsonStream(
    childOutput,
    process.stdin,
    onParseError: (line, error) =>
        driver.fail('ACP agent emitted malformed JSON: $error'),
  );
  final connection = ClientSideConnection((_) => client, stream);
  driver = _AcpBridgeDriver(spec, process, connection);
  unawaited(
    outputClosed.then<void>(
      (_) => driver.fail('ACP agent output closed before protocol completion'),
      onError: (Object error, StackTrace stack) =>
          driver.fail('ACP agent output failed: $error'),
    ),
  );
  unawaited(
    process.exitCode.then(
      (code) => driver.fail(
        'ACP agent exited before protocol completion (exit code $code)',
      ),
    ),
  );
  try {
    await driver.initialize();
  } on Object catch (error, stack) {
    stderr.writeln('ACP session setup failed: $error\n$stack');
    driver.fail('ACP session setup failed: $error');
    await driver.consume(stdin);
    return;
  }
  await driver.consume(stdin);
}

class _AcpBridgeDriver {
  _AcpBridgeDriver(this.spec, this.process, this.connection);

  final AcpBridgeSpec spec;
  final Process process;
  final ClientSideConnection connection;

  String? sessionId;
  String? selectedModel;
  int requestedGeneration = 0;
  int turns = 0;
  int tokensIn = 0;
  int tokensOut = 0;
  bool terminal = false;
  Future<void> tail = Future<void>.value();
  final StringBuffer text = StringBuffer();
  final StringBuffer thought = StringBuffer();

  Future<void> initialize() async {
    await connection.initialize(
      InitializeRequest(
        protocolVersion: kAcpProtocolVersion,
        // acp_dart serializes an absent fs capability as `fs: null`, which
        // Copilot rejects. An all-false object is the interoperable empty
        // capability: the client still exposes neither filesystem method.
        clientCapabilities: ClientCapabilities(fs: FileSystemCapability()),
      ),
    );
    final response = await connection.newSession(
      NewSessionRequest(cwd: spec.cwd, mcpServers: const <McpServerBase>[]),
    );
    sessionId = response.sessionId;
    selectedModel = response.models?.currentModelId;
    final want = spec.model;
    if (want == null) return;
    final offered =
        response.models?.availableModels
            .map((model) => model.modelId)
            .toList(growable: false) ??
        const <String>[];
    final resolved = resolveAcpModelId(
      want: want,
      available: offered,
      current: selectedModel,
    );
    if (resolved == null) {
      throw StateError(
        'ACP agent does not offer pinned model "$want" '
        '(available: ${offered.join(', ')})',
      );
    }
    if (resolved != selectedModel) {
      await connection.setSessionModel(
        SetSessionModelRequest(sessionId: sessionId!, modelId: resolved),
      );
    }
    selectedModel = resolved;
  }

  /// Consumes controls without waiting for an in-flight prompt, so a steer can
  /// supersede that turn's right to complete while remaining serialized.
  Future<void> consume(Stream<List<int>> input) async {
    try {
      await for (final line
          in input.transform(utf8.decoder).transform(const LineSplitter())) {
        final frame = jsonDecode(line) as Map<String, dynamic>;
        switch (frame['kind']) {
          case 'brief' || 'steer':
            final prompt = frame['text'];
            if (prompt is! String) {
              throw const FormatException('ACP bridge input text is required');
            }
            enqueue(prompt);
          case 'cancel':
            await cancel();
          default:
            throw FormatException('unknown ACP bridge input: $frame');
        }
      }
      await cancel();
    } on Object catch (error) {
      fail('malformed ACP bridge input: $error');
      await cancel();
    }
  }

  void enqueue(String prompt) {
    if (terminal) return;
    final generation = ++requestedGeneration;
    tail = tail.then((_) => _prompt(prompt, generation)).catchError((
      Object error,
      StackTrace stack,
    ) {
      fail('ACP prompt failed: $error');
    });
  }

  Future<void> _prompt(String prompt, int generation) async {
    if (terminal) return;
    final response = await connection.prompt(
      PromptRequest(
        sessionId: sessionId!,
        prompt: <ContentBlock>[TextContentBlock(text: prompt)],
      ),
    );
    turns += 1;
    tokensIn += response.usage?.inputTokens ?? 0;
    tokensOut += response.usage?.outputTokens ?? 0;
    if (generation != requestedGeneration || terminal) return;
    switch (response.stopReason) {
      case StopReason.endTurn:
        terminal = true;
        emit(<String, Object?>{
          'kind': 'completed',
          'result': <String, String>{
            'text': text.toString(),
            if (thought.isNotEmpty) 'thought': thought.toString(),
          },
          'tokensIn': tokensIn,
          'tokensOut': tokensOut,
          'numTurns': turns,
          if (selectedModel case final model?) 'model': model,
        });
      case StopReason.maxTokens ||
          StopReason.maxTurnRequests ||
          StopReason.refusal ||
          StopReason.cancelled:
        fail('ACP prompt stopped with ${response.stopReason.name}');
    }
  }

  Future<void> cancel() async {
    if (terminal || sessionId == null) return;
    try {
      await connection.cancel(CancelNotification(sessionId: sessionId!));
      await Future<void>.delayed(Duration.zero);
      await process.stdin.flush();
      fail('ACP session cancelled');
    } on Object catch (error) {
      fail('ACP session cancellation failed: $error');
    }
  }

  void onSessionUpdate(SessionUpdate update) {
    if (terminal) return;
    switch (update) {
      case AgentMessageChunkSessionUpdate(:final content):
        if (content is TextContentBlock) {
          text.write(content.text);
          emit(<String, Object?>{
            'kind': 'progress',
            'fields': <String, String>{'text': content.text},
          });
        }
      case AgentThoughtChunkSessionUpdate(:final content):
        if (content is TextContentBlock) {
          thought.write(content.text);
          emit(<String, Object?>{
            'kind': 'progress',
            'fields': <String, String>{'thought': content.text},
          });
        }
      case UserMessageChunkSessionUpdate() ||
          ToolCallSessionUpdate() ||
          ToolCallUpdateSessionUpdate() ||
          PlanSessionUpdate() ||
          AvailableCommandsUpdateSessionUpdate() ||
          CurrentModeUpdateSessionUpdate() ||
          ConfigOptionUpdate() ||
          SessionInfoUpdate() ||
          UsageUpdate() ||
          UnknownSessionUpdate():
        return;
    }
  }

  void emit(Map<String, Object?> frame) => stdout.writeln(jsonEncode(frame));

  void fail(String reason) {
    if (terminal) return;
    terminal = true;
    emit(<String, Object?>{'kind': 'failed', 'reason': reason});
  }
}
