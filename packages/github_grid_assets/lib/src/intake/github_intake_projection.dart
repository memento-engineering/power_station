import 'package:grid_engine/grid_engine.dart';

import '../code/workflow_run_intake_rule.dart';
import '../github/reconciler_event.dart';
import 'github_intake_store.dart';
import 'github_self_trust.dart';

/// Projects admitted GitHub events into intake beads.
///
/// Admission is the SAME predicate for every arm — [Trust] must answer
/// [TrustLevel.self] — but the identity differs by arm: an issue or a pull is
/// authored by a `github` login, while a workflow run has no human author and
/// is identified by the repository whose workflow file produced it.
final class GitHubIntakeProjection {
  /// Creates the projection from engine trust and a bead store.
  const GitHubIntakeProjection({
    required Trust trust,
    required GitHubIntakeStore store,
    List<WorkflowRunIntakeRule> workflowRuns = const <WorkflowRunIntakeRule>[],
    String defaultBranch = 'main',
  }) : _trust = trust,
       _store = store,
       _workflowRuns = workflowRuns,
       _defaultBranch = defaultBranch;

  final Trust _trust;
  final GitHubIntakeStore _store;
  final List<WorkflowRunIntakeRule> _workflowRuns;
  final String _defaultBranch;

  /// Handles one normalized event; raw GitHub JSON never enters this seam.
  Future<void> call(NormalizedGitHubEvent event) async {
    switch (event) {
      case CheckConcluded():
        return;
      // A watched OUTBOUND issue is projected onto the bead that CAUSED it,
      // not filed as fresh intake, so this seam returns from both arms.
      case IssueCommented() || WatchedIssueStateChanged():
        return;
      case IssueOpened() || PullRequestOpened():
        await _projectOpened(event);
      case WorkflowRunConcluded():
        await _projectWorkflowRun(event);
    }
  }

  Future<void> _projectOpened(NormalizedGitHubEvent opened) async {
    final actor = switch (opened) {
      IssueOpened(:final actor) => actor,
      PullRequestOpened(:final actor) => actor,
      _ => throw StateError('unreachable non-opened event'),
    };
    if (!await _isSelf(ActorIdentity(scheme: 'github', id: actor))) return;
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
      _ => throw StateError('unreachable non-opened event'),
    };
    await _store.upsert(record);
  }

  /// Files one concluded workflow run the seat's first matching rule admits.
  ///
  /// The rule is RESELECTED here rather than carried on the event: the event is
  /// the transport-neutral observation a future webhook decoder must also be
  /// able to produce, and it stays free of seat policy. Reselection is exact —
  /// both sides call [matchWorkflowRunRule] over the same declared list — so a
  /// run the poll leg admitted is admitted again here.
  Future<void> _projectWorkflowRun(WorkflowRunConcluded event) async {
    final rule = matchWorkflowRunRule(
      _workflowRuns,
      workflowPath: event.workflowPath,
      event: event.event,
      headBranch: event.headBranch,
      conclusion: event.conclusion,
      defaultBranch: _defaultBranch,
    );
    if (rule == null) return;
    final identity = ActorIdentity(
      scheme: kGitHubWorkflowScheme,
      id: event.repository,
    );
    if (!await _isSelf(identity)) return;
    await _store.upsert(
      GitHubIntakeRecord.workflowRun(
        nodeId: event.nodeId,
        repository: event.repository,
        runId: event.runId,
        runNumber: event.runNumber,
        workflowPath: event.workflowPath,
        workflowName: event.workflowName,
        event: event.event,
        headBranch: event.headBranch,
        headSha: event.headSha,
        conclusion: event.conclusion,
        htmlUrl: event.htmlUrl,
        failedJobs: event.failedJobs,
        validationPlan: rule.validationPlan,
        priority: rule.priority,
        approve: rule.approve,
      ),
    );
  }

  Future<bool> _isSelf(ActorIdentity actor) async =>
      await _trust.levelOf(actor) == TrustLevel.self;
}
