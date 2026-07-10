// Track C — PinDiffCapability (the scope-pinning pre-critic step, bead pow-6wo).
//
// pin-diff computes the bead BRANCH'S OWN delta (`git diff origin/<base>...HEAD`)
// once, up front, and pins it as the critics' EXCLUSIVE review scope. An EMPTY
// delta — the live finding: a branch with ZERO commits beyond origin/main whose
// critics graded PRE-EXISTING mainline work A/B as if it were the bead's diff —
// routes to a human GATE instead of reaching the critics. A git error that
// leaves the scope UNKNOWN fails LOUD (never a silent gate). Zero live git — an
// injected canned runner (Fakes, not mocks) and a real temp workspace.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A canned [GitRunner]: returns a configured output per leading git subcommand
/// (`log` / `diff`), records every argv, and is settable to make the `diff`
/// probe FAIL. Mirrors [RecordingGitRunner]'s posture but with per-subcommand
/// output (that fake always returns empty output, which pin-diff reads as an
/// empty delta).
class _CannedGitRunner implements GitRunner {
  _CannedGitRunner({this.logOut = '', this.diffOut = '', this.diffOk = true});

  String logOut;
  String diffOut;
  bool diffOk;
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.of(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'diff') {
      return diffOk
          ? GitRunResult(exitCode: 0, output: diffOut)
          : const GitRunResult(
              exitCode: 128,
              output: 'fatal: bad revision origin/main...HEAD',
            );
    }
    return GitRunResult(exitCode: 0, output: sub == 'log' ? logOut : '');
  }
}

({FakeTreeContext context, StepArgs args}) _ctx(
  String workspaceDir, {
  String base = 'main',
}) => (
  context: FakeTreeContext(
    values: {
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
        baseBranch: base,
      ),
    },
  ),
  args: stepArgs('tg-1/review/pin-diff'),
);

void main() {
  group('Track C — PinDiffCapability (scope-pinning, bead pow-6wo)', () {
    test('runs `git log origin/<base>..HEAD` + `git diff origin/<base>...HEAD` '
        'in the workspace (two-dot log, three-dot diff)', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-argv-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 did the work',
        diffOut: '--- a/x\n+++ b/x\n+work',
      );
      final c = _ctx(dir.path);
      await PinDiffCapability(runner: runner).run(c.context, c.args);
      // `equals` for deep list comparison (a bare List matches by identity).
      expect(runner.calls, contains(equals(['log', '--oneline', 'origin/main..HEAD'])));
      expect(runner.calls, contains(equals(['diff', 'origin/main...HEAD'])));
    });

    test('a non-empty delta -> Ok with route-style provenance AND writes the '
        'pinned-diff file the critics read', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-ok-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 first\ndef456 second',
        diffOut: '--- a/x.dart\n+++ b/x.dart\n+final x = 1;',
      );
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {
        'base': 'origin/main',
        'commits': '2',
        'diffBytes': '${'--- a/x.dart\n+++ b/x.dart\n+final x = 1;'.length}',
      });
      // The pinned diff lands where each critic's prompt points it.
      final pinned = File(pinnedDiffPath(dir.path));
      expect(pinned.existsSync(), isTrue);
      final body = pinned.readAsStringSync();
      expect(body, contains('+final x = 1;'), reason: 'the raw diff body');
      expect(body, contains('abc123 first'), reason: 'the commit provenance header');
    });

    test('an EMPTY delta with ZERO commits -> Gate (the stale-bead terminal); '
        'no pinned diff is written', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-stale-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: '', diffOut: '');
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).run(c.context, c.args);
      expect(outcome, isA<Gate>());
      expect(
        (outcome as Gate).reason,
        contains('ZERO commits beyond origin/main'),
        reason: 'the exact live-finding condition, named for the human ruling',
      );
      expect(
        File(pinnedDiffPath(dir.path)).existsSync(),
        isFalse,
        reason: 'nothing to review -> no scope pinned',
      );
    });

    test('commits present but a net-EMPTY diff -> Gate (the no-op terminal)',
        () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-noop-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 add\ndef456 revert',
        diffOut: '   \n',
      );
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).run(c.context, c.args);
      expect(outcome, isA<Gate>());
      final reason = (outcome as Gate).reason;
      expect(reason, contains('2 commit'));
      expect(reason, contains('net'));
    });

    test('git cannot compute the delta -> Failed (LOUD), never a silent Gate '
        'that would masquerade as a stale bead', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-giterr-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(diffOk: false);
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).run(c.context, c.args);
      expect(outcome, isA<Failed>());
      final reason = (outcome as Failed).reason;
      expect(reason, contains('could not compute'));
      expect(reason, contains('bad revision'), reason: 'the git output tail');
    });

    test('no ambient Workspace -> Ok no-op (offline, never throws)', () async {
      final outcome = await const PinDiffCapability().run(
        FakeTreeContext(values: const {}),
        stepArgs('tg-1/review/pin-diff'),
      );
      expect(outcome, isA<Ok>());
    });

    test('a workspace dir that does not exist -> Ok no-op with NO git call '
        '(offline/dry-run posture, mirrors provisionWorkspace)', () async {
      final runner = _CannedGitRunner(diffOut: 'should never be read');
      final c = _ctx('/grid/worktrees/pin-diff-does-not-exist-tg-1');
      final outcome = await PinDiffCapability(runner: runner).run(c.context, c.args);
      expect(outcome, isA<Ok>());
      expect(runner.calls, isEmpty, reason: 'no worktree on disk -> no git run');
    });
  });
}
