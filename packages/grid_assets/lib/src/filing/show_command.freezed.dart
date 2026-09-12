// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'show_command.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShowOutcome {

 String get beadId;
/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShowOutcomeCopyWith<ShowOutcome> get copyWith => _$ShowOutcomeCopyWithImpl<ShowOutcome>(this as ShowOutcome, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShowOutcome&&(identical(other.beadId, beadId) || other.beadId == beadId));
}


@override
int get hashCode => Object.hash(runtimeType,beadId);

@override
String toString() {
  return 'ShowOutcome(beadId: $beadId)';
}


}

/// @nodoc
abstract mixin class $ShowOutcomeCopyWith<$Res>  {
  factory $ShowOutcomeCopyWith(ShowOutcome value, $Res Function(ShowOutcome) _then) = _$ShowOutcomeCopyWithImpl;
@useResult
$Res call({
 String beadId
});




}
/// @nodoc
class _$ShowOutcomeCopyWithImpl<$Res>
    implements $ShowOutcomeCopyWith<$Res> {
  _$ShowOutcomeCopyWithImpl(this._self, this._then);

  final ShowOutcome _self;
  final $Res Function(ShowOutcome) _then;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? beadId = null,}) {
  return _then(_self.copyWith(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ShowOutcome].
extension ShowOutcomePatterns on ShowOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BeadShown value)?  shown,TResult Function( ShowUnchanged value)?  unchanged,TResult Function( ShowRefused value)?  refused,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BeadShown() when shown != null:
return shown(_that);case ShowUnchanged() when unchanged != null:
return unchanged(_that);case ShowRefused() when refused != null:
return refused(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BeadShown value)  shown,required TResult Function( ShowUnchanged value)  unchanged,required TResult Function( ShowRefused value)  refused,}){
final _that = this;
switch (_that) {
case BeadShown():
return shown(_that);case ShowUnchanged():
return unchanged(_that);case ShowRefused():
return refused(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BeadShown value)?  shown,TResult? Function( ShowUnchanged value)?  unchanged,TResult? Function( ShowRefused value)?  refused,}){
final _that = this;
switch (_that) {
case BeadShown() when shown != null:
return shown(_that);case ShowUnchanged() when unchanged != null:
return unchanged(_that);case ShowRefused() when refused != null:
return refused(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String beadId,  String title,  IssueType issueType,  BeadStatus status,  int priority,  String description,  String design,  String acceptanceCriteria,  String notes,  Map<String, String?> approval,  List<BeadDependency> dependencies,  String? revision,  Map<String, int> withheld)?  shown,TResult Function( String beadId,  String revision)?  unchanged,TResult Function( String beadId,  String reason,  int withheldReasonBytes)?  refused,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BeadShown() when shown != null:
return shown(_that.beadId,_that.title,_that.issueType,_that.status,_that.priority,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.approval,_that.dependencies,_that.revision,_that.withheld);case ShowUnchanged() when unchanged != null:
return unchanged(_that.beadId,_that.revision);case ShowRefused() when refused != null:
return refused(_that.beadId,_that.reason,_that.withheldReasonBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String beadId,  String title,  IssueType issueType,  BeadStatus status,  int priority,  String description,  String design,  String acceptanceCriteria,  String notes,  Map<String, String?> approval,  List<BeadDependency> dependencies,  String? revision,  Map<String, int> withheld)  shown,required TResult Function( String beadId,  String revision)  unchanged,required TResult Function( String beadId,  String reason,  int withheldReasonBytes)  refused,}) {final _that = this;
switch (_that) {
case BeadShown():
return shown(_that.beadId,_that.title,_that.issueType,_that.status,_that.priority,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.approval,_that.dependencies,_that.revision,_that.withheld);case ShowUnchanged():
return unchanged(_that.beadId,_that.revision);case ShowRefused():
return refused(_that.beadId,_that.reason,_that.withheldReasonBytes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String beadId,  String title,  IssueType issueType,  BeadStatus status,  int priority,  String description,  String design,  String acceptanceCriteria,  String notes,  Map<String, String?> approval,  List<BeadDependency> dependencies,  String? revision,  Map<String, int> withheld)?  shown,TResult? Function( String beadId,  String revision)?  unchanged,TResult? Function( String beadId,  String reason,  int withheldReasonBytes)?  refused,}) {final _that = this;
switch (_that) {
case BeadShown() when shown != null:
return shown(_that.beadId,_that.title,_that.issueType,_that.status,_that.priority,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.approval,_that.dependencies,_that.revision,_that.withheld);case ShowUnchanged() when unchanged != null:
return unchanged(_that.beadId,_that.revision);case ShowRefused() when refused != null:
return refused(_that.beadId,_that.reason,_that.withheldReasonBytes);case _:
  return null;

}
}

}

