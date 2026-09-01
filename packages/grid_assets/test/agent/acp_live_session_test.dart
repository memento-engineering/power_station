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

class _LiveSteers implements AgentSteerSource {
  final StreamController<ProcessSessionCommand> controller =
      StreamController<ProcessSessionCommand>();

  @override
  Stream<ProcessSessionCommand> watch(String workBeadId) => controller.stream;
}

class _LiveRun {
  _LiveRun({
    required this.allocation,
    required this.runtime,
    required this.reports,
    required this.steers,
    required this.workspace,
    required this.processName,
  });

  final Allocation allocation;
  final SubprocessProvider runtime;
  final List<AllocationReport> reports;
  final _LiveSteers steers;
  final Directory workspace;
  final String processName;

  Future<void> waitForProgressContaining(String text) async {
    for (var i = 0; i < 3600; i++) {
      final output = runtime.peek(processName, 0);
      final progress = StringBuffer();
      for (final line in const LineSplitter().convert(output)) {
        try {
          final frame = jsonDecode(line) as Map<String, dynamic>;
          if (frame['kind'] != 'progress') continue;
          final fields = frame['fields'] as Map<String, dynamic>;
          final chunk = fields['text'];
          if (chunk is String) progress.write(chunk);
        } on Object {
          // The runtime snapshot may end in a partial line while the agent is
          // streaming. The next poll observes the completed normalized frame.
        }
      }
      if (progress.toString().contains(text)) return;
      final failures = reports.whereType<AllocationFailed>();
      if (failures.isNotEmpty) {
        throw StateError(
          'live ACP allocation failed before "$text": '
          '${failures.map((failure) => failure.reason).join('; ')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException(
      'live ACP allocation never emitted "$text"; '
      'output=${runtime.peek(processName, 0)} reports=$reports',
    );
  }

  void sendSteer(String text) {
    steers.controller.add(
      ProcessSessionCommand(
        commandId: 'steer-1',
        attemptId: 'attempt-1',
        instanceFence: 'fence-1',
        body: text,
      ),
    );
  }

  Future<void> close() async {
    await allocation.dispose();
    if (!steers.controller.isClosed) await steers.controller.close();
    await runtime.dispose();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  }
}

Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

Future<_LiveRun> _buildLiveAcpRun({
  required String name,
  required AgentEnvironment environment,
  required AcpSessionAdapter adapter,
}) async {
  final workspace = await Directory.systemTemp.createTemp(
    'grid_assets_live_acp_${name}_',
  );
  await _git(workspace.path, const <String>['init', '-q', '-b', 'main']);
  await _git(workspace.path, const <String>[
    'config',
    'user.email',
    'grid-acp-test@example.invalid',
  ]);
  await _git(workspace.path, const <String>[
    'config',
    'user.name',
    'Grid ACP Test',
  ]);
  File(
    p.join(workspace.path, 'README.md'),
  ).writeAsStringSync('# ACP live test\n');
  await _git(workspace.path, const <String>['add', 'README.md']);
  await _git(workspace.path, const <String>[
    'commit',
    '-q',
    '-m',
    'initialize',
  ]);

  final workBeadId = 'live-$name';
  final tree = FakeTreeContext(
    values: <Type, Object>{
      Bead: Bead(
        id: workBeadId,
        title: 'Live ACP steer proof for $name',
        description:
            'First emit the exact text READY FOR STEER before using tools. '
            'Then inspect the repository and run `sleep 10` in the shell to '
            'leave time for a correction. Do not create any acp file during '
            'this first turn. Finish the turn after the wait; a correction '
            'will arrive through the same session.',
      ),
      Workspace: Workspace(
        workspaceDir: workspace.path,
        branch: 'main',
        baseBranch: 'main',
      ),
      AgentConfig: AgentConfig(harness: name),
      EnvironmentRegistry: EnvironmentRegistry(
        custom: <String, AgentEnvironment>{name: environment},
      ),
    },
  );
  final steers = _LiveSteers();
  final capability = AgentCapability(
    overlayRoot: p.join(workspace.path, 'absent-overlay'),
    sessionAdapters: AgentSessionAdapterRegistry(<String, AgentSessionAdapter>{
      kAcpSessionAdapterId: adapter,
    }),
    steers: steers,
  );
  final runtime = SubprocessProvider(
    parentEnvironment: Platform.environment,
    livenessPollPeriod: const Duration(milliseconds: 100),
    agentDeadline: null,
  );
  final nodePath = '$workBeadId/agent';
  final processName = 'live-session/$nodePath';
  final reports = <AllocationReport>[];
  final args = StepArgs(nodePath: nodePath, cancel: CancelToken());
  final leaseContext = AllocationContext(
    treeContext: tree,
    args: args,
    transport: runtime,
    address: AllocationAddress('live-session', nodePath),
    env: const <String, String>{
      'GRID_ATTEMPT_ID': 'attempt-1',
      'GRID_INSTANCE_TOKEN': 'fence-1',
    },
    sink: reports.add,
    kind: StepKind.job,
  );
  final request = ProcessLeaseRequest(
    stepBeadId: '$workBeadId-step',
    capability: capability,
    allocation: leaseContext,
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
          address: AllocationAddress('live-session', nodePath),
          env: const <String, String>{},
          sink: reports.add,
          kind: StepKind.job,
        ),
      );
  return _LiveRun(
    allocation: allocation,
    runtime: runtime,
    reports: reports,
    steers: steers,
    workspace: workspace,
    processName: processName,
  );
}

void main() {
  test(
    'live Copilot and Codex complete one steered ACP grid step',
    () async {
      if (Platform.environment['GRID_ACP_LIVE'] != '1') {
        markTestSkipped('set GRID_ACP_LIVE=1 to run installed ACP harnesses');
        return;
      }
      const adapter = AcpSessionAdapter();
      for (final name in <String>['copilot', 'codex']) {
        final run = await _buildLiveAcpRun(
          name: name,
          environment: kBuiltinEnvironments[name]!,
          adapter: adapter,
        );
        try {
          final done = run.allocation.startOrAdopt();
          await run.waitForProgressContaining('READY FOR STEER');
          run.sendSteer(
            'Create acp-$name.txt containing STEERED-$name, then finish.',
          );
          await done.timeout(const Duration(minutes: 5));
          expect(run.runtime.isRunning(run.processName), isTrue);
          final payload = run.reports
              .whereType<AllocationCompleted>()
              .single
              .payload!;
          final output = run.runtime.peek(run.processName, 0);
          final resultFile = File(p.join(run.workspace.path, 'acp-$name.txt'));
          expect(
            resultFile.existsSync(),
            isTrue,
            reason: 'payload=$payload\noutput=$output',
          );
          expect(resultFile.readAsStringSync(), contains('STEERED-$name'));
          expect(payload['text'], isNotEmpty);
          expect(payload['tokensIn'], isNotEmpty);
          expect(payload['tokensOut'], isNotEmpty);
          expect(payload['numTurns'], '2');
          expect(payload['model'], isNotEmpty);
          if (name == 'codex') {
            expect(
              payload['model'],
              matches(RegExp(r'^gpt-5\.6-sol\[[a-z]+\]$')),
            );
          }
        } finally {
          await run.close();
        }
      }
    },
    tags: const <String>['integration'],
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
