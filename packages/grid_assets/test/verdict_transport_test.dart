import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The critic's (ambient tree, per-step args) pair — the same context rip-out
/// shape the critic unit file uses: the work Bead + Workspace ride the tree, the
/// rubric rides the step params, and `grid.round` is the engine's injected round
/// the verdict stamp is fenced against.
({FakeTreeContext context, StepArgs args}) _criticCtx({
  required String rubric,
  required String workspaceDir,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs(
    'tg-1/review/$rubric',
    params: {'rubric': rubric, 'grid.round': '0'},
  ),
);

/// Writes the captured-stdout RESULT ENVELOPE the durability probe recovers
/// from — the embedded-JSON transport, with no canonical file on disk so the
/// probe must repair.
void _writeEnvelope(String workspaceDir, String rubric, String resultText) {
  File('$workspaceDir/${usageReportPath('tg-1/review/$rubric')}')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({'result': resultText}));
}

/// The canonical verdict document the probe's rewrite left on disk.
Map<String, Object?> _canonical(String workspaceDir, String rubric) =>
    jsonDecode(
          File('$workspaceDir/.grid/critique/$rubric.json').readAsStringSync(),
        )
        as Map<String, Object?>;

/// An embedded-JSON result envelope carrying [columns] beside a `B` grade — the
/// shape a critic emits when it fences its verdict in a markdown block.
String _envelopeText(Map<String, String> columns) =>
    'Here is my verdict:\n```json\n'
    '${jsonEncode({'grade': 'B', 'rationale': 'covered, with a tracker note', ...columns})}\n```\n';