/// @nodoc


class BeadShown extends ShowOutcome {
  const BeadShown({required this.beadId, required this.title, required this.issueType, required this.status, required this.priority, required this.description, required this.design, required this.acceptanceCriteria, required this.notes, required final  Map<String, String?> approval, required final  List<BeadDependency> dependencies, this.revision, final  Map<String, int> withheld = const <String, int>{}}): _approval = approval,_dependencies = dependencies,_withheld = withheld,super._();
  

@override final  String beadId;
 final  String title;
 final  IssueType issueType;
 final  BeadStatus status;
 final  int priority;
 final  String description;
 final  String design;
 final  String acceptanceCriteria;
 final  String notes;
 final  Map<String, String?> _approval;
 Map<String, String?> get approval {
  if (_approval is EqualUnmodifiableMapView) return _approval;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_approval);
}

 final  List<BeadDependency> _dependencies;
 List<BeadDependency> get dependencies {
  if (_dependencies is EqualUnmodifiableListView) return _dependencies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dependencies);
}

 final  String? revision;
 final  Map<String, int> _withheld;
@JsonKey() Map<String, int> get withheld {
  if (_withheld is EqualUnmodifiableMapView) return _withheld;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_withheld);
}


/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadShownCopyWith<BeadShown> get copyWith => _$BeadShownCopyWithImpl<BeadShown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadShown&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.title, title) || other.title == title)&&(identical(other.issueType, issueType) || other.issueType == issueType)&&(identical(other.status, status) || other.status == status)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.description, description) || other.description == description)&&(identical(other.design, design) || other.design == design)&&(identical(other.acceptanceCriteria, acceptanceCriteria) || other.acceptanceCriteria == acceptanceCriteria)&&(identical(other.notes, notes) || other.notes == notes)&&const DeepCollectionEquality().equals(other._approval, _approval)&&const DeepCollectionEquality().equals(other._dependencies, _dependencies)&&(identical(other.revision, revision) || other.revision == revision)&&const DeepCollectionEquality().equals(other._withheld, _withheld));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,title,issueType,status,priority,description,design,acceptanceCriteria,notes,const DeepCollectionEquality().hash(_approval),const DeepCollectionEquality().hash(_dependencies),revision,const DeepCollectionEquality().hash(_withheld));

@override
String toString() {
  return 'ShowOutcome.shown(beadId: $beadId, title: $title, issueType: $issueType, status: $status, priority: $priority, description: $description, design: $design, acceptanceCriteria: $acceptanceCriteria, notes: $notes, approval: $approval, dependencies: $dependencies, revision: $revision, withheld: $withheld)';
}


}

