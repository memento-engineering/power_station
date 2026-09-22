import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/allocation_mount.dart';
import '../support/package_root.dart';

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
    required this.tree,
  });

  final Allocation allocation;
  final SubprocessProvider runtime;
  final List<AllocationReport> reports;
  final RuntimeConfig config;
  final _Steers steers;
  final String name;
  final File trace;
  final TreeContext tree;
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
    required this.bound,
    required this.asks,
    required this.fallbacks,
  });

  final Map<String, dynamic> frame;
  final RuntimeConfig config;
  final String stderr;
  final List<Map<String, dynamic>> trace;

  /// The `session_bound` frame the bridge published after `session/new`.
  final Map<String, dynamic>? bound;

  /// Every normalized permission ask the bridge published.
  final List<AgentPermissionRequest> asks;

  /// Every bridge-local cancellation record the bridge flushed.
  final List<AgentPermissionDecision> fallbacks;

  /// The FT-2 envelope the bridge wrote, read before the temp workspace is
  /// deleted; null when this run asked for no `usageOut` or none landed.
  final String? usageEnvelope;
}

Future<_Run> _buildAcpRun({
  required String probePath,
  required String identity,
  List<String> probeArgs = const <String>[],
  bool leased = true,
  AgentPermissionPolicy policy = const AgentPermissionPolicy.trustedHeadless(
    id: 'acp-lease-test',
  ),
  RecordingExplorationTransport? transport,
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
    args: <String>[probePath, '--identity=$identity', ...probeArgs],
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
      // EXPLICIT, both of them (bead `pow-ed1c`): the trusted-headless posture
      // is only ever reached by configuration, and it is only reachable at all
      // because a carrier exists to record what it authorizes.
      AgentPermissionPolicy: policy,
      ServiceBundle: ServiceBundle(
        transport: transport ?? RecordingExplorationTransport(),
      ),
    },
  );
  final steers = _Steers();
  final capability = AgentCapability(
    // NO asset registry: this suite isolates the session adapter, so the
    // provision leg materializes nothing at all.
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
  final allocationInputs = AllocationInputs(
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
    inputs: allocationInputs,
  );
  final ProcessLeaseVendor vendor = SelfManagedProcessVendor(
    spawn: stationProcessSpawner,
    dispatch: stationProcessDispatcher,
  );
  // LEASED is the station's own fork (the host routes every ProcessCapability
  // through the ambient vendor). `leased: false` mints the capability's DIRECT
  // `ProcessAllocation` instead — the engine seam that carries a channel's
  // declared failure kind onto its report.
  final allocation = leased
      ? vendor
            .leaseFor(request)
            .createAllocation(
              AllocationInputs(
                args: args,
                transport: runtime,
                address: const AllocationAddress('session-1', 'work-1/agent'),
                env: const <String, String>{},
                sink: reports.add,
                kind: StepKind.job,
              ),
            )
      : capability.createAllocation(allocationInputs);
  final run = _Run(
    allocation: allocation,
    runtime: runtime,
    reports: reports,
    config: config,
    steers: steers,
    name: name,
    trace: trace,
    tree: tree,
  );
  addTearDown(run.close);
  return run;
}

/// Every reported failure the engine would resolve to [StepFailureClass.work]
/// — i.e. every one that WOULD charge the bead's attempt cursor.
///
/// The resolution is the engine's own [resolveFailureClass], not a local
/// re-derivation: this asserts what the engine decides, never what this test
/// believes it decides.
List<AllocationFailed> _workClassed(List<AllocationReport> reports) => reports
    .whereType<AllocationFailed>()
    .where(
      (failed) =>
          resolveFailureClass(
            kind: failed.kind,
            ranFor: const Duration(minutes: 1),
            kindDeclared: failed.kindDeclared,
          ) ==
          StepFailureClass.work,
    )
    .toList(growable: false);

/// The ONE wall-clock bound on a real ACP fixture's progress.
///
/// It is a LIVENESS tripwire, never a latency assertion: every wait below
/// returns the instant its observable outcome lands, and trips only when that
/// outcome never arrives at all. A child that is merely SLOW — the machine is
/// running another suite, the front end is compiling the bridge — is not a
/// defect, and the bounds this replaced kept reporting it as one.
const Duration _fixtureLivenessCeiling = Duration(seconds: 30);

