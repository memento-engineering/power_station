// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FencedAgentSteer _$FencedAgentSteerFromJson(Map<String, dynamic> json) =>
    _FencedAgentSteer(
      commandId: json['commandId'] as String,
      attemptId: json['attemptId'] as String,
      instanceFence: json['instanceFence'] as String,
      text: json['text'] as String,
    );

Map<String, dynamic> _$FencedAgentSteerToJson(_FencedAgentSteer instance) =>
    <String, dynamic>{
      'commandId': instance.commandId,
      'attemptId': instance.attemptId,
      'instanceFence': instance.instanceFence,
      'text': instance.text,
    };
