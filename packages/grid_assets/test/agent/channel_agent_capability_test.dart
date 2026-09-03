import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _ProbeAdapter implements AgentSessionAdapter {
  _ProbeAdapter(this.fixture, {this.args = const <String>[]});

  final String fixture;
  final List<String> args;

  /// The last `usageOut` the capability handed this adapter.
  String? usageOut;

  @override
  String get id => 'probe';

  @override
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  }) {
    this.usageOut = usageOut;
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: Platform.resolvedExecutable,
      args: <String>[fixture, ...args],
      lifecycle: Lifecycle.longLived,
    );
  }

  @override
  List<int> encodeBrief(AgentBrief brief) => utf8.encode(
    '${jsonEncode(<String, Object?>{'type': 'brief', 'brief': brief.render()})}\n',
  );

  @override
  List<int> encodeSteer(String text) => utf8.encode(
    '${jsonEncode(<String, Object?>{'type': 'steer', 'text': text})}\n',
  );

  @override
  Stream<AgentProtocolEvent> decode(Stream<List<int>> stdout) => stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((line) {
        final frame = jsonDecode(line) as Map<String, dynamic>;
        return switch (frame['type']) {
          'progress' => const AgentProtocolEvent.progress(),
          'completed' => AgentProtocolEvent.completed(
            result: (frame['result'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, value as String),
            ),
            usage: _usage(frame['usage'] as Map<String, dynamic>),
          ),
          'failed' => AgentProtocolEvent.failed(
            reason: frame['reason'] as String,
          ),
          _ => throw FormatException('unknown probe frame: $frame'),
        };
      });

  UsageReport _usage(Map<String, dynamic> json) => UsageReport(
    tokensIn: json['tokensIn'] as int?,
    tokensOut: json['tokensOut'] as int?,
    numTurns: json['numTurns'] as int?,
    model: json['model'] as String?,
  );
}

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
  });

  final Allocation allocation;
  final SubprocessProvider runtime;
  final List<AllocationReport> reports;
  final RuntimeConfig config;
  final _Steers steers;
  final String name;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await allocation.dispose();
    if (!steers.controller.isClosed) await steers.controller.close();
  }
}

Future<_Run> _buildRun({required _ProbeAdapter adapter}) async {
  final workspaceDir = await Directory.systemTemp.createTemp(
    'grid_assets_channel_',
  );
  addTearDown(() async {
    if (workspaceDir.existsSync()) await workspaceDir.delete(recursive: true);
  });
  final workspace = Workspace(
    workspaceDir: workspaceDir.path,
    branch: 'grid/work-1',
    baseBranch: 'main',
  );
  final environment = const AgentEnvironment(
    command: 'probe',
    promptMode: PromptMode.none,
    sessionAdapter: 'probe',
  );
  final tree = FakeTreeContext(
    values: <Type, Object>{
      Bead: const Bead(
        id: 'work-1',
        title: 'Channel probe work',
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
    sessionAdapters: AgentSessionAdapterRegistry(<String, AgentSessionAdapter>{
      'probe': adapter,
    }),
    steers: steers,
  );
  final runtime = SubprocessProvider(
    parentEnvironment: const <String, String>{},
    livenessPollPeriod: const Duration(milliseconds: 20),
    agentDeadline: null,
  );
  addTearDown(runtime.dispose);
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
  );
  addTearDown(run.close);
  return run;
}

Future<void> _waitForProgress(_Run run) async {
  for (var i = 0; i < 500; i++) {
    if (run.runtime.peek(run.name, 0).contains('"type":"progress"')) return;
    final failures = run.reports.whereType<AllocationFailed>();
    if (failures.isNotEmpty) {
      throw StateError(
        'probe allocation failed before progress: '
        '${failures.map((failure) => failure.reason).join('; ')}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'probe never reported progress; reports=${run.reports}, '
    'running=${run.runtime.isRunning(run.name)}, '
    'terminal=${run.runtime.terminalOf(run.name)}',
  );
}

void main() {
  final fixture = <String>[
    p.absolute('test/fixtures/channel_probe.dart'),
    p.absolute('packages/grid_assets/test/fixtures/channel_probe.dart'),
  ].firstWhere((path) => File(path).existsSync());

  test('lease allocation delivers brief only over channel and completes from '
      'protocol result', () async {
    final run = await _buildRun(adapter: _ProbeAdapter(fixture));
    final done = run.allocation.startOrAdopt();
    await _waitForProgress(run);
    run.steers.controller.add(
      const ProcessSessionCommand(
        commandId: 'steer-1',
        attemptId: 'attempt-1',
        instanceFence: 'fence-1',
        body: 'finish with the structured result',
      ),
    );
    await done.timeout(const Duration(seconds: 10));

    expect(run.config.args.join('\n'), isNot(contains('Channel probe work')));
    final completed = run.reports.whereType<AllocationCompleted>().single;
    expect(
      completed.payload,
      containsPair('observedBrief', contains('Channel probe work')),
    );
    expect(
      completed.payload,
      containsPair('observedSteer', 'finish with the structured result'),
    );
    expect(completed.payload, containsPair('tokensIn', '21'));
    expect(completed.payload, containsPair('tokensOut', '8'));
    expect(completed.payload, containsPair('numTurns', '2'));
    expect(completed.payload, containsPair('model', 'probe-model'));
    expect(run.reports.whereType<AllocationFailed>(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('clean probe disappearance before protocol completion fails channel '
      'allocation', () async {
    final run = await _buildRun(
      adapter: _ProbeAdapter(fixture, args: const ['--exit-after-brief']),
    );
    await run.allocation.startOrAdopt().timeout(const Duration(seconds: 10));

    expect(run.reports.whereType<AllocationFailed>(), hasLength(1));
    expect(run.reports.whereType<AllocationCompleted>(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
