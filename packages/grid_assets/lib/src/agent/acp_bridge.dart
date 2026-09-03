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
import 'captured_output.dart';
import 'usage_report.dart';

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

/// How long the bridge waits for a vanished child's exit status and for its
/// stderr pipe to drain before reporting. Bounded so a wedged pipe can never
/// hold a failure open; generous enough that the exit code is normally known.
const Duration kChildReapGrace = Duration(seconds: 2);

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
  // TEE, don't drop: the child's stderr still rides the bridge's own stderr
  // (an operator tailing the process sees it live), but a bounded tail is
  // RETAINED so a failure reason can carry it (bead `pow-39tl` — four live
  // codex specify runs left no readable diagnosis anywhere).
  final stderrTail = _ChildStderrTail();
  final stderrDrained = process.stderr
      .forEach((chunk) {
        stderr.add(chunk);
        stderrTail.add(chunk);
      })
      .catchError((Object _) {});

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
        driver.failFromAgent('emitted malformed JSON: $error'),
  );
  final connection = ClientSideConnection((_) => client, stream);
  driver = _AcpBridgeDriver(spec, process, connection, stderrTail);
  // The child's stdout closing and its process exiting are the SAME fact — the
  // agent is gone — and either observation can win the race, so both ride one
  // reporter. It waits, bounded, for the real exit status and for the stderr
  // pipe to finish draining before assembling the reason: `exitCode` can
  // complete with bytes still buffered in the pipe, and those last bytes ARE
  // the diagnosis (bead `pow-39tl`).
  var reportedChildEnd = false;
  Future<void> reportChildEnded(String diagnostic) async {
    if (reportedChildEnd || driver.terminal) return;
    reportedChildEnd = true;
    int? code;
    try {
      code = await process.exitCode.timeout(kChildReapGrace);
    } on TimeoutException {
      code = null; // still running: `exit unknown` rather than an invented 0.
    }
    driver.exitCode ??= code;
    try {
      await stderrDrained.timeout(kChildReapGrace);
    } on TimeoutException {
      // A wedged pipe must never hold the failure open — report the tail so far.
    }
    driver.fail(
      capturedOutputReason(
        verb: 'acp agent',
        adapter: kAcpSessionAdapterId,
        output: stderrTail.text,
        exitCode: code,
        diagnostic: diagnostic,
      ),
    );
  }

  unawaited(
    outputClosed.then<void>(
      (_) => reportChildEnded('ended before protocol completion'),
      onError: (Object error, StackTrace stack) =>
          reportChildEnded('output stream failed: $error'),
    ),
  );
  unawaited(
    process.exitCode.then((code) {
      driver.exitCode = code;
      return reportChildEnded('ended before protocol completion');
    }),
  );
  try {
    await driver.initialize();
  } on Object catch (error, stack) {
    stderr.writeln('ACP session setup failed: $error\n$stack');
    driver.fail(
      capturedOutputReason(
        verb: 'acp session setup',
        adapter: kAcpSessionAdapterId,
        output: stderrTail.text,
        diagnostic: '$error',
      ),
    );
    await driver.consume(stdin);
    return;
  }
  await driver.consume(stdin);
}

class _AcpBridgeDriver {
  _AcpBridgeDriver(this.spec, this.process, this.connection, this.stderrTail);

  final AcpBridgeSpec spec;
  final Process process;
  final ClientSideConnection connection;

  /// The child's retained stderr tail — the only diagnosis a failed ACP run
  /// leaves behind (bead `pow-39tl`).
  final _ChildStderrTail stderrTail;

  /// The child's exit status once reaped; null while it is still running, so a
  /// reason says `exit unknown` rather than inventing a 0.
  int? exitCode;

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
      failFromAgent('prompt failed: $error');
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
        writeUsage();
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
        failFromAgent('prompt stopped with ${response.stopReason.name}');
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

  /// Fails with an AGENT-side reason: exit-code-led where the exit status is
  /// already known, adapter-named, and carrying the child's stderr TAIL —
  /// which is where a harness that could not do its job says so (bead
  /// `pow-39tl`). Grid-side failures (a malformed bridge input, our own
  /// cancellation) keep their plain reasons: the child said nothing about them.
  void failFromAgent(String diagnostic) => fail(
    capturedOutputReason(
      verb: 'acp agent',
      adapter: kAcpSessionAdapterId,
      output: stderrTail.text,
      exitCode: exitCode,
      diagnostic: diagnostic,
    ),
  );

  /// Writes this incarnation's FT-2 usage envelope — on EVERY terminal, clean
  /// or not (bead `pow-39tl`: an absent telemetry file and an empty-usage one
  /// are different diagnoses, and the absent one told an operator nothing).
  /// FAIL-SAFE: [writeUsageEnvelope] swallows I/O surprises, so telemetry can
  /// never gate a run.
  void writeUsage() {
    final out = spec.usageOut;
    if (out == null) return;
    writeUsageEnvelope(
      workspaceDir: spec.cwd,
      usageOut: out,
      content: usageEnvelopeJson(
        result: text.isEmpty ? null : text.toString(),
        tokensIn: tokensIn,
        tokensOut: tokensOut,
        numTurns: turns,
        model: selectedModel,
      ),
    );
  }

  void fail(String reason) {
    if (terminal) return;
    terminal = true;
    writeUsage();
    emit(<String, Object?>{'kind': 'failed', 'reason': reason});
  }
}

/// A bounded ring over the child's stderr bytes — the LAST
/// [kRevalidateReasonTailChars] characters, decoded lazily and malformed-safe.
///
/// Bounded on purpose: a chatty harness can emit megabytes, and the only part
/// any failure reason can carry is the end of it.
class _ChildStderrTail {
  final List<int> _bytes = <int>[];

  /// Retains twice the character budget in BYTES so a multi-byte tail can
  /// never be starved by the cut, then trims from the FRONT.
  static const int _byteBudget = kRevalidateReasonTailChars * 2;

  void add(List<int> chunk) {
    _bytes.addAll(chunk);
    if (_bytes.length > _byteBudget) {
      _bytes.removeRange(0, _bytes.length - _byteBudget);
    }
  }

  /// The retained tail as text; a partial leading rune is dropped by
  /// `allowMalformed`, never thrown over.
  String get text => utf8.decode(_bytes, allowMalformed: true);
}