/// @nodoc
abstract mixin class $BeadShownCopyWith<$Res> implements $ShowOutcomeCopyWith<$Res> {
  factory $BeadShownCopyWith(BeadShown value, $Res Function(BeadShown) _then) = _$BeadShownCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String title, IssueType issueType, BeadStatus status, int priority, String description, String design, String acceptanceCriteria, String notes, Map<String, String?> approval, List<BeadDependency> dependencies, String? revision, Map<String, int> withheld
});




}
/// @nodoc
class _$BeadShownCopyWithImpl<$Res>
    implements $BeadShownCopyWith<$Res> {
  _$BeadShownCopyWithImpl(this._self, this._then);

  final BeadShown _self;
  final $Res Function(BeadShown) _then;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? title = null,Object? issueType = null,Object? status = null,Object? priority = null,Object? description = null,Object? design = null,Object? acceptanceCriteria = null,Object? notes = null,Object? approval = null,Object? dependencies = null,Object? revision = freezed,Object? withheld = null,}) {
  return _then(BeadShown(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,issueType: null == issueType ? _self.issueType : issueType // ignore: cast_nullable_to_non_nullable
as IssueType,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,design: null == design ? _self.design : design // ignore: cast_nullable_to_non_nullable
as String,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,approval: null == approval ? _self._approval : approval // ignore: cast_nullable_to_non_nullable
as Map<String, String?>,dependencies: null == dependencies ? _self._dependencies : dependencies // ignore: cast_nullable_to_non_nullable
as List<BeadDependency>,revision: freezed == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String?,withheld: null == withheld ? _self._withheld : withheld // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}


}

/// @nodoc


class ShowUnchanged extends ShowOutcome {
  const ShowUnchanged({required this.beadId, required this.revision}): super._();
  

@override final  String beadId;
 final  String revision;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShowUnchangedCopyWith<ShowUnchanged> get copyWith => _$ShowUnchangedCopyWithImpl<ShowUnchanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShowUnchanged&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,revision);

@override
String toString() {
  return 'ShowOutcome.unchanged(beadId: $beadId, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $ShowUnchangedCopyWith<$Res> implements $ShowOutcomeCopyWith<$Res> {
  factory $ShowUnchangedCopyWith(ShowUnchanged value, $Res Function(ShowUnchanged) _then) = _$ShowUnchangedCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String revision
});




}
/// @nodoc
class _$ShowUnchangedCopyWithImpl<$Res>
    implements $ShowUnchangedCopyWith<$Res> {
  _$ShowUnchangedCopyWithImpl(this._self, this._then);

  final ShowUnchanged _self;
  final $Res Function(ShowUnchanged) _then;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? revision = null,}) {
  return _then(ShowUnchanged(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShowRefused extends ShowOutcome {
  const ShowRefused({required this.beadId, required this.reason, this.withheldReasonBytes = 0}): super._();
  

@override final  String beadId;
 final  String reason;
@JsonKey() final  int withheldReasonBytes;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShowRefusedCopyWith<ShowRefused> get copyWith => _$ShowRefusedCopyWithImpl<ShowRefused>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShowRefused&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.withheldReasonBytes, withheldReasonBytes) || other.withheldReasonBytes == withheldReasonBytes));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,reason,withheldReasonBytes);

@override
String toString() {
  return 'ShowOutcome.refused(beadId: $beadId, reason: $reason, withheldReasonBytes: $withheldReasonBytes)';
}


}

/// @nodoc
abstract mixin class $ShowRefusedCopyWith<$Res> implements $ShowOutcomeCopyWith<$Res> {
  factory $ShowRefusedCopyWith(ShowRefused value, $Res Function(ShowRefused) _then) = _$ShowRefusedCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String reason, int withheldReasonBytes
});




}
/// @nodoc
class _$ShowRefusedCopyWithImpl<$Res>
    implements $ShowRefusedCopyWith<$Res> {
  _$ShowRefusedCopyWithImpl(this._self, this._then);

  final ShowRefused _self;
  final $Res Function(ShowRefused) _then;

/// Create a copy of ShowOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? reason = null,Object? withheldReasonBytes = null,}) {
  return _then(ShowRefused(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,withheldReasonBytes: null == withheldReasonBytes ? _self.withheldReasonBytes : withheldReasonBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
