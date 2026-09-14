// Track C — PinDiffCapability (the scope-pinning pre-critic step, bead pow-6wo).
//
// pin-diff computes the bead BRANCH'S OWN delta (`git diff origin/<base>...HEAD`)
// once, up front, and pins it as the critics' EXCLUSIVE review scope. An EMPTY
// delta — the live finding: a branch with ZERO commits beyond origin/main whose
// critics graded PRE-EXISTING mainline work A/B as if it were the bead's diff —
// routes to a human GATE instead of reaching the critics. A git error that
// leaves the scope UNKNOWN fails LOUD (never a silent gate). The scope-pinning
// group runs zero live git — an injected canned runner (Fakes, not mocks) and
// a real temp workspace; the checkout-root-guard group (bead pow-4pr) ALSO
// drives real git, because the flaw it pins (symlink-resolved vs lexical
// roots) only exists against a live `rev-parse`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A canned [GitRunner]: returns a configured output per leading git subcommand
/// (`log` / `diff`), records every argv, and is settable to make the `diff`
/// probe FAIL. Mirrors [RecordingGitRunner]'s posture but with per-subcommand
/// output (that fake always returns empty output, which pin-diff reads as an
/// empty delta).
class _CannedGitRunner implements GitRunner {
  _CannedGitRunner({
    this.logOut = '',
    this.diffOut = '',
    this.diffOk = true,
    this.statusOut = '',
    this.statusOk = true,
    this.toplevelOut,
    this.toplevelOk = true,
  });

  String logOut;
  String diffOut;
  bool diffOk;

  /// The `status --porcelain` answer; empty is a CLEAN worktree, which is what
  /// a genuinely stale bead leaves behind.
  String statusOut;
  bool statusOk;

  /// The `rev-parse --show-toplevel` answer; null ECHOES the call's
  /// `workingDirectory` — what real git reports when the dir IS the checkout
  /// root (the guard symlink-resolves both sides, so the echo compares equal).
  String? toplevelOut;
  bool toplevelOk;
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.of(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'rev-parse') {
      return toplevelOk
          ? GitRunResult(exitCode: 0, output: toplevelOut ?? workingDirectory)
          : const GitRunResult(
              exitCode: 128,
              output:
                  'fatal: not a git repository (or any of the parent '
                  'directories): .git',
            );
    }
    if (sub == 'diff') {
      return diffOk
          ? GitRunResult(exitCode: 0, output: diffOut)
          : const GitRunResult(
              exitCode: 128,
              output: 'fatal: bad revision origin/main...HEAD',
            );
    }
    if (sub == 'status') {
      return statusOk
          ? GitRunResult(exitCode: 0, output: statusOut)
          : const GitRunResult(
              exitCode: 128,
              output: 'fatal: not a git repository',
            );
    }
    return GitRunResult(exitCode: 0, output: sub == 'log' ? logOut : '');
  }
}

