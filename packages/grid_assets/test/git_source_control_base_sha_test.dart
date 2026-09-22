// The `SourceControl.baseShaFor` seam (grid_engine 0.4.0-dev.2, the_grid#436):
// the committee pins its review diff to the exact commit the provisioner cut
// from, so the answer must be the PROVISION-TIME HEAD and never a re-probe of
// a moving ref.
//
// `GitSourceControl` delegates to grid_runtime's `StationGitRepository` — the
// station-lifetime projection that retains each provisioned worktree's base
// commit — so this suite drives REAL git over temp repos (the offline-
// integration posture `federated_grid_assets/test/git_sync_test.dart` already
// takes) rather than faking the one value under test.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'filing/real_bd_store.dart';

/// Workspace provisioning never opens a pull request.
final class _NoPrOpener implements PrOpener {
  const _NoPrOpener();

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => throw StateError('provisioning never opens a PR');
}

void main() {
  late Directory temp;
  late SystemGitRunner runner;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-assets-base-sha-');
    final home = Directory(p.join(temp.path, 'home'))..createSync();
    runner = SystemGitRunner(
      parentEnvironment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': home.path,
        'GIT_CONFIG_GLOBAL': p.join(home.path, '.gitconfig'),
        'GIT_AUTHOR_NAME': 'grid-test',
        'GIT_AUTHOR_EMAIL': 'grid-test@example.test',
        'GIT_COMMITTER_NAME': 'grid-test',
        'GIT_COMMITTER_EMAIL': 'grid-test@example.test',
      },
    );
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Future<String> git(String workingDirectory, List<String> args) async {
    final result = await runner.run(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (!result.ok) {
      throw StateError('git ${args.join(' ')} failed: ${result.output}');
    }
    return result.output.trim();
  }

  test('a provisioned worktree answers its provision-time HEAD, and an '
      'unprovisioned bead answers null', () async {
    final rootPath = p.join(temp.path, 'root');
    Directory(rootPath).createSync();
    await git(rootPath, const ['init', '--initial-branch=main']);
    File(p.join(rootPath, 'README.md')).writeAsStringSync('base\n');
    await git(rootPath, const ['add', '-A']);
    await git(rootPath, const ['commit', '-m', 'initial']);

    final repository = StationGitRepository(
      service: StationGitService(runner: runner, prOpener: const _NoPrOpener()),
    );
    addTearDown(repository.dispose);
    final sc = GitSourceControl(
      provisioner: repository,
      root: RootCheckout(
        path: rootPath,
        defaultBranch: 'main',
        substation: 'power_station',
      ),
      gitRunner: runner,
    );

    // Unknown before anything is cut — the contract's "does not know it".
    expect(sc.baseShaFor('pow-1'), isNull);

    await sc.provisionWorkspace(
      beadId: 'pow-1',
      workspaceDir: sc.workspaceFor('pow-1'),
    );

    final head = await git(sc.workspaceFor('pow-1'), const [
      'rev-parse',
      'HEAD',
    ]);
    expect(head, hasLength(40));
    expect(sc.baseShaFor('pow-1'), head);

    // A bead this station never provisioned is still unknown — never the last
    // answer, and never a fabricated sha.
    expect(sc.baseShaFor('pow-never-cut'), isNull);

    // The base is PINNED at cut time: a later commit on the root's mainline
    // does not move the answer.
    File(p.join(rootPath, 'README.md')).writeAsStringSync('moved\n');
    await git(rootPath, const ['add', '-A']);
    await git(rootPath, const ['commit', '-m', 'second']);
    expect(await git(rootPath, const ['rev-parse', 'HEAD']), isNot(head));
    expect(sc.baseShaFor('pow-1'), head);
  });

  test('the offline source control knows no base sha', () {
    const offline = GitSourceControl();

    expect(offline.baseShaFor('pow-1'), isNull);
  });

  // The BEAD-STORE ROUTING of a provisioned worktree (bead `pow-qsds`). The
  // subject is bd's own resolution walk, so these drive the REAL binary over
  // REAL git worktrees: a fake store seam cannot show which database `bd`
  // picks, and picking the wrong one is the whole defect.
  group('provisioned worktrees write where the repository root writes', () {
    test(
      'grid-home provisioning writes a relative redirect and bd info '
      'reports the primary store',
      () async {
        final repo = await _provisionedBdRepo(
          gridHome: true,
          runner: runner,
          git: git,
        );

        final redirect = File(p.join(repo.workspaceDir, '.beads', 'redirect'));
        expect(redirect.existsSync(), isTrue);
        final body = redirect.readAsStringSync();
        expect(body, endsWith('\n'));
        expect(
          p.isAbsolute(body.trim()),
          isFalse,
          reason:
              'bd documents the redirect as a RELATIVE path, and the tree '
              'it is written into may be archived or moved',
        );
        expect(
          p.canonicalize(p.join(repo.workspaceDir, body.trim())),
          p.canonicalize(p.join(repo.rootPath, '.beads')),
          reason: 'the target resolves against the WORKTREE ROOT',
        );

        final fromWorktree = await _bdInfo(repo.workspaceDir);
        final fromRoot = await _bdInfo(repo.rootPath);
        expect(fromWorktree['database_path'], fromRoot['database_path']);
        expect(fromWorktree['mode'], fromRoot['mode']);

        // A provision that dirties the tree would land in every bead's PR: bd's
        // own `.beads/.gitignore` excludes the redirect, and this is where that
        // stops being an assumption.
        final status = await git(repo.workspaceDir, const [
          'status',
          '--porcelain',
        ]);
        expect(status, isEmpty);
      },
      skip: skipWithoutBd,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'grid-home bd show reaches the work bead only with the '
      'redirect',
      () async {
        final repo = await _provisionedBdRepo(
          gridHome: true,
          runner: runner,
          git: git,
        );
        final redirect = File(p.join(repo.workspaceDir, '.beads', 'redirect'));

        final bound = await _bdShow(repo.workspaceDir);
        expect(
          bound.exitCode,
          0,
          reason:
              'the provisioned worktree reads the work bead: '
              '${bound.stdout}${bound.stderr}',
        );

        // The CONTROL: without the redirect the walk stops at the station's own
        // state store, and the work bead is not there. This is the measured
        // failure — `sql: no rows in result set` — not a hypothetical.
        redirect.deleteSync();
        final stranded = await _bdShow(repo.workspaceDir);
        expect(
          stranded.exitCode,
          isNot(0),
          reason: 'the grid home shadows the work store: ${stranded.stdout}',
        );
        // …and it fails for THE reason under repair. A bare non-zero exit
        // would also be satisfied by a broken fixture or an unrelated bd
        // error, so name the store: unbound, the worktree resolves the grid
        // home's STATE database, not the root's work store.
        final strandedInfo = await _bdInfo(repo.workspaceDir);
        expect(
          strandedInfo['database_path'],
          isNot((await _bdInfo(repo.rootPath))['database_path']),
          reason: 'the unbound worktree is bound to another database',
        );
        expect(
          strandedInfo['database_path'],
          contains(p.join('.grid', '.beads')),
          reason: 'and that database is the station state store',
        );

        // Adopting the same checkout re-binds it, so a worktree cut by an older
        // station arm is repaired on its next mount rather than only at cut.
        await repo.sourceControl.provisionWorkspace(
          beadId: _workBead,
          workspaceDir: repo.workspaceDir,
        );
        expect(redirect.existsSync(), isTrue);
        final rebound = await _bdShow(repo.workspaceDir);
        expect(
          rebound.exitCode,
          0,
          reason:
              'adoption restores the binding: '
              '${rebound.stdout}${rebound.stderr}',
        );
      },
      skip: skipWithoutBd,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'non-grid-home bd show reaches the work store with and without the '
      'redirect',
      () async {
        final repo = await _provisionedBdRepo(
          gridHome: false,
          runner: runner,
          git: git,
        );
        final redirect = File(p.join(repo.workspaceDir, '.beads', 'redirect'));
        expect(
          redirect.existsSync(),
          isTrue,
          reason:
              'the binding is unconditional — a repository with no grid '
              'home is bound too',
        );

        final bound = await _bdShow(repo.workspaceDir);
        expect(
          bound.exitCode,
          0,
          reason:
              'the redirect binds the work store: '
              '${bound.stdout}${bound.stderr}',
        );

        // Compatibility, not indifference: a repository with no store nested
        // above the worktree already resolved correctly by accident of the
        // walk, and the redirect must not change that answer.
        redirect.deleteSync();
        final unbound = await _bdShow(repo.workspaceDir);
        expect(
          unbound.exitCode,
          0,
          reason:
              'the walk still finds the only store there is: '
              '${unbound.stdout}${unbound.stderr}',
        );
      },
      skip: skipWithoutBd,
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}

/// The work bead the routing probes read — minted in the repository root's
/// store and reachable from the worktree ONLY through the redirect when the
/// repository is also a grid home.
const String _workBead = 'work-redirect';

/// A git repository carrying a real `.beads` WORK store, [gridHome] adding the
/// station's own `.grid/.beads` STATE store above the worktrees — the exact
/// nesting under which bd's resolution walk binds a worktree to the wrong
/// database — with one per-bead worktree provisioned through
/// [GitSourceControl].
///
/// The state store is minted FIRST because `bd init` refuses to initialize
/// under an ancestor that already holds one ("This workspace is already
/// initialized"), so `<repo>/.grid/.beads` can only exist if it predates
/// `<repo>/.beads`. Both are torn down by [bdStore]'s process census.
///
/// Every process here is given its working directory explicitly; nothing
/// reads or assigns [Directory.current]
/// (power_station#test-tree-package-root-is-source-located).
Future<({String rootPath, String workspaceDir, GitSourceControl sourceControl})>
_provisionedBdRepo({
  required bool gridHome,
  required SystemGitRunner runner,
  required Future<String> Function(String, List<String>) git,
}) async {
  final repo = Directory.systemTemp.createTempSync('grid-assets-redirect-');
  await git(repo.path, const ['init', '--initial-branch=main']);
  if (gridHome) {
    await bdStore(prefix: 'state', at: Directory(p.join(repo.path, '.grid')));
  }
  final work = await bdStore(prefix: 'work', at: repo);
  await runBd(work, const [
    'create',
    'redirect routing probe',
    '--id',
    _workBead,
    '--actor',
    'grid-test',
  ]);

  // The TRACKED scaffold — `.beads` minus its own ignores — so the provisioned
  // checkout carries exactly what a real worktree carries: config and
  // metadata, no database.
  File(p.join(repo.path, 'README.md')).writeAsStringSync('base\n');
  await git(repo.path, const ['add', 'README.md', '.beads']);
  await git(repo.path, const ['commit', '-m', 'initial']);

  final repository = StationGitRepository(
    service: StationGitService(runner: runner, prOpener: const _NoPrOpener()),
  );
  addTearDown(repository.dispose);
  final sourceControl = GitSourceControl(
    provisioner: repository,
    root: RootCheckout(
      path: repo.path,
      defaultBranch: 'main',
      substation: 'power_station',
    ),
    gitRunner: runner,
  );
  final workspaceDir = sourceControl.workspaceFor(_workBead);
  await sourceControl.provisionWorkspace(
    beadId: _workBead,
    workspaceDir: workspaceDir,
  );

  return (
    rootPath: repo.path,
    workspaceDir: workspaceDir,
    sourceControl: sourceControl,
  );
}

/// `bd show <work bead>` run from [workingDirectory], REPORTED rather than
/// asserted — the absent-redirect leg is a control that must fail.
///
/// Spawned IN that directory as well as pointed at it: `-C` is the subject
/// here — the walk it performs is what the redirect steers — but it is not the
/// isolation it reads as. Measured on bd 1.1.0, a `.beads/` redirect above the
/// SPAWNING process wins over `-C`, and this suite runs from a per-bead grid
/// worktree that has exactly one, so without the working directory this probe
/// answers out of the ambient checkout's store instead of the fixture's.
Future<ProcessResult> _bdShow(String workingDirectory) => Process.run(
  'bd',
  ['-C', workingDirectory, 'show', _workBead, '--json'],
  workingDirectory: workingDirectory,
  environment: {...Platform.environment, 'BD_NON_INTERACTIVE': '1'},
);

/// The `bd info --json` record bd answers from [workingDirectory].
///
/// Parses BOTH shapes: bare, and the `{schema_version, data}` envelope
/// `BD_JSON_ENVELOPE=1` produces — the station sets that variable, so a
/// developer's ambient environment decides which one arrives.
Future<Map<String, Object?>> _bdInfo(String workingDirectory) async {
  final result = await Process.run(
    'bd',
    ['-C', workingDirectory, 'info', '--json'],
    workingDirectory: workingDirectory,
    environment: {...Platform.environment, 'BD_NON_INTERACTIVE': '1'},
  );
  expect(
    result.exitCode,
    0,
    reason: 'bd info in $workingDirectory\n${result.stdout}\n${result.stderr}',
  );
  final decoded = jsonDecode(result.stdout as String);
  expect(decoded, isA<Map<String, Object?>>());
  final record = decoded as Map<String, Object?>;
  final data = record['data'];
  return data is Map<String, Object?> ? data : record;
}
