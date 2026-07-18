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
    this.toplevelOut,
    this.toplevelOk = true,
  });

  String logOut;
  String diffOut;
  bool diffOk;

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
      await PinDiffCapability(runner: runner).route(c.context, c.args);
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
      final outcome = await PinDiffCapability(runner: runner).route(c.context, c.args);
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
      expect(body, contains('abc123 first'), reason: 'the commit provenance header');
    });

    test('an EMPTY delta with ZERO commits -> Gate (the stale-bead terminal); '
        'no pinned diff is written', () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-stale-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(logOut: '', diffOut: '');
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).route(c.context, c.args);
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

    test('commits present but a net-EMPTY diff -> Gate (the no-op terminal)',
        () async {
      final dir = Directory.systemTemp.createTempSync('pin-diff-noop-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 add\ndef456 revert',
        diffOut: '   \n',
      );
      final c = _ctx(dir.path);
      final outcome = await PinDiffCapability(runner: runner).route(c.context, c.args);
      expect(outcome, isA<Escalate>());
      final reason = (outcome as Escalate).reason;
      expect(reason, contains('2 commit'));
      expect(reason, contains('net'));
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

    test('no ambient Workspace -> Advance no-op (offline, never throws)', () async {
      final outcome = await const PinDiffCapability().route(
        FakeTreeContext(values: const {}),
        stepArgs('tg-1/review/pin-diff'),
      );
      expect(outcome, isA<Advance>());
    });

    test('a workspace dir that does not exist -> Advance no-op with NO git call '
        '(offline/dry-run posture, mirrors provisionWorkspace)', () async {
      final runner = _CannedGitRunner(diffOut: 'should never be read');
      final c = _ctx('/grid/worktrees/pin-diff-does-not-exist-tg-1');
      final outcome = await PinDiffCapability(runner: runner).route(c.context, c.args);
      expect(outcome, isA<Advance>());
      expect(runner.calls, isEmpty, reason: 'no worktree on disk -> no git run');
    });
  });

  group('Track C — the checkout-root guard (bead pow-4pr)', () {
    test('the guard probes `rev-parse --show-toplevel` FIRST — before any '
        'log/diff', () async {
      final dir = Directory.systemTemp.createTempSync('pin-guard-argv-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = _CannedGitRunner(
        logOut: 'abc123 work',
        diffOut: '+work',
      );
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
    test('REAL git: a genuine checkout root under a symlinked temp parent '
        'advances and pins the diff (the comparison symlink-resolves)', () async {
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
      final outcome = await const PinDiffCapability().route(c.context, c.args);
      expect(
        outcome,
        isA<Advance>(),
        reason: 'a genuine root must never be refused as an ancestor mismatch',
      );
      expect(File(pinnedDiffPath(clone)).existsSync(), isTrue);
    });

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
}

/// Runs `git` in [cwd], asserting success — real-git test setup only.
void _git(List<String> args, String cwd) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} in $cwd failed (${r.exitCode}): '
        '${r.stderr}\n${r.stdout}');
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
