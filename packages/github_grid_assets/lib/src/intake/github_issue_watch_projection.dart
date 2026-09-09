import 'package:grid_engine/grid_engine.dart';

import '../github/issue_watch.dart';
import '../github/reconciler_event.dart';
import 'github_intake_store.dart';

/// The delivery-leg name under which [GitHubIssueWatchProjection] is
/// registered.
///
/// Its OWN durable acknowledgement key beside `ci-feedback`: the outbox records
/// it against a pending observation once this leg returns, so a replay after a
/// crash never appends the same reply to a bead twice, and a failure in one leg
/// never re-drives the other.
const String kGitHubIssueWatchDeliveryLeg = 'issue-watch';

/// Projects observations on WATCHED OUTBOUND issues onto the beads that caused
/// them.
///
/// Ownership is asked of the EXISTING [Trust] and asked about ONE identity: the
/// issue's AUTHOR. That is the only question with an answer — an issue in a
/// repository we do not control, and every maintainer replying on it, is
/// external — and the whole point of the watch is to hear from those external
/// voices. Promoting a commenter's authority would invert the feature.
///
/// Nothing here approves anything. The self-approval authority the seat holds
/// is workflow-run-only, so a watch observation lands its bead OPEN and
/// unstamped, exactly where human issue and pull intake leaves one.
final class GitHubIssueWatchProjection {
  /// Creates the projection over existing trust and the existing intake store.
  const GitHubIssueWatchProjection({
    required Trust trust,
    required GitHubIntakeStore store,
  }) : _trust = trust,
       _store = store;

  final Trust _trust;
  final GitHubIntakeStore _store;

  /// Handles one normalized event; raw GitHub JSON never enters this seam.
  Future<void> call(NormalizedGitHubEvent event) async {
    switch (event) {
      // Intake and CI feedback own these; the arms are listed so the sealed
      // union keeps the disjointness a COMPILE error to break.
      case IssueOpened() ||
          PullRequestOpened() ||
          CheckConcluded() ||
          WorkflowRunConcluded():
        return;
      case IssueCommented():
        await _project(
          event,
          issueAuthor: event.issueAuthor,
          update: GitHubIssueWatchUpdate(
            beadId: event.originatingBeadId,
            repository: event.repository,
            issueNumber: event.issueNumber,
            issueNodeId: event.issueNodeId,
            observationId: event.observationId,
            actor: event.actor,
            change: kIssueWatchCommentedChange,
            // A comment observes no state, so it asserts none: the
            // `github.watch.state` the last transition wrote stands.
            state: null,
            stateReason: null,
            updatedAt: event.updatedAt,
            url: event.url.isEmpty ? null : event.url,
            headline: 'new comment from @${event.actor}',
            detail: event.body,
          ),
        );
      case WatchedIssueStateChanged():
        await _project(
          event,
          issueAuthor: event.issueAuthor,
          update: GitHubIssueWatchUpdate(
            beadId: event.originatingBeadId,
            repository: event.repository,
            issueNumber: event.issueNumber,
            issueNodeId: event.issueNodeId,
            observationId: event.observationId,
            actor: event.actor,
            change: event.change.wire,
            state: event.state,
            stateReason: event.stateReason,
            updatedAt: event.updatedAt,
            url: event.url,
            headline: _headline(event.change, locked: event.locked),
            detail: _detail(event),
          ),
        );
    }
  }

  Future<void> _project(
    NormalizedGitHubEvent event, {
    required String issueAuthor,
    required GitHubIssueWatchUpdate update,
  }) async {
    final level = await _trust.levelOf(
      ActorIdentity(scheme: 'github', id: issueAuthor),
    );
    // NOT ours: an issue somebody else opened is somebody else's to answer,
    // and its bead id would name work this seat never did.
    if (level != TrustLevel.self) return;
    await _store.appendIssueWatch(update);
  }

  String _headline(GitHubIssueWatchChange change, {required bool locked}) =>
      switch (change) {
        GitHubIssueWatchChange.closedCompleted => 'closed as completed',
        GitHubIssueWatchChange.closedNotPlanned => 'closed as not planned',
        GitHubIssueWatchChange.reopened => 'reopened',
        GitHubIssueWatchChange.locked => locked ? 'locked' : 'unlocked',
        GitHubIssueWatchChange.transferred =>
          'transferred to another '
              'repository',
        GitHubIssueWatchChange.deleted => 'deleted',
        GitHubIssueWatchChange.convertedToDiscussion =>
          'converted to a discussion',
        GitHubIssueWatchChange.unreadable => 'no longer readable',
      };

  String _detail(WatchedIssueStateChanged event) => switch (event.change) {
    GitHubIssueWatchChange.transferred =>
      'The issue no longer lives at these coordinates; this watch stops here.',
    GitHubIssueWatchChange.deleted =>
      'GitHub reports the issue as gone; this watch stops here.',
    GitHubIssueWatchChange.convertedToDiscussion =>
      'The thread continues as a discussion; this watch stops here.',
    GitHubIssueWatchChange.unreadable =>
      'GitHub answered 404 — the repository may have gone private. The watch '
          'keeps asking for the issue until access returns.',
    _ =>
      'The issue is now ${event.state}'
          '${event.stateReason == null ? '' : ' (${event.stateReason})'}'
          '${event.locked ? ' and locked' : ''}.',
  };
}
