// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reconciler_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorkflowRunFailedJob {

 String get jobName; String? get failedStepName;
/// Create a copy of WorkflowRunFailedJob
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowRunFailedJobCopyWith<WorkflowRunFailedJob> get copyWith => _$WorkflowRunFailedJobCopyWithImpl<WorkflowRunFailedJob>(this as WorkflowRunFailedJob, _$identity);

  /// Serializes this WorkflowRunFailedJob to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowRunFailedJob&&(identical(other.jobName, jobName) || other.jobName == jobName)&&(identical(other.failedStepName, failedStepName) || other.failedStepName == failedStepName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,jobName,failedStepName);

@override
String toString() {
  return 'WorkflowRunFailedJob(jobName: $jobName, failedStepName: $failedStepName)';
}


}

/// @nodoc
abstract mixin class $WorkflowRunFailedJobCopyWith<$Res>  {
  factory $WorkflowRunFailedJobCopyWith(WorkflowRunFailedJob value, $Res Function(WorkflowRunFailedJob) _then) = _$WorkflowRunFailedJobCopyWithImpl;
@useResult
$Res call({
 String jobName, String? failedStepName
});




}
/// @nodoc
class _$WorkflowRunFailedJobCopyWithImpl<$Res>
    implements $WorkflowRunFailedJobCopyWith<$Res> {
  _$WorkflowRunFailedJobCopyWithImpl(this._self, this._then);

  final WorkflowRunFailedJob _self;
  final $Res Function(WorkflowRunFailedJob) _then;

/// Create a copy of WorkflowRunFailedJob
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jobName = null,Object? failedStepName = freezed,}) {
  return _then(_self.copyWith(
jobName: null == jobName ? _self.jobName : jobName // ignore: cast_nullable_to_non_nullable
as String,failedStepName: freezed == failedStepName ? _self.failedStepName : failedStepName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowRunFailedJob].
extension WorkflowRunFailedJobPatterns on WorkflowRunFailedJob {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowRunFailedJob value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowRunFailedJob() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowRunFailedJob value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowRunFailedJob():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowRunFailedJob value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowRunFailedJob() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String jobName,  String? failedStepName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowRunFailedJob() when $default != null:
return $default(_that.jobName,_that.failedStepName);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String jobName,  String? failedStepName)  $default,) {final _that = this;
switch (_that) {
case _WorkflowRunFailedJob():
return $default(_that.jobName,_that.failedStepName);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String jobName,  String? failedStepName)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowRunFailedJob() when $default != null:
return $default(_that.jobName,_that.failedStepName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkflowRunFailedJob implements WorkflowRunFailedJob {
  const _WorkflowRunFailedJob({required this.jobName, this.failedStepName});
  factory _WorkflowRunFailedJob.fromJson(Map<String, dynamic> json) => _$WorkflowRunFailedJobFromJson(json);

@override final  String jobName;
@override final  String? failedStepName;

/// Create a copy of WorkflowRunFailedJob
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowRunFailedJobCopyWith<_WorkflowRunFailedJob> get copyWith => __$WorkflowRunFailedJobCopyWithImpl<_WorkflowRunFailedJob>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkflowRunFailedJobToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowRunFailedJob&&(identical(other.jobName, jobName) || other.jobName == jobName)&&(identical(other.failedStepName, failedStepName) || other.failedStepName == failedStepName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,jobName,failedStepName);

@override
String toString() {
  return 'WorkflowRunFailedJob(jobName: $jobName, failedStepName: $failedStepName)';
}


}

/// @nodoc
abstract mixin class _$WorkflowRunFailedJobCopyWith<$Res> implements $WorkflowRunFailedJobCopyWith<$Res> {
  factory _$WorkflowRunFailedJobCopyWith(_WorkflowRunFailedJob value, $Res Function(_WorkflowRunFailedJob) _then) = __$WorkflowRunFailedJobCopyWithImpl;
@override @useResult
$Res call({
 String jobName, String? failedStepName
});




}
/// @nodoc
class __$WorkflowRunFailedJobCopyWithImpl<$Res>
    implements _$WorkflowRunFailedJobCopyWith<$Res> {
  __$WorkflowRunFailedJobCopyWithImpl(this._self, this._then);

  final _WorkflowRunFailedJob _self;
  final $Res Function(_WorkflowRunFailedJob) _then;

/// Create a copy of WorkflowRunFailedJob
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jobName = null,Object? failedStepName = freezed,}) {
  return _then(_WorkflowRunFailedJob(
jobName: null == jobName ? _self.jobName : jobName // ignore: cast_nullable_to_non_nullable
as String,failedStepName: freezed == failedStepName ? _self.failedStepName : failedStepName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

NormalizedGitHubEvent _$NormalizedGitHubEventFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'issueOpened':
          return IssueOpened.fromJson(
            json
          );
                case 'pullRequestOpened':
          return PullRequestOpened.fromJson(
            json
          );
                case 'checkConcluded':
          return CheckConcluded.fromJson(
            json
          );
                case 'workflowRunConcluded':
          return WorkflowRunConcluded.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'NormalizedGitHubEvent',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$NormalizedGitHubEvent {

 String get nodeId; String get actor; String get repository; String get substation; String get observationId;
/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NormalizedGitHubEventCopyWith<NormalizedGitHubEvent> get copyWith => _$NormalizedGitHubEventCopyWithImpl<NormalizedGitHubEvent>(this as NormalizedGitHubEvent, _$identity);

  /// Serializes this NormalizedGitHubEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NormalizedGitHubEvent&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.observationId, observationId) || other.observationId == observationId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,nodeId,actor,repository,substation,observationId);

@override
String toString() {
  return 'NormalizedGitHubEvent(nodeId: $nodeId, actor: $actor, repository: $repository, substation: $substation, observationId: $observationId)';
}


}

/// @nodoc
abstract mixin class $NormalizedGitHubEventCopyWith<$Res>  {
  factory $NormalizedGitHubEventCopyWith(NormalizedGitHubEvent value, $Res Function(NormalizedGitHubEvent) _then) = _$NormalizedGitHubEventCopyWithImpl;
@useResult
$Res call({
 String nodeId, String actor, String repository, String substation, String observationId
});




}
/// @nodoc
class _$NormalizedGitHubEventCopyWithImpl<$Res>
    implements $NormalizedGitHubEventCopyWith<$Res> {
  _$NormalizedGitHubEventCopyWithImpl(this._self, this._then);

  final NormalizedGitHubEvent _self;
  final $Res Function(NormalizedGitHubEvent) _then;

/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? actor = null,Object? repository = null,Object? substation = null,Object? observationId = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String,substation: null == substation ? _self.substation : substation // ignore: cast_nullable_to_non_nullable
as String,observationId: null == observationId ? _self.observationId : observationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [NormalizedGitHubEvent].
extension NormalizedGitHubEventPatterns on NormalizedGitHubEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IssueOpened value)?  issueOpened,TResult Function( PullRequestOpened value)?  pullRequestOpened,TResult Function( CheckConcluded value)?  checkConcluded,TResult Function( WorkflowRunConcluded value)?  workflowRunConcluded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IssueOpened() when issueOpened != null:
return issueOpened(_that);case PullRequestOpened() when pullRequestOpened != null:
return pullRequestOpened(_that);case CheckConcluded() when checkConcluded != null:
return checkConcluded(_that);case WorkflowRunConcluded() when workflowRunConcluded != null:
return workflowRunConcluded(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IssueOpened value)  issueOpened,required TResult Function( PullRequestOpened value)  pullRequestOpened,required TResult Function( CheckConcluded value)  checkConcluded,required TResult Function( WorkflowRunConcluded value)  workflowRunConcluded,}){
final _that = this;
switch (_that) {
case IssueOpened():
return issueOpened(_that);case PullRequestOpened():
return pullRequestOpened(_that);case CheckConcluded():
return checkConcluded(_that);case WorkflowRunConcluded():
return workflowRunConcluded(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IssueOpened value)?  issueOpened,TResult? Function( PullRequestOpened value)?  pullRequestOpened,TResult? Function( CheckConcluded value)?  checkConcluded,TResult? Function( WorkflowRunConcluded value)?  workflowRunConcluded,}){
final _that = this;
switch (_that) {
case IssueOpened() when issueOpened != null:
return issueOpened(_that);case PullRequestOpened() when pullRequestOpened != null:
return pullRequestOpened(_that);case CheckConcluded() when checkConcluded != null:
return checkConcluded(_that);case WorkflowRunConcluded() when workflowRunConcluded != null:
return workflowRunConcluded(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body)?  issueOpened,TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body,  String headRef)?  pullRequestOpened,TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  String headBranch,  String checkName,  String conclusion)?  checkConcluded,TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int runId,  int runNumber,  String workflowPath,  String workflowName,  String event,  String headBranch,  String headSha,  String conclusion,  String htmlUrl,  List<WorkflowRunFailedJob> failedJobs)?  workflowRunConcluded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IssueOpened() when issueOpened != null:
return issueOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body);case PullRequestOpened() when pullRequestOpened != null:
return pullRequestOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body,_that.headRef);case CheckConcluded() when checkConcluded != null:
return checkConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.headBranch,_that.checkName,_that.conclusion);case WorkflowRunConcluded() when workflowRunConcluded != null:
return workflowRunConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.runId,_that.runNumber,_that.workflowPath,_that.workflowName,_that.event,_that.headBranch,_that.headSha,_that.conclusion,_that.htmlUrl,_that.failedJobs);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body)  issueOpened,required TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body,  String headRef)  pullRequestOpened,required TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  String headBranch,  String checkName,  String conclusion)  checkConcluded,required TResult Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int runId,  int runNumber,  String workflowPath,  String workflowName,  String event,  String headBranch,  String headSha,  String conclusion,  String htmlUrl,  List<WorkflowRunFailedJob> failedJobs)  workflowRunConcluded,}) {final _that = this;
switch (_that) {
case IssueOpened():
return issueOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body);case PullRequestOpened():
return pullRequestOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body,_that.headRef);case CheckConcluded():
return checkConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.headBranch,_that.checkName,_that.conclusion);case WorkflowRunConcluded():
return workflowRunConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.runId,_that.runNumber,_that.workflowPath,_that.workflowName,_that.event,_that.headBranch,_that.headSha,_that.conclusion,_that.htmlUrl,_that.failedJobs);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body)?  issueOpened,TResult? Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int number,  String title,  String body,  String headRef)?  pullRequestOpened,TResult? Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  String headBranch,  String checkName,  String conclusion)?  checkConcluded,TResult? Function( String nodeId,  String actor,  String repository,  String substation,  String observationId,  int runId,  int runNumber,  String workflowPath,  String workflowName,  String event,  String headBranch,  String headSha,  String conclusion,  String htmlUrl,  List<WorkflowRunFailedJob> failedJobs)?  workflowRunConcluded,}) {final _that = this;
switch (_that) {
case IssueOpened() when issueOpened != null:
return issueOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body);case PullRequestOpened() when pullRequestOpened != null:
return pullRequestOpened(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.number,_that.title,_that.body,_that.headRef);case CheckConcluded() when checkConcluded != null:
return checkConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.headBranch,_that.checkName,_that.conclusion);case WorkflowRunConcluded() when workflowRunConcluded != null:
return workflowRunConcluded(_that.nodeId,_that.actor,_that.repository,_that.substation,_that.observationId,_that.runId,_that.runNumber,_that.workflowPath,_that.workflowName,_that.event,_that.headBranch,_that.headSha,_that.conclusion,_that.htmlUrl,_that.failedJobs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class IssueOpened implements NormalizedGitHubEvent {
  const IssueOpened({required this.nodeId, required this.actor, required this.repository, required this.substation, required this.observationId, required this.number, required this.title, required this.body, final  String? $type}): $type = $type ?? 'issueOpened';
  factory IssueOpened.fromJson(Map<String, dynamic> json) => _$IssueOpenedFromJson(json);

@override final  String nodeId;
@override final  String actor;
@override final  String repository;
@override final  String substation;
@override final  String observationId;
 final  int number;
 final  String title;
 final  String body;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IssueOpenedCopyWith<IssueOpened> get copyWith => _$IssueOpenedCopyWithImpl<IssueOpened>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IssueOpenedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IssueOpened&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.observationId, observationId) || other.observationId == observationId)&&(identical(other.number, number) || other.number == number)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,nodeId,actor,repository,substation,observationId,number,title,body);

