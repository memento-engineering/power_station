import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Steers implements AgentSteerSource {
  final StreamController<ProcessSessionCommand> controller =
      StreamController<ProcessSessionCommand>();

  @override
  Stream<ProcessSessionCommand> watch(String workBeadId) => controller.stream;
}

class _Run {
  _Run({
    required this.allocation,
    required this.runtime,
    required this.reports,
    required this.config,
    required this.steers,
    required this.name,
    required this.trace,
  });

  final Allocation allocation;
  final SubprocessProvider runtime;
  final List<AllocationReport> reports;
  final RuntimeConfig config;
  final _Steers steers;
  final String name;
  final File trace;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await allocation.dispose();
    if (!steers.controller.isClosed) await steers.controller.close();
    await runtime.dispose();
  }
}

class _BridgeResult {
  const _BridgeResult({
    required this.frame,
    required this.config,
    required this.stderr,
    required this.trace,
    required this.usageEnvelope,
  });

  final Map<String, dynamic> frame;
  final RuntimeConfig config;
  final String stderr;
  final List<Map<String, dynamic>> trace;

  /// The FT-2 envelope the bridge wrote, read before the temp workspace is
  /// deleted; null when this run asked for no `usageOut` or none landed.
  final String? usageEnvelope;
}

Future<_Run> _buildAcpRun({
  required String probePath,
  required String identity,
}) async {
  final workspaceDir = await Directory.systemTemp.createTemp(
    'grid_assets_acp_lease_',
  );
  addTearDown(() async {
    if (workspaceDir.existsSync()) await workspaceDir.delete(recursive: true);
  });
  final trace = File(p.join(workspaceDir.path, '$identity.trace.jsonl'));
  final workspace = Workspace(
    workspaceDir: workspaceDir.path,
    branch: 'grid/work-1',
    baseBranch: 'main',
  );
  final environment = AgentEnvironment(
    command: Platform.resolvedExecutable,
    args: <String>[probePath, '--identity=$identity'],
    env: <String, String>{'GRID_ACP_PROBE_TRACE': trace.path},
    promptMode: PromptMode.none,
    sessionAdapter: kAcpSessionAdapterId,
    model: 'gpt-5.6-sol',
  );
  final tree = FakeTreeContext(
    values: <Type, Object>{
      Bead: const Bead(
        id: 'work-1',
        title: 'ACP channel work',
        description: 'Deliver this only over the channel.',
      ),
      Workspace: workspace,
      AgentConfig: const AgentConfig(harness: 'probe'),
      EnvironmentRegistry: EnvironmentRegistry(
        custom: <String, AgentEnvironment>{'probe': environment},
      ),
    },
  );
  final steers = _Steers();
  final capability = AgentCapability(
    overlayRoot: p.join(workspaceDir.path, 'absent-overlay'),
    steers: steers,
  );
  final runtime = SubprocessProvider(
    parentEnvironment: Platform.environment,
    livenessPollPeriod: const Duration(milliseconds: 20),
    agentDeadline: null,
  );
  const name = 'session-1/work-1/agent';
  final reports = <AllocationReport>[];
  final args = StepArgs(nodePath: 'work-1/agent', cancel: CancelToken());
  final allocationContext = AllocationContext(
    treeContext: tree,
    args: args,
    transport: runtime,
    address: const AllocationAddress('session-1', 'work-1/agent'),
    env: const <String, String>{
      'GRID_ATTEMPT_ID': 'attempt-1',
      'GRID_INSTANCE_TOKEN': 'fence-1',
    },
    sink: reports.add,
    kind: StepKind.job,
  );
  final config = capability.spawn(tree, args);
  final request = ProcessLeaseRequest(
    stepBeadId: 'step-1',
    capability: capability,
    allocation: allocationContext,
  );
  final ProcessLeaseVendor vendor = SelfManagedProcessVendor(
    spawn: stationProcessSpawner,
    dispatch: stationProcessDispatcher,
  );
  final allocation = vendor
      .leaseFor(request)
      .createAllocation(
        AllocationContext(
          treeContext: tree,
          args: args,
          transport: runtime,
          address: const AllocationAddress('session-1', 'work-1/agent'),
          env: const <String, String>{},
          sink: reports.add,
          kind: StepKind.job,
        ),
      );
  final run = _Run(
    allocation: allocation,
    runtime: runtime,
    reports: reports,
    config: config,
    steers: steers,
    name: name,
    trace: trace,
  );
  addTearDown(run.close);
  return run;
}