void main() {
  group('atomic verdict prompt contract', () {
    final bead = Bead(id: 'tg-1', title: 'Atomic verdict transport');
    final prompts = <String>[
      const CriticCapability().buildCriticPrompt(
        bead,
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      ),
      const SpecCriticCapability().buildSpecCriticPrompt(
        bead,
        'coherence',
        'tg-1/spec_review/coherence',
        '/w/tg-1',
        round: 0,
      ),
      const ReadinessCriticCapability().buildReadinessPrompt(
        bead,
        kReadinessRubric,
        'tg-1/spec_review/readiness',
        '/w/tg-1',
        round: 0,
      ),
    ];

    test('every critic ends with same-directory atomic replacement', () {
      for (final prompt in prompts) {
        expect(prompt, contains('Do NOT write JSON directly'));
        expect(prompt, contains('mktemp "/w/tg-1/.grid/critique/'));
        expect(prompt, contains('mv -f -- "\$verdict_tmp"'));
        expect(
          prompt.trimRight(),
          endsWith(
            'never reuse one writer\'s temporary path in another writer.',
          ),
        );
        expect(prompt, isNot(contains('You MUST write that JSON to')));
      }
    });

    test('ONLY the spec critic is taught the owner column', () {
      expect(prompts[1], contains('"$kVerdictOwnerKey":"<architect|author>"'));
      expect(prompts[1], contains(kVerdictOwnerInstruction));
      for (final other in [prompts[0], prompts[2]]) {
        expect(other, isNot(contains('"$kVerdictOwnerKey":')));
        expect(other, isNot(contains(kVerdictOwnerInstruction)));
      }
    });
  });

  test('concurrent atomic verdict replacement stays parseable', () async {
    final dir = await Directory.systemTemp.createTemp('verdict-transport-');
    addTearDown(() async => dir.delete(recursive: true));
    final destination = File('${dir.path}/verdict.json');
    final payloads = [
      {'writer': 'one', 'rationale': List.filled(4000, 'alpha').join(' ')},
      {'writer': 'two', 'rationale': List.filled(4000, 'bravo').join(' ')},
    ];
    await destination.writeAsString(jsonEncode(payloads.first));

    Future<ProcessResult> writer(Map<String, Object> payload) async {
      final encoded = jsonEncode(payload);
      return Process.run('/bin/sh', [
        '-c',
        'verdict_tmp=\$(mktemp "\$1/.verdict.json.XXXXXX") && '
            'printf %s "\$2" > "\$verdict_tmp" && '
            'mv -f -- "\$verdict_tmp" "\$1/verdict.json"',
        'writer',
        dir.path,
        encoded,
      ]);
    }

    final writers = Future.wait([
      for (final payload in payloads) writer(payload),
    ]);
    while (true) {
      final observed = jsonDecode(await destination.readAsString());
      expect(
        payloads.any((payload) => jsonEncode(payload) == jsonEncode(observed)),
        isTrue,
      );
      final complete = await Future.any<Object?>([
        writers.then<Object?>((value) => value),
        Future<void>.delayed(const Duration(milliseconds: 1)),
      ]);
      if (complete is List<ProcessResult>) break;
    }
    final results = await writers;
    for (final result in results) {
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final finalDocument = jsonDecode(await destination.readAsString());
    expect(
      payloads.any(
        (payload) => jsonEncode(payload) == jsonEncode(finalDocument),
      ),
      isTrue,
    );
  });

  group('ledger session ownership', () {
    test('rejects and deletes a retired root', () async {
      final dir = await Directory.systemTemp.createTemp('ledger-retired-');
      addTearDown(() async => dir.delete(recursive: true));
      writeRespecLedger(
        dir.path,
        const RespecLedger(
          sessionRoot: 'retired-1',
          round: 3,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'retired rationale',
            ),
          ],
        ),
      );

      expect(
        readRespecLedger(dir.path, expectedSessionRoot: 'current-1'),
        isNull,
      );
      expect(File(respecLedgerPath(dir.path)).existsSync(), isFalse);
    });

    test('round-trips the current root', () async {
      final dir = await Directory.systemTemp.createTemp('ledger-current-');
      addTearDown(() async => dir.delete(recursive: true));
      writeRespecLedger(
        dir.path,
        const RespecLedger(
          sessionRoot: 'current-1',
          round: 2,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'verbatim rationale',
            ),
          ],
        ),
      );

      final ledger = readRespecLedger(
        dir.path,
        expectedSessionRoot: 'current-1',
      );
      expect(ledger?.sessionRoot, 'current-1');
      expect(ledger?.round, 2);
      expect(ledger?.lanes.single.rationale, 'verbatim rationale');
    });
  });

  // The NON-GRADING bead-graph column (bead `pow-bhm`) survives a verdict
  // TRANSPORT REPAIR: the embedded-JSON reader picks it off the envelope and
  // the probe's canonical rewrite persists it, so a repair never silently drops
  // the finding the operator flag is built from. Driven through the BASE
  // `CriticCapability` deliberately — the transport stack is shared by every
  // critic family, so a column proven here rides all of them.
  group('the `refinement` column survives verdict-transport recovery', () {
    const rubric = 'test-coverage';
    const refinement =
        'tg-yau duplicates this bead; tg-9kk deps on the duplicate';

    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('verdict-refine-'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Map<String, String>?> recover(String envelope) async {
      _writeEnvelope(dir.path, rubric, envelope);
      final c = _criticCtx(rubric: rubric, workspaceDir: dir.path);
      expect(
        await const CriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.clear,
      );
      return const CriticCapability().result(c.context, c.args);
    }

    test('an embedded-JSON envelope carries `refinement` through recovery into '
        'result()', () async {
      final out = await recover(
        _envelopeText(const {kVerdictRefinementKey: refinement}),
      );
      expect(out?['grade'], 'B');
      expect(out?['transport'], 'file'); // repaired INTO the canonical file
      expect(out?[kVerdictRefinementKey], refinement);
    });

    test('the canonical REWRITE persists the recovered `refinement` on disk, '
        'beside grade / rationale / nodePath / round', () async {
      await recover(_envelopeText(const {kVerdictRefinementKey: refinement}));
      final written = _canonical(dir.path, rubric);
      expect(written[kVerdictRefinementKey], refinement);
      expect(written['grade'], 'B');
      expect(written['nodePath'], 'tg-1/review/$rubric');
      expect(written[kVerdictRoundKey], 0);
    });

    test(
      'a MISSPELLED column key recovers NO refinement — and still grades the '
      'lane (the strict decode stays the ONE place a verdict fails)',
      () async {
        final out = await recover(
          _envelopeText(const {'refinment': refinement}),
        );
        expect(out?['grade'], 'B');
        expect(out!.containsKey(kVerdictRefinementKey), isFalse);
        expect(
          _canonical(dir.path, rubric).containsKey(kVerdictRefinementKey),
          isFalse,
        );
      },
    );
  });
}
