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
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
}
