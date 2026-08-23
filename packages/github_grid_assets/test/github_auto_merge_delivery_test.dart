import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _Git implements GitRunner {
  final calls = <List<String>>[];
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(args);
    return const GitRunResult(exitCode: 0, output: '');
  }
}

class _Pr implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.opened(
    const PullRequestRef(url: 'https://github.test/pr/1'),
  );
}

class _Merge implements GitHubMergeRunner {
  _Merge(this.result);
  final GitHubMergeResult result;
  var calls = 0;
  @override
  Future<GitHubMergeResult> enableAutoMerge(
    String workDir,
    String prUrl,
  ) async {
    calls++;
    return result;
  }

  @override
  Future<GitHubProtectionResult> protection(
    String workDir,
    String base,
  ) async => const GitHubUnprotected();
}

class _Flares implements ExplorationTransport {
  final events = <(String, Map<String, String>)>[];
  @override
  void flare(String name, Map<String, String> data) => events.add((name, data));
}

DeliveryRequest _request(Map<String, String> payload) => DeliveryRequest(
  bead: const Bead(id: 'work-1'),
  sessionId: 'session',
  nodePath: 'work-1/deliver',
  workspace: const Workspace(
    workspaceDir: '/tmp',
    branch: 'grid/work-1',
    baseBranch: 'main',
  ),
  payload: payload,
);

GitHubPrDelivery _pr(_Git git) =>
    GitHubPrDelivery(gitOps: GitOps(git), prOpener: _Pr(), gitRunner: git);

void main() {
  test('system runner invokes queue-compatible gh argv exactly', () async {
    final dir = Directory.systemTemp.createTempSync('github-merge-runner-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final log = File('${dir.path}/argv');
    final executable = File('${dir.path}/fake-gh')
      ..writeAsStringSync('#!/bin/sh\nprintf "%s\\n" "\$@" > "${log.path}"\n');
    await Process.run('chmod', ['+x', executable.path]);
    final result = await SystemGitHubMergeRunner(
      executable: executable.path,
    ).enableAutoMerge(dir.path, 'https://github.test/pr/1');
    expect(result, isA<GitHubMergeEnabled>());
    expect(log.readAsLinesSync(), [
      'pr',
      'merge',
      'https://github.test/pr/1',
      '--auto',
    ]);
  });

  test('enables native auto-merge after opening a qualifying PR', () async {
    final git = _Git();
    final merge = _Merge(const GitHubMergeEnabled());
    final outcome =
        await GitHubAutoMergeDelivery(
              prDelivery: _pr(git),
              runner: merge,
              policy: const PrAutoMergePolicy(),
            ).deliver(
              _request(const {
                'validation_rc': '0',
                'committee_grades': 'code-validation=B',
              }),
            )
            as Ok;
    expect(outcome.payload!['auto_merge'], 'enabled');
    expect(merge.calls, 1);
  });

  test(
    'a C preserves the PR, names and flares the fallback, and never polls',
    () async {
      final git = _Git();
      final merge = _Merge(const GitHubMergeEnabled());
      final flares = _Flares();
      final outcome =
          await GitHubAutoMergeDelivery(
                prDelivery: _pr(git),
                runner: merge,
                policy: const PrAutoMergePolicy(),
                transport: flares,
              ).deliver(
                _request(const {
                  'validation_rc': '0',
                  'committee_grades': 'spec-adherence=C',
                }),
              )
              as Ok;
      expect(outcome.payload!['pr_url'], 'https://github.test/pr/1');
      expect(
        outcome.payload!['auto_merge_reason'],
        'spec-adherence=C is below B',
      );
      expect(merge.calls, 0);
      expect(flares.events.single.$1, 'delivery.autoMergeFallback');
      expect(flares.events.single.$2['reason'], 'spec-adherence=C is below B');
    },
  );

  test('API refusal falls back loudly', () async {
    final git = _Git();
    final flares = _Flares();
    final outcome =
        await GitHubAutoMergeDelivery(
              prDelivery: _pr(git),
              runner: _Merge(const GitHubMergeRefused('auto-merge disabled')),
              policy: const PrAutoMergePolicy(),
              transport: flares,
            ).deliver(
              _request(const {
                'validation_rc': '0',
                'committee_grades': 'code-validation=A',
              }),
            )
            as Ok;
    expect(outcome.payload!['auto_merge'], 'fallback-pr-no-merge');
    expect(flares.events.single.$2['reason'], 'auto-merge disabled');
  });
}