@override
String toString() {
  return 'NormalizedGitHubEvent.issueOpened(nodeId: $nodeId, actor: $actor, repository: $repository, substation: $substation, observationId: $observationId, number: $number, title: $title, body: $body)';
}


}

/// @nodoc
abstract mixin class $IssueOpenedCopyWith<$Res> implements $NormalizedGitHubEventCopyWith<$Res> {
  factory $IssueOpenedCopyWith(IssueOpened value, $Res Function(IssueOpened) _then) = _$IssueOpenedCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String actor, String repository, String substation, String observationId, int number, String title, String body
});




}
/// @nodoc
class _$IssueOpenedCopyWithImpl<$Res>
    implements $IssueOpenedCopyWith<$Res> {
  _$IssueOpenedCopyWithImpl(this._self, this._then);

  final IssueOpened _self;
  final $Res Function(IssueOpened) _then;

/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? actor = null,Object? repository = null,Object? substation = null,Object? observationId = null,Object? number = null,Object? title = null,Object? body = null,}) {
  return _then(IssueOpened(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String,substation: null == substation ? _self.substation : substation // ignore: cast_nullable_to_non_nullable
as String,observationId: null == observationId ? _self.observationId : observationId // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class PullRequestOpened implements NormalizedGitHubEvent {
  const PullRequestOpened({required this.nodeId, required this.actor, required this.repository, required this.substation, required this.observationId, required this.number, required this.title, required this.body, required this.headRef, final  String? $type}): $type = $type ?? 'pullRequestOpened';
  factory PullRequestOpened.fromJson(Map<String, dynamic> json) => _$PullRequestOpenedFromJson(json);

@override final  String nodeId;
@override final  String actor;
@override final  String repository;
@override final  String substation;
@override final  String observationId;
 final  int number;
 final  String title;
 final  String body;
 final  String headRef;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PullRequestOpenedCopyWith<PullRequestOpened> get copyWith => _$PullRequestOpenedCopyWithImpl<PullRequestOpened>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PullRequestOpenedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PullRequestOpened&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.observationId, observationId) || other.observationId == observationId)&&(identical(other.number, number) || other.number == number)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.headRef, headRef) || other.headRef == headRef));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,nodeId,actor,repository,substation,observationId,number,title,body,headRef);

