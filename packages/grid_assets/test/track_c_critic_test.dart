// Track C2 — the critic capability (one rubric, in isolation).
//
// `code-validation` is the GATING lane: it runs the bead's OWN Validation Plan
// via `sh`, capturing the plan's exit code so the step always `complete`s and
// the grade (A iff zero, else F) rides `result()`. The three LLM lanes ride the
// resolved agent harness (claude by default — same argv shape) with ONLY their
// own rubric (anti-anchoring) and write a verdict JSON `result()` parses. Zero
// I/O — no real `claude`/`sh`: the spawn config is inspected directly and
// `result()` reads files a test writes into a temp dir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderScope;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The critic's (ambient tree, per-step args) pair — the context rip-out shape:
/// the work Bead + Workspace ride the tree; the rubric rides the step params.
/// [round] is the respec LEDGER's own `round` (A27(3), re-sourced into the
/// verdict stamp by A27(7)(a)'s follow-up, bead `pow-96s`) — the round the
/// critic stamps and `result()` verifies. A non-zero round writes a REAL
/// ledger into [workspaceDir] (callers pass a real temp dir for that); round 0
/// is the no-ledger default, which also holds for the synthetic '/w/tg-1' dir
/// (`roundOf` reads 0 off a worktree that does not exist).
({FakeTreeContext context, StepArgs args}) _ctx({
  required String rubric,
  String workspaceDir = '/w/tg-1',
  Bead? beadOverride,
  String? nodePath,
  int round = 0,
  ExplorationTransport? transport,
}) {
  final path = nodePath ?? 'tg-1/review/$rubric';
  return (
    context: FakeTreeContext(
      values: {
        Bead: beadOverride ?? bead('tg-1'),
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: workspaceDir,
          branch: 'grid/tg-1',
        ),
        if (transport != null)
          ServiceBundle: ServiceBundle(transport: transport),
      },
    ),
    args: stepArgs(path, params: {'rubric': rubric, 'grid.round': '$round'}),
  );
}

/// Plants a critic INCARNATION MARKER whose mtime IS [at] — the spawn instant
/// [restampVerdictRound] proves freshness against. Pinned explicitly so the
/// comparison never races the wall clock.
void _plantIncarnation(String workspaceDir, String rubric, DateTime at) {
  File(criticIncarnationPath(workspaceDir, rubric))
    ..createSync(recursive: true)
    ..writeAsStringSync(at.toIso8601String())
    ..setLastModifiedSync(at);
}

/// Plants a verdict at [path] carrying [nodePath] and (when non-null) [round],
/// with its mtime pinned to [modifiedAt].
void _plantVerdictAt(
  String path, {
  required String nodePath,
  required DateTime modifiedAt,
  Object? round,
  String grade = 'A',
}) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'grade': grade,
        'rationale': 'the lane graded it',
        'nodePath': nodePath,
        if (round != null) kVerdictRoundKey: round,
      }),
    )
    ..setLastModifiedSync(modifiedAt);
}

