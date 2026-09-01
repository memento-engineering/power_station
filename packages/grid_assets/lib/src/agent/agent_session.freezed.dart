// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentProtocolEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProtocolEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AgentProtocolEvent()';
}


}

/// @nodoc
class $AgentProtocolEventCopyWith<$Res>  {
$AgentProtocolEventCopyWith(AgentProtocolEvent _, $Res Function(AgentProtocolEvent) __);
}


/// Adds pattern-matching-related methods to [AgentProtocolEvent].
extension AgentProtocolEventPatterns on AgentProtocolEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentProtocolProgress value)?  progress,TResult Function( AgentProtocolCompleted value)?  completed,TResult Function( AgentProtocolFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentProtocolProgress() when progress != null:
return progress(_that);case AgentProtocolCompleted() when completed != null:
return completed(_that);case AgentProtocolFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentProtocolProgress value)  progress,required TResult Function( AgentProtocolCompleted value)  completed,required TResult Function( AgentProtocolFailed value)  failed,}){
final _that = this;
switch (_that) {
case AgentProtocolProgress():
return progress(_that);case AgentProtocolCompleted():
return completed(_that);case AgentProtocolFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentProtocolProgress value)?  progress,TResult? Function( AgentProtocolCompleted value)?  completed,TResult? Function( AgentProtocolFailed value)?  failed,}){
final _that = this;
switch (_that) {
case AgentProtocolProgress() when progress != null:
return progress(_that);case AgentProtocolCompleted() when completed != null:
return completed(_that);case AgentProtocolFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Map<String, String> fields)?  progress,TResult Function( Map<String, String> result,  UsageReport usage)?  completed,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentProtocolProgress() when progress != null:
return progress(_that.fields);case AgentProtocolCompleted() when completed != null:
return completed(_that.result,_that.usage);case AgentProtocolFailed() when failed != null:
return failed(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Map<String, String> fields)  progress,required TResult Function( Map<String, String> result,  UsageReport usage)  completed,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case AgentProtocolProgress():
return progress(_that.fields);case AgentProtocolCompleted():
return completed(_that.result,_that.usage);case AgentProtocolFailed():
return failed(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Map<String, String> fields)?  progress,TResult? Function( Map<String, String> result,  UsageReport usage)?  completed,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case AgentProtocolProgress() when progress != null:
return progress(_that.fields);case AgentProtocolCompleted() when completed != null:
return completed(_that.result,_that.usage);case AgentProtocolFailed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AgentProtocolProgress implements AgentProtocolEvent {
  const AgentProtocolProgress({final  Map<String, String> fields = const <String, String>{}}): _fields = fields;


 final  Map<String, String> _fields;
@JsonKey() Map<String, String> get fields {
  if (_fields is EqualUnmodifiableMapView) return _fields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fields);
}


/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProtocolProgressCopyWith<AgentProtocolProgress> get copyWith => _$AgentProtocolProgressCopyWithImpl<AgentProtocolProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProtocolProgress&&const DeepCollectionEquality().equals(other._fields, _fields));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_fields));

@override
String toString() {
  return 'AgentProtocolEvent.progress(fields: $fields)';
}


}

/// @nodoc
abstract mixin class $AgentProtocolProgressCopyWith<$Res> implements $AgentProtocolEventCopyWith<$Res> {
  factory $AgentProtocolProgressCopyWith(AgentProtocolProgress value, $Res Function(AgentProtocolProgress) _then) = _$AgentProtocolProgressCopyWithImpl;
@useResult
$Res call({
 Map<String, String> fields
});




}
/// @nodoc
class _$AgentProtocolProgressCopyWithImpl<$Res>
    implements $AgentProtocolProgressCopyWith<$Res> {
  _$AgentProtocolProgressCopyWithImpl(this._self, this._then);

  final AgentProtocolProgress _self;
  final $Res Function(AgentProtocolProgress) _then;

/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fields = null,}) {
  return _then(AgentProtocolProgress(
fields: null == fields ? _self._fields : fields // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

/// @nodoc


class AgentProtocolCompleted implements AgentProtocolEvent {
  const AgentProtocolCompleted({required final  Map<String, String> result, required this.usage}): _result = result;


 final  Map<String, String> _result;
 Map<String, String> get result {
  if (_result is EqualUnmodifiableMapView) return _result;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_result);
}

 final  UsageReport usage;

/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProtocolCompletedCopyWith<AgentProtocolCompleted> get copyWith => _$AgentProtocolCompletedCopyWithImpl<AgentProtocolCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProtocolCompleted&&const DeepCollectionEquality().equals(other._result, _result)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_result),usage);

@override
String toString() {
  return 'AgentProtocolEvent.completed(result: $result, usage: $usage)';
}


}

/// @nodoc
abstract mixin class $AgentProtocolCompletedCopyWith<$Res> implements $AgentProtocolEventCopyWith<$Res> {
  factory $AgentProtocolCompletedCopyWith(AgentProtocolCompleted value, $Res Function(AgentProtocolCompleted) _then) = _$AgentProtocolCompletedCopyWithImpl;
@useResult
$Res call({
 Map<String, String> result, UsageReport usage
});




}
/// @nodoc
class _$AgentProtocolCompletedCopyWithImpl<$Res>
    implements $AgentProtocolCompletedCopyWith<$Res> {
  _$AgentProtocolCompletedCopyWithImpl(this._self, this._then);

  final AgentProtocolCompleted _self;
  final $Res Function(AgentProtocolCompleted) _then;

/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,Object? usage = null,}) {
  return _then(AgentProtocolCompleted(
result: null == result ? _self._result : result // ignore: cast_nullable_to_non_nullable
as Map<String, String>,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as UsageReport,
  ));
}


}

/// @nodoc


