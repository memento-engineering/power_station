import 'package:grid_engine/grid_engine.dart';

import '../github/reconciler_event.dart';
import 'github_intake_store.dart';

/// Projects admitted GitHub-open events into deferred beads.
final class GitHubIntakeProjection {
  /// Creates the projection from engine trust and a bead store.
  const GitHubIntakeProjection({
    required Trust trust,
    required GitHubIntakeStore store,
  }) : _trust = trust,
       _store = store;

  final Trust _trust;
  final GitHubIntakeStore _store;

  /// Handles one normalized event; raw GitHub JSON never enters this seam.
  Future<void> call(NormalizedGitHubEvent event) async {
    final opened = switch (event) {
      IssueOpened() => event,
      PullRequestOpened() => event,
      CheckConcluded() => null,
    };
    if (opened == null) return;
    final actor = switch (opened) {
      IssueOpened(:final actor) => actor,
      PullRequestOpened(:final actor) => actor,
      CheckConcluded() => throw StateError('unreachable feedback event'),
    };
    final level = await _trust.levelOf(
      ActorIdentity(scheme: 'github', id: actor),
    );
    if (level != TrustLevel.self) return;
    final record = switch (opened) {
      IssueOpened(
        :final nodeId,
        :final repository,
        :final number,
        :final title,
        :final body,
      ) =>
        GitHubIntakeRecord(
          nodeId: nodeId,
          kind: 'issue',
          repository: repository,
          number: number,
          actor: actor,
          title: title,
          body: body,
        ),
      PullRequestOpened(
        :final nodeId,
        :final repository,
        :final number,
        :final title,
        :final body,
      ) =>
        GitHubIntakeRecord(
          nodeId: nodeId,
          kind: 'pull request',
          repository: repository,
          number: number,
          actor: actor,
          title: title,
          body: body,
        ),
      CheckConcluded() => throw StateError('unreachable feedback event'),
    };
    await _store.upsertDeferred(record);
  }
}