Map<String, dynamic> _readVerdictJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Future<List<AllocationReport>> _runCriticAllocation({
  required Directory dir,
  required String rubric,
  required String nodePath,
  int round = 0,
  CriticCapability capability = const CriticCapability(),
}) async {
  final c = _ctx(
    rubric: rubric,
    workspaceDir: dir.path,
    nodePath: nodePath,
    round: round,
  );
  final provider = FakeRuntimeProvider();
  final reports = <AllocationReport>[];
  final allocation = ProcessAllocation(
    capability,
    AllocationContext(
      treeContext: c.context,
      args: c.args,
      transport: provider,
      address: AllocationAddress('sess-1', nodePath),
      env: const {},
      sink: reports.add,
    ),
  );
  addTearDown(() async {
    await allocation.dispose();
    await provider.close();
  });
  await allocation.startOrAdopt();
  allocation.deliverEventForTest(Exited(name: 'sess-1/$nodePath', exitCode: 0));
  for (var attempt = 0; reports.isEmpty && attempt < 100; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return reports;
}

final class _UnexpectedReadFailure implements Exception {
  const _UnexpectedReadFailure(this.message);

  final String message;

  @override
  String toString() => 'unexpected verdict read failure: $message';
}

/// The detail prefix every [_UnexpectedReadFailure] receipt leads with.
const _readFailureDetail = 'unexpected verdict read failure: ';

/// A reader whose failure detail ALONE overruns the engine's reason bound, so
/// the receipt can only stay inside [kMaxReasonChars] by truncating the detail
/// — which is exactly what proves the rubric and path are written FIRST.
String _throwLongUnexpectedRead(File _) =>
    throw _UnexpectedReadFailure('torn read seam ${'x' * kMaxReasonChars}');

/// The typed non-result the strict decoder REPORTS for a malformed or
/// incomplete artifact: kind `invalidResult` (a broken completion contract,
/// never a substantive F), and a bounded receipt naming the lane and the file
/// before the parser's own detail.
Matcher _invalidVerdictReport({
  required String rubric,
  required String path,
  required String detail,
}) => isA<AllocationFailed>()
    .having(
      (failure) => failure.kind,
      'kind',
      CapabilityFailureKind.invalidResult,
    )
    .having(
      (failure) => failure.reason,
      'receipt',
      allOf(contains('rubric "$rubric"'), contains(path), contains(detail)),
    )
    .having(
      (failure) => failure.reason.length,
      'bounded receipt length',
      lessThanOrEqualTo(kMaxReasonChars),
    );

/// [_invalidVerdictReport]'s THROWN twin, for the hooks a test drives directly
/// instead of through an allocation.
Matcher _invalidVerdictThrow({
  required String rubric,
  required String path,
  required String detail,
}) => isA<CapabilityFailure>()
    .having(
      (failure) => failure.kind,
      'kind',
      CapabilityFailureKind.invalidResult,
    )
    .having(
      (failure) => failure.reason,
      'receipt',
      allOf(contains('rubric "$rubric"'), contains(path), contains(detail)),
    )
    .having(
      (failure) => failure.reason.length,
      'bounded receipt length',
      lessThanOrEqualTo(kMaxReasonChars),
    );

void main() {
  group('critic completion artifact durability', () {
    test('declares the artifact-durability contract', () {
      expect(
        const CriticCapability().completionContract,
        CompletionContract.artifactDurability,
      );
    });

    test(
      'probes missing, fresh, stale, malformed, and stray verdicts',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-probe-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'coherence';
        const nodePath = 'tg-1/review/coherence';
        final c = _ctx(
          rubric: rubric,
          workspaceDir: dir.path,
          nodePath: nodePath,
          round: 1,
        );
        const cap = CriticCapability();
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.present,
        );
        final verdict = File('${dir.path}/.grid/critique/$rubric.json')
          ..createSync(recursive: true);
        verdict.writeAsStringSync(
          jsonEncode({
            'grade': 'A',
            'rationale': 'stale',
            'nodePath': nodePath,
            'round': 0,
          }),
        );
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.present,
        );
        verdict.writeAsStringSync(
          jsonEncode({
            'grade': 'A',
            'rationale': 'fresh canonical',
            'nodePath': nodePath,
            'round': 1,
          }),
        );
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.clear,
        );
        verdict.writeAsStringSync('not json');
        // The probe no longer FLATTENS a broken completion contract into the
        // fail-closed `probeError`: it reports the kind the decoder named.
        await expectLater(
          cap.probeCompletionArtifact(c.context, c.args),
          throwsA(
            _invalidVerdictThrow(
              rubric: rubric,
              path: verdict.path,
              detail: 'Unexpected character',
            ),
          ),
        );
        verdict.deleteSync();
        File('${dir.path}/pkg/.grid/critique/$rubric.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'grade': 'B',
              'rationale': 'fresh stray',
              'nodePath': nodePath,
              'round': 1,
            }),
          );
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.clear,
        );
      },
    );

    test('probes deterministic gating rc absence and presence', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-probe-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(rubric: kGatingRubric, workspaceDir: dir.path);
      const cap = CriticCapability();
      expect(
        await cap.probeCompletionArtifact(c.context, c.args),
        GateOutcome.present,
      );
      File('${dir.path}/.grid/critique/$kGatingRubric.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0');
      expect(
        await cap.probeCompletionArtifact(c.context, c.args),
        GateOutcome.clear,
      );
    });
  });

  group('Track C2 — code-validation (the GATING lane)', () {
    test(
      'spawns `sh -c` running the bead\'s Validation Plan, capturing its rc',
      () {
        final withPlan = bead('tg-1').copyWith(
          metadata: const {'validation_plan': 'melos analyze && melos test'},
        );
        final c = _ctx(rubric: kGatingRubric, beadOverride: withPlan);
        final cfg = const CriticCapability().spawn(c.context, c.args);
        expect(cfg.command, 'sh');
        expect(cfg.args[0], '-c');
        expect(
          cfg.args[1],
          'mkdir -p .grid/critique; ( melos analyze && melos test ) ; '
          r'echo $? > .grid/critique/code-validation.rc',
        );
        expect(cfg.args[1], isNot(contains('command -v')));
        // The rc is captured to the critique dir so result() can read the grade.
        expect(cfg.args[1], contains('.grid/critique/code-validation.rc'));
        expect(cfg.args[1], contains(r'echo $?'));
        expect(cfg.workDir, '/w/tg-1');
        expect(cfg.lifecycle, Lifecycle.oneTurn);
        // tg-uad follow-through: the gating lane is minutes-scale by
        // definition — it must NOT ride the runtime provider's 2-hour
        // default watchdog.
        expect(cfg.deadline, kGatingDeadline);
      },
    );

    test('a plan-less bead defaults to an explicit `false` (never silently '
        'passes)', () {
      final c = _ctx(rubric: kGatingRubric);
      final cfg = const CriticCapability().spawn(c.context, c.args);
      // `( false )` ⇒ a non-zero rc ⇒ result() grades F.
      expect(cfg.args[1], contains('( false )'));
    });

    test('ANY terminal exit completes the gating step (the grade rides '
        'result()); a death fails', () {
      const cap = CriticCapability();
      const name = 'tgdog-s/tg-1/review/code-validation';
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 0)),
        StepSignal.complete,
      );
      // A non-zero plan still COMPLETES (the route decides via the F grade) —
      // not `failed`, so there is no retry storm on a deterministic failure.
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 1)),
        StepSignal.complete,
      );
      expect(cap.interpretEvent(const Died(name: name)), StepSignal.failed);
    });

    test('result() grades A on rc 0, F on a non-zero rc, F when the rc is '
        'absent (fail-closed)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();

      final c = _ctx(rubric: kGatingRubric, workspaceDir: dir.path);

      // Absent rc ⇒ fail-closed F, named transport + rationale (gate-integrity
      // #3 — a fail-closed default must never be silently unexplained).
      expect(await cap.result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'round': '0',
        'rationale': 'no validation-plan rc file — fail-closed default',
      });

      // rc "0" ⇒ A.
      final rcFile = File('${dir.path}/.grid/critique/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');
      expect(await cap.result(c.context, c.args), {
        'grade': 'A',
        'transport': 'file',
        'round': '0',
      });

      // rc non-zero ⇒ F.
      rcFile.writeAsStringSync('1\n');
      expect(await cap.result(c.context, c.args), {
        'grade': 'F',
        'transport': 'file',
        'round': '0',
      });
    });

    test('result() adds candidate commands only for rc 127', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-127-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final withPlan = bead(
        'tg-1',
      ).copyWith(metadata: const {'validation_plan': 'rg needle'});
      final c = _ctx(
        rubric: kGatingRubric,
        workspaceDir: dir.path,
        beadOverride: withPlan,
      );
      File('${dir.path}/.grid/critique/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('127\n');

      expect(await const CriticCapability().result(c.context, c.args), {
        'grade': 'F',
        'transport': 'file',
        'round': '0',
        'rationale': 'exit 127 — candidate missing commands: rg',
      });
    });
  });

  group('Track C2 — the LLM critics (one rubric each, isolated)', () {
    test('spawns claude WRAPPED for usage capture, carrying only its own rubric '
        '(FT-2)', () {
      final c = _ctx(rubric: 'spec-adherence');
      final cfg = const CriticCapability().spawn(c.context, c.args);
      // The LLM lane rides the SAME wrapped claude invocation as the agent: the
      // `--output-format json` envelope redirects to the per-step telemetry file.
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(
        cfg.args[1],
        contains('.grid/telemetry/tg-1_review_spec-adherence.usage.json'),
      );
      expect(cfg.args[2], 'grid-claude');
      expect(cfg.args[3], 'claude');
      expect(cfg.args[4], '--dangerously-skip-permissions');
      // A critic spawns in the GRADE role (bead `pow-edp`): absent a station or
      // bead override it grades on the MID tier (sonnet) while the build rides
      // the FRONTIER tier (opus) — the split this argv is the proof of.
      expect(cfg.args[5], '--model');
      expect(cfg.args[6], kMidModelDefault);
      expect(cfg.args[7], '--output-format');
      expect(cfg.args[8], 'json');
      expect(cfg.args[9], '-p');
      // The prompt (its own rubric only) rides as the final positional.
      expect(cfg.args.last, contains('spec-adherence'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
      // The LLM lanes legitimately ride the runtime provider's long default —
      // only the deterministic gating lane gets the minutes-scale deadline.
      expect(cfg.deadline, isNull);
    });

    test('a clean exit completes; a non-zero exit / death fails', () {
      const cap = CriticCapability();
      const name = 'tgdog-s/tg-1/review/spec-adherence';
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 0)),
        StepSignal.complete,
      );
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 2)),
        StepSignal.failed,
      );
      expect(cap.interpretEvent(const Died(name: name)), StepSignal.failed);
    });

    test('the prompt names ONLY its own rubric (anti-anchoring)', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      );
      expect(prompt, contains('spec-adherence'));
      // The other lanes' concerns must NOT leak into this critic's prompt.
      expect(prompt, isNot(contains('regression-risk')));
      expect(prompt, isNot(contains('test-coverage')));
      expect(prompt, isNot(contains('code-validation')));
      // It carries the verdict-file instruction for its own rubric only, as the
      // workspace-derived ABSOLUTE path (gate-integrity #4 — cwd-invariant).
      expect(prompt, contains('/w/tg-1/.grid/critique/spec-adherence.json'));
    });

    test('the prompt carries a nodePath freshness stamp (gate-integrity #3) '
        'the critic must copy verbatim into its verdict', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1#r3/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      );
      expect(prompt, contains('"nodePath":"tg-1#r3/review/spec-adherence"'));
      expect(prompt, contains('copy them byte-for-byte'));
    });

    test('the prompt stamps the ROUND beside the nodePath (A15(5) alt-A)', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 2,
      );
      expect(
        prompt,
        contains('"nodePath":"tg-1/review/spec-adherence","round":2}'),
      );
      expect(prompt, contains('copy them byte-for-byte'));
    });

    test('spawn reads the session circuit round from step params', () {
      final dir = Directory.systemTemp.createTempSync('critic-spawn-round-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(
        rubric: 'regression-risk',
        workspaceDir: dir.path,
        round: 2,
      );
      final cfg = const CriticCapability().spawn(c.context, c.args);
      expect(cfg.args.last, contains('"round":2}'));
    });

    group('verdictRound', () {
      test('reads the reserved session circuit round', () {
        final c = _ctx(rubric: 'spec-adherence', round: 2);
        expect(verdictRound(c.args), 2);
      });

      test('missing input falls back loudly to zero', () {
        final messages = <String>[];
        expect(
          verdictRound(
            stepArgs(
              'tg-1/review/coherence',
              params: const {'rubric': 'coherence'},
            ),
            diagnostic: messages.add,
          ),
          0,
        );
        expect(messages.single, contains("'grid.round'"));
      });
    });

    test('the prompt pins the review scope to the pinned diff (bead pow-6wo) — '
        'the critic reviews the bead branch delta, not the worktree', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      );
      // The critic is pointed at the pinned-diff file as its EXCLUSIVE scope
      // (the ABSOLUTE path PinDiffCapability wrote it to).
      expect(prompt, contains('/w/tg-1/.grid/critique/pinned.diff'));
      expect(prompt, contains('Review scope'));
      expect(prompt, contains('git diff origin/<base>...HEAD'));
      // The load-bearing instruction: pre-existing / already-in-mainline code
      // outside the diff is OUT OF SCOPE (the live-finding fix).
      expect(prompt, contains('OUT OF SCOPE'));
      expect(prompt, contains('already in mainline'));
    });

    test('the prompt carries the full bead', () {
      final rich = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
        design: 'A lossy inter-station gossip bus.',
      );
      final prompt = const CriticCapability().buildCriticPrompt(
        rich,
        'test-coverage',
        'tg-1/review/test-coverage',
        '/w/tg-1',
        round: 0,
      );
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains('Connect The Studio to The Dashboard.'));
      expect(prompt, contains('A lossy inter-station gossip bus.'));
    });

    test(
      'result() parses a written verdict JSON into a grade + rationale',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-llm-');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/.grid/critique/regression-risk.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'rubric': 'regression-risk',
              'version': 1,
              'grade': 'b',
              'rationale': 'a narrow blast radius',
              'nodePath': 'tg-1/review/regression-risk',
              'round': 0,
            }),
          );
        final c = _ctx(rubric: 'regression-risk', workspaceDir: dir.path);
        final out = await const CriticCapability().result(c.context, c.args);
        expect(out, {
          'grade': 'B',
          'transport': 'file',
          'round': '0',
          'rationale': 'a narrow blast radius',
        });
      },
    );

    test(
      'stdout-only verdict is persisted before allocation completion',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'critic-probe-recovery-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'test-coverage';
        const nodePath = 'tg-1/review/test-coverage';
        File('${dir.path}/${usageReportPath(nodePath)}')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'result': '{"grade":"B","rationale":"real stdout verdict"}',
            }),
          );

        final reports = await _runCriticAllocation(
          dir: dir,
          rubric: rubric,
          nodePath: nodePath,
        );

        expect(reports.whereType<AllocationFailed>(), isEmpty);
        expect(reports.whereType<AllocationEscalated>(), isEmpty);
        expect(reports.whereType<AllocationCompleted>().single.payload, {
          'grade': 'B',
          'transport': 'file',
          'round': '0',
          'rationale': 'real stdout verdict [from result envelope]',
        });
        final persisted =
            jsonDecode(
                  File(
                    '${dir.path}/.grid/critique/$rubric.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(persisted, {
          'grade': 'B',
          'rationale': 'real stdout verdict [from result envelope]',
          'nodePath': nodePath,
          'round': 0,
        });
      },
    );

    test(
      'invalid critic JSON fails the allocation loudly without a grade',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-llm-bad-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const cap = CriticCapability();
        final c = _ctx(rubric: 'test-coverage', workspaceDir: dir.path);
        // A missing verdict never reaches result after the durability probe.
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.present,
        );
        // A present malformed artifact is a lane failure, never a fallback.
        final verdict = File('${dir.path}/.grid/critique/test-coverage.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('not json');
        await expectLater(
          cap.result(c.context, c.args),
          throwsA(
            _invalidVerdictThrow(
              rubric: 'test-coverage',
              path: verdict.path,
              detail: 'Unexpected character',
            ),
          ),
        );
      },
    );

    test(
      'result() fail-closes to F on a STALE verdict — a nodePath that '
      'does not match this round (gate-integrity #3: a rework round reuses '
      'the SAME workspace, so a prior round\'s file otherwise survives)',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-llm-stale-');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/.grid/critique/regression-risk.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'grade': 'A',
              'rationale': 'a stale round-1 verdict',
              'nodePath': 'tg-1#r1/review/regression-risk',
              // Round-FRESH: only the nodePath is foreign, so this proves A4's fence
              // still rejects ON ITS OWN, independent of the round check.
              'round': 0,
            }),
          );
        final c = _ctx(
          rubric: 'regression-risk',
          workspaceDir: dir.path,
          nodePath: 'tg-1#r2/review/regression-risk',
        );
        expect(
          await const CriticCapability().probeCompletionArtifact(
            c.context,
            c.args,
          ),
          GateOutcome.present,
        );
      },
    );

    test('a STALE round verdict under a BYTE-IDENTICAL nodePath is REJECTED — '
        'the Rewind case A4\'s stamp cannot see (A15(5))', () async {
      final dir = Directory.systemTemp.createTempSync('critic-stale-round-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/review/regression-risk';
      File('${dir.path}/.grid/critique/regression-risk.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'grade': 'A',
            'rationale': 'round 0 approved it',
            'nodePath':
                nodePath, // IDENTICAL — a Rewind does not move the path.
            'round': 0,
          }),
        );
      final c = _ctx(
        rubric: 'regression-risk',
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
      );
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });

    test('a parseable verdict missing a freshness stamp fails the lane with '
        'the honest persisted reason and no grade payload', () async {
      final dir = Directory.systemTemp.createTempSync('critic-unstamped-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      const nodePath = 'tg-1/review/test-coverage';
      File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': rubric,
            'version': 1,
            'grade': 'A',
            'rationale': 'the tests cover the new path',
          }),
        );
      final reports = await _runCriticAllocation(
        dir: dir,
        rubric: rubric,
        nodePath: nodePath,
      );

      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      final failed = reports.whereType<AllocationFailed>().single;
      expect(
        failed,
        _invalidVerdictReport(
          rubric: rubric,
          path: '${dir.path}/.grid/critique/$rubric.json',
          detail: 'nodePath must be a non-empty string',
        ),
      );
      expect(failed.reason, isNot(contains('Bad state:')));
    });

    test('a non-numeric round stamp fails loudly', () async {
      final dir = Directory.systemTemp.createTempSync('critic-badround-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/review/test-coverage';
      File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'grade': 'A',
            'rationale': 'bad wire stamp',
            'nodePath': nodePath,
            'round': 'not-a-number',
          }),
        );
      final c = _ctx(
        rubric: 'test-coverage',
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      await expectLater(
        const CriticCapability().result(c.context, c.args),
        throwsA(
          _invalidVerdictThrow(
            rubric: 'test-coverage',
            path: '${dir.path}/.grid/critique/test-coverage.json',
            detail: 'round must be an integer',
          ),
        ),
      );
    });

    test(
      'a round-fresh verdict at round 2 still parses (transport file)',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-fresh-round-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const nodePath = 'tg-1/review/regression-risk';
        File('${dir.path}/.grid/critique/regression-risk.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'grade': 'B',
              'rationale': 'a narrow blast radius',
              'nodePath': nodePath,
              'round': 2,
            }),
          );
        final c = _ctx(
          rubric: 'regression-risk',
          workspaceDir: dir.path,
          nodePath: nodePath,
          round: 2,
        );
        expect(await const CriticCapability().result(c.context, c.args), {
          'grade': 'B',
          'transport': 'file',
          'round': '2',
          'rationale': 'a narrow blast radius',
        });
      },
    );

    test('required verdict fields are loud', () async {
      final dir = Directory.systemTemp.createTempSync('critic-required-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/review/test-coverage';
      final verdict = File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true);
      final c = _ctx(
        rubric: 'test-coverage',
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      for (final field in ['grade', 'rationale', 'round', 'nodePath']) {
        final payload = <String, Object>{
          'grade': 'B',
          'rationale': 'complete rationale',
          'round': 0,
          'nodePath': nodePath,
        }..remove(field);
        verdict.writeAsStringSync(jsonEncode(payload));
        await expectLater(
          const CriticCapability().result(c.context, c.args),
          throwsA(
            _invalidVerdictThrow(
              rubric: 'test-coverage',
              path: verdict.path,
              detail: field,
            ),
          ),
        );
      }
    });

    test(
      'an UNREADABLE fresh artifact is a typed bounded non-result, not a grade',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-read-failure-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'regression-risk';
        const nodePath = 'tg-1/review/regression-risk';
        // A verdict the NORMAL probe clears (it reads with the real reader), so
        // the injected torn read is what the result hook — and only the result
        // hook — trips over.
        final verdict = File('${dir.path}/.grid/critique/$rubric.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'grade': 'B',
              'rationale': 'a narrow blast radius',
              'nodePath': nodePath,
              'round': 0,
            }),
          );
        final reports = await _runCriticAllocation(
          dir: dir,
          rubric: rubric,
          nodePath: nodePath,
          capability: const CriticCapability(
            verdictTextReader: _throwLongUnexpectedRead,
          ),
        );

        expect(reports.whereType<AllocationCompleted>(), isEmpty);
        expect(
          reports.whereType<AllocationFailed>().single,
          _invalidVerdictReport(
            rubric: rubric,
            path: verdict.path,
            detail: _readFailureDetail,
          ),
        );
        expect(
          reports.whereType<AllocationFailed>().single.reason.length,
          kMaxReasonChars,
          reason:
              'the detail alone overruns the bound, so the receipt is cut — '
              'and the rubric/path it leads with survive the cut',
        );
      },
    );

    test('incident fixtures are refused loudly', () async {
      for (final incident in [
        (
          fixture: 'tg-nlwo-regression-risk.json',
          rubric: 'regression-risk',
          nodePath: 'tg-nlwo/code_review/regression-risk',
        ),
        (
          fixture: 'pow-1rn.5-acceptance-testability.json',
          rubric: 'acceptance-testability',
          nodePath: 'pow-1rn.5/spec_review/acceptance-testability',
        ),
      ]) {
        final dir = Directory.systemTemp.createTempSync('critic-incident-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final verdict = File(
          '${dir.path}/.grid/critique/${incident.rubric}.json',
        )..createSync(recursive: true);
        File(
          'test/fixtures/critique/${incident.fixture}',
        ).copySync(verdict.path);
        final c = _ctx(
          rubric: incident.rubric,
          workspaceDir: dir.path,
          nodePath: incident.nodePath,
          round: 1,
        );
        await expectLater(
          const CriticCapability().result(c.context, c.args),
          throwsA(
            _invalidVerdictThrow(
              rubric: incident.rubric,
              path: verdict.path,
              detail: 'escape',
            ),
          ),
        );
      }
    });

    test('repair prompt carries the bounded invalid-result receipt once', () {
      final dir = Directory.systemTemp.createTempSync('critic-reask-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      const nodePath = 'tg-1/review/regression-risk';
      final verdict = File('${dir.path}/.grid/critique/$rubric.json');
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      const capability = CriticCapability(
        verdictTextReader: _throwLongUnexpectedRead,
      );
      final firstPrompt = capability.spawn(c.context, c.args).args.join(' ');
      expect(firstPrompt, isNot(contains('## Verdict contract repair')));

      verdict
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final restartedPrompt = capability
          .spawn(c.context, c.args)
          .args
          .join(' ');
      expect(restartedPrompt.split('## Verdict contract repair').length - 1, 1);

      // The prompt carries the SAME receipt the engine was handed — one
      // section, the rubric, the canonical path, the parser detail, bounded.
      final receipt = restartedPrompt
          .split('The previous artifact was refused: ')
          .last
          .split('\n')
          .first;
      expect(receipt, contains('rubric "$rubric"'));
      expect(receipt, contains(verdict.path));
      expect(receipt, contains(_readFailureDetail));
      expect(receipt.length, lessThanOrEqualTo(kMaxReasonChars));
      expect(
        receipt,
        isNot(matches(RegExp(r'\bgrade of [A-F]\b'))),
        reason: 'the repair receipt reports the CONTRACT breach, never a grade',
      );
    });

    test('invalid verdict shapes are typed bounded non-results', () async {
      const rubric = 'regression-risk';
      const nodePath = 'tg-1/review/regression-risk';
      const valid = {
        'grade': 'B',
        'rationale': 'a narrow blast radius',
        'nodePath': nodePath,
        'round': 0,
      };
      Map<String, Object> without(String field) =>
          Map<String, Object>.of(valid)..remove(field);
      Map<String, Object> with_(String field, Object value) =>
          Map<String, Object>.of(valid)..[field] = value;

      final rows =
          <({String shape, String body, String detail, CriticCapability cap})>[
            (
              shape: 'malformed JSON',
              body: 'not json',
              detail: 'Unexpected character',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a non-object (list) root',
              body: '[]',
              detail: 'root must be a JSON object',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a missing grade',
              body: jsonEncode(without('grade')),
              detail: 'grade must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a blank grade',
              body: jsonEncode(with_('grade', '   ')),
              detail: 'grade must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'an off-ladder grade',
              body: jsonEncode(with_('grade', 'G')),
              detail: 'grade must be one of A–F',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a missing rationale',
              body: jsonEncode(without('rationale')),
              detail: 'rationale must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a blank rationale',
              body: jsonEncode(with_('rationale', '  ')),
              detail: 'rationale must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'an owner off the closed vocabulary',
              body: jsonEncode(with_(kVerdictOwnerKey, 'nobody')),
              detail:
                  '$kVerdictOwnerKey must be one of ${kVerdictOwners.join('|')}',
              cap: const CriticCapability(),
            ),
            (
              // The owner column is a per-FAMILY switch (A37): only the spec
              // critic is held to it, and only on an actionable D/E.
              shape: 'a D naming no owner, under the spec family',
              body: jsonEncode(with_('grade', 'D')),
              detail: 'a grade of D REQUIRES',
              cap: const SpecCriticCapability(),
            ),
            (
              shape: 'a missing nodePath',
              body: jsonEncode(without('nodePath')),
              detail: 'nodePath must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a blank nodePath',
              body: jsonEncode(with_('nodePath', '   ')),
              detail: 'nodePath must be a non-empty string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a missing round',
              body: jsonEncode(without('round')),
              detail: 'round must be an integer or integer-readable string',
              cap: const CriticCapability(),
            ),
            (
              shape: 'a non-integer round',
              body: jsonEncode(with_('round', 'not-a-number')),
              detail: 'round must be an integer or integer-readable string',
              cap: const CriticCapability(),
            ),
          ];

      for (final row in rows) {
        final dir = Directory.systemTemp.createTempSync('critic-invalid-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final verdict = File('${dir.path}/.grid/critique/$rubric.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(row.body);

        final reports = await _runCriticAllocation(
          dir: dir,
          rubric: rubric,
          nodePath: nodePath,
          capability: row.cap,
        );

        expect(
          reports.whereType<AllocationCompleted>(),
          isEmpty,
          reason: '${row.shape} must never contribute a grade',
        );
        expect(
          reports.whereType<AllocationFailed>().single,
          _invalidVerdictReport(
            rubric: rubric,
            path: verdict.path,
            detail: row.detail,
          ),
          reason: row.shape,
        );
      }
    });

    test('valid A through F verdicts complete unchanged', () async {
      const rubric = 'regression-risk';
      const nodePath = 'tg-1/review/regression-risk';
      for (final grade in ['A', 'B', 'C', 'D', 'E', 'F']) {
        final dir = Directory.systemTemp.createTempSync('critic-grade-');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/.grid/critique/$rubric.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'grade': grade,
              'rationale': 'the lane graded it $grade',
              'nodePath': nodePath,
              'round': 0,
            }),
          );

        final reports = await _runCriticAllocation(
          dir: dir,
          rubric: rubric,
          nodePath: nodePath,
        );

        // F is a REAL verdict — the substantive negative result the whole
        // typed-non-result seam exists NOT to swallow.
        final completed = reports.whereType<AllocationCompleted>().single;
        expect(reports.whereType<AllocationFailed>(), isEmpty);
        expect(completed.payload!['grade'], grade);
        expect(completed.payload!['transport'], 'file');
      }
    });

    test('critic invalid-result policy permits one repair retry', () {
      final policy = const CriticCapability().supervisionPolicy(
        stepArgs(
          'tg-1/review/regression-risk',
          params: const {'rubric': 'regression-risk'},
        ),
      );
      expect(
        policy.policyFor(CapabilityFailureKind.invalidResult),
        const RetryPolicy(
          maxRestarts: 2,
          backoff: Backoff.standard,
          onExhaustion: ExhaustionBehavior.parkAtGate,
        ),
      );
      // Only the broken CONTRACT is narrowed: a real F and a missing artifact
      // keep the circuit's own budget.
      expect(policy.policyFor(CapabilityFailureKind.work), const RetryPolicy());
      expect(
        policy.policyFor(CapabilityFailureKind.noResult),
        const RetryPolicy(),
      );
      expect(Backoff.standard.delayFor(1), const Duration(seconds: 1));
    });

    test('an injected rubric source replaces the inline placeholder', () {
      final cap = CriticCapability(rubrics: (id) => 'CUSTOM BANDS for $id');
      final prompt = cap.buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      );
      expect(prompt, contains('CUSTOM BANDS for spec-adherence'));
      expect(prompt, isNot(contains('Packaged-AI-Asset loader')));
    });

    test('(tg-291 d) the file-write instruction is the LAST thing in the '
        'prompt, imperative, exact ABSOLUTE path, and required even if a '
        'verdict appears in prose', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      );
      // The path is the workspace-derived ABSOLUTE canonical path
      // (gate-integrity #4 — cwd-invariant), not a workspace-relative one.
      expect(
        prompt.trimRight(),
        endsWith('never reuse one writer\'s temporary path in another writer.'),
      );
      expect(
        prompt,
        contains('mktemp "/w/tg-1/.grid/critique/.spec-adherence.json.XXXXXX"'),
      );
      expect(prompt, contains('mv -f -- "\$verdict_tmp"'));
      expect(prompt, contains('Do NOT write JSON directly'));
    });
  });

  group('Track C2 — the LLM critic result() merges usage telemetry (FT-2)', () {
    void writeVerdict(String workspaceDir, String rubric, String content) {
      File('$workspaceDir/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    void writeUsage(String workspaceDir, String rubric, String content) {
      File('$workspaceDir/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test(
      'MERGES tokens/cost into the grade + rationale (collision-safe keys)',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-usage-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'regression-risk';
        writeVerdict(
          dir.path,
          rubric,
          jsonEncode({
            'grade': 'B',
            'rationale': 'narrow',
            'nodePath': 'tg-1/review/$rubric',
            'round': 0,
          }),
        );
        writeUsage(
          dir.path,
          rubric,
          '{"total_cost_usd": 0.02, '
          '"usage": {"input_tokens": 9, "output_tokens": 8}, '
          '"modelUsage": {"claude-sonnet-5": {}}}',
        );
        final c = _ctx(rubric: rubric, workspaceDir: dir.path);
        final out = await const CriticCapability().result(c.context, c.args);
        // The critic graded on SONNET — the ledger-side proof of the role split
        // (bead `pow-edp`): the argv says what we asked for, `modelUsage` says
        // what ran.
        expect(out, {
          'grade': 'B',
          'transport': 'file',
          'round': '0',
          'rationale': 'narrow',
          'tokensIn': '9',
          'tokensOut': '8',
          'costUsd': '0.02',
          'costSource': 'reported',
          'model': 'claude-sonnet-5',
        });
      },
    );

    test(
      'a malformed verdict fails before usage can contribute a grade',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'critic-usage-badverdict-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'test-coverage';
        writeVerdict(dir.path, rubric, 'not json');
        writeUsage(dir.path, rubric, '{"num_turns": 2}');
        final c = _ctx(rubric: rubric, workspaceDir: dir.path);
        await expectLater(
          const CriticCapability().result(c.context, c.args),
          throwsA(
            _invalidVerdictThrow(
              rubric: rubric,
              path: '${dir.path}/.grid/critique/$rubric.json',
              detail: 'Unexpected character',
            ),
          ),
        );
      },
    );

    test(
      'a MALFORMED usage file never fails the step — just the grade',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'critic-usage-badusage-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'spec-adherence';
        writeVerdict(
          dir.path,
          rubric,
          jsonEncode({
            'grade': 'A',
            'rationale': 'the verdict remains valid',
            'nodePath': 'tg-1/review/$rubric',
            'round': 0,
          }),
        );
        writeUsage(dir.path, rubric, 'garbage not json');
        final c = _ctx(rubric: rubric, workspaceDir: dir.path);
        final out = await const CriticCapability().result(c.context, c.args);
        expect(out, {
          'grade': 'A',
          'transport': 'file',
          'round': '0',
          'rationale': 'the verdict remains valid',
        });
      },
    );

    test('the GATING lane never merges usage (it is not an agent)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      // A passing rc + a STRAY telemetry file at the gating nodePath: the gating
      // result() must ignore it (the gating lane spawns `sh`, never the harness).
      File('${dir.path}/.grid/critique/$kGatingRubric.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');
      writeUsage(dir.path, kGatingRubric, '{"usage": {"input_tokens": 5}}');
      final c = _ctx(rubric: kGatingRubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'A',
        'transport': 'file',
        'round': '0',
      }, reason: 'no usage merge on the gating lane');
    });
  });

  group('stdout verdict recovery in the durability probe', () {
    Future<Map<String, String>?> recover(
      FakeTreeContext context,
      StepArgs args,
    ) async {
      expect(
        await const CriticCapability().probeCompletionArtifact(context, args),
        GateOutcome.clear,
      );
      return const CriticCapability().result(context, args);
    }

    void writeVerdict(String workspaceDir, String rubric, String content) {
      File('$workspaceDir/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    void writeEnvelope(String workspaceDir, String rubric, String resultText) {
      File('$workspaceDir/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'result': resultText}));
    }

    test('(a) file-absent + envelope "Verdict: X" heading -> grade X, '
        'rationale marked [from result envelope]', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-heading-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeEnvelope(
        dir.path,
        rubric,
        'Reviewed the diff — narrow blast radius, well covered.\n\n'
        'Verdict: A',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'A');
      expect(out?['rationale'], contains('[from result envelope]'));
    });

    test('(gate-integrity #4) file-absent + envelope "## Grade: X" markdown '
        'heading -> grade X (the summary shape a critic emits instead of '
        '"Verdict:", missed live in tg-m2q r1)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-fallback-grade-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeEnvelope(
        dir.path,
        rubric,
        'Reviewed the diff. Coverage is complete for the new path.\n\n'
        '## Grade: A',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'A');
      expect(out?['transport'], 'file');
      expect(out?['rationale'], contains('[from result envelope]'));
    });

    test('(a) file-absent + an embedded JSON verdict in the envelope -> '
        'grade + rationale, marked', () async {
      final dir = Directory.systemTemp.createTempSync('critic-fallback-json-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeEnvelope(
        dir.path,
        rubric,
        'Here is my verdict:\n```json\n{"rubric":"test-coverage",'
        '"grade":"B","rationale":"missing an edge case"}\n```\n',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'B');
      expect(out?['rationale'], contains('missing an edge case'));
      expect(out?['rationale'], contains('[from result envelope]'));
    });

    test('(b) the FILE verdict wins when both a file and an envelope verdict '
        'exist', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-filewins-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeVerdict(
        dir.path,
        rubric,
        jsonEncode({
          'grade': 'C',
          'rationale': 'from the file',
          'nodePath': 'tg-1/review/$rubric',
          'round': 0,
        }),
      );
      writeEnvelope(dir.path, rubric, 'Verdict: A');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out, {
        'grade': 'C',
        'transport': 'file',
        'round': '0',
        'rationale': 'from the file',
      });
    });

    test('a malformed file refuses before envelope fallback', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-filebad-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeVerdict(dir.path, rubric, 'not json');
      writeEnvelope(dir.path, rubric, 'Verdict: B');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      await expectLater(
        const CriticCapability().result(c.context, c.args),
        throwsA(
          _invalidVerdictThrow(
            rubric: rubric,
            path: '${dir.path}/.grid/critique/$rubric.json',
            detail: 'Unexpected character',
          ),
        ),
      );
    });

    test('(c) no parseable verdict anywhere (no file, no envelope) -> F '
        '(fail-closed pinned)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-fallback-none-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(rubric: 'regression-risk', workspaceDir: dir.path);
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });

    test('malformed file + malformed envelope fails loudly', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-bothbad-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeVerdict(dir.path, rubric, 'not json');
      File('${dir.path}/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync('{ not json either');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      await expectLater(
        const CriticCapability().result(c.context, c.args),
        throwsA(
          _invalidVerdictThrow(
            rubric: rubric,
            path: '${dir.path}/.grid/critique/$rubric.json',
            detail: 'Unexpected character',
          ),
        ),
      );
    });

    test('missing file + an envelope with no parseable verdict -> F '
        '(fail-closed pinned)', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-noverdict-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeEnvelope(
        dir.path,
        rubric,
        'I looked at the diff, seems fine, no complaints.',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });

    test('(rework 1) a template echo `"grade":"<A-F>"` before a real verdict '
        'object -> the REAL verdict wins (the template grade is not a single '
        'A-F letter, so it never matches)', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-template-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeEnvelope(
        dir.path,
        rubric,
        'Your verdict is JSON of this exact shape:\n'
        '{"rubric":"regression-risk","version":1,"grade":"<A-F>",'
        '"rationale":"<why>"}\n\n'
        'Reviewed the diff — narrow blast radius.\n'
        '{"rubric":"regression-risk","version":1,"grade":"A",'
        '"rationale":"well covered"}',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'A');
      expect(out?['rationale'], contains('well covered'));
    });

    test('(rework 1) an example object with grade A in prose followed by a '
        'real F verdict -> the LAST (real) object wins, F', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-example-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeEnvelope(
        dir.path,
        rubric,
        'For example, a clean pass might look like '
        '{"grade":"A","rationale":"example only"}.\n\n'
        'Having actually reviewed this diff, coverage is missing entirely.\n'
        '{"rubric":"test-coverage","version":1,"grade":"F",'
        '"rationale":"no tests for the new path"}',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'F');
      expect(out?['rationale'], contains('no tests for the new path'));
    });

    test('(rework 1) a template-echo-only envelope (no real verdict object '
        'or heading) -> F (fail-closed — the template grade is not a valid '
        'A-F letter)', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-templateonly-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeEnvelope(
        dir.path,
        rubric,
        'Your verdict is JSON of this exact shape:\n'
        '{"rubric":"spec-adherence","version":1,"grade":"<A-F>",'
        '"rationale":"<why>"}',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });

    test('(rework 2) an early "Verdict: A" heading followed by a later, real '
        '"Verdict: F" heading -> the LAST heading wins, F', () async {
      final dir = Directory.systemTemp.createTempSync(
        'critic-fallback-headtail-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeEnvelope(
        dir.path,
        rubric,
        'A clean pass typically reads like: Verdict: A\n\n'
        'Having actually reviewed this diff, the blast radius is unbounded.\n'
        'Verdict: F',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out?['grade'], 'F');
    });

    test('a recovered fallback grade still merges FT-2 usage telemetry when '
        'present', () async {
      final dir = Directory.systemTemp.createTempSync('critic-fallback-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      File('${dir.path}/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'result': 'Verdict: A', 'num_turns': 36}),
        );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await recover(c.context, c.args);
      expect(out, {
        'grade': 'A',
        'transport': 'file',
        'round': '0',
        'rationale': '[from result envelope]',
        'numTurns': '36',
      });
    });
  });

  group('Track C — gate-integrity #4 (bead tg-r66): the cwd-relative STRAY '
      'verdict read-side belt', () {
    // A critic that cd's mid-run resolves its (formerly relative) verdict path
    // against the NEW cwd, writing .grid/critique/<rubric>.json under a SUBDIR
    // instead of at the worktree root. result() recovers a ROUND-FRESH such
    // stray (the nodePath stamp keeps it safe), naming transport `file-stray`.
    void writeStray(
      String workspaceDir,
      String subdir,
      String rubric,
      Map<String, dynamic> verdict,
    ) {
      File('$workspaceDir/$subdir/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(verdict));
    }

    test('a round-fresh stray under a package subdir is recovered, transport '
        'file-stray', () async {
      final dir = Directory.systemTemp.createTempSync('critic-stray-fresh-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      const nodePath = 'tg-1/review/test-coverage';
      // The observed live location: the critic cd'd into the package.
      writeStray(dir.path, 'packages/grid_assets', rubric, {
        'rubric': rubric,
        'version': 1,
        'grade': 'B',
        'rationale': 'covered the new path',
        'nodePath': nodePath,
        'round': 0,
      });
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'B',
        'transport': 'file-stray',
        'round': '0',
        'rationale': 'covered the new path',
      });
    });

    test(
      'a STALE stray (nodePath from a prior round) is NOT recovered -> F '
      '(the freshness stamp is what makes accepting an off-path file safe)',
      () async {
        final dir = Directory.systemTemp.createTempSync('critic-stray-stale-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const rubric = 'test-coverage';
        writeStray(dir.path, 'packages/grid_assets', rubric, {
          'grade': 'A',
          'rationale': 'a stale round-1 stray',
          'nodePath': 'tg-1#r1/review/test-coverage',
          // Round-FRESH: the foreign nodePath alone must reject it.
          'round': 0,
        });
        final c = _ctx(
          rubric: rubric,
          workspaceDir: dir.path,
          nodePath: 'tg-1#r2/review/test-coverage',
        );
        expect(
          await const CriticCapability().probeCompletionArtifact(
            c.context,
            c.args,
          ),
          GateOutcome.present,
        );
      },
    );

    test('the canonical verdict still WINS over a fresh stray', () async {
      final dir = Directory.systemTemp.createTempSync('critic-stray-canon-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      const nodePath = 'tg-1/review/test-coverage';
      File('${dir.path}/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'grade': 'C',
            'rationale': 'from the canonical file',
            'nodePath': nodePath,
            'round': 0,
          }),
        );
      // A fresh stray with a DIFFERENT grade — must never be consulted.
      writeStray(dir.path, 'packages/grid_assets', rubric, {
        'grade': 'A',
        'rationale': 'from the stray',
        'nodePath': nodePath,
        'round': 0,
      });
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'C',
        'transport': 'file',
        'round': '0',
        'rationale': 'from the canonical file',
      });
    });

    test('a stray buried in a pruned dir (.dart_tool) is ignored -> F '
        '(the fallback walk stays bounded)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-stray-pruned-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      const nodePath = 'tg-1/review/test-coverage';
      writeStray(dir.path, '.dart_tool/x', rubric, {
        'grade': 'A',
        'rationale': 'inside a pruned tree',
        'nodePath': nodePath,
        'round': 0,
      });
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });
  });

  group('Track C — ClearCritiqueCapability (gate-integrity #3): wipes '
      '.grid/critique at the START of every round', () {
    ({FakeTreeContext context, StepArgs args}) ctx(String workspaceDir) => (
      context: FakeTreeContext(
        values: {
          Workspace: testWorkspace(
            'tg-1',
            workspaceDir: workspaceDir,
            branch: 'grid/tg-1',
          ),
        },
      ),
      args: stepArgs('tg-1/review/clear-critique'),
    );

    test('deletes a PRIOR round\'s stale verdict/rc files and recreates an '
        'empty critique dir', () async {
      final dir = Directory.systemTemp.createTempSync('clear-critique-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final critiqueDir = Directory('${dir.path}/.grid/critique')
        ..createSync(recursive: true);
      File('${critiqueDir.path}/regression-risk.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"grade":"A","nodePath":"tg-1#r1/review/x"}');
      File('${critiqueDir.path}/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');

      final c = ctx(dir.path);
      final outcome = await const ClearCritiqueCapability().run(
        c.context,
        c.args,
      );
      expect(outcome, isA<Ok>());
      expect(critiqueDir.existsSync(), isTrue);
      expect(critiqueDir.listSync(), isEmpty);
    });

    test('an absent critique dir is simply created (a first round, nothing '
        'to clear)', () async {
      final dir = Directory.systemTemp.createTempSync('clear-critique-first-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = ctx(dir.path);
      final outcome = await const ClearCritiqueCapability().run(
        c.context,
        c.args,
      );
      expect(outcome, isA<Ok>());
      expect(Directory('${dir.path}/.grid/critique').existsSync(), isTrue);
    });

    test('no ambient Workspace -> Ok no-op (never throws)', () async {
      final c = (
        context: FakeTreeContext(values: const {}),
        args: stepArgs('tg-1/review/clear-critique'),
      );
      final outcome = await const ClearCritiqueCapability().run(
        c.context,
        c.args,
      );
      expect(outcome, isA<Ok>());
    });

    test(
      'a throwing clearer never Gates the round — best-effort hygiene, '
      'the verdict\'s nodePath + round stamps are the fail-safe backstop',
      () async {
        final c = ctx('/w/tg-1');
        final outcome = await const ClearCritiqueCapability(
          clearer: _throwingClearer,
        ).run(c.context, c.args);
        expect(outcome, isA<Ok>());
      },
    );

    test('an injected clearer replaces the real delete+recreate (the '
        'offline-suite seam — never touches a real filesystem)', () async {
      String? cleared;
      final c = ctx('/w/tg-1');
      final outcome = await ClearCritiqueCapability(
        clearer: (dir) => cleared = dir,
      ).run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(cleared, '/w/tg-1/.grid/critique');
    });
  });

  group('the CAPABILITY writes the round stamp (Nico 2026-09-01 — keep '
      'A15(5) alt-A\'s clause, change the WRITER)', () {
    const rubric = 'adr-alignment';
    const nodePath = 'tg-j9ac/spec_review/adr-alignment';
    final spawnAt = DateTime.utc(2026, 9, 1, 19, 6);
    final afterSpawn = spawnAt.add(const Duration(seconds: 30));
    final beforeSpawn = spawnAt.subtract(const Duration(seconds: 30));

    late Directory dir;
    late RecordingExplorationTransport flares;
    late String canonical;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('critic-restamp-');
      canonical = '${dir.path}/.grid/critique/$rubric.json';
      flares = RecordingExplorationTransport();
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('a CONTAMINATED fresh stamp (the critic copied a rework ROUND out of '
        'the bead notes) is re-stamped to grid.round, ACCEPTED, and flared '
        'with model_round', () async {
      _plantIncarnation(dir.path, rubric, spawnAt);
      _plantVerdictAt(
        canonical,
        nodePath: nodePath,
        modifiedAt: afterSpawn,
        round: 4,
      );
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
        transport: flares,
      );

      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.clear,
      );
      expect(_readVerdictJson(canonical)[kVerdictRoundKey], 1);
      expect(_readVerdictJson(canonical)[kVerdictModelRoundKey], 4);

      final payload = await const CriticCapability().result(c.context, c.args);
      expect(payload, containsPair('grade', 'A'));
      expect(payload, containsPair(kVerdictRoundKey, '1'));

      final flare = flares.named('critic.verdictRoundRestamped').single;
      expect(flare.data, containsPair('rubric', rubric));
      expect(flare.data, containsPair('nodePath', nodePath));
      expect(flare.data, containsPair('round', '1'));
      expect(flare.data, containsPair(kVerdictModelRoundKey, '4'));
      expect(flares.named('critic.verdictProbeUnresolved'), isEmpty);
    });

    test(
      'a verdict written BEFORE this incarnation is left BYTE-IDENTICAL and '
      'still REJECTED — the marker is the proof, the wipe is the belt',
      () async {
        _plantIncarnation(dir.path, rubric, spawnAt);
        _plantVerdictAt(
          canonical,
          nodePath: nodePath,
          modifiedAt: beforeSpawn,
          round: 0,
        );
        final before = File(canonical).readAsStringSync();
        final c = _ctx(
          rubric: rubric,
          workspaceDir: dir.path,
          nodePath: nodePath,
          round: 1,
          transport: flares,
        );

        expect(
          await const CriticCapability().probeCompletionArtifact(
            c.context,
            c.args,
          ),
          GateOutcome.present,
        );
        expect(File(canonical).readAsStringSync(), before);
        final flare = flares.named('critic.verdictProbeUnresolved').single;
        expect(flare.data, containsPair('rubric', rubric));
        expect(flare.data, containsPair('nodePath', nodePath));
        expect(flare.data, containsPair('round', '1'));
        expect(flare.data, containsPair('fileRound', '0'));
        expect(
          flare.data,
          containsPair('restamp', 'skipped: verdict predates this incarnation'),
        );
        expect(flare.data, containsPair('strayTried', 'true'));
        expect(flare.data, containsPair('envelopeTried', 'true'));
      },
    );

    test('a FOREIGN nodePath is NEVER re-stamped into validity — A4\'s fence '
        'holds ahead of the writer', () async {
      _plantIncarnation(dir.path, rubric, spawnAt);
      _plantVerdictAt(
        canonical,
        nodePath: 'other-bead/spec_review/$rubric',
        modifiedAt: afterSpawn,
        round: 4,
      );
      final before = File(canonical).readAsStringSync();
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
        transport: flares,
      );

      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
      expect(File(canonical).readAsStringSync(), before);
      expect(
        flares.named('critic.verdictProbeUnresolved').single.data,
        containsPair('restamp', 'skipped: foreign nodePath stamp'),
      );
    });

    test('a verdict with NO round stamp stays the pow-q5n transport defect — '
        'the writer never invents one', () async {
      _plantIncarnation(dir.path, rubric, spawnAt);
      _plantVerdictAt(canonical, nodePath: nodePath, modifiedAt: afterSpawn);
      final before = File(canonical).readAsStringSync();
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
        transport: flares,
      );

      await expectLater(
        const CriticCapability().probeCompletionArtifact(c.context, c.args),
        throwsA(
          _invalidVerdictThrow(
            rubric: rubric,
            path: canonical,
            detail: 'round must be an integer or integer-readable string',
          ),
        ),
      );
      expect(File(canonical).readAsStringSync(), before);
      expect(
        File(canonical).readAsStringSync(),
        isNot(contains(kVerdictModelRoundKey)),
      );
    });

    test(
      'the STRAY belt still rejects a stale round — the writer never reaches '
      'an off-canonical file',
      () async {
        _plantIncarnation(dir.path, rubric, spawnAt);
        final stray =
            '${dir.path}/packages/grid_assets/.grid/critique/$rubric.json';
        _plantVerdictAt(
          stray,
          nodePath: nodePath,
          modifiedAt: afterSpawn,
          round: 0,
        );
        final before = File(stray).readAsStringSync();
        final c = _ctx(
          rubric: rubric,
          workspaceDir: dir.path,
          nodePath: nodePath,
          round: 1,
          transport: flares,
        );

        expect(
          await const CriticCapability().probeCompletionArtifact(
            c.context,
            c.args,
          ),
          GateOutcome.present,
        );
        expect(File(stray).readAsStringSync(), before);
        expect(
          flares.named('critic.verdictProbeUnresolved').single.data,
          containsPair('restamp', 'skipped: no canonical verdict file'),
        );
      },
    );

    test('with NO artifact at all the probe flare still names the lane and '
        'carries an EMPTY fileRound', () async {
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
        transport: flares,
      );

      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
      final flare = flares.named('critic.verdictProbeUnresolved').single;
      expect(flare.data, containsPair('rubric', rubric));
      expect(flare.data, containsPair('nodePath', nodePath));
      expect(flare.data, containsPair('round', '1'));
      expect(flare.data, containsPair('fileRound', ''));
      expect(
        flare.data,
        containsPair('restamp', 'skipped: no canonical verdict file'),
      );
    });

    test('spawn records the incarnation for an LLM lane and NOT for the '
        'deterministic gating runner', () {
      final llm = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
      );
      const CriticCapability().spawn(llm.context, llm.args);
      expect(
        File(criticIncarnationPath(dir.path, rubric)).existsSync(),
        isTrue,
      );

      final gating = _ctx(
        rubric: kGatingRubric,
        workspaceDir: dir.path,
        nodePath: 'tg-j9ac/review/$kGatingRubric',
        round: 1,
      );
      const CriticCapability().spawn(gating.context, gating.args);
      expect(
        File(criticIncarnationPath(dir.path, kGatingRubric)).existsSync(),
        isFalse,
      );
    });
  });

  group('critic invalid-result EXHAUSTION (the visible gate)', () {
    test(
      'parks one actionable gate, with no failed cursor and no grade',
      () async {
        final fakes = buildFakes();
        final owner = TreeOwner();
        addTearDown(() {
          owner.dispose();
          unawaited(fakes.provider.close());
        });
        const receipt =
            'invalid critic verdict for rubric "regression-risk" at '
            '/w/tg-1/.grid/critique/regression-risk.json: '
            'grade must be one of A–F';

        final root = owner.mountRoot(
          ProviderScope(
            child: InheritedSeed<StationServices>(
              value: fakes.ctx,
              child: InheritedSeed<CapabilityRegistry>(
                value: RecordingCapabilityRegistry(clock: DateTime(2026)),
                child: InheritedSeed<InheritedCircuit>(
                  value: _criticCircuit,
                  child: const CapabilityHost(
                    capability: _CriticPolicyProbeCapability(),
                    mount: _criticMount,
                  ),
                ),
              ),
            ),
          ),
        );
        await pumpEventQueue();
        fakes.runner.calls.clear();

        final hostBranch =
            _branchWithSeed<CapabilityHost>(root) as StatefulBranch;
        // ignore: invalid_use_of_protected_member
        final host = hostBranch.state as CapabilityHostState;
        // The SECOND invalid attempt: the mount's cursor already carries one
        // restart, so the declared budget of two is spent by this report.
        host.deliverReportForTest(
          const AllocationFailed.invalidResult(receipt),
        );
        await pumpEventQueue();

        final stepMetadata = callMetadata(
          fakes.runner
              .callsFor('update')
              .firstWhere((call) => call.contains(_criticStepBeadId)),
        );
        expect(stepMetadata[MoleculeStepKeys.state], 'gated');
        expect(
          stepMetadata.containsKey(
            ResultKeys.keyFor(_criticNodePath, ResultKeys.grade),
          ),
          isFalse,
          reason: 'an unusable artifact contributes NO grade to the committee',
        );

        // Exactly ONE actionable gate — not a whole-round replay.
        expect(fakes.runner.callsFor('create'), hasLength(1));
        expect(
          fakes.runner.callsFor('create').single,
          containsAllInOrder(['--type', 'gate']),
        );
        final gateMetadata = fakes.runner
            .callsFor('update')
            .map(callMetadata)
            .firstWhere((metadata) => metadata.containsKey('reason'));
        expect(gateMetadata['reason'], contains('invalid_result'));
        expect(gateMetadata['reason'], contains(receipt));

        for (final call in fakes.runner.calls) {
          expect(call.join(' '), isNot(contains('grid.step.state=failed')));
        }
      },
    );
  });
}