Future<void> _waitForOutput(_Run run, String text) async {
  for (var i = 0; i < 1000; i++) {
    if (run.runtime.peek(run.name, 0).contains(text)) return;
    final failures = run.reports.whereType<AllocationFailed>();
    if (failures.isNotEmpty) {
      throw StateError(
        'ACP allocation failed before "$text": '
        '${failures.map((failure) => failure.reason).join('; ')}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError(
    'ACP allocation never emitted "$text"; reports=${run.reports}, '
    'output=${run.runtime.peek(run.name, 0)}',
  );
}

Future<_BridgeResult> _runBridge({
  required String probePath,
  required List<String> probeArgs,
  String? model = 'gpt-5.6-sol',
  bool cancelOnProgress = false,
  String? usageOut,
}) async {
  final workspace = await Directory.systemTemp.createTemp(
    'grid_assets_acp_bridge_',
  );
  final trace = File(p.join(workspace.path, 'trace.jsonl'));
  final environment = AgentEnvironment(
    command: Platform.resolvedExecutable,
    args: <String>[probePath, ...probeArgs],
    env: <String, String>{'GRID_ACP_PROBE_TRACE': trace.path},
    promptMode: PromptMode.none,
    sessionAdapter: kAcpSessionAdapterId,
    model: model,
  );
  final config = const AcpSessionAdapter().launch(
    environment: environment,
    workspace: Workspace(
      workspaceDir: workspace.path,
      branch: 'grid/probe',
      baseBranch: 'main',
    ),
    usageOut: usageOut,
  );
  final process = await Process.start(
    config.command,
    config.args,
    workingDirectory: config.workDir,
    environment: <String, String>{...Platform.environment, ...config.env},
    includeParentEnvironment: false,
  );
  final error = StringBuffer();
  final errorDone = process.stderr.transform(utf8.decoder).forEach(error.write);
  final terminal = Completer<Map<String, dynamic>>();
  var cancelled = false;
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final frame = jsonDecode(line) as Map<String, dynamic>;
        if (cancelOnProgress && !cancelled && frame['kind'] == 'progress') {
          cancelled = true;
          process.stdin.writeln(
            jsonEncode(<String, Object?>{'kind': 'cancel'}),
          );
        }
        if (!terminal.isCompleted &&
            (frame['kind'] == 'completed' || frame['kind'] == 'failed')) {
          terminal.complete(frame);
        }
      }, onError: terminal.completeError);
  process.stdin.add(
    const AcpSessionAdapter().encodeBrief(
      const AgentBrief(task: 'bridge probe brief'),
    ),
  );
  await process.stdin.flush();

  Map<String, dynamic> frame;
  try {
    frame = await terminal.future.timeout(const Duration(seconds: 10));
  } finally {
    await subscription.cancel();
    process.kill();
    await process.exitCode;
    await errorDone;
  }
  final traceEntries = trace.existsSync()
      ? trace
            .readAsLinesSync()
            .where((line) => line.trim().isNotEmpty)
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList(growable: false)
      : const <Map<String, dynamic>>[];
  // The workspace is deleted below, so the bridge's telemetry must be read
  // HERE — its whole point is that it survives the run (bead `pow-39tl`).
  final envelopeFile = usageOut == null
      ? null
      : File(p.join(workspace.path, usageOut));
  final envelope = envelopeFile != null && envelopeFile.existsSync()
      ? envelopeFile.readAsStringSync()
      : null;
  await workspace.delete(recursive: true);
  return _BridgeResult(
    frame: frame,
    config: config,
    stderr: error.toString(),
    trace: traceEntries,
    usageEnvelope: envelope,
  );
}

List<String> _methods(_BridgeResult result) => result.trace
    .where((entry) => entry['kind'] == 'method')
    .map((entry) => entry['method']! as String)
    .toList(growable: false);

