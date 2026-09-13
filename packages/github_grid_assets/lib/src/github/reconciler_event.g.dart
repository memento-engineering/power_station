// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reconciler_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorkflowRunFailedJob _$WorkflowRunFailedJobFromJson(
  Map<String, dynamic> json,
) => _WorkflowRunFailedJob(
  jobName: json['jobName'] as String,
  failedStepName: json['failedStepName'] as String?,
);

Map<String, dynamic> _$WorkflowRunFailedJobToJson(
  _WorkflowRunFailedJob instance,
) => <String, dynamic>{
  'jobName': instance.jobName,
  'failedStepName': instance.failedStepName,
};

IssueOpened _$IssueOpenedFromJson(Map<String, dynamic> json) => IssueOpened(
  nodeId: json['nodeId'] as String,
  actor: json['actor'] as String,
  repository: json['repository'] as String,
  substation: json['substation'] as String,
  observationId: json['observationId'] as String,
  number: (json['number'] as num).toInt(),
  title: json['title'] as String,
  body: json['body'] as String,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$IssueOpenedToJson(IssueOpened instance) =>
    <String, dynamic>{
      'nodeId': instance.nodeId,
      'actor': instance.actor,
      'repository': instance.repository,
      'substation': instance.substation,
      'observationId': instance.observationId,
      'number': instance.number,
      'title': instance.title,
      'body': instance.body,
      'runtimeType': instance.$type,
    };

PullRequestOpened _$PullRequestOpenedFromJson(Map<String, dynamic> json) =>
    PullRequestOpened(
      nodeId: json['nodeId'] as String,
      actor: json['actor'] as String,
      repository: json['repository'] as String,
      substation: json['substation'] as String,
      observationId: json['observationId'] as String,
      number: (json['number'] as num).toInt(),
      title: json['title'] as String,
      body: json['body'] as String,
      headRef: json['headRef'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$PullRequestOpenedToJson(PullRequestOpened instance) =>
    <String, dynamic>{
      'nodeId': instance.nodeId,
      'actor': instance.actor,
      'repository': instance.repository,
      'substation': instance.substation,
      'observationId': instance.observationId,
      'number': instance.number,
      'title': instance.title,
      'body': instance.body,
      'headRef': instance.headRef,
      'runtimeType': instance.$type,
    };

PullRequestFeedback _$PullRequestFeedbackFromJson(Map<String, dynamic> json) =>
    PullRequestFeedback(
      nodeId: json['nodeId'] as String,
      actor: json['actor'] as String,
      repository: json['repository'] as String,
      substation: json['substation'] as String,
      observationId: json['observationId'] as String,
      number: (json['number'] as num).toInt(),
      body: json['body'] as String,
      headBranch: json['headBranch'] as String,
      headSha: json['headSha'] as String,
      checkState: $enumDecode(
        _$PullRequestCheckStateEnumMap,
        json['checkState'],
      ),
      mergeability: $enumDecode(
        _$PullRequestMergeabilityEnumMap,
        json['mergeability'],
      ),
      openedAt: DateTime.parse(json['openedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      greenSince: json['greenSince'] == null
          ? null
          : DateTime.parse(json['greenSince'] as String),
      observedAt: DateTime.parse(json['observedAt'] as String),
      stalled: json['stalled'] as bool,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$PullRequestFeedbackToJson(
  PullRequestFeedback instance,
) => <String, dynamic>{
  'nodeId': instance.nodeId,
  'actor': instance.actor,
  'repository': instance.repository,
  'substation': instance.substation,
  'observationId': instance.observationId,
  'number': instance.number,
  'body': instance.body,
  'headBranch': instance.headBranch,
  'headSha': instance.headSha,
  'checkState': _$PullRequestCheckStateEnumMap[instance.checkState]!,
  'mergeability': _$PullRequestMergeabilityEnumMap[instance.mergeability]!,
  'openedAt': instance.openedAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'greenSince': instance.greenSince?.toIso8601String(),
  'observedAt': instance.observedAt.toIso8601String(),
  'stalled': instance.stalled,
  'runtimeType': instance.$type,
};

const _$PullRequestCheckStateEnumMap = {
  PullRequestCheckState.notReported: 'notReported',
  PullRequestCheckState.pending: 'pending',
  PullRequestCheckState.green: 'green',
  PullRequestCheckState.failing: 'failing',
  PullRequestCheckState.inconclusive: 'inconclusive',
};

const _$PullRequestMergeabilityEnumMap = {
  PullRequestMergeability.unknown: 'unknown',
  PullRequestMergeability.mergeable: 'mergeable',
  PullRequestMergeability.conflicting: 'conflicting',
};

CheckConcluded _$CheckConcludedFromJson(Map<String, dynamic> json) =>
    CheckConcluded(
      nodeId: json['nodeId'] as String,
      actor: json['actor'] as String,
      repository: json['repository'] as String,
      substation: json['substation'] as String,
      observationId: json['observationId'] as String,
      headBranch: json['headBranch'] as String,
      checkName: json['checkName'] as String,
      conclusion: json['conclusion'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$CheckConcludedToJson(CheckConcluded instance) =>
    <String, dynamic>{
      'nodeId': instance.nodeId,
      'actor': instance.actor,
      'repository': instance.repository,
      'substation': instance.substation,
      'observationId': instance.observationId,
      'headBranch': instance.headBranch,
      'checkName': instance.checkName,
      'conclusion': instance.conclusion,
      'runtimeType': instance.$type,
    };

WorkflowRunConcluded _$WorkflowRunConcludedFromJson(
  Map<String, dynamic> json,
) => WorkflowRunConcluded(
  nodeId: json['nodeId'] as String,
  actor: json['actor'] as String,
  repository: json['repository'] as String,
  substation: json['substation'] as String,
  observationId: json['observationId'] as String,
  runId: (json['runId'] as num).toInt(),
  runNumber: (json['runNumber'] as num).toInt(),
  workflowPath: json['workflowPath'] as String,
  workflowName: json['workflowName'] as String,
  event: json['event'] as String,
  headBranch: json['headBranch'] as String,
  headSha: json['headSha'] as String,
  conclusion: json['conclusion'] as String,
  htmlUrl: json['htmlUrl'] as String,
  failedJobs: (json['failedJobs'] as List<dynamic>)
      .map((e) => WorkflowRunFailedJob.fromJson(e as Map<String, dynamic>))
      .toList(),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$WorkflowRunConcludedToJson(
  WorkflowRunConcluded instance,
) => <String, dynamic>{
  'nodeId': instance.nodeId,
  'actor': instance.actor,
  'repository': instance.repository,
  'substation': instance.substation,
  'observationId': instance.observationId,
  'runId': instance.runId,
  'runNumber': instance.runNumber,
  'workflowPath': instance.workflowPath,
  'workflowName': instance.workflowName,
  'event': instance.event,
  'headBranch': instance.headBranch,
  'headSha': instance.headSha,
  'conclusion': instance.conclusion,
  'htmlUrl': instance.htmlUrl,
  'failedJobs': instance.failedJobs,
  'runtimeType': instance.$type,
};

IssueCommented _$IssueCommentedFromJson(Map<String, dynamic> json) =>
    IssueCommented(
      nodeId: json['nodeId'] as String,
      actor: json['actor'] as String,
      repository: json['repository'] as String,
      substation: json['substation'] as String,
      observationId: json['observationId'] as String,
      originatingBeadId: json['originatingBeadId'] as String,
      issueNodeId: json['issueNodeId'] as String,
      issueAuthor: json['issueAuthor'] as String,
      issueNumber: (json['issueNumber'] as num).toInt(),
      commentId: (json['commentId'] as num).toInt(),
      body: json['body'] as String,
      url: json['url'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$IssueCommentedToJson(IssueCommented instance) =>
    <String, dynamic>{
      'nodeId': instance.nodeId,
      'actor': instance.actor,
      'repository': instance.repository,
      'substation': instance.substation,
      'observationId': instance.observationId,
      'originatingBeadId': instance.originatingBeadId,
      'issueNodeId': instance.issueNodeId,
      'issueAuthor': instance.issueAuthor,
      'issueNumber': instance.issueNumber,
      'commentId': instance.commentId,
      'body': instance.body,
      'url': instance.url,
      'updatedAt': instance.updatedAt.toIso8601String(),
      'runtimeType': instance.$type,
    };

WatchedIssueStateChanged _$WatchedIssueStateChangedFromJson(
  Map<String, dynamic> json,
) => WatchedIssueStateChanged(
  nodeId: json['nodeId'] as String,
  actor: json['actor'] as String,
  repository: json['repository'] as String,
  substation: json['substation'] as String,
  observationId: json['observationId'] as String,
  originatingBeadId: json['originatingBeadId'] as String,
  issueNodeId: json['issueNodeId'] as String,
  issueAuthor: json['issueAuthor'] as String,
  issueNumber: (json['issueNumber'] as num).toInt(),
  change: $enumDecode(_$GitHubIssueWatchChangeEnumMap, json['change']),
  state: json['state'] as String,
  stateReason: json['stateReason'] as String?,
  locked: json['locked'] as bool,
  url: json['url'] as String?,
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$WatchedIssueStateChangedToJson(
  WatchedIssueStateChanged instance,
) => <String, dynamic>{
  'nodeId': instance.nodeId,
  'actor': instance.actor,
  'repository': instance.repository,
  'substation': instance.substation,
  'observationId': instance.observationId,
  'originatingBeadId': instance.originatingBeadId,
  'issueNodeId': instance.issueNodeId,
  'issueAuthor': instance.issueAuthor,
  'issueNumber': instance.issueNumber,
  'change': _$GitHubIssueWatchChangeEnumMap[instance.change]!,
  'state': instance.state,
  'stateReason': instance.stateReason,
  'locked': instance.locked,
  'url': instance.url,
  'updatedAt': instance.updatedAt.toIso8601String(),
  'runtimeType': instance.$type,
};

const _$GitHubIssueWatchChangeEnumMap = {
  GitHubIssueWatchChange.closedCompleted: 'closed_completed',
  GitHubIssueWatchChange.closedNotPlanned: 'closed_not_planned',
  GitHubIssueWatchChange.reopened: 'reopened',
  GitHubIssueWatchChange.locked: 'locked',
  GitHubIssueWatchChange.transferred: 'transferred',
  GitHubIssueWatchChange.deleted: 'deleted',
  GitHubIssueWatchChange.convertedToDiscussion: 'converted_to_discussion',
  GitHubIssueWatchChange.unreadable: 'unreadable',
};