void _throwingClearer(String dir) => throw StateError('disk is full');

// ── the invalid-result exhaustion harness ────────────────────────────────────
//
// PRODUCTION critics keep riding the lease-vended `ProcessAllocation`; this
// passive allocation exists only so the host has an effect to drive while the
// REAL `CriticCapability.supervisionPolicy` decides what its failure costs.

const _criticNodePath = 'tg-1/regression-risk';
const _criticStepBeadId = 'tgdog-step-regression-risk';

const _criticCircuitValue = Circuit(
  id: 'code_review',
  terminalStepId: 'regression-risk',
  maxRestarts: 3,
  steps: [CapabilityStep(stepId: 'regression-risk', capabilityId: 'critic')],
);

const _criticMount = StepMount(
  step: CapabilityStep(stepId: 'regression-risk', capabilityId: 'critic'),
  nodePath: _criticNodePath,
  circuit: _criticCircuitValue,
  circuitPath: 'tg-1',
  session: SessionHandle('tgdog-s'),
  // The FIRST supervised restart is already spent, so the next invalid report
  // exhausts the critic's declared budget of two.
  node: NodeCursor(state: StepState.running, restartCount: 1),
  key: ValueKey('$_criticStepBeadId#1'),
  maxRestarts: 3,
);

final _criticCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _criticStepBeadId]),
  beadIdByNodePath: const {_criticNodePath: _criticStepBeadId},
  cursor: const {},
);

/// An effect that starts and stops and does nothing else — the host stimulus
/// for a policy test (never a production allocation shape).
final class _PassiveAllocation extends Allocation {
  _PassiveAllocation(super.context);

  @override
  Future<void> startOrAdopt() {
    state = AllocationState.live;
    return Future<void>.value();
  }

  @override
  Future<void> dispose() {
    state = AllocationState.gone;
    return Future<void>.value();
  }
}

/// Carries the REAL [CriticCapability.supervisionPolicy] over a passive
/// effect, so the host resolves the critic's own declaration with no process,
/// no lease vendor, and no verdict file in play.
final class _CriticPolicyProbeCapability extends Capability {
  const _CriticPolicyProbeCapability();

  @override
  Allocation createAllocation(AllocationContext ctx) => _PassiveAllocation(ctx);

  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) =>
      const CriticCapability().supervisionPolicy(args);
}

Branch _branchWithSeed<T extends Seed>(Branch root) {
  Branch? found;
  void walk(Branch branch) {
    if (branch.seed is T) found = branch;
    branch.visitChildren(walk);
  }

  walk(root);
  return found!;
}
