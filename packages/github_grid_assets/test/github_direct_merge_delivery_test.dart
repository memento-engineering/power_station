import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

class _Git implements GitRunner {
  final calls = <List<String>>[];
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final root = gitRootProbeAnswer(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (root != null) return root;
    calls.add(args);
    return const GitRunResult(exitCode: 0, output: '');
  }
}

class _Merge implements GitHubMergeRunner {
  _Merge(this.probe);
  final GitHubProtectionResult probe;
  @override
  Future<GitHubMergeResult> enableAutoMerge(
    String workDir,
    String prUrl,
  ) async => const GitHubMergeEnabled();
  @override
  Future<GitHubProtectionResult> protection(
    String workDir,
    String base,
  ) async => probe;
}

class _Flares implements ExplorationTransport {
  final events = <(String, Map<String, String>)>[];
  @override
  void flare(String name, Map<String, String> data) => events.add((name, data));
}

const request = DeliveryRequest(
  bead: Bead(id: 'work-1'),
  sessionId: 'session',
  nodePath: 'work-1/deliver',
  workspace: Workspace(
    workspaceDir: '/tmp',
    branch: 'grid/work-1',
    baseBranch: 'main',
  ),
);

void main() {
  test('lands an unprotected base with exact branch and base pushes', () async {
    final git = _Git();
    final outcome = await GitHubDirectMergeDelivery(
      gitOps: GitOps(git),
      gitRunner: git,
      mergeRunner: _Merge(const GitHubUnprotected()),
      policy: const DirectMergePolicy(),
    ).deliver(request);
    expect(outcome, isA<Ok>());
    expect(
      git.calls,
      contains(
        equals(['push', '--force-with-lease', '-u', 'origin', 'grid/work-1']),
      ),
    );
    expect(git.calls, contains(equals(['push', 'origin', 'grid/work-1:main'])));
    expect(
      git.calls.where((call) => call.contains('commit')).single.last,
      contains('Refs: work-1'),
    );
  });

  test(
    'protected base flares after retaining branch and before base mutation',
    () async {
      final git = _Git();
      final flares = _Flares();
      final outcome = await GitHubDirectMergeDelivery(
        gitOps: GitOps(git),
        gitRunner: git,
        mergeRunner: _Merge(const GitHubProtected()),
        policy: const DirectMergePolicy(),
        transport: flares,
      ).deliver(request);
      expect(outcome, isA<Failed>());
      expect(
        git.calls,
        contains(
          equals(['push', '--force-with-lease', '-u', 'origin', 'grid/work-1']),
        ),
      );
      expect(
        git.calls,
        isNot(contains(equals(['push', 'origin', 'grid/work-1:main']))),
      );
      expect(flares.events.single.$1, 'delivery.directMergeRefused');
      expect(flares.events.single.$2['reason'], 'base branch is protected');
    },
  );
}
