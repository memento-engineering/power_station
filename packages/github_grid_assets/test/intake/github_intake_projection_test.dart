import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final class FakeGitHubIntakeStore implements GitHubIntakeStore {
  final List<GitHubIntakeRecord> records = [];

  @override
  Future<void> upsertDeferred(GitHubIntakeRecord record) async {
    records.add(record);
  }
}

final class FailingTrust implements Trust {
  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) =>
      throw StateError('trust must not be consulted for feedback');
}

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
        headBranch: 'feature',
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

  test('re-observation preserves the stable external reference', () async {
    await projection(issue());
    await projection(issue());

    expect(store.records, hasLength(2));
    expect(store.records.map((record) => record.externalRef).toSet(), {
      'github:I_1',
    });
  });
}
