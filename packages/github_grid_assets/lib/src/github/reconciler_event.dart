import 'package:freezed_annotation/freezed_annotation.dart';

part 'reconciler_event.freezed.dart';
part 'reconciler_event.g.dart';

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

  /// A newly observed pull request.
  const factory NormalizedGitHubEvent.pullRequestOpened({
    required String nodeId,
    required String actor,
    required String repository,
    required String substation,
    required String observationId,
    required int number,
    required String title,
    required String body,
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

  /// Decodes one normalized envelope; malformed shapes throw.
  factory NormalizedGitHubEvent.fromJson(Map<String, Object?> json) =>
      _$NormalizedGitHubEventFromJson(json);
}
