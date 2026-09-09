import 'package:beads_dart/beads_dart.dart' show IssueType;
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final class FakeGitHubIntakeStore implements GitHubIntakeStore {
  final List<GitHubIntakeRecord> records = [];

  @override
  Future<void> upsert(GitHubIntakeRecord record) async {
    records.add(record);
  }
}

final class FailingTrust implements Trust {
  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) =>
      throw StateError('trust must not be consulted for feedback');
}

WorkflowRunIntakeRule nightlyRule({int priority = 1, bool approve = true}) =>
    WorkflowRunIntakeRule(
      workflowPath: '.github/workflows/ci.yaml',
      validationPlan: 'dart test',
      events: const {'schedule'},
      priority: priority,
      approve: approve,
    );

NormalizedGitHubEvent workflowRun({
  String repository = 'memento/power_station',
  String workflowPath = '.github/workflows/ci.yaml',
  String event = 'schedule',
  String headBranch = 'main',
  String conclusion = 'failure',
}) => NormalizedGitHubEvent.workflowRunConcluded(
  nodeId: 'WFR_1',
  actor: repository,
  repository: repository,
  substation: 'power_station',
  observationId: 'poll:run:WFR_1:2026-09-07T06:11:00Z:$conclusion',
  runId: 9001,
  runNumber: 128,
  workflowPath: workflowPath,
  workflowName: 'CI',
  event: event,
  headBranch: headBranch,
  headSha: 'abcdef0',
  conclusion: conclusion,
  htmlUrl: 'https://github.test/memento/power_station/actions/runs/9001',
  failedJobs: const [
    WorkflowRunFailedJob(jobName: 'test', failedStepName: 'dart test'),
  ],
);

NormalizedGitHubEvent issue({String actor = 'nico'}) =>
    NormalizedGitHubEvent.issueOpened(
      nodeId: 'I_1',
      actor: actor,
      repository: 'memento/power_station',
      substation: 'power_station',
      observationId: 'obs-1',
      number: 42,
      title: 'Issue title',
      body: 'Issue body',
    );