/// Polls until the allocation reports a failure, so a terminal that arrives
/// through the channel drive (not through `startOrAdopt`'s own future) is
/// observed without a fixed sleep.
Future<AllocationFailed> _waitForFailure(_Run run) async {
  final waited = Stopwatch()..start();
  while (true) {
    final failures = run.reports.whereType<AllocationFailed>();
    if (failures.isNotEmpty) return failures.first;
    if (run.reports.whereType<AllocationCompleted>().isNotEmpty) {
      throw StateError('ACP allocation COMPLETED; expected a failure');
    }
    if (waited.elapsed > _fixtureLivenessCeiling) {
      throw StateError('ACP allocation never failed; reports=${run.reports}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _waitForOutput(_Run run, String text) async {
  final waited = Stopwatch()..start();
  while (true) {
    if (run.runtime.peek(run.name, 0).contains(text)) return;
    final failures = run.reports.whereType<AllocationFailed>();
    if (failures.isNotEmpty) {
      throw StateError(
        'ACP allocation failed before "$text": '
        '${failures.map((failure) => failure.reason).join('; ')}',
      );
    }
    if (waited.elapsed > _fixtureLivenessCeiling) {
      throw StateError(
        'ACP allocation never emitted "$text"; reports=${run.reports}, '
        'output=${run.runtime.peek(run.name, 0)}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The STATION stand-in for a direct bridge run: the same decision function the
/// channel session uses, over an explicitly trusted-headless policy.
AgentPermissionDecision? _headlessStation(AgentPermissionRequest request) =>
    decideAgentPermission(
      policy: const AgentPermissionPolicy.trustedHeadless(
        id: 'acp-bridge-test',
      ),
      request: request,
      admittedAttemptId: request.attemptId,
      boundSessionId: request.sessionId,
      audited: true,
    );

Future<_BridgeResult> _runBridge({
  required String probePath,
  required List<String> probeArgs,
  String? model = 'gpt-5.6-sol',
  bool cancelOnProgress = false,
  String? usageOut,
  String attemptId = 'attempt-bridge',
  AgentTier tier = AgentTier.frontier,
  AgentPermissionDecision? Function(AgentPermissionRequest) station =
      _headlessStation,
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
    tier: tier,
  );
  final process = await Process.start(
    config.command,
    config.args,
    workingDirectory: config.workDir,
    environment: <String, String>{
      ...Platform.environment,
      ...config.env,
      // The engine's allocation env overlay, which is where the bridge learns
      // the attempt it was ADMITTED under.
      kGridAttemptEnvironment: attemptId,
    },
    includeParentEnvironment: false,
  );
  final error = StringBuffer();
  final errorDone = process.stderr.transform(utf8.decoder).forEach(error.write);
  final terminal = Completer<Map<String, dynamic>>();
  var cancelled = false;
  Map<String, dynamic>? bound;
  final asks = <AgentPermissionRequest>[];
  final fallbacks = <AgentPermissionDecision>[];
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
        switch (frame['kind']) {
          case 'session_bound':
            bound = frame;
          case 'permission_request':
            final request = AgentPermissionRequest.fromJson(
              (frame['request']! as Map<String, dynamic>)
                  .cast<String, Object?>(),
            );
            asks.add(request);
            final decision = station(request);
            if (decision != null) {
              process.stdin.add(
                const AcpSessionAdapter().encodePermissionDecision(decision),
              );
              unawaited(process.stdin.flush());
            }
          case 'permission_fallback':
            fallbacks.add(
              AgentPermissionDecision.fromJson(
                (frame['decision']! as Map<String, dynamic>)
                    .cast<String, Object?>(),
              ),
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
    frame = await terminal.future.timeout(
      _fixtureLivenessCeiling,
      onTimeout: () => throw StateError(
        'the ACP bridge never reached a terminal frame; stderr=$error',
      ),
    );
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
    bound: bound,
    asks: asks,
    fallbacks: fallbacks,
  );
}

List<String> _methods(_BridgeResult result) => result.trace
    .where((entry) => entry['kind'] == 'method')
    .map((entry) => entry['method']! as String)
    .toList(growable: false);

/// The hermetic ACP agent fixture SOURCE, off the shared cwd-independent
/// package root.
String _probePath() =>
    p.join(packageRoot(), 'test', 'fixtures', 'acp_agent_probe.dart');

/// How many times this suite compiled the fixture. Asserted, not assumed: a
/// child compiled from source PER TEST is what made this suite load sensitive.
int _probeCompileCount = 0;

/// Compiles the ACP fixture ONCE for the whole suite and returns the artifact
/// every real-child test launches, so a cold compile is paid up front instead
/// of on the critical path of each protocol exchange.
///
/// A KERNEL snapshot, not a `jit-snapshot`: a JIT snapshot is trained by
/// RUNNING the script, and this fixture is a protocol server that blocks on
/// stdin until its peer closes it — the training run never returns. Compiling
/// to kernel pays the front end once with no training run at all.
Future<String> _compileProbe(Directory into) async {
  final output = p.join(into.path, 'acp_agent_probe.dill');
  _probeCompileCount++;
  final compiled = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'kernel',
    '-o',
    output,
    _probePath(),
  ]);
  if (compiled.exitCode != 0 || !File(output).existsSync()) {
    throw StateError(
      'could not compile the ACP probe fixture '
      '(exit ${compiled.exitCode}): ${compiled.stdout}\n${compiled.stderr}',
    );
  }
  return output;
}

void main() {
  late final String probePath;
  Directory? snapshotDir;

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp(
      'grid_assets_acp_probe_',
    );
    snapshotDir = directory;
    probePath = await _compileProbe(directory);
  });

  tearDownAll(() async {
    final directory = snapshotDir;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('ACP probe fixture is compiled exactly once per suite', () {
    expect(_probeCompileCount, 1, reason: 'one compile for the whole suite');
    expect(File(probePath).existsSync(), isTrue);
    expect(
      probePath,
      isNot(_probePath()),
      reason: 'every child launches the COMPILED probe, never the source',
    );
  });

  test(
    'one adapter drives two agent values and steers before protocol completion',
    () async {
      for (final identity in <String>['copilot-probe', 'codex-probe']) {
        final run = await _buildAcpRun(
          probePath: probePath,
          identity: identity,
        );
        final done = run.allocation.startMounted(run.tree);
        await _waitForOutput(run, 'READY FOR STEER');
        run.steers.controller.add(
          const ProcessSessionCommand(
            commandId: 'steer-1',
            attemptId: 'attempt-1',
            instanceFence: 'fence-1',
            body: 'apply the correction and finish',
          ),
        );
        await done.timeout(_fixtureLivenessCeiling);

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
        // The seat is the FRONTIER rung and the pin is bare, so the agent's own
        // current selection (`[xhigh]`) loses to the rung's variant.
        expect(payload, containsPair('model', 'gpt-5.6-sol[high]'));
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
    // NO competing deadline: `_fixtureLivenessCeiling` is the only tripwire.
    timeout: Timeout.none,
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
    // NO competing deadline: `_fixtureLivenessCeiling` is the only tripwire.
    timeout: Timeout.none,
  );

  // The CAPACITY-REFUSAL terminal, the live genesis-7ob shape: the agent
  // implemented the whole bead, then its LAST turn ended POSITIVELY on the
  // provider's apology, before the commit it had announced. Read as a
  // completion — a full turn, a real usage envelope — it flared step.complete
  // over an uncommitted tree and gated the round as a stale/no-op bead.
  test('an end turn whose final line is a provider capacity refusal is a typed '
      'NON-RESULT; an ordinary end turn is untouched', () async {
    const capacity =
        'Selected model is at capacity. Please try a different model.';
    final refused = await _runBridge(
      probePath: probePath,
      probeArgs: <String>[
        '--identity=capacity-probe',
        // The LIVE shape: a prior line saying what the agent did, then the
        // refusal, padded — never a bare one-line result.
        '--final-message=I implemented the bead and will commit now.\n'
            '   $capacity  ',
      ],
      usageOut: 'capacity.usage.json',
    );
    expect(refused.frame['kind'], 'failed', reason: '${refused.frame}');
    expect(refused.frame['reason'], capacity, reason: 'the COMPLETE line');
    expect(refused.frame['failureKind'], 'noResult');
    // The envelope is the evidence the turn RAN, and it survives the typed
    // failure exactly as it survives a completion.
    final refusedUsage = UsageReport.tryParse(refused.usageEnvelope);
    expect(refusedUsage?.tokensIn, 11);
    expect(refusedUsage?.tokensOut, 7);
    expect(refusedUsage?.numTurns, 1);

    final completed = await _runBridge(
      probePath: probePath,
      probeArgs: const <String>['--identity=capacity-control'],
      usageOut: 'control.usage.json',
    );
    expect(completed.frame['kind'], 'completed', reason: '${completed.frame}');
    expect(
      (completed.frame['result']! as Map<String, dynamic>)['text'],
      contains('READY FOR STEER capacity-control'),
    );
    expect(completed.frame['failureKind'], isNull);
    final controlUsage = UsageReport.tryParse(completed.usageEnvelope);
    expect(controlUsage?.tokensIn, 11);
    expect(controlUsage?.tokensOut, 7);
    expect(controlUsage?.numTurns, 1);
  }, timeout: Timeout.none);

  // Bead `pow-u1bi`: the codex 0.155.1 incident. The CLI moved at 23:22Z and
  // from 23:3xZ every codex session setup refused the pinned model — and the
  // station charged each refusal to the BEAD, one attempt at a time, while the
  // wedge counter read `0 running`. A failure that happens BEFORE the first
  // turn cannot be the bead's fault: no brief was delivered, so no work was
  // attempted and none could have failed.
  //
  // BOTH SHAPES, because the phase is a LINE and not a message: the typed
  // pinned-model refusal the incident produced, and the child that simply
  // vanishes during the handshake — which the setup catch cannot claim,
  // because the exit reporter observes it first.
  test('ACP failures before the first turn are infra and do not charge a work '
      'attempt', () async {
    // THE WIRE. The bridge DECLARES the kind and the evidence; nothing
    // downstream parses the reason prose to recover either.
    final refused = await _runBridge(
      probePath: probePath,
      probeArgs: const <String>[
        '--identity=setup-refusal',
        // The measured catalog shape: six effort variants of the pinned base,
        // and a frontier seat needs `[high]`, which this agent does not offer.
        '--models=gpt-5.6-sol[low],gpt-5.6-sol[medium]',
        '--current=other',
      ],
    );
    expect(refused.frame['kind'], 'failed', reason: '${refused.frame}');
    expect(refused.frame['failureKind'], CapabilityFailureKind.noResult.name);
    final fields = (refused.frame['fields']! as Map<String, dynamic>)
        .cast<String, String>();
    expect(fields[kAgentFailurePhaseField], kAgentSetupPhase);
    expect(fields[kAgentFailurePinField], 'gpt-5.6-sol');
    // STRUCTURE, not prose: the offered catalog decodes back to a list.
    expect(decodeOfferedField(fields[kAgentFailureOfferedField]), <String>[
      'gpt-5.6-sol[low]',
      'gpt-5.6-sol[medium]',
    ]);
    expect(
      fields[kAgentFailureResolverVerdictField],
      allOf(contains('gpt-5.6-sol'), contains('frontier'), contains('[high]')),
    );

    // THE ENGINE'S RESOLUTION, over the DIRECT `ProcessAllocation` — the seam
    // that carries a channel's declared kind onto its report.
    final run = await _buildAcpRun(
      probePath: probePath,
      identity: 'setup-refusal-alloc',
      probeArgs: const <String>[
        '--models=gpt-5.6-sol[low],gpt-5.6-sol[medium]',
        '--current=other',
      ],
      leased: false,
    );
    // The BEFORE half of the work-attempt claim: nothing has been charged yet.
    expect(_workClassed(run.reports), isEmpty);
    unawaited(run.allocation.startMounted(run.tree));
    final failure = await _waitForFailure(run);
    expect(failure.kind, CapabilityFailureKind.noResult);
    expect(failure.kindDeclared, isTrue);
    expect(
      resolveFailureClass(
        kind: failure.kind,
        // IRRESPECTIVE OF THE CLOCK. A setup refusal is normally fast, but a
        // slow handshake is still a handshake: the DECLARATION is what earns
        // infra, never the elapsed-time floor. In the live incident the codex
        // seats failed after a real npx fetch, well past any silence window.
        ranFor: const Duration(minutes: 1),
        kindDeclared: failure.kindDeclared,
      ),
      StepFailureClass.infra,
    );
    // THE AFTER half: the whole report stream still resolves to zero `work`
    // failures, so the bead's attempt cursor saw nothing to advance on. The
    // control below is what makes that load-bearing — the same kind, over the
    // same long turn, UNDECLARED, is not infra.
    expect(_workClassed(run.reports), isEmpty);
    expect(
      resolveFailureClass(
        kind: failure.kind,
        ranFor: const Duration(minutes: 1),
      ),
      StepFailureClass.noResult,
    );
    expect(run.reports.whereType<AllocationCompleted>(), isEmpty);
    await run.close();

    // THE SECOND SHAPE: the child DIES before the first turn — a binary that
    // cannot authenticate, a launcher the upgrade broke. The setup catch never
    // sees it (the exit reporter wins the race and claims the terminal), so
    // without a declaration here the same pre-turn environment fault would
    // reach the engine as the bead's own untyped work failure — the exact
    // attribution the incident was made of.
    final died = await _runBridge(
      probePath: probePath,
      probeArgs: const <String>[
        '--identity=setup-exit',
        '--die-with=9',
        '--stderr=FATAL: codex-acp could not authenticate',
      ],
    );
    expect(died.frame['kind'], 'failed', reason: '${died.frame}');
    expect(died.frame['failureKind'], CapabilityFailureKind.noResult.name);
    // The PHASE, and ONLY the phase: no catalog was ever observed, so none is
    // invented — the reader learns the lane failed before the first turn
    // without being handed evidence nobody took.
    expect(died.frame['fields'], <String, String>{
      kAgentFailurePhaseField: kAgentSetupPhase,
    });
    // ...and the child's own diagnosis still rides the reason, unchanged.
    expect(died.frame['reason'], contains('FATAL: codex-acp could not '));

    // THE CONTROL that makes the line above load-bearing: the SAME death, one
    // turn later. The brief was delivered and the agent was working on it, so
    // this one IS the bead's and keeps its historical undeclared meaning —
    // the phase is a line, not a blanket amnesty for every dying child.
    final midTurn = await _runBridge(
      probePath: probePath,
      probeArgs: const <String>['--identity=turn-exit', '--exit-on-prompt'],
    );
    expect(midTurn.frame['kind'], 'failed', reason: '${midTurn.frame}');
    expect(midTurn.frame['failureKind'], isNull);
    expect(midTurn.frame['fields'], isNull);

    final exited = await _buildAcpRun(
      probePath: probePath,
      identity: 'setup-exit-alloc',
      probeArgs: const <String>['--die-with=9'],
      leased: false,
    );
    expect(_workClassed(exited.reports), isEmpty);
    unawaited(exited.allocation.startMounted(exited.tree));
    final vanished = await _waitForFailure(exited);
    expect(vanished.kind, CapabilityFailureKind.noResult);
    expect(vanished.kindDeclared, isTrue);
    expect(
      resolveFailureClass(
        kind: vanished.kind,
        // Same clock-independence: a child that dies after a slow npx fetch is
        // still a child that never took a turn.
        ranFor: const Duration(minutes: 1),
        kindDeclared: vanished.kindDeclared,
      ),
      StepFailureClass.infra,
    );
    expect(_workClassed(exited.reports), isEmpty);
    expect(exited.reports.whereType<AllocationCompleted>(), isEmpty);
    await exited.close();
  }, timeout: Timeout.none);

  test('the capacity refusal reaches the engine as a DECLARED non-result '
      'allocation the engine resolves to infra, never a completion', () async {
    const capacity =
        'Selected model is at capacity. Please try a different model.';
    final run = await _buildAcpRun(
      probePath: probePath,
      identity: 'capacity-alloc',
      probeArgs: const <String>['--final-message=$capacity'],
      // The DIRECT process allocation: `ProcessAllocation._driveChannel` is the
      // engine seam that reads a channel failure's declared kind. The lease
      // dispatcher this suite otherwise drives still collapses every
      // `ProcessSessionFailed` to an untyped `Failed(reason)` — an engine-side
      // gap, and the reason this probe names the seam it asserts on.
      leased: false,
    );
    unawaited(run.allocation.startMounted(run.tree));
    final failure = await _waitForFailure(run);
    expect(failure.reason, capacity);
    expect(failure.kind, CapabilityFailureKind.noResult);
    expect(run.reports.whereType<AllocationCompleted>(), isEmpty);
    // DECLARED, not inferred — and that provenance is the whole ruling. The
    // engine's own resolution reads it (`declared process-session non-results
    // are infra`): a kind this side NAMED resolves without consulting the
    // elapsed-time floor, which is what the live shape needs. genesis-7ob's
    // refusal arrived after a FULL turn — 38k tokens in, a real usage
    // envelope — so the artifact-less fast-exit evidence never applied to it.
    expect(failure.kindDeclared, isTrue);
    expect(
      resolveFailureClass(
        kind: failure.kind,
        ranFor: const Duration(minutes: 1),
        kindDeclared: failure.kindDeclared,
      ),
      StepFailureClass.infra,
      reason: 'grid_assets declares the KIND; the engine resolves the CLASS',
    );
    // The control that makes the line above load-bearing: the SAME kind over
    // the SAME long turn, undeclared, is not infra. The declaration is what
    // buys it — never the clock, and never anything grid_assets re-implements.
    expect(
      resolveFailureClass(
        kind: failure.kind,
        ranFor: const Duration(minutes: 1),
      ),
      StepFailureClass.noResult,
    );
    await run.close();
  }, timeout: Timeout.none);

  // The KIND is carried, not re-derived: whatever the bridge DECLARED on the
  // wire is what the engine's update reports. An absent declaration keeps the
  // historical untyped meaning, so every failure written before this seam
  // existed still means what it meant.
  test(
    'a declared failure kind survives decode and the channel session',
    () async {
      Future<ProcessSessionUpdate> terminalFor(
        Map<String, Object?> frame,
      ) async {
        const name = 'session-raw/work-1/agent';
        final runtime = FakeRuntimeProvider();
        await runtime.start(
          name,
          const RuntimeConfig(
            workDir: '.',
            command: 'probe',
            lifecycle: Lifecycle.longLived,
          ),
        );
        final commands = StreamController<ProcessSessionCommand>();
        addTearDown(commands.close);
        final session = AgentSession(
          runtime: runtime,
          name: name,
          adapter: const AcpSessionAdapter(),
          brief: const AgentBrief(task: 'raw frame probe'),
          commands: commands.stream,
          attemptId: 'attempt-raw',
          instanceFence: 'fence-raw',
        );
        addTearDown(session.close);
        final terminal = session.updates.first;
        await session.start();
        runtime.emitInteraction(name, utf8.encode('${jsonEncode(frame)}\n'));
        return terminal.timeout(const Duration(seconds: 5));
      }

      expect(
        await terminalFor(<String, Object?>{
          'kind': 'failed',
          'reason': 'Selected model is at capacity.',
          'failureKind': 'noResult',
        }),
        isA<ProcessSessionFailed>()
            .having((f) => f.reason, 'reason', 'Selected model is at capacity.')
            .having((f) => f.kind, 'kind', CapabilityFailureKind.noResult),
      );

      expect(
        await terminalFor(<String, Object?>{
          'kind': 'failed',
          'reason': 'the harness died',
        }),
        isA<ProcessSessionFailed>()
            .having((f) => f.reason, 'reason', 'the harness died')
            .having((f) => f.kind, 'kind', CapabilityFailureKind.work),
        reason: 'an undeclared kind keeps the historical untyped meaning',
      );

      expect(
        await terminalFor(<String, Object?>{
          'kind': 'failed',
          'reason': 'ignored',
          'failureKind': 'somethingElse',
        }),
        isA<ProcessSessionFailed>().having(
          (f) => f.reason,
          'reason',
          contains('unknown ACP bridge failure kind: somethingElse'),
        ),
        reason: 'a kind nobody can read is LOUD, never a downgrade to work',
      );
    },
  );

  // The ACP client no longer HAS a posture: it applies the station's decision
  // and nothing else (bead `pow-ed1c`). The blanket allow-always answer that
  // used to live here is gone, not wrapped.
  test(
    'permission bridge applies only the station decision',
    () async {
      PermissionOption option(String id, PermissionOptionKind kind) =>
          PermissionOption(optionId: id, name: 'LABEL $id', kind: kind);
      final offered = <PermissionOption>[
        option('reject-once', PermissionOptionKind.rejectOnce),
        option('reject-always', PermissionOptionKind.rejectAlways),
        option('once', PermissionOptionKind.allowOnce),
        option('always', PermissionOptionKind.allowAlways),
      ];
      RequestPermissionRequest ask({
        ToolKind? kind = ToolKind.execute,
        List<PermissionOption>? options,
      }) => RequestPermissionRequest(
        sessionId: 'acp-1',
        options: options ?? offered,
        toolCall: ToolCallUpdate(
          toolCallId: 'tool',
          kind: kind,
          title: 'SECRET TOOL TITLE',
          rawInput: <String, dynamic>{'secret': 'RAW INPUT'},
        ),
      );

      final seen = <AgentPermissionRequest>[];
      final fallbacks = <AgentPermissionDecision>[];
      GridPolicyAcpClient client(
        AgentPermissionDecision? Function(AgentPermissionRequest) station,
      ) => GridPolicyAcpClient(
        attemptId: 'attempt-1',
        onUpdate: (_) {},
        decide: (request) async {
          seen.add(request);
          return station(request);
        },
        audit: fallbacks.add,
      );

      // EXACTLY the station's outcome, whatever else is offered: a one-shot
      // authorization takes the one-shot option even though a durable one is
      // right there, and a refusal is applied just as faithfully.
      for (final (outcome, optionId) in <(AgentPermissionOutcome, String)>[
        (AgentPermissionOutcome.allowOnce, 'once'),
        (AgentPermissionOutcome.allowAlways, 'always'),
        (AgentPermissionOutcome.rejectOnce, 'reject-once'),
        (AgentPermissionOutcome.rejectAlways, 'reject-always'),
      ]) {
        final response = await client(
          (request) => AgentPermissionDecision(
            requestId: request.requestId,
            attemptId: request.attemptId,
            sessionId: request.sessionId,
            capability: request.capability,
            policyId: 'station',
            outcome: outcome,
            reason: 'probe',
          ),
        ).requestPermission(ask());
        expect(
          (response.outcome as SelectedOutcome).optionId,
          optionId,
          reason: outcome.name,
        );
      }
      expect(fallbacks, isEmpty);

      // The ask that crossed carries IDENTITY and SHAPE only.
      final crossed = seen.first;
      expect(crossed.attemptId, 'attempt-1');
      expect(crossed.sessionId, 'acp-1');
      expect(crossed.capability, AgentPermissionCapability.execute);
      expect(crossed.offered, <AgentPermissionOutcome>[
        AgentPermissionOutcome.rejectOnce,
        AgentPermissionOutcome.rejectAlways,
        AgentPermissionOutcome.allowOnce,
        AgentPermissionOutcome.allowAlways,
      ]);
      final rendered = jsonEncode(crossed.toJson());
      for (final leak in const <String>[
        'SECRET TOOL TITLE',
        'RAW INPUT',
        'LABEL',
        'reject-once',
        'tool',
      ]) {
        expect(rendered, isNot(contains(leak)), reason: leak);
      }

      // An UNNAMED or uncategorized tool normalizes to the non-grantable
      // sentinel, so no policy can scope it.
      for (final kind in <ToolKind?>[null, ToolKind.other]) {
        seen.clear();
        await client((_) => null).requestPermission(ask(kind: kind));
        expect(seen.single.capability, AgentPermissionCapability.unknown);
      }
      // Every named kind normalizes to its own capability — no default arm.
      for (final kind in ToolKind.values) {
        expect(
          acpPermissionCapability(kind) == AgentPermissionCapability.unknown,
          kind == ToolKind.other,
          reason: kind.name,
        );
      }

      // END TO END: the bridge publishes the binding, asks, and applies the
      // answer to the option the harness actually offered.
      final scoped = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>['--identity=scoped-probe'],
        attemptId: 'attempt-bridge',
        station: (request) => decideAgentPermission(
          policy: const AgentPermissionPolicy.scoped(
            id: 'station-execute-once',
            grants: <AgentPermissionCapability, AgentPermissionGrant>{
              AgentPermissionCapability.execute: AgentPermissionGrant.allowOnce,
            },
          ),
          request: request,
          admittedAttemptId: 'attempt-bridge',
          boundSessionId: request.sessionId,
          audited: true,
        ),
      );
      expect(scoped.frame, containsPair('kind', 'completed'));
      expect(scoped.bound, isNotNull);
      expect(scoped.bound!['attemptId'], 'attempt-bridge');
      expect(scoped.bound!['sessionId'], 'session-scoped-probe');
      expect(scoped.asks.single.attemptId, 'attempt-bridge');
      expect(scoped.asks.single.capability, AgentPermissionCapability.execute);
      expect(scoped.fallbacks, isEmpty);
      expect(
        scoped.trace
            .where((entry) => entry['kind'] == 'permission')
            .map((entry) => entry['optionId']),
        // ONE-SHOT, though the probe also offers the durable option.
        everyElement(startsWith('allow-once-')),
      );
    },
    // NO competing deadline: `_fixtureLivenessCeiling` is the only tripwire.
    timeout: Timeout.none,
  );

  test(
    'permission cancellation is fail closed',
    () async {
      PermissionOption option(String id, PermissionOptionKind kind) =>
          PermissionOption(optionId: id, name: id, kind: kind);
      final offered = <PermissionOption>[
        option('once', PermissionOptionKind.allowOnce),
        option('reject-once', PermissionOptionKind.rejectOnce),
      ];
      final request = RequestPermissionRequest(
        sessionId: 'acp-1',
        options: offered,
        toolCall: ToolCallUpdate(toolCallId: 'tool', kind: ToolKind.execute),
      );
      AgentPermissionDecision answer(
        AgentPermissionRequest ask, {
        String? requestId,
        String? attemptId,
        String? sessionId,
        AgentPermissionCapability? capability,
        AgentPermissionOutcome outcome = AgentPermissionOutcome.allowAlways,
      }) => AgentPermissionDecision(
        requestId: requestId ?? ask.requestId,
        attemptId: attemptId ?? ask.attemptId,
        sessionId: sessionId ?? ask.sessionId,
        capability: capability ?? ask.capability,
        policyId: 'station',
        outcome: outcome,
        reason: 'probe',
      );

      final fallbacks = <AgentPermissionDecision>[];
      Future<RequestPermissionResponse> settle(
        AgentPermissionDecider decide, {
        Duration timeout = const Duration(seconds: 5),
      }) => GridPolicyAcpClient(
        attemptId: 'attempt-1',
        onUpdate: (_) {},
        decide: decide,
        audit: fallbacks.add,
        timeout: timeout,
      ).requestPermission(request);

      // No answer, a REPLAYED or mismatched one, a throwing exchange, a bounded
      // timeout, and an authorized kind the harness never offered. Every one is
      // a cancellation, recorded first, and NONE of them selects an option.
      final refusals = <String, Future<RequestPermissionResponse>>{
        'no answer': settle((_) async => null),
        'replayed request': settle(
          (ask) async => answer(ask, requestId: 'acp-permission-99'),
        ),
        'foreign attempt': settle(
          (ask) async => answer(ask, attemptId: 'attempt-other'),
        ),
        'superseded session': settle(
          (ask) async => answer(ask, sessionId: 'acp-old'),
        ),
        'different capability': settle(
          (ask) async =>
              answer(ask, capability: AgentPermissionCapability.read),
        ),
        'exchange threw': settle((_) async => throw StateError('bridge broke')),
        'decision timed out': settle(
          (_) => Completer<AgentPermissionDecision?>().future,
          timeout: const Duration(milliseconds: 20),
        ),
        // The station authorized DURABLY but only a one-shot option exists;
        // narrowing here would be the client deciding.
        'unoffered kind': settle((ask) async => answer(ask)),
      };
      for (final entry in refusals.entries) {
        expect(
          (await entry.value).outcome,
          isA<CancelledOutcome>(),
          reason: entry.key,
        );
      }
      expect(fallbacks, hasLength(refusals.length));
      expect(
        fallbacks.every((decision) => !decision.grants),
        isTrue,
        reason: 'a fail-closed fallback never grants',
      );
      expect(
        fallbacks.map((decision) => decision.policyId).toSet(),
        <String>{''},
        reason: 'no station policy produced these',
      );

      // A STATION cancellation is already recorded upstream, so the bridge adds
      // no second record of it.
      fallbacks.clear();
      expect(
        (await settle(
          (ask) async => answer(ask, outcome: AgentPermissionOutcome.cancelled),
        )).outcome,
        isA<CancelledOutcome>(),
      );
      expect(fallbacks, isEmpty);

      // END TO END: an answer whose identity does not match the ask is
      // cancelled by the bridge, and that cancellation is FLUSHED as a record —
      // the station never produced it, so this frame is the only place it
      // exists. (An answer naming an unknown ask never routes at all: the
      // bridge drops it, and the ask cancels on its bound timeout.)
      final mismatched = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>['--identity=mismatch-probe'],
        station: (ask) => AgentPermissionDecision(
          requestId: ask.requestId,
          attemptId: ask.attemptId,
          sessionId: 'a-superseded-session',
          capability: ask.capability,
          policyId: 'station',
          outcome: AgentPermissionOutcome.allowAlways,
          reason: 'probe',
        ),
      );
      expect(mismatched.asks, hasLength(1));
      expect(mismatched.fallbacks, hasLength(1));
      expect(mismatched.fallbacks.single.grants, isFalse);
      expect(
        mismatched.fallbacks.single.requestId,
        mismatched.asks.single.requestId,
      );
      expect(
        mismatched.trace
            .where((entry) => entry['kind'] == 'permission')
            .map((entry) => entry['outcome']),
        everyElement('cancelled'),
      );
      // NO ADMITTED ATTEMPT: the bridge stamps a blank attempt and the station's
      // own guard refuses it — the whole run authorizes nothing.
      final unadmitted = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>['--identity=unadmitted-probe'],
        attemptId: '',
      );
      expect(unadmitted.asks.single.attemptId, isEmpty);
      expect(
        unadmitted.trace
            .where((entry) => entry['kind'] == 'permission')
            .map((entry) => entry['optionId']),
        everyElement(startsWith('reject-always-')),
      );
    },
    // NO competing deadline: `_fixtureLivenessCeiling` is the only tripwire.
    timeout: Timeout.none,
  );

  test(
    'model pin is resolved before prompt',
    () async {
      expect(
        'gpt-5.6-sol[xhigh]',
        matches(RegExp(r'^gpt-5\.6-sol\[[a-z]+\]$')),
      );
      // THE CATALOG codex 0.155.1 started offering, verbatim: six efforts of
      // the pinned base plus efforts of two others. Before the seat's rung
      // picked among them the bare pin resolved to nothing and every codex
      // seat died at session setup.
      const codex = <String>[
        'gpt-5.6-sol[low]',
        'gpt-5.6-sol[medium]',
        'gpt-5.6-sol[high]',
        'gpt-5.6-sol[xhigh]',
        'gpt-5.6-sol[max]',
        'gpt-5.6-sol[ultra]',
        'gpt-5.6-terra[low]',
        'gpt-5.6-terra[high]',
        'gpt-5.6-luna[medium]',
      ];
      // The table is DECLARED and TOTAL: every rung names its effort, so no
      // rung can fall through to a guess at the pin's own text.
      expect(kAcpEffortSuffixByTier, <AgentTier, String>{
        AgentTier.cheap: '[low]',
        AgentTier.mid: '[medium]',
        AgentTier.frontier: '[high]',
      });
      expect(kAcpEffortSuffixByTier.keys, AgentTier.values);
      for (final (tier, expected) in const <(AgentTier, String)>[
        (AgentTier.cheap, 'gpt-5.6-sol[low]'),
        (AgentTier.mid, 'gpt-5.6-sol[medium]'),
        (AgentTier.frontier, 'gpt-5.6-sol[high]'),
      ]) {
        expect(
          resolveAcpModelId(want: 'gpt-5.6-sol', available: codex, tier: tier),
          expected,
          reason: tier.name,
        );
      }
      // A base-matching `current` at the WRONG effort is the agent's default,
      // not the seat's declaration, so the rung's variant wins over it.
      expect(
        resolveAcpModelId(
          want: 'gpt-5.6-sol',
          available: codex,
          current: 'gpt-5.6-sol[ultra]',
          tier: AgentTier.frontier,
        ),
        'gpt-5.6-sol[high]',
      );
      // Already satisfied — the bare pin itself, or the rung's own variant —
      // keeps the agent where it is.
      expect(
        resolveAcpModelId(
          want: 'gpt-5.6-sol',
          available: codex,
          current: 'gpt-5.6-sol[high]',
          tier: AgentTier.frontier,
        ),
        'gpt-5.6-sol[high]',
      );
      // COMPATIBILITY, unchanged by the rung: an exact offered id, then a sole
      // variant of the base.
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model', 'model[high]'],
          current: 'other',
          tier: AgentTier.cheap,
        ),
        'model',
      );
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model[low]'],
          current: 'other',
          tier: AgentTier.frontier,
        ),
        'model[low]',
      );
      expect(
        resolveAcpModelId(
          want: 'missing',
          available: const <String>['model[low]'],
          tier: AgentTier.frontier,
        ),
        isNull,
      );
      // AMBIGUOUS AND UNMATCHED: two efforts, neither this rung's. Riding one
      // anyway would spend a rung the seat never declared, so it refuses — and
      // says which rung asked, what that rung needs, and what was offered.
      expect(
        resolveAcpModelId(
          want: 'model',
          available: const <String>['model[low]', 'model[xhigh]'],
          current: 'other',
          tier: AgentTier.frontier,
        ),
        isNull,
      );
      expect(
        acpModelRefusal(
          want: 'gpt-5.6-sol',
          available: const <String>['gpt-5.6-sol[low]', 'gpt-5.6-sol[medium]'],
          tier: AgentTier.frontier,
        ),
        allOf(
          contains('gpt-5.6-sol'),
          contains('frontier'),
          contains('[high]'),
          contains('[low]'),
          contains('[medium]'),
        ),
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

      // A LIVE cheap seat against the effort-suffixed catalog: the rung, not
      // the agent's current selection, decides which variant the child is set
      // to — proof the tier survives the spec handoff into the bridge process.
      final cheap = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>[
          '--identity=model-cheap',
          '--models=gpt-5.6-sol[low],gpt-5.6-sol[high]',
          '--current=gpt-5.6-sol[high]',
        ],
        tier: AgentTier.cheap,
      );
      expect(cheap.frame, containsPair('kind', 'completed'));
      expect(cheap.frame, containsPair('model', 'gpt-5.6-sol[low]'));

      final ambiguous = await _runBridge(
        probePath: probePath,
        probeArgs: const <String>[
          '--identity=model-ambiguous',
          '--models=gpt-5.6-sol[low],gpt-5.6-sol[medium]',
          '--current=other',
        ],
      );
      expect(ambiguous.frame, containsPair('kind', 'failed'));
      expect(
        ambiguous.frame['reason'],
        allOf(
          contains('frontier'),
          contains('[high]'),
          contains('[low]'),
          contains('[medium]'),
        ),
      );
    },
    // NO competing deadline: `_fixtureLivenessCeiling` is the only tripwire.
    timeout: Timeout.none,
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
  }, timeout: Timeout.none);

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
        roleAsset: '.agents/agents/$kSeatHole.md',
        primeMode: SeatPrimeMode.prompt,
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
        // The AGENT, not the launcher (bead `pow-u1bi`): `npx` is on every box
        // with node, so it proves nothing about codex being installed.
        pathCheck: 'codex',
        sessionAdapter: kAcpSessionAdapterId,
        roleAsset: '.agents/agents/$kSeatHole.md',
        primeMode: SeatPrimeMode.prompt,
      ),
    );
    expect(
      kBuiltinAgentSessionAdapters.require('acp'),
      isA<AcpSessionAdapter>(),
    );

    final source = File(
      p.join(packageRoot(), 'lib', 'src', 'code', 'code_capabilities.dart'),
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
    // Anchored on the package root, never probed relative to the process cwd:
    // the old form tried the path as-is and then under `packages/grid_assets`,
    // so it only resolved when the process happened to sit at this package or
    // at the workspace root — and it read whichever tree the cwd named.
    File source(String relative) => File(p.join(packageRoot(), relative));

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