@override
String toString() {
  return 'NormalizedGitHubEvent.pullRequestOpened(nodeId: $nodeId, actor: $actor, repository: $repository, substation: $substation, observationId: $observationId, number: $number, title: $title, body: $body, headRef: $headRef)';
}


}

/// @nodoc
abstract mixin class $PullRequestOpenedCopyWith<$Res> implements $NormalizedGitHubEventCopyWith<$Res> {
  factory $PullRequestOpenedCopyWith(PullRequestOpened value, $Res Function(PullRequestOpened) _then) = _$PullRequestOpenedCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String actor, String repository, String substation, String observationId, int number, String title, String body, String headRef
});




}
/// @nodoc
class _$PullRequestOpenedCopyWithImpl<$Res>
    implements $PullRequestOpenedCopyWith<$Res> {
  _$PullRequestOpenedCopyWithImpl(this._self, this._then);

  final PullRequestOpened _self;
  final $Res Function(PullRequestOpened) _then;

/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? actor = null,Object? repository = null,Object? substation = null,Object? observationId = null,Object? number = null,Object? title = null,Object? body = null,Object? headRef = null,}) {
  return _then(PullRequestOpened(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String,substation: null == substation ? _self.substation : substation // ignore: cast_nullable_to_non_nullable
as String,observationId: null == observationId ? _self.observationId : observationId // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,headRef: null == headRef ? _self.headRef : headRef // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class CheckConcluded implements NormalizedGitHubEvent {
  const CheckConcluded({required this.nodeId, required this.actor, required this.repository, required this.substation, required this.observationId, required this.headBranch, required this.checkName, required this.conclusion, final  String? $type}): $type = $type ?? 'checkConcluded';
  factory CheckConcluded.fromJson(Map<String, dynamic> json) => _$CheckConcludedFromJson(json);

@override final  String nodeId;
@override final  String actor;
@override final  String repository;
@override final  String substation;
@override final  String observationId;
 final  String headBranch;
 final  String checkName;
 final  String conclusion;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckConcludedCopyWith<CheckConcluded> get copyWith => _$CheckConcludedCopyWithImpl<CheckConcluded>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CheckConcludedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckConcluded&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.observationId, observationId) || other.observationId == observationId)&&(identical(other.headBranch, headBranch) || other.headBranch == headBranch)&&(identical(other.checkName, checkName) || other.checkName == checkName)&&(identical(other.conclusion, conclusion) || other.conclusion == conclusion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,nodeId,actor,repository,substation,observationId,headBranch,checkName,conclusion);

@override
String toString() {
  return 'NormalizedGitHubEvent.checkConcluded(nodeId: $nodeId, actor: $actor, repository: $repository, substation: $substation, observationId: $observationId, headBranch: $headBranch, checkName: $checkName, conclusion: $conclusion)';
}


}

