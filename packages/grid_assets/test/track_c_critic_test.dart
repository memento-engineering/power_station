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
import 'package:beads_dart/beads_dart.dart';
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

      // Absent rc ⇒ fail-closed F, named transport + rationale (gate-integrity
      // #3 — a fail-closed default must never be silently unexplained).
      expect(await cap.result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale': 'no validation-plan rc file — fail-closed default',
      });

      // rc "0" ⇒ A.
      final rcFile = File('${dir.path}/.grid/critique/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');
      expect(
        await cap.result(c.context, c.args),
        {'grade': 'A', 'transport': 'file'},
      );

      // rc non-zero ⇒ F.
      rcFile.writeAsStringSync('1\n');
      expect(
        await cap.result(c.context, c.args),
        {'grade': 'F', 'transport': 'file'},
      );
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
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
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
      );
      expect(prompt, contains('"nodePath":"tg-1#r3/review/spec-adherence"'));
      expect(prompt, contains('copy it byte-for-byte'));
    });

    test('the prompt pins the review scope to the pinned diff (bead pow-6wo) — '
        'the critic reviews the bead branch delta, not the worktree', () {
      final prompt = const CriticCapability().buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
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
      );
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
          'nodePath': 'tg-1/review/regression-risk',
        }));
      final c = _ctx(rubric: 'regression-risk', workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'B',
        'transport': 'file',
        'rationale': 'a narrow blast radius',
      });
    });

    test('result() fail-closes to F on a missing or malformed verdict', () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-bad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();
      final c = _ctx(rubric: 'test-coverage', workspaceDir: dir.path);
      // Missing verdict ⇒ F.
      expect(await cap.result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale':
            'no parseable verdict via file or envelope — fail-closed default',
      });
      // Malformed verdict ⇒ F.
      File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(await cap.result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale':
            'no parseable verdict via file or envelope — fail-closed default',
      });
    });

    test('result() fail-closes to F on a STALE verdict — a nodePath that '
        'does not match this round (gate-integrity #3: a rework round reuses '
        'the SAME workspace, so a prior round\'s file otherwise survives)',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-stale-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/.grid/critique/regression-risk.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'grade': 'A',
          'rationale': 'a stale round-1 verdict',
          'nodePath': 'tg-1#r1/review/regression-risk',
        }));
      final c = _ctx(
        rubric: 'regression-risk',
        workspaceDir: dir.path,
        nodePath: 'tg-1#r2/review/regression-risk',
      );
      final out = await const CriticCapability().result(c.context, c.args);
      expect(
        out,
        {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        },
        reason: 'a stale nodePath stamp must be treated as a MISSING file, '
            'never silently read as this round\'s verdict',
      );
    });

    test('an injected rubric source replaces the inline placeholder', () {
      final cap = CriticCapability(
        rubrics: (id) => 'CUSTOM BANDS for $id',
      );
      final prompt = cap.buildCriticPrompt(
        bead('tg-1'),
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
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
      );
      // The path is the workspace-derived ABSOLUTE canonical path
      // (gate-integrity #4 — cwd-invariant), not a workspace-relative one.
      expect(
        prompt.trimRight(),
        endsWith(
          'Write the file at `/w/tg-1/.grid/critique/spec-adherence.json`.',
        ),
      );
      expect(
        prompt,
        contains(
          'You MUST write that JSON to the exact ABSOLUTE path '
          '`/w/tg-1/.grid/critique/spec-adherence.json` before you finish.',
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
      writeVerdict(dir.path, rubric, jsonEncode({
        'grade': 'B',
        'rationale': 'narrow',
        'nodePath': 'tg-1/review/$rubric',
      }));
      writeUsage(dir.path, rubric,
          '{"total_cost_usd": 0.02, "usage": {"input_tokens": 9, "output_tokens": 8}}');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'B',
        'transport': 'file',
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
      expect(out, {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale':
            'no parseable verdict via file or envelope — fail-closed default',
        'numTurns': '2',
      });
    });

    test('a MALFORMED usage file never fails the step — just the grade',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-usage-badusage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'spec-adherence';
      writeVerdict(dir.path, rubric,
          jsonEncode({'grade': 'A', 'nodePath': 'tg-1/review/$rubric'}));
      writeUsage(dir.path, rubric, 'garbage not json');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {'grade': 'A', 'transport': 'file'});
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
      expect(
        out,
        {'grade': 'A', 'transport': 'file'},
        reason: 'no usage merge on the gating lane',
      );
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

    test('(gate-integrity #4) file-absent + envelope "## Grade: X" markdown '
        'heading -> grade X (the summary shape a critic emits instead of '
        '"Verdict:", missed live in tg-m2q r1)', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-grade-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeEnvelope(
        dir.path,
        rubric,
        'Reviewed the diff. Coverage is complete for the new path.\n\n'
        '## Grade: A',
      );
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'A');
      expect(out?['transport'], 'envelope');
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
        jsonEncode({
          'grade': 'C',
          'rationale': 'from the file',
          'nodePath': 'tg-1/review/$rubric',
        }),
      );
      writeEnvelope(dir.path, rubric, 'Verdict: A');
      final c = _ctx(rubric: rubric, workspaceDir: dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'C',
        'transport': 'file',
        'rationale': 'from the file',
      });
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
        {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        },
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
        {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        },
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
        {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        },
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
        {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        },
      );
    });

    test('(rework 2) an early "Verdict: A" heading followed by a later, real '
        '"Verdict: F" heading -> the LAST heading wins, F', () async {
      final dir =
          Directory.systemTemp.createTempSync('critic-fallback-headtail-');
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
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out?['grade'], 'F');
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
        'transport': 'envelope',
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
      });
      final c = _ctx(rubric: rubric, workspaceDir: dir.path, nodePath: nodePath);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'B',
        'transport': 'file-stray',
        'rationale': 'covered the new path',
      });
    });

    test('a STALE stray (nodePath from a prior round) is NOT recovered -> F '
        '(the freshness stamp is what makes accepting an off-path file safe)',
        () async {
      final dir = Directory.systemTemp.createTempSync('critic-stray-stale-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      writeStray(dir.path, 'packages/grid_assets', rubric, {
        'grade': 'A',
        'rationale': 'a stale round-1 stray',
        'nodePath': 'tg-1#r1/review/test-coverage',
      });
      final c = _ctx(
        rubric: rubric,
        workspaceDir: dir.path,
        nodePath: 'tg-1#r2/review/test-coverage',
      );
      expect(await const CriticCapability().result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale':
            'no parseable verdict via file or envelope — fail-closed default',
      });
    });

    test('the canonical verdict still WINS over a fresh stray', () async {
      final dir = Directory.systemTemp.createTempSync('critic-stray-canon-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'test-coverage';
      const nodePath = 'tg-1/review/test-coverage';
      File('${dir.path}/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'grade': 'C',
          'rationale': 'from the canonical file',
          'nodePath': nodePath,
        }));
      // A fresh stray with a DIFFERENT grade — must never be consulted.
      writeStray(dir.path, 'packages/grid_assets', rubric, {
        'grade': 'A',
        'rationale': 'from the stray',
        'nodePath': nodePath,
      });
      final c = _ctx(rubric: rubric, workspaceDir: dir.path, nodePath: nodePath);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out, {
        'grade': 'C',
        'transport': 'file',
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
      });
      final c = _ctx(rubric: rubric, workspaceDir: dir.path, nodePath: nodePath);
      expect(await const CriticCapability().result(c.context, c.args), {
        'grade': 'F',
        'transport': 'fail-closed-default',
        'rationale':
            'no parseable verdict via file or envelope — fail-closed default',
      });
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
      final outcome = await const ClearCritiqueCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(critiqueDir.existsSync(), isTrue);
      expect(critiqueDir.listSync(), isEmpty);
    });

    test('an absent critique dir is simply created (a first round, nothing '
        'to clear)', () async {
      final dir = Directory.systemTemp.createTempSync('clear-critique-first-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = ctx(dir.path);
      final outcome = await const ClearCritiqueCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(Directory('${dir.path}/.grid/critique').existsSync(), isTrue);
    });

    test('no ambient Workspace -> Ok no-op (never throws)', () async {
      final c = (
        context: FakeTreeContext(values: const {}),
        args: stepArgs('tg-1/review/clear-critique'),
      );
      final outcome = await const ClearCritiqueCapability().run(c.context, c.args);
      expect(outcome, isA<Ok>());
    });

    test('a throwing clearer never Gates the round — best-effort hygiene, '
        'the nodePath stamp is the fail-safe backstop', () async {
      final c = ctx('/w/tg-1');
      final outcome = await const ClearCritiqueCapability(
        clearer: _throwingClearer,
      ).run(c.context, c.args);
      expect(outcome, isA<Ok>());
    });

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
}

void _throwingClearer(String dir) => throw StateError('disk is full');
