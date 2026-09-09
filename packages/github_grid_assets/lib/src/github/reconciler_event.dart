import 'package:freezed_annotation/freezed_annotation.dart';

part 'reconciler_event.freezed.dart';
part 'reconciler_event.g.dart';

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

  /// A completed check run observed on a station branch.
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

  /// Decodes one normalized envelope; malformed shapes throw.
  factory NormalizedGitHubEvent.fromJson(Map<String, Object?> json) =>
      _$NormalizedGitHubEventFromJson(json);
}
