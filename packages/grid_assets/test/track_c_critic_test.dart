// Track C2 — the critic capability (one rubric, in isolation).
//
// `code-validation` is the GATING lane: it runs the bead's OWN Validation Plan
// via `sh`, capturing the plan's exit code so the step always `complete`s and
// the grade (A iff zero, else F) rides `result()`. The three LLM lanes ride the
// resolved agent harness (claude by default — same argv shape) with ONLY their
// own rubric (anti-anchoring) and write a verdict JSON `result()` parses. Zero
// I/O — no real `claude`/`sh`: the spawn config is inspected directly and
// `result()` reads files a test writes into a temp dir.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The critic's (ambient tree, per-step args) pair — the context rip-out shape:
/// the work Bead + Workspace ride the tree; the rubric rides the step params.
({FakeTreeContext context, StepArgs args}) _ctx({
  required String rubric,
  String workspaceDir = '/w/tg-1',
  Bead? beadOverride,
  String? nodePath,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: beadOverride ?? bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs(nodePath ?? 'tg-1/review/$rubric', params: {'rubric': rubric}),
);

void main() {
  group('Track C2 — code-validation (the GATING lane)', () {
    test('spawns `sh -c` running the bead\'s Validation Plan, capturing its rc',
        () {
      final withPlan = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'melos analyze && melos test'},
      );
      final c = _ctx(rubric: kGatingRubric, beadOverride: withPlan);
      final cfg = const CriticCapability().spawn(c.context, c.args);
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(cfg.args[1], contains('melos analyze && melos test'));
      // The rc is captured to the critique dir so result() can read the grade.
      expect(cfg.args[1], contains('.grid/critique/code-validation.rc'));
      expect(cfg.args[1], contains(r'echo $?'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

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
      expect(
        cap.interpretEvent(const Died(name: name)),
        StepSignal.failed,
      );
    });

    test('result() grades A on rc 0, F on a non-zero rc, F when the rc is '
        'absent (fail-closed)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();

      final c = _ctx(rubric: kGatingRubric, workspaceDir: dir.path);

      // Absent rc ⇒ fail-closed F.
      expect(await cap.result(c.context, c.args), {'grade': 'F'});

      // rc "0" ⇒ A.
      final rcFile = File('${dir.path}/.grid/critique/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');
      expect(await cap.result(c.context, c.args), {'grade': 'A'});

      // rc non-zero ⇒ F.
      rcFile.writeAsStringSync('1\n');
      expect(await cap.result(c.context, c.args), {'grade': 'F'});
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
      expect(cfg.args[5], '--output-format');
      expect(cfg.args[6], 'json');
      expect(cfg.args[7], '-p');
      // The prompt (its own rubric only) rides as the final positional.
      expect(cfg.args.last, contains('spec-adherence'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('a clean exit completes; a non-zero exit / death fails', () {
      const cap = CriticCapability();
      const name = 'tgdog-s/tg-1/review/spec-adherence';
      expect(cap.interpretEvent(const Exited(name: name, exitCode: 0)),
          StepSignal.complete);
      expect(cap.interpretEvent(const Exited(name: name, exitCode: 2)),
          StepSignal.failed);
      expect(cap.interpretEvent(const Died(name: name)), StepSignal.failed);
    });

    test('the prompt names ONLY its own rubric (anti-anchoring)', () {
      final prompt =
          const CriticCapability().buildCriticPrompt(bead('tg-1'), 'spec-adherence');
      expect(prompt, contains('spec-adherence'));
      // The other lanes' concerns must NOT leak into this critic's prompt.
      expect(prompt, isNot(contains('regression-risk')));
      expect(prompt, isNot(contains('test-coverage')));
      expect(prompt, isNot(contains('code-validation')));
      // It carries the verdict-file instruction for its own rubric only.
      expect(prompt, contains('.grid/critique/spec-adherence.json'));
    });

    test('the prompt carries the full bead', () {
      final rich = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
        design: 'A lossy inter-station gossip bus.',
      );
      final prompt =
          const CriticCapability().buildCriticPrompt(rich, 'test-coverage');
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains('Connect The Studio to The Dashboard.'));
      expect(prompt, contains('A lossy inter-station gossip bus.'));
    });

    test('result() parses a written verdict JSON into a grade + rationale', () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/.grid/critique/regression-risk.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'rubric': 'regression-risk',
          'version': 1,
          'grade': 'b',
          'rationale': 'a narrow blast radius',
        }));
      final c = _ctx(rubric: 'regression-risk', workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {'grade': 'B', 'rationale': 'a narrow blast radius'});
    });

    test('result() fail-closes to F on a missing or malformed verdict', () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-bad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();
      final c = _ctx(rubric: 'test-coverage', workspaceDir: dir.path);
      // Missing verdict ⇒ F.
      expect(await cap.result(c.context, c.args), {'grade': 'F'});
      // Malformed verdict ⇒ F.
      File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(await cap.result(c.context, c.args), {'grade': 'F'});
    });

    test('an injected rubric source replaces the inline placeholder', () {
      final cap = CriticCapability(
        rubrics: (id) => 'CUSTOM BANDS for $id',
      );
      final prompt = cap.buildCriticPrompt(bead('tg-1'), 'spec-adherence');
      expect(prompt, contains('CUSTOM BANDS for spec-adherence'));
      expect(prompt, isNot(contains('Packaged-AI-Asset loader')));
    });

    test('(tg-291 d) the file-write instruction is the LAST thing in the '
        'prompt, imperative, exact-path, and required even if a verdict '
        'appears in prose', () {
      final prompt = const CriticCapability()
          .buildCriticPrompt(bead('tg-1'), 'spec-adherence');
      expect(
        prompt.trimRight(),
        endsWith(
          'Write the file at `.grid/critique/spec-adherence.json`.',
        ),
      );
      expect(
        prompt,
        contains(
          'You MUST write that JSON to the exact path '
          '`.grid/critique/spec-adherence.json` before you finish.',
        ),
      );
      expect(
        prompt,
        contains('even if you also state your verdict in your response text'),
      );
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

    test('MERGES tokens/cost into the grade + rationale (collision-safe keys)',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeVerdict(dir.path, rubric,
          jsonEncode({'grade': 'B', 'rationale': 'narrow'}));
      writeUsage(dir.path, rubric,
          '{"total_cost_usd": 0.02, "usage": {"input_tokens": 9, "output_tokens": 8}}');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'B',
        'rationale': 'narrow',
        'tokensIn': '9',
        'tokensOut': '8',
        'costUsd': '0.02',
      });
    });

    test('still grades F on a MALFORMED verdict but merges usage if present',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-usage-badverdict-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeVerdict(dir.path, rubric, 'not json');
      writeUsage(dir.path, rubric, '{"num_turns": 2}');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {'grade': 'F', 'numTurns': '2'});
    });

    test('a MALFORMED usage file never fails the step — just the grade',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-usage-badusage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeVerdict(dir.path, rubric, jsonEncode({'grade': 'A'}));
      writeUsage(dir.path, rubric, 'garbage not json');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {'grade': 'A'});
    });

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
      expect(out, {'grade': 'A'}, reason: 'no usage merge on the gating lane');
    });
  });

  group('Track C2 — tg-291 verdict-transport fallback to the harness RESULT '
      'TEXT (the missing-file false-gate fix)', () {
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
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-heading-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeEnvelope(
        dir.path,
        rubric,
        'Reviewed the diff — narrow blast radius, well covered.\n\n'
        'Verdict: A',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'A');
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
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'B');
      expect(out?['rationale'], contains('missing an edge case'));
      expect(out?['rationale'], contains('[from result envelope]'));
    });

    test('(b) the FILE verdict wins when both a file and an envelope verdict '
        'exist', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-filewins-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeVerdict(
        dir.path,
        rubric,
        jsonEncode({'grade': 'C', 'rationale': 'from the file'}),
      );
      writeEnvelope(dir.path, rubric, 'Verdict: A');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {'grade': 'C', 'rationale': 'from the file'});
    });

    test('a MALFORMED file falls back to a valid envelope verdict', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-filebad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'regression-risk';
      writeVerdict(dir.path, rubric, 'not json');
      writeEnvelope(dir.path, rubric, 'Verdict: B');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'B');
      expect(out?['rationale'], contains('[from result envelope]'));
    });

    test('(c) no parseable verdict anywhere (no file, no envelope) -> F '
        '(fail-closed pinned)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-fallback-none-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(rubric: 'regression-risk', workspaceDir: dir.path);
      expect(
        await const CriticCapability().result(c.context, c.args),
        {'grade': 'F'},
      );
    });

    test('malformed file + malformed envelope -> F (fail-closed pinned)',
        () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-bothbad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeVerdict(dir.path, rubric, 'not json');
      File('${dir.path}/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync('{ not json either');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      expect(
        await const CriticCapability().result(c.context, c.args),
        {'grade': 'F'},
      );
    });

    test('missing file + an envelope with no parseable verdict -> F '
        '(fail-closed pinned)', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-noverdict-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeEnvelope(
        dir.path,
        rubric,
        'I looked at the diff, seems fine, no complaints.',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      expect(
        await const CriticCapability().result(c.context, c.args),
        {'grade': 'F'},
      );
    });

    test('(rework 1) a template echo `"grade":"<A-F>"` before a real verdict '
        'object -> the REAL verdict wins (the template grade is not a single '
        'A-F letter, so it never matches)', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-template-');
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
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'A');
      expect(out?['rationale'], contains('well covered'));
    });

    test('(rework 1) an example object with grade A in prose followed by a '
        'real F verdict -> the LAST (real) object wins, F', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-example-');
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
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'F');
      expect(out?['rationale'], contains('no tests for the new path'));
    });

    test('(rework 1) a template-echo-only envelope (no real verdict object '
        'or heading) -> F (fail-closed — the template grade is not a valid '
        'A-F letter)', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-templateonly-');
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
        await const CriticCapability().result(c.context, c.args),
        {'grade': 'F'},
      );
    });

    test('a recovered fallback grade still merges FT-2 usage telemetry when '
        'present', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      File('${dir.path}/${usageReportPath('tg-1/review/$rubric')}')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'result': 'Verdict: A',
          'num_turns': 36,
        }));
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'A',
        'rationale': '[from result envelope]',
        'numTurns': '36',
      });
    });
  });
}
