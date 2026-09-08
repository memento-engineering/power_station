// Track C — FormatCleanCapability (the formatting gate, bead pow-jicn).
//
// The live finding: three codex-built branches in one epoch passed the FULL
// committee (three inference critics plus the deterministic gating lane) and
// were delivered, then failed CI at its FIRST step — the workspace format gate
// — on four unformatted files each. This step asks that one-second question
// over the PINNED scope, before the priced lanes, and refuses the round with
// the offending files NAMED.
//
// Three postures pinned here. A DECIDED dirty verdict is substantive WORK (the
// probe ran and named files) — never a letter grade the route's matrix could
// soften, and never the silent infra exit a breaker counts toward
// `harness.throttled`; an UNDECIDABLE probe stays a typed non-result. And the
// diff is never rewritten on the builder's behalf — every case asserts the
// source bytes survive the check unchanged. The default probe runs the real
// `dart format` over a real temp worktree (the whole point is that this check
// is deterministic); the non-Dart/deleted-path and operational-failure cases
// ride an injected Fake (Fakes, not mocks) so their claims are exact.
import 'dart:async';
import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderScope;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A canned [DartFormatService]: answers a fixed [outcome] and records whether
/// it was asked at all, and with which files.
class _CannedFormatter implements DartFormatService {
  _CannedFormatter(this.outcome);

  final DartFormatOutcome outcome;
  final List<List<String>> calls = [];

  @override
  Future<DartFormatOutcome> check({
    required String workspaceDir,
    required Iterable<String> files,
  }) async {
    calls.add(files.toList());
    return outcome;
  }
}