void main() {
  final probePath = <String>[
    p.absolute('test/fixtures/acp_agent_probe.dart'),
    p.absolute('packages/grid_assets/test/fixtures/acp_agent_probe.dart'),
  ].firstWhere((path) => File(path).existsSync());

  test(
    'one adapter drives two agent values and steers before protocol completion',
    () async {
      for (final identity in <String>['copilot-probe', 'codex-probe']) {
        final run = await _buildAcpRun(
          probePath: probePath,
          identity: identity,
        );
        final done = run.allocation.startOrAdopt();
        await _waitForOutput(run, 'READY FOR STEER');
        run.steers.controller.add(
          const ProcessSessionCommand(
            commandId: 'steer-1',
            attemptId: 'attempt-1',
            instanceFence: 'fence-1',
            body: 'apply the correction and finish',
          ),
        );
        await done.timeout(const Duration(seconds: 10));

        expect(run.config.args.join('\n'), isNot(contains('ACP channel work')));
        expect(
          run.config.env.values.join('\n'),
          isNot(contains('ACP channel work')),
        );
        expect(run.runtime.isRunning(run.name), isTrue);
        final completed = run.reports.whereType<AllocationCompleted>().single;
        final payload = completed.payload!;
        expect(payload['text'], contains('READY FOR STEER $identity'));
        expect(payload['text'], contains('FINISHED $identity'));
        expect(payload['thought'], contains('thought-$identity-1'));
        expect(payload['thought'], contains('thought-$identity-2'));
        expect(payload, containsPair('tokensIn', '22'));
        expect(payload, containsPair('tokensOut', '14'));
        expect(payload, containsPair('numTurns', '2'));
        expect(payload, containsPair('model', 'gpt-5.6-sol[xhigh]'));
        expect(run.reports.whereType<AllocationFailed>(), isEmpty);
        final permissions = run.trace
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .where((entry) => entry['kind'] == 'permission');
        expect(
          permissions.map((entry) => entry['optionId']),
          everyElement(startsWith('allow-always-')),
        );
        await run.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'terminal mapping is fail closed',
    () async {
      for (final reason in <String>[
        'max_tokens',
        'max_turn_requests',
        'refusal',
        'cancelled',
      ]) {
        final result = await _runBridge(
          probePath: probePath,
          probeArgs: <String>[
            '--identity=stop-$reason',
            '--stop-reason=$reason',
          ],
        );
        expect(result.frame['kind'], 'failed');
        final reported = switch (reason) {
          'max_tokens' => 'maxTokens',
          'max_turn_requests' => 'maxTurnRequests',
          _ => reason,
        };
        expect(
          result.frame['reason'],
          contains(reported),
          reason: '${result.frame}',
        );
      }

      for (final flag in <String>[
        '--prompt-error',
        '--exit-on-prompt',
        '--malformed-on-prompt',
        '--close-output-on-prompt',
      ]) {
        final result = await _runBridge(
          probePath: probePath,
          probeArgs: <String>['--identity=terminal-probe', flag],
        );
        expect(result.frame['kind'], 'failed', reason: '${result.frame}');
        expect(result.frame['reason'], isNotEmpty);
      }

      final cancelled = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>['--identity=cancel-probe'],
        cancelOnProgress: true,
      );
      expect(cancelled.frame, containsPair('kind', 'failed'));
      expect(cancelled.frame['reason'], contains('cancelled'));
      expect(_methods(cancelled), contains('session/cancel'));

      expect(
        const AcpSessionAdapter()
            .decode(
              Stream<List<int>>.value(utf8.encode('{"kind":"mystery"}\n')),
            )
            .toList(),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('permission posture never selects reject', () async {
    final client = GridAllowAllAcpClient(onUpdate: (_) {});
    RequestPermissionRequest request(List<PermissionOption> options) =>
        RequestPermissionRequest(
          sessionId: 's',
          options: options,
          toolCall: ToolCallUpdate(toolCallId: 'tool'),
        );
    PermissionOption option(String id, PermissionOptionKind kind) =>
        PermissionOption(optionId: id, name: id, kind: kind);

    final always = await client.requestPermission(
      request(<PermissionOption>[
        option('reject', PermissionOptionKind.rejectAlways),
        option('once', PermissionOptionKind.allowOnce),
        option('always', PermissionOptionKind.allowAlways),
      ]),
    );
    expect(always.outcome, isA<SelectedOutcome>());
    expect((always.outcome as SelectedOutcome).optionId, 'always');

    final once = await client.requestPermission(
      request(<PermissionOption>[
        option('reject', PermissionOptionKind.rejectOnce),
        option('once', PermissionOptionKind.allowOnce),
      ]),
    );
    expect((once.outcome as SelectedOutcome).optionId, 'once');

    final cancelled = await client.requestPermission(
      request(<PermissionOption>[
        option('reject-once', PermissionOptionKind.rejectOnce),
        option('reject-always', PermissionOptionKind.rejectAlways),
      ]),
    );
    expect(cancelled.outcome, isA<CancelledOutcome>());
  });

  test(
    'model pin is resolved before prompt',
    () async {
      expect(
        'gpt-5.6-sol[xhigh]',
        matches(RegExp(r'^gpt-5\.6-sol\[[a-z]+\]$')),
      );
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model', 'model[high]'],
          current: 'other',
        ),
        'model',
      );
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model[low]', 'model[high]'],
          current: 'model[high]',
        ),
        'model[high]',
      );
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model[low]'],
          current: 'other',
        ),
        'model[low]',
      );
      expect(
        resolveAcpModelId(
          want: 'missing',
          available: const <String>['model[low]'],
        ),
        isNull,
      );
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model[low]', 'model[high]'],
          current: 'other',
        ),
        isNull,
      );

      final ordered = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>[
          '--identity=model-order',
          '--models=gpt-5.6-sol,other',
          '--current=other',
        ],
      );
      expect(ordered.frame, containsPair('kind', 'completed'));
      expect(ordered.frame, containsPair('model', 'gpt-5.6-sol'));
      final initialize = ordered.trace.singleWhere(
        (entry) => entry['method'] == 'initialize',
      );
      expect(
        (initialize['params'] as Map<String, dynamic>)['clientCapabilities'],
        <String, Object?>{
          'fs': <String, Object?>{
            'readTextFile': false,
            'writeTextFile': false,
          },
          'terminal': false,
        },
      );
      final methods = _methods(ordered);
      expect(methods.indexOf('session/set_model'), greaterThanOrEqualTo(0));
      expect(
        methods.indexOf('session/set_model'),
        lessThan(methods.indexOf('session/prompt')),
      );

      final absent = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>[
          '--identity=model-absent',
          '--models=other',
          '--current=other',
        ],
      );
      expect(absent.frame, containsPair('kind', 'failed'));
      expect(
        absent.frame['reason'],
        allOf(contains('gpt-5.6-sol'), contains('other')),
      );

      final ambiguous = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>[
          '--identity=model-ambiguous',
          '--models=gpt-5.6-sol[low],gpt-5.6-sol[high]',
          '--current=other',
        ],
      );
      expect(ambiguous.frame, containsPair('kind', 'failed'));
      expect(
        ambiguous.frame['reason'],
        allOf(contains('[low]'), contains('[high]')),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // The DIAGNOSIS four live codex specify runs never left behind (bead
  // `pow-39tl`): a child that dies before speaking the protocol now reports its
  // exit code, its transport and the last thing it said — and still writes its
  // telemetry, because an absent envelope and an empty one mean different
  // things.
  test('a child that dies before the protocol reports exit code, adapter and '
      'tail — and still writes its usage envelope', () async {
    final result = await _runBridge(
      probePath: probePath,
      probeArgs: const <String>[
        '--die-with=3',
        '--stderr=FATAL: codex-acp could not authenticate',
      ],
      usageOut: 'probe.usage.json',
    );
    expect(result.frame['kind'], 'failed', reason: '${result.frame}');
    final reason = result.frame['reason']! as String;
    // Exit-code-led and adapter-named: an operator reads the CLASS of
    // failure and WHICH transport produced it before the log.
    expect(reason, startsWith('acp agent failed (exit 3) [acp]: '));
    // TAIL-first: the fatal line is the LAST thing the child wrote, and the
    // 2000-odd characters of noise ahead of it are cut, not the diagnosis.
    expect(reason, contains('FATAL: codex-acp could not authenticate'));
    expect(reason, isNot(contains('HEAD-OF-CHILD-STDERR')));
    expect(reason.length, lessThan(kRevalidateReasonTailChars + 200));
    // The envelope lands on a FAILED terminal too, and reads back through
    // the production parser: an absent telemetry file and an empty-usage one
    // are different diagnoses, and only the second one says "it ran".
    expect(result.usageEnvelope, isNotNull);
    expect(() => UsageReport.tryParse(result.usageEnvelope), returnsNormally);
    expect(UsageReport.tryParse(result.usageEnvelope)?.toResultFields(), {
      'tokensIn': '0',
      'tokensOut': '0',
      'numTurns': '0',
    });
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('adapter launch is package resolved and brief free', () {
    const brief = AgentBrief(task: 'SECRET BRIEF');
    final config = const AcpSessionAdapter().launch(
      environment: const AgentEnvironment(
        command: 'agent-command',
        args: <String>['--serve-acp'],
        argsAppend: <String>['--allow-tools'],
        env: <String, String>{'AGENT_KEY': 'value'},
        promptMode: PromptMode.none,
        target: InferenceTarget.openAiCompatible,
        model: 'agent-model',
        sessionAdapter: kAcpSessionAdapterId,
      ),
      workspace: const Workspace(
        workspaceDir: '/worktree',
        branch: 'grid/work',
        baseBranch: 'main',
      ),
      model: 'resolved-model',
      endpoint: Uri.parse('http://127.0.0.1:8080'),
      usageOut: usageReportPath('tg-1/spec_review/specify'),
    );
    expect(config.command, Platform.resolvedExecutable);
    expect(config.lifecycle, Lifecycle.longLived);
    expect(config.args.first, startsWith('--packages='));
    expect(config.args.last, endsWith('lib/src/agent/acp_bridge.dart'));
    expect(config.args.join('\n'), isNot(contains(brief.render())));
    expect(config.env.values.join('\n'), isNot(contains(brief.render())));
    final spec = AcpBridgeSpec.fromJson(
      (jsonDecode(config.env[kAcpBridgeSpecEnvironment]!)
              as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    expect(spec.command, 'agent-command');
    expect(spec.args, <String>['--serve-acp', '--allow-tools']);
    expect(spec.env, <String, String>{
      'AGENT_KEY': 'value',
      'OPENAI_BASE_URL': 'http://127.0.0.1:8080',
    });
    expect(spec.cwd, '/worktree');
    expect(spec.model, 'resolved-model');
    // The FT-2 telemetry path rides the bridge spec: a channel harness has no
    // `sh -c` wrapper, so the adapter must carry it (bead `pow-39tl`).
    expect(
      spec.usageOut,
      '.grid/telemetry/tg-1_spec_review_specify.usage.json',
    );
    expect(const AcpSessionAdapter().encodeBrief(brief), isNotEmpty);
  });

  test('ACP-backed builtins are channel values', () {
    expect(
      kBuiltinEnvironments['copilot'],
      const AgentEnvironment(
        command: 'copilot',
        args: <String>['--acp', '--allow-all-tools'],
        promptMode: PromptMode.none,
        target: InferenceTarget.providerManaged,
        sessionAdapter: kAcpSessionAdapterId,
      ),
    );
    expect(
      kBuiltinEnvironments['codex'],
      const AgentEnvironment(
        command: 'npx',
        args: <String>['-y', '@agentclientprotocol/codex-acp@1.6.2'],
        env: <String, String>{'INITIAL_AGENT_MODE': 'agent-full-access'},
        promptMode: PromptMode.none,
        target: InferenceTarget.providerManaged,
        model: 'gpt-5.6-sol',
        sessionAdapter: kAcpSessionAdapterId,
      ),
    );
    expect(
      kBuiltinAgentSessionAdapters.require('acp'),
      isA<AcpSessionAdapter>(),
    );

    final source = File('lib/src/code/code_capabilities.dart').existsSync()
        ? File('lib/src/code/code_capabilities.dart').readAsStringSync()
        : File(
            'packages/grid_assets/lib/src/code/code_capabilities.dart',
          ).readAsStringSync();
    expect(
      RegExp(
        r'AgentSessionAdapterRegistry sessionAdapters =\s*'
        r'kBuiltinAgentSessionAdapters',
      ).allMatches(source),
      hasLength(2),
    );
  });

  test('ACP boundary stays behind neutral seam', () async {
    File source(String relative) {
      final local = File(relative);
      if (local.existsSync()) return local;
      return File(p.join('packages/grid_assets', relative));
    }

    final seam = source('lib/src/agent/agent_session.dart').readAsStringSync();
    for (final method in const <String>[
      'initialize',
      'session/new',
      'session/prompt',
      'session/update',
      'session/cancel',
      'session/request_permission',
      'session/set_model',
    ]) {
      expect(seam, isNot(contains(method)), reason: method);
    }
    final adapter = source(
      'lib/src/agent/acp_session_adapter.dart',
    ).readAsStringSync();
    expect(adapter, isNot(contains('acp_envelope.dart')));
    expect(adapter, isNot(contains('federated_grid_assets')));

    final diff = await Process.run('git', const <String>[
      'diff',
      '--name-only',
    ], workingDirectory: source('pubspec.yaml').parent.path);
    expect(diff.exitCode, 0, reason: '${diff.stderr}');
    expect(
      '${diff.stdout}',
      isNot(
        contains(
          'packages/federated_grid_assets/lib/src/protocol/acp_envelope.dart',
        ),
      ),
    );
  });
}
