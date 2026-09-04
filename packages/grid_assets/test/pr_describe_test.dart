// The DESCRIBE pass — the one-shot inference over a bounded MANIFEST of the
// branch's facts, its two fail-safe guards, the harness invocation it renders,
// and the FT-2 usage it now captures. Offline: a canned GitRunner + a fake
// InferenceRunner; the only real I/O is a temp dir (the guard reads
// `Directory.existsSync`, and the telemetry envelope is a real file).
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A [GitRunner] that FAILS the test if it is ever called — proves a guard.
class _ExplodingGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => fail('git must not run: $args');
}

/// An [InferenceRunner] that FAILS the test if it is ever called.
class _ExplodingInferenceRunner implements InferenceRunner {
  @override
  Future<InferenceResult> run(RuntimeConfig config) async =>
      fail('inference must not run: ${config.command}');
}

const String _answer =
    '{"type":"feat","scope":"landing","breaking":false,'
    '"description":"infer the pr title from the branch diff",'
    '"summary":"The land step reads the branch delta and describes it. '
    'The title no longer restates the tracker.","breakingChange":""}';

Future<DescribeOutcome> _describe({
  required String workspaceDir,
  GitRunner? git,
  InferenceRunner? inference,
  PrComposition composition = const PrComposition(),
  Bead? beadOverride,
  String nodePath = 'tg-1/deliver',
  List<DescribeReceipt> receipts = const [],
}) => describeBranch(
  bead: beadOverride ?? bead('tg-1'),
  beadId: 'tg-1',
  nodePath: nodePath,
  workspace: testWorkspace(
    'tg-1',
    workspaceDir: workspaceDir,
    branch: 'grid/tg-1',
    baseBranch: 'main',
  ),
  composition: composition,
  ambient: const AgentConfig(),
  registry: buildBuiltinEnvironmentRegistry(),
  receipts: receipts,
  git: git,
  inference: inference,
);

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('pow8dx'));
  tearDown(() => work.deleteSync(recursive: true));

  group('the two FAIL-SAFE guards (no real git, no real claude, ever)', () {
    test(
      'no InferenceRunner wired (a bare `const DeliverRouteCapability()`) ⇒ the '
      'fallback, with ZERO git calls',
      () async {
        final outcome = await _describe(
          workspaceDir: work.path,
          git: _ExplodingGitRunner(),
        );
        expect(outcome.description, isNull);
        expect(outcome.source, 'fallback');
        expect(outcome.commits.isEmpty, isTrue);
      },
    );

    test(
      'a workspace dir that does not exist on disk (the offline/dry-run posture '
      'every acceptance fixture mounts) ⇒ the fallback, with ZERO git and ZERO '
      'inference',
      () async {
        final outcome = await _describe(
          workspaceDir: '/grid/worktrees/tg-1',
          git: _ExplodingGitRunner(),
          inference: _ExplodingInferenceRunner(),
        );
        expect(outcome.source, 'fallback');
      },
    );
  });

  group('the happy path — inference over the ACTUAL delta, as FACTS', () {
    test('reads the branch delta as FACTS, renders the harness invocation with '
        'the CHEAP model, and parses the answer', () async {
      final git = CannedGitRunner(
        log: 'feat(x): do a thing\n\nRefs: tg-1\x00',
        diff: '--- a/lib/x.dart\n+++ b/lib/x.dart\n+the change',
      );
      final inference = FakeInferenceRunner(output: _answer);
      final outcome = await _describe(
        workspaceDir: work.path,
        git: git,
        inference: inference,
      );

      expect(outcome.source, 'inference');
      expect(outcome.description!.type, 'feat');
      expect(outcome.description!.scope, 'landing');
      expect(outcome.description!.summary, startsWith('The land step reads'));
      expect(outcome.commits.total, 1);
      expect(outcome.commits.compliant, 1);
      expect(outcome.commits.trailered, 1);

      // The branch's OWN delta as FACTS: the three-dot merge-base range
      // PinDiffCapability pins the critics to, and the NUL-separated log the
      // lint reads.
      expect(git.calls[0], ['log', '--format=%s%n%b%x00', 'origin/main..HEAD']);
      expect(git.calls[1], [
        'diff',
        '--name-status',
        '-z',
        'origin/main...HEAD',
      ]);
      expect(git.calls[2], ['diff', '--numstat', '-z', 'origin/main...HEAD']);
      expect(git.calls[3], ['diff', '--shortstat', 'origin/main...HEAD']);
      // The PATCH read is GONE — nothing here asks git for a hunk.
      expect(
        git.calls.any((argv) => argv.join(' ') == 'diff origin/main...HEAD'),
        isFalse,
      );

      // The harness (the SAME one the critics ride) rendered a one-shot claude
      // invocation on the cheap model, wrapped by the FT-2 usage-capture shell
      // because the describe call is now METERED.
      final invocation = inference.calls.single;
      expect(invocation.command, 'sh');
      expect(invocation.args[0], '-c');
      expect(
        invocation.args[1],
        contains('.grid/telemetry/tg-1_deliver.usage.json'),
      );
      expect(invocation.args[2], 'grid-claude');
      expect(invocation.args[3], 'claude');
      expect(invocation.args, containsAllInOrder(<String>['--model', 'haiku']));
      expect(invocation.workDir, work.path);
      // The brief is the MANIFEST, not the patch.
      expect(invocation.args.last, contains('## The change manifest'));
      expect(invocation.args.last, contains('- M lib/x.dart +2 -1'));
      expect(
        invocation.args.last,
        contains('USE ONLY THE FACTS IN THE MANIFEST'),
      );
      expect(invocation.args.last, isNot(contains('+the change')));
      expect(
        invocation.args.last,
        contains('NEVER write the tracker id `tg-1`'),
      );
    });

    test("the composition's model is a knob", () async {
      final inference = FakeInferenceRunner(output: _answer);
      await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(),
        inference: inference,
        composition: const PrComposition(model: 'sonnet'),
      );
      expect(
        inference.calls.single.args,
        containsAllInOrder(<String>['--model', 'sonnet']),
      );
    });

    test(
      "a bead's grid.agent envelope does NOT re-point the describe pass — it is "
      "STATION policy over the landing prose, not the bead's work agent",
      () async {
        final inference = FakeInferenceRunner(output: _answer);
        await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(),
          inference: inference,
          beadOverride: bead('tg-1').copyWith(
            metadata: const {
              'grid.agent': {
                'assets_version': '0.0.1',
                'payload': {'harness': 'opencode'},
              },
            },
          ),
        );
        expect(inference.calls.single.args[3], 'claude');
      },
    );
  });

  group('every failure path falls back — a land NEVER fails over PR prose', () {
    test(
      'a failing `git diff --name-status` ⇒ fallback, but the commit lint '
      'still lands',
      () async {
        final outcome = await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(log: 'wip\x00', nameStatusOk: false),
          inference: _ExplodingInferenceRunner(),
        );
        expect(outcome.source, 'fallback');
        expect(outcome.commits.total, 1);
        expect(outcome.commits.compliant, 0);
      },
    );

    test('an EMPTY changed-file set ⇒ fallback, no inference spent', () async {
      final outcome = await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(nameStatus: '', numstat: ''),
        inference: _ExplodingInferenceRunner(),
      );
      expect(outcome.source, 'fallback');
    });

    test(
      'a non-zero inference run, or unparseable output, ⇒ fallback',
      () async {
        final failed = await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(),
          inference: FakeInferenceRunner(output: _answer, ok: false),
        );
        expect(failed.source, 'fallback');
        final garbage = await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(),
          inference: FakeInferenceRunner(output: 'I refuse.'),
        );
        expect(garbage.source, 'fallback');
      },
    );
  });

  group('the describe call is METERED (FT-2) and its answer is the envelope', () {
    test(
      'an FT-2 envelope on disk supplies BOTH the answer text and the usage '
      'fields',
      () async {
        final telemetry = File(
          p.join(work.path, usageReportPath('tg-1/deliver')),
        )..parent.createSync(recursive: true);
        telemetry.writeAsStringSync(
          jsonEncode({
            'result': _answer,
            'usage': {'input_tokens': 812, 'output_tokens': 143},
            'num_turns': 1,
            'duration_ms': 2400,
            'modelUsage': {'claude-haiku-4-5': <String, Object?>{}},
          }),
        );
        final outcome = await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(log: 'feat(x): do a thing\x00'),
          // stdout is EMPTY: the real harness redirected it into the envelope.
          inference: FakeInferenceRunner(),
        );
        expect(outcome.source, 'inference');
        expect(outcome.description!.type, 'feat');
        expect(outcome.usage['tokensIn'], '812');
        expect(outcome.usage['tokensOut'], '143');
        expect(outcome.usage['numTurns'], '1');
        expect(outcome.usage['harnessDurationMs'], '2400');
        expect(outcome.usage['model'], 'claude-haiku-4-5');
        expect(outcome.usage['describe_harness'], 'claude');
        expect(outcome.usage['describe_model'], 'haiku');
        expect(outcome.usage['describe_stop'], 'ok');
      },
    );

    test(
      'NO envelope on disk ⇒ stdout is the answer, and the stop outcome still '
      'lands',
      () async {
        final outcome = await _describe(
          workspaceDir: work.path,
          git: CannedGitRunner(),
          inference: FakeInferenceRunner(output: _answer, ok: false),
        );
        expect(outcome.source, 'fallback');
        expect(outcome.usage['describe_stop'], 'failed');
        expect(outcome.usage.containsKey('tokensIn'), isFalse);
      },
    );

    test('the manifest carries the circuit receipts the ROUTE threads in', () async {
      final inference = FakeInferenceRunner(output: _answer);
      await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(),
        inference: inference,
        receipts: const [
          DescribeReceipt(
            label: 'validation',
            nodePath: 'tg-1/land/revalidate',
            result: {'rc': '0'},
          ),
        ],
      );
      expect(
        inference.calls.single.args.last,
        contains('- validation: rc=0 [from `tg-1/land/revalidate`]'),
      );
    });
  });
}
