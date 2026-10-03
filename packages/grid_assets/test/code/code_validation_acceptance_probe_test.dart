// The acceptance-probe regression
// (`power_station#acceptance-probe-base-failure-is-no-regression-evidence`).
//
// The live regression (lunar epoch 100): every butane round whose Validation
// Plan was an acceptance PROBE — `flutter pub get && grep -q …` — reached
// code-validation and gated identically. The probe MUST fail at the merge
// base, where the feature does not exist yet; the base leg named no failing
// test, the lane reported an uncomparable base as `noResult`, and the engine
// counted it as one harness silent exit, flared `harness.throttled` and parked
// a human gate — though no model step had run at all.
//
// These probes drive the REAL `CodeValidationCapability` through the REAL
// `CapabilityHost`, so the classification and the supervision policy are the
// engine's, not restated by the test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

const _probePlan =
    'flutter pub get && grep -q isConnectable '
    'packages/butane_dart/test/porcelain_test.dart';

const _baseNote =
    'merge-base validation exited 1 without a named failing test; the base '
    'gave no regression evidence, so the branch result decided';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('acceptance-probe-');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  /// Mounts the lane over the real host with [shell] as the plan seam, and
  /// waits for it to report.
  Future<({Fakes fakes, RecordingExplorationTransport flares})> hostRun(
    RecordingShellRunner shell, {
    required bool gates,
  }) async {
    final fakes = buildFakes();
    final flares = RecordingExplorationTransport();
    final owner = TreeOwner();
    addTearDown(() {
      owner.dispose();
      unawaited(fakes.provider.close());
    });

    owner.mountRoot(
      ProviderScope(
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: flares),
            child: InheritedSeed<Bead>(
              value: bead(
                'tg-1',
              ).copyWith(metadata: const {'validation_plan': _probePlan}),
              child: InheritedSeed<Workspace>(
                value: testWorkspace(
                  'tg-1',
                  workspaceDir: workspace.path,
                  branch: 'grid/tg-1',
                ),
                child: InheritedSeed<CapabilityRegistry>(
                  value: RecordingCapabilityRegistry(clock: DateTime(2026)),
                  child: InheritedSeed<InheritedCircuit>(
                    value: _hostCircuit,
                    child: CapabilityHost(
                      capability: CodeValidationCapability(
                        comparison: ValidationDeltaRunner(
                          gitRunner: CannedGitRunner(),
                          shellRunner: shell,
                          cacheHome: workspace.path,
                          hostIdentity: 'lunar-test-host',
                        ),
                      ),
                      mount: _hostMount,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(
      () => _stepUpdates(fakes).any(
        (metadata) =>
            metadata[MoleculeStepKeys.state] ==
            (gates ? 'gated' : StepState.complete.name),
      ),
      maxPumps: 400,
      ioSlice: const Duration(milliseconds: 5),
    );
    return (fakes: fakes, flares: flares);
  }

  test('base grep probe passes without a harness throttle or gate', () async {
    final shell = RecordingShellRunner()
      // The scratch merge-base checkout (an unpredictable temp path) answers
      // the probe's base failure: grep exited 1, after pub's own chatter.
      ..exitCode = 1
      ..output = 'Resolving dependencies...\nGot dependencies!\n'
      ..resultsByDirectory[workspace.path] = const ShellRunResult(
        exitCode: 0,
        output: 'Resolving dependencies...\nGot dependencies!\n',
      );

    final run = await hostRun(shell, gates: false);

    // Both sides ran the literal probe, the base OUTSIDE the bead workspace.
    expect(shell.calls.map((call) => call.command), [_probePlan, _probePlan]);
    expect(shell.calls.first.workingDirectory, isNot(workspace.path));

    // ONE completed step, graded A off the branch result.
    final completed = _stepUpdates(run.fakes)
        .where(
          (metadata) =>
              metadata[MoleculeStepKeys.state] == StepState.complete.name,
        )
        .toList();
    expect(completed, hasLength(1));
    final result = completed.single;
    String? field(String name) =>
        result[ResultKeys.keyFor(_hostNodePath, name)] as String?;
    expect(field('grade'), 'A');
    expect(field('regressions'), '[]');
    expect(field('baseRc'), '1');
    expect(field('baseNote'), _baseNote);

    // No silent exit was counted, and no human gate was opened.
    expect(run.flares.named(kHarnessThrottledFlare), isEmpty);
    expect(run.fakes.runner.callsFor('create'), isEmpty);
    expect(
      _stepUpdates(
        run.fakes,
      ).where((metadata) => metadata[MoleculeStepKeys.state] == 'gated'),
      isEmpty,
    );

    // The verdict artifact keeps the base's diagnostics; the EFFECTIVE rc is 0.
    final critique = p.join(workspace.path, '.grid', 'critique');
    final artifact =
        jsonDecode(
              File(p.join(critique, 'code-validation.json')).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(artifact['grade'], 'A');
    expect(artifact['baseRc'], 1);
    expect(artifact['baseNote'], _baseNote);
    expect(
      artifact['baseOutputTail'],
      endsWith('Resolving dependencies...\nGot dependencies!'),
    );
    expect(
      File(p.join(critique, 'code-validation.rc')).readAsStringSync().trim(),
      '0',
    );

    // The PR composed from the completed lane result says so on ONE line.
    final body = const PrComposition().bodyOf(
      PrCompositionContext(
        beadId: 'tg-1',
        bead: bead('tg-1'),
        siblings: SiblingView(
          results: {
            'tg-1/land/rebase': const {'outcome': 'clean'},
            'tg-1/land/revalidate': const {'outcome': 'passed'},
            'tg-1/review/code-validation': {
              for (final name in const [
                'grade',
                'regressions',
                'preexisting',
                'baseRc',
                'baseNote',
              ])
                name: field(name)!,
            },
          },
        ),
        description: null,
        commits: const CommitLintReport(),
        titleSource: 'fallback',
      ),
    );
    final lines = body.split('\n').where((line) => line.contains(_baseNote));
    expect(lines, ['- base validation: $_baseNote']);
  });

  test('a completed deterministic branch exit is an invalid result, never '
      'harness silence', () async {
    final shell = RecordingShellRunner()
      ..exitCode = 1
      ..output = 'Got dependencies!\n'
      // The branch probe fails too: grep found nothing, and named no test.
      ..resultsByDirectory[workspace.path] = const ShellRunResult(
        exitCode: 1,
        output: 'Got dependencies!\n',
      );

    final run = await hostRun(shell, gates: true);

    final gateReason = run.fakes.runner
        .callsFor('update')
        .map(callMetadata)
        .firstWhere((metadata) => metadata.containsKey('reason'))['reason'];
    expect(gateReason, contains(StepFailureClass.invalidResult.wire));
    expect(gateReason, contains('validation branch'));
    expect(run.flares.named(kHarnessThrottledFlare), isEmpty);
    expect(
      CapabilityFailureKind.invalidResult,
      isNot(CapabilityFailureKind.noResult),
    );
  });
}

Iterable<Map<String, dynamic>> _stepUpdates(Fakes fakes) => fakes.runner
    .callsFor('update')
    .where((call) => call.contains(_hostStepBeadId))
    .map(callMetadata);

// ── the host probe's mount ───────────────────────────────────────────────────
//
// One step, one circuit, one session: the smallest tree that lets the REAL
// lane report through the REAL host.

const _hostNodePath = 'tg-1/review/$kGatingRubric';
const _hostStepBeadId = 'tgdog-step-code-validation';

const _hostCircuitValue = Circuit(
  id: 'code_review',
  terminalStepId: kGatingRubric,
  steps: [CapabilityStep(stepId: kGatingRubric, capabilityId: kGatingRubric)],
);

const _hostMount = StepMount(
  step: CapabilityStep(stepId: kGatingRubric, capabilityId: kGatingRubric),
  nodePath: _hostNodePath,
  circuit: _hostCircuitValue,
  circuitPath: 'tg-1/review',
  session: SessionHandle('tgdog-s'),
  // A FRESH mount: the declared budget of one is spent by this first report.
  node: NodeCursor(state: StepState.running),
  key: ValueKey('$_hostStepBeadId#0'),
);

final _hostCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _hostStepBeadId]),
  beadIdByNodePath: const {_hostNodePath: _hostStepBeadId},
  cursor: const {},
);