void main() {
  late FakeGitHubIntakeStore store;
  late GitHubIntakeProjection projection;

  setUp(() {
    store = FakeGitHubIntakeStore();
    projection = GitHubIntakeProjection(
      trust: GitHubSelfTrust(githubUser: 'nico'),
      store: store,
    );
  });

  test('projects a self-authored newly opened issue', () async {
    await projection(issue());

    expect(store.records, hasLength(1));
    expect(store.records.single.nodeId, 'I_1');
    expect(store.records.single.kind, 'issue');
  });

  test('projects a self-authored newly opened pull request', () async {
    await projection(
      const NormalizedGitHubEvent.pullRequestOpened(
        nodeId: 'PR_1',
        actor: 'nico',
        repository: 'memento/power_station',
        substation: 'power_station',
        observationId: 'obs-2',
        number: 43,
        title: 'PR title',
        body: 'PR body',
        headRef: 'grid/pow-1',
      ),
    );

    expect(store.records, hasLength(1));
    expect(store.records.single.nodeId, 'PR_1');
    expect(store.records.single.kind, 'pull request');
  });

  test('ignores every event from another actor', () async {
    await projection(issue(actor: 'somebody-else'));

    expect(store.records, isEmpty);
  });

  test('ignores check conclusions', () async {
    final feedbackProjection = GitHubIntakeProjection(
      trust: FailingTrust(),
      store: store,
    );
    await feedbackProjection(
      const NormalizedGitHubEvent.checkConcluded(
        nodeId: 'CHECK_1',
        actor: 'nico',
        repository: 'memento/power_station',
        substation: 'power_station',
        observationId: 'obs-3',
        headBranch: 'feature',
        checkName: 'test',
        conclusion: 'success',
      ),
    );

    expect(store.records, isEmpty);
  });

  group('workflow run', () {
    late GitHubIntakeProjection seat;

    setUp(() {
      seat = GitHubIntakeProjection(
        trust: GitHubSelfTrust(
          githubUser: 'nico',
          repository: 'memento/power_station',
        ),
        store: store,
        workflowRuns: [nightlyRule(priority: 0, approve: true)],
      );
    });

    test('files the seat\'s own matching failure as an approved bug', () async {
      await seat(workflowRun());

      final record = store.records.single;
      expect(record.kind, 'workflow run');
      expect(record.type, IssueType.bug);
      expect(record.priority, 0);
      expect(record.approve, isTrue);
      expect(record.externalRef, 'github:WFR_1');
      expect(
        record.beadTitle,
        '[GitHub workflow memento/power_station ci.yaml#128] '
        'CI failed on main (schedule)',
      );
      expect(record.description, contains('/actions/runs/9001'));
      expect(record.description, contains('Head sha: abcdef0'));
      expect(
        record.description,
        contains(
          '- test — first failed step: '
          'dart test',
        ),
      );
      expect(record.acceptanceCriteria, contains('test'));
      expect(record.acceptanceCriteria, contains('`dart test`'));
      expect(record.metadata['github.run_id'], '9001');
      expect(
        record.metadata['github.workflow_path'],
        '.github/workflows/ci.yaml',
      );
      expect(record.metadata['github.head_branch'], 'main');
      expect(record.metadata['github.head_sha'], 'abcdef0');
      expect(record.metadata['github.conclusion'], 'failure');
      expect(record.metadata['validation_plan'], 'dart test');
      expect(record.openDuplicateFilter, {
        'github.workflow_path': '.github/workflows/ci.yaml',
        'github.head_branch': 'main',
      });
    });

    test('the rule decides priority and the approval posture', () async {
      final quiet = GitHubIntakeProjection(
        trust: GitHubSelfTrust(
          githubUser: 'nico',
          repository: 'memento/power_station',
        ),
        store: store,
        workflowRuns: [nightlyRule(priority: 3, approve: false)],
      );
      await quiet(workflowRun());

      expect(store.records.single.priority, 3);
      expect(store.records.single.approve, isFalse);
    });

    test('a run no rule admits is never trusted, let alone filed', () async {
      final refusingTrust = GitHubIntakeProjection(
        trust: FailingTrust(),
        store: store,
        workflowRuns: [nightlyRule()],
      );
      await refusingTrust(workflowRun(event: 'pull_request'));
      await refusingTrust(workflowRun(conclusion: 'success'));
      await refusingTrust(
        workflowRun(workflowPath: '.github/workflows/release.yaml'),
      );
      await refusingTrust(workflowRun(headBranch: 'topic'));

      expect(store.records, isEmpty);
    });

    test('a run of ANOTHER repository is external and never filed', () async {
      await seat(workflowRun(repository: 'forker/power_station'));

      expect(store.records, isEmpty);
    });

    test('a seat with no declared rule files nothing', () async {
      final off = GitHubIntakeProjection(trust: FailingTrust(), store: store);
      await off(workflowRun());

      expect(store.records, isEmpty);
    });

    test('a non-default branch resolves through defaultBranch', () async {
      final release = GitHubIntakeProjection(
        trust: GitHubSelfTrust(
          githubUser: 'nico',
          repository: 'memento/power_station',
        ),
        store: store,
        workflowRuns: [nightlyRule()],
        defaultBranch: 'release',
      );
      await release(workflowRun(headBranch: 'main'));
      expect(store.records, isEmpty);
      await release(workflowRun(headBranch: 'release'));
      expect(store.records, hasLength(1));
    });

    test('a run with no failed job still names a falsifier', () async {
      await seat(
        const NormalizedGitHubEvent.workflowRunConcluded(
          nodeId: 'WFR_2',
          actor: 'memento/power_station',
          repository: 'memento/power_station',
          substation: 'power_station',
          observationId: 'poll:run:WFR_2:2026-09-07T06:11:00Z:timed_out',
          runId: 9002,
          runNumber: 129,
          workflowPath: '.github/workflows/ci.yaml',
          workflowName: 'CI',
          event: 'schedule',
          headBranch: 'main',
          headSha: 'beef',
          conclusion: 'timed_out',
          htmlUrl: 'https://github.test/runs/9002',
          failedJobs: <WorkflowRunFailedJob>[],
        ),
      );

      final record = store.records.single;
      expect(record.description, contains('no failed job'));
      expect(record.acceptanceCriteria, contains('CI'));
      expect(record.acceptanceCriteria, contains('`dart test`'));
    });
  });

  test('re-observation preserves the stable external reference', () async {
    await projection(issue());
    await projection(issue());

    expect(store.records, hasLength(2));
    expect(store.records.map((record) => record.externalRef).toSet(), {
      'github:I_1',
    });
  });
}