/// @nodoc
abstract mixin class $CheckConcludedCopyWith<$Res> implements $NormalizedGitHubEventCopyWith<$Res> {
  factory $CheckConcludedCopyWith(CheckConcluded value, $Res Function(CheckConcluded) _then) = _$CheckConcludedCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String actor, String repository, String substation, String observationId, String headBranch, String checkName, String conclusion
});




}
/// @nodoc
class _$CheckConcludedCopyWithImpl<$Res>
    implements $CheckConcludedCopyWith<$Res> {
  _$CheckConcludedCopyWithImpl(this._self, this._then);

  final CheckConcluded _self;
  final $Res Function(CheckConcluded) _then;

/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? actor = null,Object? repository = null,Object? substation = null,Object? observationId = null,Object? headBranch = null,Object? checkName = null,Object? conclusion = null,}) {
  return _then(CheckConcluded(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String,substation: null == substation ? _self.substation : substation // ignore: cast_nullable_to_non_nullable
as String,observationId: null == observationId ? _self.observationId : observationId // ignore: cast_nullable_to_non_nullable
as String,headBranch: null == headBranch ? _self.headBranch : headBranch // ignore: cast_nullable_to_non_nullable
as String,checkName: null == checkName ? _self.checkName : checkName // ignore: cast_nullable_to_non_nullable
as String,conclusion: null == conclusion ? _self.conclusion : conclusion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class WorkflowRunConcluded implements NormalizedGitHubEvent {
  const WorkflowRunConcluded({required this.nodeId, required this.actor, required this.repository, required this.substation, required this.observationId, required this.runId, required this.runNumber, required this.workflowPath, required this.workflowName, required this.event, required this.headBranch, required this.headSha, required this.conclusion, required this.htmlUrl, required final  List<WorkflowRunFailedJob> failedJobs, final  String? $type}): _failedJobs = failedJobs,$type = $type ?? 'workflowRunConcluded';
  factory WorkflowRunConcluded.fromJson(Map<String, dynamic> json) => _$WorkflowRunConcludedFromJson(json);

@override final  String nodeId;
@override final  String actor;
@override final  String repository;
@override final  String substation;
@override final  String observationId;
 final  int runId;
 final  int runNumber;
 final  String workflowPath;
 final  String workflowName;
 final  String event;
 final  String headBranch;
 final  String headSha;
 final  String conclusion;
 final  String htmlUrl;
 final  List<WorkflowRunFailedJob> _failedJobs;
 List<WorkflowRunFailedJob> get failedJobs {
  if (_failedJobs is EqualUnmodifiableListView) return _failedJobs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_failedJobs);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowRunConcludedCopyWith<WorkflowRunConcluded> get copyWith => _$WorkflowRunConcludedCopyWithImpl<WorkflowRunConcluded>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkflowRunConcludedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowRunConcluded&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.observationId, observationId) || other.observationId == observationId)&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.runNumber, runNumber) || other.runNumber == runNumber)&&(identical(other.workflowPath, workflowPath) || other.workflowPath == workflowPath)&&(identical(other.workflowName, workflowName) || other.workflowName == workflowName)&&(identical(other.event, event) || other.event == event)&&(identical(other.headBranch, headBranch) || other.headBranch == headBranch)&&(identical(other.headSha, headSha) || other.headSha == headSha)&&(identical(other.conclusion, conclusion) || other.conclusion == conclusion)&&(identical(other.htmlUrl, htmlUrl) || other.htmlUrl == htmlUrl)&&const DeepCollectionEquality().equals(other._failedJobs, _failedJobs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,nodeId,actor,repository,substation,observationId,runId,runNumber,workflowPath,workflowName,event,headBranch,headSha,conclusion,htmlUrl,const DeepCollectionEquality().hash(_failedJobs));

