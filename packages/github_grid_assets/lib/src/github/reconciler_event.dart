import 'package:freezed_annotation/freezed_annotation.dart';

import 'issue_watch.dart';

part 'reconciler_event.freezed.dart';
part 'reconciler_event.g.dart';

/// The AGGREGATE state of every check run GitHub reported for one pull
/// request's head commit.
///
/// One state for the whole head, never one per check: a pull whose `analyze`
/// job is green while its `test` job is still running is NOT green, and the
/// per-check envelope this replaces said it was. The five values are a total,
/// disjoint partition of the shapes GitHub can answer with.
enum PullRequestCheckState {
  /// GitHub listed NO check run for the head commit.
  ///
  /// Distinct from [green] on purpose: "nobody has reported yet" and "everybody
  /// reported success" are the same empty-failure set and opposite facts, and
  /// collapsing them is exactly how an unchecked head merges.
  notReported,

  /// At least one run has not completed, and none completed badly.
  pending,

  /// The head has runs, every one of them completed, and every one of them
  /// concluded `success`.
  ///
  /// Deliberately strict: a `neutral`, `skipped` or `stale` completion is NOT
  /// a success, so a head carrying one is [inconclusive] rather than green.
  /// Over-reporting green is the failure that costs a merge; under-reporting it
  /// costs one human glance.
  green,

  /// At least one run completed `failure`, `timed_out`, `cancelled` or
  /// `action_required`.
  ///
  /// Outranks [pending]: a head with one red job and one still running has
  /// already failed, and waiting to say so only delays the rework.
  failing,

  /// Every run completed, none badly, and not all successfully.
  inconclusive,
}

/// Whether GitHub could merge the pull request when it was observed.
enum PullRequestMergeability {
  /// GitHub has not finished computing mergeability (`mergeable: null`).
  unknown,

  /// GitHub reports the pull request merges cleanly.
  mergeable,

  /// GitHub reports a conflict with the base branch.
  conflicting,
}

/// One job of a concluded workflow run that did NOT succeed.
///
/// [failedStepName] is the FIRST step the job reported as failed or timed out,
/// and is null when GitHub reported no such step — a job cancelled before any
/// step ran has nothing to name, and inventing one would be a lie in the bead
/// an agent reads.
@freezed
abstract class WorkflowRunFailedJob with _$WorkflowRunFailedJob {
  /// Creates one failed-job summary.
  const factory WorkflowRunFailedJob({
    required String jobName,
    String? failedStepName,
  }) = _WorkflowRunFailedJob;

  /// Decodes one failed-job summary; malformed shapes throw.
  factory WorkflowRunFailedJob.fromJson(Map<String, Object?> json) =>
      _$WorkflowRunFailedJobFromJson(json);
}

/// One transport-neutral GitHub observation consumed by projection siblings.
///
/// Trust and issue/PR projection belong to the intake sibling; check-result,
/// rework, and landing projection belong to the feedback sibling. A future
/// webhook decoder supplies this same envelope without changing projections.
@freezed
sealed class NormalizedGitHubEvent with _$NormalizedGitHubEvent {
  /// A newly observed issue.
  const factory NormalizedGitHubEvent.issueOpened({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required int number,
    required String title,
    required String body,
  }) = IssueOpened;

  /// A newly observed pull request, carrying the head ref of its full
  /// `/pulls/{number}` resource (the issues row alone has no `head`).
  const factory NormalizedGitHubEvent.pullRequestOpened({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required int number,
    required String title,
    required String body,
    required String headRef,
  }) = PullRequestOpened;