/// Writes [body] to [rel] under [dir], creating parents; answers the file.
File _plant(Directory dir, String rel, String body) =>
    File(p.join(dir.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(body);

/// Pins a review scope naming [files] as this round's touched paths.
void _pin(Directory dir, List<String> files) {
  final b = StringBuffer('# Pinned review scope: grid/tg-1 vs origin/main\n\n');
  for (final f in files) {
    b
      ..writeln('diff --git a/$f b/$f')
      ..writeln('--- a/$f')
      ..writeln('+++ b/$f');
  }
  File(pinnedDiffPath(dir.path))
    ..createSync(recursive: true)
    ..writeAsStringSync(b.toString());
}

({FakeTreeContext context, StepArgs args}) _ctx(String workspaceDir) => (
  context: FakeTreeContext(
    values: {
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs('tg-1/review/format-clean'),
);

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Source `dart format` WOULD change (loose spacing, no trailing newline).
const _unformatted = 'final   x =   1 ;';

/// The same source, already formatted.
const _formatted = 'final x = 1;\n';

void main() {
  group('Track C — FormatCleanCapability (bead pow-jicn)', () {
    test('one unformatted touched Dart file GATES the round with the file '
        'NAMED — and the file is left byte-identical', () async {
      final dir = _tempDir('format-clean-dirty-');
      const rel = 'packages/example/lib/unformatted.dart';
      final source = _plant(dir, rel, _unformatted);
      _pin(dir, [rel]);

      final c = _ctx(dir.path);
      final outcome = await const FormatCleanCapability().run(
        c.context,
        c.args,
      );

      expect(outcome, isA<Failed>());
      final failed = outcome as Failed;
      expect(
        failed.kind,
        CapabilityFailureKind.work,
        reason:
            'the probe RAN and refused — substantive work, never the '
            'artifact-less exit the breaker reads as harness silence',
      );
      expect(failed.reason, contains(rel));
      expect(failed.reason, contains('dart format would change'));
      expect(
        source.readAsStringSync(),
        _unformatted,
        reason: 'the gate REFUSES the diff; it never silently rewrites it',
      );
    });

    test('a formatted touched Dart file passes through to the critics — and is '
        'left byte-identical', () async {
      final dir = _tempDir('format-clean-ok-');
      const rel = 'packages/example/lib/formatted.dart';
      final source = _plant(dir, rel, _formatted);
      _pin(dir, [rel]);

      final c = _ctx(dir.path);
      final outcome = await const FormatCleanCapability().run(
        c.context,
        c.args,
      );

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'checked': '1'});
      expect(source.readAsStringSync(), _formatted);
    });

    test('every dirty file is named in ONE reason, so the next round fixes '
        'exactly them', () async {
      final dir = _tempDir('format-clean-many-');
      const a = 'packages/example/lib/a.dart';
      const b = 'packages/example/lib/b.dart';
      _plant(dir, a, _unformatted);
      _plant(dir, b, _unformatted);
      _plant(dir, 'packages/example/lib/clean.dart', _formatted);
      _pin(dir, [a, b, 'packages/example/lib/clean.dart']);

      final c = _ctx(dir.path);
      final outcome = await const FormatCleanCapability().run(
        c.context,
        c.args,
      );

      expect(outcome, isA<Failed>());
      final reason = (outcome as Failed).reason;
      expect(reason, contains(a));
      expect(reason, contains(b));
      expect(reason, isNot(contains('clean.dart')));
    });

    test('non-Dart and DELETED Dart paths are not formatter inputs — the probe '
        'is never even asked', () async {
      final dir = _tempDir('format-clean-skip-');
      _plant(dir, 'README.md', 'not dart\n');
      _plant(dir, 'pubspec.yaml', 'name: example\n');
      // `deleted.dart` is named by the diff but does NOT exist in the worktree.
      _pin(dir, [
        'README.md',
        'pubspec.yaml',
        'packages/example/lib/deleted.dart',
      ]);
      final formatter = _CannedFormatter(const DartFormatClean([]));

      final c = _ctx(dir.path);
      final outcome = await FormatCleanCapability(
        formatter: formatter,
      ).run(c.context, c.args);

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'checked': '0'});
      expect(
        formatter.calls,
        [<String>[]],
        reason: 'asked with an EMPTY file list — it spawns no process',
      );
    });

    test('an operational probe failure is a NAMED typed non-result, never a '
        'silent pass', () async {
      final dir = _tempDir('format-clean-probe-fail-');
      const rel = 'packages/example/lib/broken.dart';
      _plant(dir, rel, _formatted);
      _pin(dir, [rel]);
      final formatter = _CannedFormatter(
        const DartFormatProbeFailed(
          file: rel,
          exitCode: 65,
          output: 'Could not format because the source could not be parsed',
        ),
      );

      final c = _ctx(dir.path);
      final outcome = await FormatCleanCapability(
        formatter: formatter,
      ).run(c.context, c.args);

      expect(outcome, isA<Failed>());
      final failed = outcome as Failed;
      expect(failed.kind, CapabilityFailureKind.noResult);
      expect(failed.reason, contains(rel));
      expect(failed.reason, contains('exit 65'));
      expect(failed.reason, contains('could not be parsed'));
    });

    test('a MISSING pinned scope in a real worktree is LOUD, never a silent '
        'pass', () async {
      final dir = _tempDir('format-clean-no-scope-');
      final formatter = _CannedFormatter(const DartFormatClean([]));

      final c = _ctx(dir.path);
      final outcome = await FormatCleanCapability(
        formatter: formatter,
      ).run(c.context, c.args);

      expect(outcome, isA<Failed>());
      final failed = outcome as Failed;
      expect(failed.kind, CapabilityFailureKind.noResult);
      expect(failed.reason, contains('no pinned diff'));
      expect(formatter.calls, isEmpty);
    });

    test('offline/dry-run (no worktree on disk) is a no-op Ok with NO probe — '
        'the PinDiffCapability posture', () async {
      final formatter = _CannedFormatter(const DartFormatClean([]));

      final c = _ctx('/grid/worktrees/does-not-exist/tg-1');
      final outcome = await FormatCleanCapability(
        formatter: formatter,
      ).run(c.context, c.args);

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'checked': '0'});
      expect(formatter.calls, isEmpty);
    });

    test('the HOST parks the dirty verdict at ONE gate on its FIRST attempt, '
        'naming every file and flaring no harness throttle', () async {
      // The live regression (lunar epoch 51): the dirty verdict rode an
      // untyped exit with empty exit output, so the breaker classed it INFRA,
      // counted five silent harness exits, flared `harness.throttled` and made
      // the operator dig the file name out of the flare's `underlying` field.
      // The REAL capability, over the REAL host, must instead spend its ONE
      // deterministic attempt and park a gate that reads.
      final dir = _tempDir('format-clean-host-');
      // Planted and pinned in REVERSE lexical order: the reason is sorted by
      // the probe, not by the order the diff happened to name them.
      const zeta = 'packages/example/lib/zeta.dart';
      const alpha = 'packages/example/lib/alpha.dart';
      final zetaFile = _plant(dir, zeta, _unformatted);
      final alphaFile = _plant(dir, alpha, _unformatted);
      _pin(dir, [zeta, alpha]);

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
              child: InheritedSeed<Workspace>(
                value: testWorkspace(
                  'tg-1',
                  workspaceDir: dir.path,
                  branch: 'grid/tg-1',
                ),
                child: InheritedSeed<CapabilityRegistry>(
                  value: RecordingCapabilityRegistry(clock: DateTime(2026)),
                  child: InheritedSeed<InheritedCircuit>(
                    value: _hostCircuit,
                    child: const CapabilityHost(
                      capability: FormatCleanCapability(),
                      mount: _hostMount,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The real `dart format` runs one process per file below this seam, so
      // the wait yields REAL time (bead `pow-d26`) rather than pumping turns.
      await settle(
        () => fakes.runner.callsFor('create').isNotEmpty,
        maxPumps: 400,
        ioSlice: const Duration(milliseconds: 25),
      );

      final gatedUpdates = fakes.runner
          .callsFor('update')
          .where((call) => call.contains(_hostStepBeadId))
          .map(callMetadata)
          .where((metadata) => metadata[MoleculeStepKeys.state] == 'gated')
          .toList();
      expect(
        gatedUpdates,
        hasLength(1),
        reason: 'ONE deterministic attempt, parked — not a spent breaker',
      );

      expect(fakes.runner.callsFor('create'), hasLength(1));
      expect(
        fakes.runner.callsFor('create').single,
        containsAllInOrder(['--type', 'gate']),
      );
      final gateReason = fakes.runner
          .callsFor('update')
          .map(callMetadata)
          .firstWhere((metadata) => metadata.containsKey('reason'))['reason'];
      expect(
        gateReason,
        contains(StepFailureClass.work.wire),
        reason: 'the operator reads the failure CLASS off the gate itself',
      );
      expect(gateReason, contains('$alpha, $zeta'));

      expect(
        flares.named(kHarnessThrottledFlare),
        isEmpty,
        reason: 'a decided refusal is never counted as a silent infra exit',
      );
      expect(zetaFile.readAsStringSync(), _unformatted);
      expect(alphaFile.readAsStringSync(), _unformatted);
    });
  });
}

// ── the dirty-verdict host probe's mount ─────────────────────────────────────
//
// One step, one circuit, one session: the smallest tree that lets the REAL
// `FormatCleanCapability` report through the REAL `CapabilityHost`, so the
// classification and `FormatCleanCapability.supervisionPolicy` are resolved by
// the engine rather than restated by the test.

const _hostNodePath = 'tg-1/review/$kFormatCleanStep';
const _hostStepBeadId = 'tgdog-step-format-clean';

const _hostCircuitValue = Circuit(
  id: 'code_review',
  terminalStepId: kFormatCleanStep,
  steps: [
    CapabilityStep(stepId: kFormatCleanStep, capabilityId: kFormatCleanStep),
  ],
);

const _hostMount = StepMount(
  step: CapabilityStep(
    stepId: kFormatCleanStep,
    capabilityId: kFormatCleanStep,
  ),
  nodePath: _hostNodePath,
  circuit: _hostCircuitValue,
  circuitPath: 'tg-1/review',
  session: SessionHandle('tgdog-s'),
  // A FRESH mount: no restart is spent yet, so the declared budget of one is
  // exhausted by this first report.
  node: NodeCursor(state: StepState.running),
  key: ValueKey('$_hostStepBeadId#0'),
);

final _hostCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _hostStepBeadId]),
  beadIdByNodePath: const {_hostNodePath: _hostStepBeadId},
  cursor: const {},
);