class AgentProtocolFailed implements AgentProtocolEvent {
  const AgentProtocolFailed({required this.reason});


 final  String reason;

/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProtocolFailedCopyWith<AgentProtocolFailed> get copyWith => _$AgentProtocolFailedCopyWithImpl<AgentProtocolFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProtocolFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'AgentProtocolEvent.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $AgentProtocolFailedCopyWith<$Res> implements $AgentProtocolEventCopyWith<$Res> {
  factory $AgentProtocolFailedCopyWith(AgentProtocolFailed value, $Res Function(AgentProtocolFailed) _then) = _$AgentProtocolFailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$AgentProtocolFailedCopyWithImpl<$Res>
    implements $AgentProtocolFailedCopyWith<$Res> {
  _$AgentProtocolFailedCopyWithImpl(this._self, this._then);

  final AgentProtocolFailed _self;
  final $Res Function(AgentProtocolFailed) _then;

/// Create a copy of AgentProtocolEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(AgentProtocolFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$FencedAgentSteer {

 String get commandId; String get attemptId; String get instanceFence; String get text;
/// Create a copy of FencedAgentSteer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FencedAgentSteerCopyWith<FencedAgentSteer> get copyWith => _$FencedAgentSteerCopyWithImpl<FencedAgentSteer>(this as FencedAgentSteer, _$identity);

  /// Serializes this FencedAgentSteer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FencedAgentSteer&&(identical(other.commandId, commandId) || other.commandId == commandId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.instanceFence, instanceFence) || other.instanceFence == instanceFence)&&(identical(other.text, text) || other.text == text));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,commandId,attemptId,instanceFence,text);

@override
String toString() {
  return 'FencedAgentSteer(commandId: $commandId, attemptId: $attemptId, instanceFence: $instanceFence, text: $text)';
}


}

/// @nodoc
abstract mixin class $FencedAgentSteerCopyWith<$Res>  {
  factory $FencedAgentSteerCopyWith(FencedAgentSteer value, $Res Function(FencedAgentSteer) _then) = _$FencedAgentSteerCopyWithImpl;
@useResult
$Res call({
 String commandId, String attemptId, String instanceFence, String text
});




}
/// @nodoc
class _$FencedAgentSteerCopyWithImpl<$Res>
    implements $FencedAgentSteerCopyWith<$Res> {
  _$FencedAgentSteerCopyWithImpl(this._self, this._then);

  final FencedAgentSteer _self;
  final $Res Function(FencedAgentSteer) _then;

/// Create a copy of FencedAgentSteer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? commandId = null,Object? attemptId = null,Object? instanceFence = null,Object? text = null,}) {
  return _then(_self.copyWith(
commandId: null == commandId ? _self.commandId : commandId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,instanceFence: null == instanceFence ? _self.instanceFence : instanceFence // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FencedAgentSteer].
extension FencedAgentSteerPatterns on FencedAgentSteer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FencedAgentSteer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FencedAgentSteer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FencedAgentSteer value)  $default,){
final _that = this;
switch (_that) {
case _FencedAgentSteer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FencedAgentSteer value)?  $default,){
final _that = this;
switch (_that) {
case _FencedAgentSteer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String commandId,  String attemptId,  String instanceFence,  String text)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FencedAgentSteer() when $default != null:
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.text);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String commandId,  String attemptId,  String instanceFence,  String text)  $default,) {final _that = this;
switch (_that) {
case _FencedAgentSteer():
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.text);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String commandId,  String attemptId,  String instanceFence,  String text)?  $default,) {final _that = this;
switch (_that) {
case _FencedAgentSteer() when $default != null:
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.text);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FencedAgentSteer implements FencedAgentSteer {
  const _FencedAgentSteer({required this.commandId, required this.attemptId, required this.instanceFence, required this.text});
  factory _FencedAgentSteer.fromJson(Map<String, dynamic> json) => _$FencedAgentSteerFromJson(json);

@override final  String commandId;
@override final  String attemptId;
@override final  String instanceFence;
@override final  String text;

/// Create a copy of FencedAgentSteer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FencedAgentSteerCopyWith<_FencedAgentSteer> get copyWith => __$FencedAgentSteerCopyWithImpl<_FencedAgentSteer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FencedAgentSteerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FencedAgentSteer&&(identical(other.commandId, commandId) || other.commandId == commandId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.instanceFence, instanceFence) || other.instanceFence == instanceFence)&&(identical(other.text, text) || other.text == text));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,commandId,attemptId,instanceFence,text);

@override
String toString() {
  return 'FencedAgentSteer(commandId: $commandId, attemptId: $attemptId, instanceFence: $instanceFence, text: $text)';
}


}

/// @nodoc
abstract mixin class _$FencedAgentSteerCopyWith<$Res> implements $FencedAgentSteerCopyWith<$Res> {
  factory _$FencedAgentSteerCopyWith(_FencedAgentSteer value, $Res Function(_FencedAgentSteer) _then) = __$FencedAgentSteerCopyWithImpl;
@override @useResult
$Res call({
 String commandId, String attemptId, String instanceFence, String text
});




}
/// @nodoc
class __$FencedAgentSteerCopyWithImpl<$Res>
    implements _$FencedAgentSteerCopyWith<$Res> {
  __$FencedAgentSteerCopyWithImpl(this._self, this._then);

  final _FencedAgentSteer _self;
  final $Res Function(_FencedAgentSteer) _then;

/// Create a copy of FencedAgentSteer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? commandId = null,Object? attemptId = null,Object? instanceFence = null,Object? text = null,}) {
  return _then(_FencedAgentSteer(
commandId: null == commandId ? _self.commandId : commandId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,instanceFence: null == instanceFence ? _self.instanceFence : instanceFence // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