  /// The feedback state of ONE OPEN pull request, on ANY branch.
  ///
  /// The envelope the governor is informed through. It carries no attribution:
  /// WHICH bead this pull belongs to is resolved downstream from an EXPLICIT
  /// reference — a `Refs:` body trailer or a `gh-<number>` external ref — and
  /// never from [headBranch], which is a naming convention, not a database.
  /// A pull nothing can attribute is still emitted, because silence is the
  /// defect this arm exists to remove.
  ///
  /// [greenSince] is the latest successful check completion for [headSha], and
  /// is non-null EXACTLY when [checkState] is [PullRequestCheckState.green].
  /// [stalled] is that instant plus `kPullRequestGreenStallBound` having
  /// passed by [observedAt] — an OBSERVATION, carrying no merge policy.
  const factory NormalizedGitHubEvent.pullRequestFeedback({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required int number,
    required String body,
    required String headBranch,
    required String headSha,
    required PullRequestCheckState checkState,
    required PullRequestMergeability mergeability,
    required DateTime openedAt,
    required DateTime updatedAt,
    required DateTime? greenSince,
    required DateTime observedAt,
    required bool stalled,
  }) = PullRequestFeedback;

  /// A completed check run observed on a station branch — the LEGACY per-check
  /// envelope, superseded by [PullRequestFeedback].
  ///
  /// Retained for exactly one reason: a cursor document written before the
  /// feedback poll changed shape may still hold one of these PENDING, and
  /// dropping the arm would make that document undecodable and wedge the seat.
  /// Nothing emits it any more.
  const factory NormalizedGitHubEvent.checkConcluded({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required String headBranch,
    required String checkName,
    required String conclusion,
  }) = CheckConcluded;

  /// A completed workflow run observed on the repository itself.
  ///
  /// [actor] is `OWNER/REPOSITORY` rather than a login: a run has no human
  /// author, and the identity that matters for trust is WHOSE workflow file
  /// produced it. [failedJobs] carries only the jobs that concluded badly.
  const factory NormalizedGitHubEvent.workflowRunConcluded({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required int runId,
    required int runNumber,
    required String workflowPath,
    required String workflowName,
    required String event,
    required String headBranch,
    required String headSha,
    required String conclusion,
    required String htmlUrl,
    required List<WorkflowRunFailedJob> failedJobs,
  }) = WorkflowRunConcluded;

  /// A comment observed on a WATCHED outbound issue.
  ///
  /// [nodeId] is the COMMENT's node id and [actor] is whoever wrote it — a
  /// third-party maintainer, most of the time. The issue's own identity rides
  /// [issueNodeId] / [issueAuthor] / [issueNumber] beside them, because
  /// ownership of the watch is decided by who opened the ISSUE, never by who
  /// replied to it. [originatingBeadId] is the bead the observation lands on.
  ///
  /// Free of trust, approval and lane policy: an installed-repository watch
  /// and a foreign one emit exactly this envelope, and so must a later webhook
  /// decoder.
  const factory NormalizedGitHubEvent.issueCommented({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required String originatingBeadId,
    required String issueNodeId,
    required String issueAuthor,
    required int issueNumber,
    required int commentId,
    required String body,
    required String url,
    required DateTime updatedAt,
  }) = IssueCommented;

  /// A state transition observed on a WATCHED outbound issue.
  ///
  /// [nodeId] is the TRANSITION's identity — the timeline event's node id, or
  /// the issue's own node id for a transition only the issue resource or an
  /// HTTP status could report. [state] and [stateReason] are the issue's
  /// CURRENT values, [locked] its current lock, and [change] names what
  /// happened. [url] is null when the transition has no addressable page.
  const factory NormalizedGitHubEvent.watchedIssueStateChanged({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required String originatingBeadId,
    required String issueNodeId,
    required String issueAuthor,
    required int issueNumber,
    required GitHubIssueWatchChange change,
    required String state,
    required String? stateReason,
    required bool locked,
    required String? url,
    required DateTime updatedAt,
  }) = WatchedIssueStateChanged;

  /// Decodes one normalized envelope; malformed shapes throw.
  factory NormalizedGitHubEvent.fromJson(Map<String, Object?> json) =>
      _$NormalizedGitHubEventFromJson(json);
}
