// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reconciler_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