@override
String toString() {
  return 'NormalizedGitHubEvent.workflowRunConcluded(nodeId: $nodeId, actor: $actor, repository: $repository, substation: $substation, observationId: $observationId, runId: $runId, runNumber: $runNumber, workflowPath: $workflowPath, workflowName: $workflowName, event: $event, headBranch: $headBranch, headSha: $headSha, conclusion: $conclusion, htmlUrl: $htmlUrl, failedJobs: $failedJobs)';
}


}

/// @nodoc
abstract mixin class $WorkflowRunConcludedCopyWith<$Res> implements $NormalizedGitHubEventCopyWith<$Res> {
  factory $WorkflowRunConcludedCopyWith(WorkflowRunConcluded value, $Res Function(WorkflowRunConcluded) _then) = _$WorkflowRunConcludedCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String actor, String repository, String substation, String observationId, int runId, int runNumber, String workflowPath, String workflowName, String event, String headBranch, String headSha, String conclusion, String htmlUrl, List<WorkflowRunFailedJob> failedJobs
});




}
/// @nodoc
class _$WorkflowRunConcludedCopyWithImpl<$Res>
    implements $WorkflowRunConcludedCopyWith<$Res> {
  _$WorkflowRunConcludedCopyWithImpl(this._self, this._then);

  final WorkflowRunConcluded _self;
  final $Res Function(WorkflowRunConcluded) _then;

/// Create a copy of NormalizedGitHubEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? actor = null,Object? repository = null,Object? substation = null,Object? observationId = null,Object? runId = null,Object? runNumber = null,Object? workflowPath = null,Object? workflowName = null,Object? event = null,Object? headBranch = null,Object? headSha = null,Object? conclusion = null,Object? htmlUrl = null,Object? failedJobs = null,}) {
  return _then(WorkflowRunConcluded(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String,substation: null == substation ? _self.substation : substation // ignore: cast_nullable_to_non_nullable
as String,observationId: null == observationId ? _self.observationId : observationId // ignore: cast_nullable_to_non_nullable
as String,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as int,runNumber: null == runNumber ? _self.runNumber : runNumber // ignore: cast_nullable_to_non_nullable
as int,workflowPath: null == workflowPath ? _self.workflowPath : workflowPath // ignore: cast_nullable_to_non_nullable
as String,workflowName: null == workflowName ? _self.workflowName : workflowName // ignore: cast_nullable_to_non_nullable
as String,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as String,headBranch: null == headBranch ? _self.headBranch : headBranch // ignore: cast_nullable_to_non_nullable
as String,headSha: null == headSha ? _self.headSha : headSha // ignore: cast_nullable_to_non_nullable
as String,conclusion: null == conclusion ? _self.conclusion : conclusion // ignore: cast_nullable_to_non_nullable
as String,htmlUrl: null == htmlUrl ? _self.htmlUrl : htmlUrl // ignore: cast_nullable_to_non_nullable
as String,failedJobs: null == failedJobs ? _self._failedJobs : failedJobs // ignore: cast_nullable_to_non_nullable
as List<WorkflowRunFailedJob>,
  ));
}


}

// dart format on