({FakeTreeContext context, StepArgs args}) _ctx(
  String workspaceDir, {
  String base = 'main',
  String? baseSha,
}) => (
  context: FakeTreeContext(
    values: {
      // Mounted DIRECTLY rather than through `testWorkspace`, which carries no
      // [Workspace.baseSha]: that field is what decides the review base, so a
      // round has to be able to arrive with one recorded and without one.
      Workspace: Workspace(
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
        baseBranch: base,
        baseSha: baseSha,
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
      await PinDiffCapability(runner: runner).route(c.context, c.args);
      // `equals` for deep list comparison (a bare List matches by identity).
      expect(
        runner.calls,
        contains(equals(['log', '--oneline', 'origin/main..HEAD'])),
      );
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
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect((outcome as Advance).payload, {
        'base': 'origin/main',
        'commits': '2',
        'diffBytes': '${'--- a/x.dart\n+++ b/x.dart\n+final x = 1;'.length}',
      });
      // The pinned diff lands where each critic's prompt points it.
      final pinned = File(pinnedDiffPath(dir.path));
      expect(pinned.existsSync(), isTrue);
      final body = pinned.readAsStringSync();
      expect(body, contains('+final x = 1;'), reason: 'the raw diff body');
      expect(
        body,
        contains('abc123 first'),
        reason: 'the commit provenance header',
      );
    });

    test('an EMPTY delta with ZERO commits -> Gate (the stale-bead terminal); '
        'no pinned diff is written', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-stale-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: '', diffOut: '');
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      expect(
        (outcome as Escalate).reason,
        contains('ZERO commits beyond origin/main'),
        reason: 'the exact live-finding condition, named for the human ruling',
      );
      expect(
        File(pinnedDiffPath(dir.path)).existsSync(),
        isFalse,
        reason: 'nothing to review -> no scope pinned',
      );
    });

    test(
      'commits present but a net-EMPTY diff -> Gate (the no-op terminal)',
      () async {
        final dir = Directory.systemTemp.createTempSync('pin-diff-noop-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final runner = _CannedGitRunner(
          logOut: 'abc123 add\ndef456 revert',
          diffOut: '   \n',
        );
        final c = _ctx(dir.path);
        final outcome = await PinDiffCapability(
          runner: runner,
        ).route(c.context, c.args);
        expect(outcome, isA<Escalate>());
        final reason = (outcome as Escalate).reason;
        expect(reason, contains('2 commit'));
        expect(reason, contains('net'));
      },
    );

    // The genesis-7ob round: the build agent implemented the whole bead, its
    // turn ended before the commit it had announced, and pin-diff ruled the
    // finished, validation-green worktree a 'stale/no-op bead'. ZERO commits
    // and a DIRTY tree are a third fact, and the human ruling must read it.
    for (final status in <String>[
      ' M packages/grid_assets/lib/src/code/committee.dart\n',
      '?? packages/grid_assets/lib/src/code/new_capability.dart\n',
    ]) {
      test('ZERO commits over a DIRTY worktree -> Gate naming the UNCOMMITTED '
          'work, never stale/no-op (status: ${status.trim()})', () async {
        final dir = Directory.systemTemp.createTempSync('pin-diff-dirty-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final runner = _CannedGitRunner(
          logOut: '',
          diffOut: '',
          statusOut: status,
        );
        final c = _ctx(dir.path);
        final outcome = await PinDiffCapability(
          runner: runner,
        ).route(c.context, c.args);
        expect(outcome, isA<Escalate>());
        final reason = (outcome as Escalate).reason;
        expect(reason, contains('uncommitted work present'));
        expect(
          reason,
          isNot(contains('stale/no-op')),
          reason: 'the exact wording that misled the live human ruling',
        );
        expect(runner.calls, contains(equals(['status', '--porcelain'])));
        expect(
          File(pinnedDiffPath(dir.path)).existsSync(),
          isFalse,
          reason: 'still nothing for the critics to review',
        );
      });
    }

    test('ZERO commits over a CLEAN worktree keeps the stale/no-op ruling, '
        'and the status probe is what proves it', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-clean-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: '', diffOut: '');
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      final reason = (outcome as Escalate).reason;
      expect(reason, contains('stale/no-op bead'));
      expect(reason, isNot(contains('uncommitted work present')));
      expect(runner.calls, contains(equals(['status', '--porcelain'])));
    });

    test('a COMMITTED net-empty branch keeps its no-op ruling and never reads '
        'the worktree status', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-noop-status-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 add\ndef456 revert',
        diffOut: '   \n',
        statusOut: ' M never-read.dart\n',
      );
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      expect((outcome as Escalate).reason, contains('no-op bead'));
      expect(
        runner.calls.where((call) => call.first == 'status'),
        isEmpty,
        reason: 'commits exist -> the tree state cannot change the ruling',
      );
    });

    test('an UNREADABLE worktree status -> a thrown RouteFailure (LOUD), never '
        'a guessed ruling about a tree nobody could read', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-statuserr-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: '', diffOut: '', statusOk: false);
      final c = _ctx(dir.path);
      await expectLater(
        PinDiffCapability(runner: runner).route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains('git status --porcelain'),
              contains('not a git repository'),
            ),
          ),
        ),
      );
    });

    test('git cannot compute the delta -> a thrown RouteFailure (LOUD), never '
        'a silent Escalate that would masquerade as a stale bead', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-giterr-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(diffOk: false);
      final c = _ctx(dir.path);
      // A route has NO failure arm: a throwing body is what RouteAllocation
      // sinks to supervision.
      await expectLater(
        PinDiffCapability(runner: runner).route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('could not compute'), contains('bad revision')),
          ),
        ),
      );
    });

    // The recorded review base (bead pow-5ljz). `origin/<base>` is a STAND-IN
    // for the commit the branch was cut from, and it stops being one when a
    // substation's local base branch runs ahead of its remote. When the
    // provisioner recorded the cut, THAT commit is the base — everywhere.
    const recordedSha = '7b225e8f0a1c2d3e4f5061728394a5b6c7d8e9f0';

    test('a recorded workspace base SHA replaces origin/<base> in BOTH the '
        'commit log and the three-dot diff', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-sha-argv-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 the round',
        diffOut: '--- a/x\n+++ b/x\n+round',
      );
      final c = _ctx(dir.path, baseSha: recordedSha);
      await PinDiffCapability(runner: runner).route(c.context, c.args);
      expect(
        runner.calls,
        contains(equals(['log', '--oneline', '$recordedSha..HEAD'])),
      );
      expect(runner.calls, contains(equals(['diff', '$recordedSha...HEAD'])));
      expect(
        runner.calls.any((call) => call.any((a) => a.contains('origin/main'))),
        isFalse,
        reason: 'ONE resolution feeds every probe — no site keeps the remote',
      );
    });

    test('a recorded workspace base SHA is the provenance the round REPORTS: '
        'the route payload and all three pinned header lines', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-sha-header-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 the round',
        diffOut: '--- a/x.dart\n+++ b/x.dart\n+final x = 1;',
      );
      final c = _ctx(dir.path, baseSha: recordedSha);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect((outcome as Advance).payload?['base'], recordedSha);
      final body = File(pinnedDiffPath(dir.path)).readAsStringSync();
      expect(
        body,
        contains('# Pinned review scope: grid/tg-1 vs $recordedSha'),
      );
      expect(body, contains('`git diff $recordedSha...HEAD`'));
      expect(body, contains('`git log $recordedSha..HEAD`'));
      expect(
        body,
        isNot(contains('origin/main')),
        reason: 'the artifact names the base it was ACTUALLY computed from',
      );
    });

    test('a recorded workspace base SHA is the base the human ruling is told '
        'about when the worktree is DIRTY over zero commits', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-sha-dirty-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: '',
        diffOut: '',
        statusOut: ' M lib/src/code/committee.dart\n',
      );
      final c = _ctx(dir.path, baseSha: recordedSha);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect(
        (outcome as Escalate).reason,
        allOf(
          contains('uncommitted work present'),
          contains('ZERO commits beyond $recordedSha'),
        ),
      );
    });

    test('a NULL workspace base SHA keeps origin/<base> in the route payload '
        'and in all three pinned header lines', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-nosha-header-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 the round',
        diffOut: '--- a/x.dart\n+++ b/x.dart\n+final x = 1;',
      );
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(
        runner: runner,
      ).route(c.context, c.args);
      expect((outcome as Advance).payload?['base'], 'origin/main');
      final body = File(pinnedDiffPath(dir.path)).readAsStringSync();
      expect(body, contains('# Pinned review scope: grid/tg-1 vs origin/main'));
      expect(body, contains('`git diff origin/main...HEAD`'));
      expect(body, contains('`git log origin/main..HEAD`'));
    });

    test(
      'no ambient Workspace -> Advance no-op (offline, never throws)',
      () async {
        final outcome = await const PinDiffCapability().route(
          FakeTreeContext(values: const {}),
          stepArgs('tg-1/review/pin-diff'),
        );
        expect(outcome, isA<Advance>());
      },
    );

    test(
      'a workspace dir that does not exist -> Advance no-op with NO git call '
      '(offline/dry-run posture, mirrors provisionWorkspace)',
      () async {
        final runner = _CannedGitRunner(diffOut: 'should never be read');
        final c = _ctx('/grid/worktrees/pin-diff-does-not-exist-tg-1');
        final outcome = await PinDiffCapability(
          runner: runner,
        ).route(c.context, c.args);
        expect(outcome, isA<Advance>());
        expect(
          runner.calls,
          isEmpty,
          reason: 'no worktree on disk -> no git run',
        );
      },
    );
  });

  group('Track C — the checkout-root guard (bead pow-4pr)', () {
    test('the guard probes `rev-parse --show-toplevel` FIRST — before any '
        'log/diff', () async {
      final dir = Directory.systemTemp.createTempSync('pin-guard-argv-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: 'abc123 work', diffOut: '+work');
      final c = _ctx(dir.path);
      await PinDiffCapability(runner: runner).route(c.context, c.args);
      expect(runner.calls.first, equals(['rev-parse', '--show-toplevel']));
    });

    test('a toplevel that is NOT the workspace dir -> a thrown RouteFailure '
        'naming BOTH roots, and the log/diff are WITHHELD (the space-ojl '
        'shape: git walked up to an ancestor checkout)', () async {
      final parent = Directory.systemTemp.createTempSync('pin-guard-parent-');
      addTearDown(() => parent.deleteSync(recursive: true));
      final child = Directory(p.join(parent.path, 'scaffold-only'))
        ..createSync();
      final runner = _CannedGitRunner(
        logOut: 'never read',
        diffOut: 'never read',
        toplevelOut: parent.path,
      );
      final c = _ctx(child.path);
      await expectLater(
        PinDiffCapability(runner: runner).route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains('resolved toplevel'),
              contains(Directory(parent.path).resolveSymbolicLinksSync()),
              contains('expected'),
              contains('false stale/no-op'),
            ),
          ),
        ),
      );
      expect(
        runner.calls,
        equals([
          ['rev-parse', '--show-toplevel'],
        ]),
        reason: 'a refused root never reaches log/diff',
      );
    });

    test('a failing probe (dir exists, no git anywhere) -> a thrown '
        'RouteFailure naming the sourceless-workspace cause', () async {
      final dir = Directory.systemTemp.createTempSync('pin-guard-nogit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(toplevelOk: false);
      final c = _ctx(dir.path);
      await expectLater(
        PinDiffCapability(runner: runner).route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('holds no git checkout'), contains('pow-2ts')),
          ),
        ),
      );
    });

    // REAL git below — the flaw this guard's comparison must survive is
    // empirical: `git rev-parse --show-toplevel` reports the SYMLINK-RESOLVED
    // root (`/private/tmp/...` on macOS) while the ambient workspace dir is
    // the unresolved `systemTemp` path. A lexical canonicalize reads those as
    // different roots and refuses every genuine checkout; only a live git can
    // pin that this comparison does not.
    test(
      'REAL git: a genuine checkout root under a symlinked temp parent '
      'advances and pins the diff (the comparison symlink-resolves)',
      () async {
        final origin = Directory.systemTemp.createTempSync('pin-real-origin-');
        final work = Directory.systemTemp.createTempSync('pin-real-work-');
        addTearDown(() => origin.deleteSync(recursive: true));
        addTearDown(() => work.deleteSync(recursive: true));
        _git(['init', '-q', '-b', 'main', '.'], origin.path);
        File(p.join(origin.path, 'f.txt')).writeAsStringSync('base\n');
        _git(['add', '.'], origin.path);
        _commit(origin.path, 'base');
        final clone = p.join(work.path, 'wt');
        _git(['clone', '-q', origin.path, clone], work.path);
        _git(['checkout', '-q', '-b', 'grid/tg-1'], clone);
        File(p.join(clone, 'f.txt')).writeAsStringSync('base\nchange\n');
        _commit(clone, 'change', all: true);

        final c = _ctx(clone);
        final outcome = await const PinDiffCapability().route(
          c.context,
          c.args,
        );
        expect(
          outcome,
          isA<Advance>(),
          reason:
              'a genuine root must never be refused as an ancestor mismatch',
        );
        expect(File(pinnedDiffPath(clone)).existsSync(), isTrue);
      },
    );

    test('REAL git: a scaffold dir INSIDE a parent checkout (the exact '
        'incident layout) -> RouteFailure naming the ancestor root', () async {
      final origin = Directory.systemTemp.createTempSync('pin-real-origin2-');
      final work = Directory.systemTemp.createTempSync('pin-real-work2-');
      addTearDown(() => origin.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));
      _git(['init', '-q', '-b', 'main', '.'], origin.path);
      File(p.join(origin.path, 'f.txt')).writeAsStringSync('base\n');
      _git(['add', '.'], origin.path);
      _commit(origin.path, 'base');
      final clone = p.join(work.path, 'wt');
      _git(['clone', '-q', origin.path, clone], work.path);
      // The sourceless-workspace shape: a scaffold-only dir nested in the
      // parent checkout — `git` resolves the PARENT as the toplevel.
      final scaffold = Directory(p.join(clone, '.grid', 'worktrees', 'tg-1'))
        ..createSync(recursive: true);
      File(p.join(scaffold.path, 'residue.json')).writeAsStringSync('{}');

      final c = _ctx(scaffold.path);
      await expectLater(
        const PinDiffCapability().route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains(Directory(clone).resolveSymbolicLinksSync()),
              contains('ancestor checkout'),
            ),
          ),
        ),
      );
    });

    test('REAL git: a dir outside any repository -> RouteFailure (sourceless '
        'workspace, never a wrong-tree diff)', () async {
      final dir = Directory.systemTemp.createTempSync('pin-real-plain-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(dir.path);
      await expectLater(
        const PinDiffCapability().route(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            contains('holds no git checkout'),
          ),
        ),
      );
    });
  });

  // The lunar_station-a7w shape (bead pow-5ljz), against REAL git: a substation
  // that hosts its own grid has a LOCAL base branch far ahead of its remote —
  // 55 unpushed commits on the live round — so `origin/<base>` names a commit
  // the branch was never cut from and the merge-base swallows every one of
  // them. Only a live git can pin that a recorded base SHA narrows the scope:
  // the merge-base arithmetic IS the mechanism.
  group('Track C — the recorded review base (bead pow-5ljz)', () {
    test('REAL git: recorded workspace base SHA excludes local-base '
        'housekeeping the round never authored', () async {
      final origin = Directory.systemTemp.createTempSync('pin-base-origin-');
      final work = Directory.systemTemp.createTempSync('pin-base-work-');
      addTearDown(() => origin.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));
      _git(['init', '-q', '-b', 'main', '.'], origin.path);
      File(p.join(origin.path, 'f.txt')).writeAsStringSync('shared\n');
      _git(['add', '.'], origin.path);
      _commit(origin.path, 'seed the shared mainline');

      final clone = p.join(work.path, 'wt');
      _git(['clone', '-q', origin.path, clone], work.path);

      // Local `main` runs ahead of `origin/main` with work the substation could
      // not push — the bead's branch is cut from the LOCAL tip, not the remote.
      File(p.join(clone, 'disc.txt')).writeAsStringSync('agent disc\n');
      _git(['add', '.'], clone);
      _commit(clone, 'untrack the agent disc');
      File(p.join(clone, 'telemetry.txt')).writeAsStringSync('scrubbed\n');
      _git(['add', '.'], clone);
      _commit(clone, 'scrub the telemetry capture');

      // What the provisioner records at cut time: the commit the worktree
      // actually starts on.
      final baseSha = _headSha(clone);

      _git(['checkout', '-q', '-b', 'grid/tg-1'], clone);
      File(p.join(clone, 'round.dart')).writeAsStringSync('final round = 1;\n');
      _git(['add', '.'], clone);
      _commit(clone, 'add the round file');

      // The control — the defect, reproduced: with no recorded base the pinned
      // scope reaches back to the shared merge-base and hands the critics the
      // substation's own housekeeping to grade.
      final remote = _ctx(clone);
      expect(
        await const PinDiffCapability().route(remote.context, remote.args),
        isA<Advance>(),
      );
      final unpinned = File(pinnedDiffPath(clone)).readAsStringSync();
      expect(unpinned, contains('untrack the agent disc'));
      expect(unpinned, contains('disc.txt'));

      final recorded = _ctx(clone, baseSha: baseSha);
      final outcome = await const PinDiffCapability().route(
        recorded.context,
        recorded.args,
      );
      expect(outcome, isA<Advance>());
      expect(
        (outcome as Advance).payload,
        containsPair('commits', '1'),
        reason: 'exactly the one commit this round authored',
      );
      final pinned = File(pinnedDiffPath(clone)).readAsStringSync();
      expect(pinned, contains('add the round file'));
      expect(pinned, contains('round.dart'));
      expect(pinned, contains('final round = 1;'));
      for (final housekeeping in const [
        'untrack the agent disc',
        'scrub the telemetry capture',
        'disc.txt',
        'telemetry.txt',
      ]) {
        expect(
          pinned,
          isNot(contains(housekeeping)),
          reason:
              'the round is graded on its own commit, never the substation'
              "'s unpushed local-main work: $housekeeping",
        );
      }
    });
  });
}

/// Reads `git rev-parse HEAD` in [cwd] — the commit a provisioner records at
/// cut time. Real-git test setup only.
String _headSha(String cwd) {
  final r = Process.runSync('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git rev-parse HEAD in $cwd failed (${r.exitCode}): ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

/// Runs `git` in [cwd], asserting success — real-git test setup only.
void _git(List<String> args, String cwd) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail(
      'git ${args.join(' ')} in $cwd failed (${r.exitCode}): '
      '${r.stderr}\n${r.stdout}',
    );
  }
}

/// Commits with a hermetic identity (no reliance on ambient git config).
void _commit(String cwd, String message, {bool all = false}) => _git([
  '-c',
  'user.name=pin-diff-test',
  '-c',
  'user.email=pin-diff-test@memento.engineering',
  'commit',
  '-q',
  if (all) '-am' else '-m',
  message,
], cwd);
