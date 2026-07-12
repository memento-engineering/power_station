// The DESCRIBE pass (bead pow-8dx) — the one-shot inference over the branch
// delta, its two fail-safe guards, and the harness invocation it renders.
// Offline: a canned GitRunner + a fake InferenceRunner; the only real I/O is a
// temp dir (the guard reads `Directory.existsSync`).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
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
    '"body":"The land step reads the branch delta.","breakingChange":""}';

Future<DescribeOutcome> _describe({
  required String workspaceDir,
  GitRunner? git,
  InferenceRunner? inference,
  PrComposition composition = const PrComposition(),
  Bead? beadOverride,
}) => describeBranch(
  bead: beadOverride ?? bead('tg-1'),
  beadId: 'tg-1',
  workspace: testWorkspace(
    'tg-1',
    workspaceDir: workspaceDir,
    branch: 'grid/tg-1',
    baseBranch: 'main',
  ),
  composition: composition,
  ambient: const AgentConfig(),
  registry: buildAgentHarnessRegistry(),
  git: git,
  inference: inference,
);

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('pow8dx'));
  tearDown(() => work.deleteSync(recursive: true));

  group('the two FAIL-SAFE guards (no real git, no real claude, ever)', () {
    test(
      'no InferenceRunner wired (a bare `const LandCapability()`) ⇒ the '
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

  group('the happy path — inference over the ACTUAL delta', () {
    test(
      'reads the branch delta, renders the harness invocation with the CHEAP '
      'model, and parses the answer',
      () async {
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
        expect(outcome.commits.total, 1);
        expect(outcome.commits.compliant, 1);
        expect(outcome.commits.trailered, 1);

        // The branch's OWN delta: the three-dot merge-base range
        // PinDiffCapability pins the critics to, and the NUL-separated log the
        // lint reads.
        expect(git.calls[0], [
          'log',
          '--format=%s%n%b%x00',
          'origin/main..HEAD',
        ]);
        expect(git.calls[1], ['diff', '--stat', 'origin/main...HEAD']);
        expect(git.calls[2], ['diff', 'origin/main...HEAD']);

        // The harness (the SAME one the critics ride) rendered a one-shot claude
        // invocation on the cheap model, carrying the diff in its prompt.
        final invocation = inference.calls.single;
        expect(invocation.command, 'claude');
        expect(invocation.args, containsAllInOrder(<String>['--model', 'haiku']));
        expect(invocation.workDir, work.path);
        expect(invocation.args.last, contains('+the change'));
        expect(
          invocation.args.last,
          contains('NEVER write the tracker id `tg-1`'),
        );
      },
    );

    test("the composition's model is a knob", () async {
      final inference = FakeInferenceRunner(output: _answer);
      await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(diff: 'a diff'),
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
          git: CannedGitRunner(diff: 'a diff'),
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
        expect(inference.calls.single.command, 'claude');
      },
    );
  });

  group('every failure path falls back — a land NEVER fails over PR prose', () {
    test('a failing `git diff` ⇒ fallback, but the commit lint still lands', () async {
      final outcome = await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(log: 'wip\x00', diff: 'fatal', diffOk: false),
        inference: _ExplodingInferenceRunner(),
      );
      expect(outcome.source, 'fallback');
      expect(outcome.commits.total, 1);
      expect(outcome.commits.compliant, 0);
    });

    test('an EMPTY delta ⇒ fallback, no inference spent', () async {
      final outcome = await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(diff: '   '),
        inference: _ExplodingInferenceRunner(),
      );
      expect(outcome.source, 'fallback');
    });

    test('a non-zero inference run, or unparseable output, ⇒ fallback', () async {
      final failed = await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(diff: 'a diff'),
        inference: FakeInferenceRunner(output: _answer, ok: false),
      );
      expect(failed.source, 'fallback');
      final garbage = await _describe(
        workspaceDir: work.path,
        git: CannedGitRunner(diff: 'a diff'),
        inference: FakeInferenceRunner(output: 'I refuse.'),
      );
      expect(garbage.source, 'fallback');
    });
  });
}
