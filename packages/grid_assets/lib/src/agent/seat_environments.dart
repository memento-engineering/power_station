/// The SEAT preference types (epic `pow-n6n`, bead `pow-n6n.2`) - the four
/// `SeatPreference` subclasses the six spawn sites resolve by, plus the
/// critics' lane aspect.
///
/// `typed_environment.dart` owns the MECHANISM (bead `pow-n6n.1`); this library
/// owns the VOCABULARY. Four is what this pack VENDS, never what the mechanism
/// admits: a seat is any [SeatPreference], it vends its own provider seed, and
/// [TypedEnvironmentProvider] mounts whatever ordered collection it is armed
/// with - so a station adds a seat type without editing this pack. The TYPE is
/// the scope (ADR-0006 D2): a station mounts
/// `InheritedSeed<BuildAgentEnvironment>` beside `InheritedSeed<ModelPreference>`
/// and the build seat shadows the station default without either naming a
/// string. A seat scopes by nesting under its Substation.
///
/// The critics are ONE class over many rubrics, so they get D4's aspect-scoped
/// shape: [CriticAgentEnvironment] carries a per-[CriticLane] map over its shared
/// entries, [CriticAgentEnvironment.of] picks the lane's preference at the spawn
/// edge, and [CriticEnvironmentSeed] scopes a BUILD-time dependent's
/// invalidation to its own lane over `genesis_tree`'s `InheritedModelSeed`.
///
/// The MECHANISM that mounts and resolves those seats lives here too:
/// [SeatProvider] and [CriticSeatProvider] are the two provider shapes a seat
/// type vends, [AgentArming] is the pure VALUE naming one environment per
/// VENDED seat (and an `Iterable<SeatPreference>`, so it composes with any
/// other ordered collection of seats), [TypedEnvironmentProvider] is the ONE
/// seed both the station rung and the per-substation rung mount (ADR-0002 D5),
/// and [SeatEnvironments] is the offline projection of the four vended
/// resolutions at a point in the tree. A
/// station's own NAMED environments and ladders stay in that station's package
/// - mechanism is vended, posture is not.
///
/// The armed seat is also a channel's ADMITTED IDENTITY, so [seatChannelPolicy]
/// resolves the station's authorization boundary off the same typed seed. It
/// lives here rather than beside the pure vocabulary in `permission_policy.dart`
/// because it needs the tree, and that library takes no `TreeContext`.
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'agent_environment.dart';
import 'environment_registry.dart';
import 'permission_policy.dart';
import 'typed_environment.dart';

/// Provides ONE [SeatPreference] over a subtree under its EXACT static type
/// [T] - the provider seed a plain seat type vends from `provider()`.
///
/// A `SingleChildStatelessSeed` rather than a bare `InheritedSeed` because
/// `InheritedSeed` requires its child at construction and so cannot be a link
/// in a `Nest`; this wrapper is the one line that bridges that, and it is what
/// lets [TypedEnvironmentProvider] compose an arming it does not enumerate.
///
/// [T] is written by the seat type itself (`SeatProvider<SpecAgentEnvironment>`
/// from `SpecAgentEnvironment.provider`), which is why the mounted value keeps
/// the exact type `resolveEnvironment` reads by.
final class SeatProvider<T extends SeatPreference>
    extends SingleChildStatelessSeed {
  /// Provides [value] over [child] as an `InheritedSeed<T>`.
  const SeatProvider(this.value, {super.child, super.key});

  /// The seat preference this seed provides.
  final T value;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<T>(value: value, child: child);
}

/// The SPEC seat - `SpecifyCapability` (its first-round and its respec spawn are
/// the same site). Folded `pow-t1w`'s architect role, which bead `pow-n6n.4`
/// deleted (ADR-0006 D5).
class SpecAgentEnvironment extends SeatPreference {
  /// Creates the spec seat's preference, most-preferred first.
  const SpecAgentEnvironment(super.entries);

  @override
  SingleChildSeed provider() => SeatProvider<SpecAgentEnvironment>(this);
}

/// The GATHER seat - the discovery explorers (`DiscoveryLensCapability`, one
/// class over three lenses, all read-only and all one seat).
class GatherAgentEnvironment extends SeatPreference {
  /// Creates the gather seat's preference, most-preferred first.
  const GatherAgentEnvironment(super.entries);

  @override
  SingleChildSeed provider() => SeatProvider<GatherAgentEnvironment>(this);
}

/// The BUILD seat - the coding agent (`AgentCapability`).
class BuildAgentEnvironment extends SeatPreference {
  /// Creates the build seat's preference, most-preferred first.
  const BuildAgentEnvironment(super.entries);

  @override
  SingleChildSeed provider() => SeatProvider<BuildAgentEnvironment>(this);
}

/// One critic LANE: the rubric id a critic already carries
/// (`args.params['rubric']` - `coherence`, `decision-alignment`, `bead-readiness`),
/// as a VALUE so it can serve as an `InheritedModelSeed` aspect.
///
/// A TYPE rather than a bare `String` on purpose: `InheritedModelBranch`
/// refuses an aspect whose type is not the provider's `A`, and with `A = String`
/// every stray string would pass and that guard would be silently dead (guards
/// LOUD or GONE - ADR-0000 A8). It introduces no new string: the id is the one
/// the route already puts on the step.
class CriticLane {
  /// Creates the lane over the critic's [rubric] id.
  const CriticLane(this.rubric);

  /// The rubric id (`coherence`, `decision-alignment`, `spec-adherence`, ...).
  final String rubric;

  @override
  bool operator ==(Object other) =>
      other is CriticLane && other.rubric == rubric;

  @override
  int get hashCode => rubric.hashCode;

  @override
  String toString() => 'CriticLane($rubric)';
}

/// The CRITIC seat - `CriticCapability`, `SpecCriticCapability` and
/// `ReadinessCriticCapability`. ONE class over many rubrics, so ONE mounted
/// value routes them: [entries] is the shared preference and [lanes] overrides
/// it per rubric (ADR-0006 D4), so a station can send `decision-alignment` somewhere
/// else without a second provider.
class CriticAgentEnvironment extends SeatPreference {
  /// Creates the critic seat's shared preference over [entries], with optional
  /// per-[lanes] overrides.
  const CriticAgentEnvironment(super.entries, {this.lanes = const {}});

  /// Per-lane overrides of [entries], keyed by the critic's own rubric id. A
  /// lane absent here rides [entries].
  final Map<CriticLane, List<AgentEnvironment>> lanes;

  /// The critic's own provider is [CriticSeatProvider], not the plain
  /// [SeatProvider]: a build-time dependent keeps D4's lane-scoped
  /// invalidation, and a spawn edge pays nothing for it.
  @override
  SingleChildSeed provider() => CriticSeatProvider(this);

  /// The preference [lane] must walk: its own override when this value routes
  /// it, else the shared [entries]. Returns a bare [ModelPreference] because
  /// the walk ([firstAvailable]) reads only the entries.
  ModelPreference preferenceFor(CriticLane? lane) {
    final routed = lane == null ? null : lanes[lane];
    return ModelPreference(routed ?? entries);
  }

  /// The critic seat's effective lookup: the nearest [CriticAgentEnvironment],
  /// routed by [lane]; else the generic [ModelPreference]; then the availability
  /// walk. Null when nothing is mounted or nothing preferred is present - the
  /// caller falls to the next rung, exactly like [resolveEnvironment].
  ///
  /// THE EFFECT VERB (`getInheritedSeedOfExactType`), per ADR-0008 D3 /
  /// ADR-0000 A8(3) and A35(6): this is called at a capability's `spawn` edge,
  /// not in a `build`. The `aspect:` argument belongs to the SUBSCRIBING verb
  /// and is used by [CriticEnvironmentSeed]'s build-time dependents; selection
  /// here reads the lane off the VALUE, which is where genesis puts it (an
  /// `InheritedModelSeed<T, A>` provides one `T`; the aspect scopes
  /// invalidation, never lookup).
  static AgentEnvironment? of(TreeContext context, {CriticLane? lane}) {
    final seat = context.getInheritedSeedOfExactType<CriticAgentEnvironment>();
    if (seat != null) return firstAvailable(context, seat.preferenceFor(lane));
    final generic = context.getInheritedSeedOfExactType<ModelPreference>();
    return generic == null ? null : firstAvailable(context, generic);
  }

  @override
  bool operator ==(Object other) =>
      other is CriticAgentEnvironment &&
      other.runtimeType == runtimeType &&
      _sameEntries(other.entries, entries) &&
      _sameLanes(other.lanes, lanes);

  @override
  int get hashCode =>
      Object.hash(runtimeType, Object.hashAll(entries), _lanesHash(lanes));
}

/// Provides a [CriticAgentEnvironment] whose BUILD-time dependents may scope
/// themselves to one [CriticLane] (`genesis-8zb`; `genesis_tree` 0.3.0's
/// `InheritedModelSeed`). A dependent that passes `aspect: CriticLane(...)` is
/// invalidated only when THAT lane's effective preference changed; one that
/// passes none keeps the whole-value dependency.
///
/// Spawn edges do not use this scoping - they read the value with the effect
/// verb through [CriticAgentEnvironment.of]. Mounting this instead of a plain
/// `InheritedSeed<CriticAgentEnvironment>` costs them nothing: lookup by exact
/// value type is identical.
class CriticEnvironmentSeed
    extends InheritedModelSeed<CriticAgentEnvironment, CriticLane> {
  /// Provides [value] over [child].
  const CriticEnvironmentSeed({
    required super.value,
    required super.child,
    super.key,
  });

  @override
  bool updateShouldNotifyDependent(
    InheritedModelSeed<CriticAgentEnvironment, CriticLane> oldSeed,
    Set<CriticLane> dependencies,
  ) => dependencies.any(
    (lane) => value.preferenceFor(lane) != oldSeed.value.preferenceFor(lane),
  );
}

/// The CRITIC seat's provider seed - [SeatProvider]'s counterpart for the one
/// seat whose value is aspect-scoped, so `provider()` can hand
/// [TypedEnvironmentProvider] a `Nest` link that mounts a
/// [CriticEnvironmentSeed] rather than a plain `InheritedSeed`.
final class CriticSeatProvider extends SingleChildStatelessSeed {
  /// Provides [value] over [child] as a [CriticEnvironmentSeed].
  const CriticSeatProvider(this.value, {super.child, super.key});

  /// The critic seat preference this seed provides.
  final CriticAgentEnvironment value;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      CriticEnvironmentSeed(value: value, child: child);
}

/// One ARMING of the TYPED environment seats - a station's or a seat's say in
/// which environment each capability runs on. A pure VALUE; it carries no
/// behavior and reaches no service. A null field leaves that seat to the
/// nearest ancestor's arming (ADR-0006 D2: the TYPE is the scope).
///
/// The MECHANISM only. A station's own named environments and the ladders built
/// over them are that station's posture and live in the station's own package.
///
/// FOUR TYPED SEATS AND NOTHING ELSE - the POST-role-retirement shape. There is
/// no role map and no role rung: ADR-0006 D5 retired them and bead `pow-n6n.4`
/// carried it out, leaving the typed lookup as the whole environment axis.
///
/// Four is this pack's VENDED shape, not a closed universe. `AgentArming` IS an
/// `Iterable<SeatPreference>` - the type [TypedEnvironmentProvider] arms - so a
/// station that declares its own seat type composes it without a fifth field
/// here: `<SeatPreference>[...arming, MyAgentEnvironment([...])]`. Iterating
/// yields the armed seats in the same stable order [seats] does, which is what
/// a boot-eager arming guard walks to name an offending seat BY TYPE.
class AgentArming extends Iterable<SeatPreference> {
  /// Creates an arming over the seats it names; every field is optional.
  const AgentArming({this.build, this.spec, this.critic, this.gather});

  /// The BUILD seat (the coding agent).
  final BuildAgentEnvironment? build;

  /// The SPEC seat (the architect / specify stage).
  final SpecAgentEnvironment? spec;

  /// The CRITIC seat (every committee lane), with optional per-lane overrides.
  final CriticAgentEnvironment? critic;

  /// The GATHER seat (the read-only discovery explorers).
  final GatherAgentEnvironment? gather;

  /// Whether this arming says nothing at all.
  @override
  bool get isEmpty =>
      build == null && spec == null && critic == null && gather == null;

  /// The armed seats, BUILD first - the stable order a station's boot-eager
  /// arming guard walks, and the order [TypedEnvironmentProvider] nests them
  /// in (the first is outermost).
  Iterable<SeatPreference> get seats => [
    if (build != null) build!,
    if (spec != null) spec!,
    if (critic != null) critic!,
    if (gather != null) gather!,
  ];

  @override
  Iterator<SeatPreference> get iterator => seats.iterator;

  @override
  bool operator ==(Object other) =>
      other is AgentArming &&
      other.build == build &&
      other.spec == spec &&
      other.critic == critic &&
      other.gather == gather;

  @override
  int get hashCode => Object.hash(build, spec, critic, gather);

  @override
  String toString() =>
      'AgentArming(build: $build, spec: $spec, critic: $critic, '
      'gather: $gather)';
}

/// Provides an [arming]'s TYPED seats over its subtree - the ONE seed both the
/// station rung and the per-substation rung mount (ADR-0002 D5, ADR-0006 D2).
///
/// A NESTED instance shadows only the types it arms: an unarmed seat keeps
/// resolving through the enclosing provider, because [resolveEnvironment] reads
/// by EXACT type and finds the nearest ancestor of that type.
///
/// THE SEAT SET IS OPEN. [arming] is any ordered `Iterable<SeatPreference>` -
/// [AgentArming] is one - and each seat vends the seed that provides it
/// (`SeatPreference.provider`), so this build enumerates no seat type and a
/// station introduces one without editing this pack. Composition is
/// `genesis_tree`'s own `Nest`: it wraps [child] with each link in order, the
/// FIRST outermost, which is the declaration order the arming yields.
///
/// THE MOUNTING SEED, so this is where the SUBSCRIBING build verb would belong
/// if a value here were derived (ADR-0000 A35(6)). Nothing here is derived -
/// [arming] is an authored VALUE - so this build reads no ambient state at all.
final class TypedEnvironmentProvider extends SingleChildStatelessSeed {
  /// Provides [arming]'s seats over [child].
  const TypedEnvironmentProvider({
    required this.arming,
    super.child,
    super.key,
  });

  /// The seats this provider mounts, outermost first.
  final Iterable<SeatPreference> arming;

  @override
  Seed buildWithChild(TreeContext context, Seed child) => Nest(
    children: [for (final seat in arming) seat.provider()],
    child: child,
  );
}

/// The BUILD seat's audit id, stamped onto every authorization its channel
/// makes. An AUDIT id, never a lookup key: nothing resolves by this string.
const String kBuildSeatPolicyId = 'seat:build';

/// The SPEC seat's audit id - [kBuildSeatPolicyId]'s counterpart.
const String kSpecSeatPolicyId = 'seat:spec';

/// The station permission policy in effect for ONE capability's channel, keyed
/// by the seat's own preference type [TSeat] and stamped with [seatId].
///
/// Total, in strict precedence:
///  1. an EXPLICITLY mounted [AgentPermissionPolicy] wins outright, returned
///     unchanged - including [AgentPermissionPolicy.unavailable], which is how a
///     station locks a subtree down over an armed seat;
///  2. else, an ARMED exact [TSeat] is the channel's admitted identity, so it
///     derives [AgentPermissionPolicy.trustedHeadless] under [seatId];
///  3. else [AgentPermissionPolicy.unavailable] - a channel with no seat
///     identity authorizes nothing.
///
/// THE IDENTITY IS THE EXACT TYPE (ADR-0006 D2: the TYPE is the scope), read
/// from the [InheritedSeed] [TypedEnvironmentProvider] mounts off
/// [AgentArming]. The GENERIC [ModelPreference] is deliberately NOT consulted:
/// it is the station's shared model default, not an arming of this seat, and
/// treating it as an identity would hand a grant to any channel that inherited
/// a default. Nothing here reads a name, a runtime type, an environment's
/// availability, or the model-spend axis - a permission is not a spend.
///
/// THE EFFECT VERB (`getInheritedSeedOfExactType`), per ADR-0008 D3: both
/// callers are `createSession` edges, not `build`s.
AgentPermissionPolicy seatChannelPolicy<TSeat extends ModelPreference>(
  TreeContext context, {
  required String seatId,
}) {
  final explicit = context.getInheritedSeedOfExactType<AgentPermissionPolicy>();
  if (explicit != null) return explicit;
  final seat = context.getInheritedSeedOfExactType<TSeat>();
  if (seat == null) return const AgentPermissionPolicy.unavailable();
  return AgentPermissionPolicy.trustedHeadless(id: seatId);
}

/// The four typed lookups RESOLVED at one point in the tree - the offline
/// projection a station's banner prints and the suites assert. A pure VALUE.
final class SeatEnvironments {
  /// Creates the projection over its four resolved environments.
  const SeatEnvironments({this.build, this.spec, this.critic, this.gather});

  /// Resolves all four seats at [context] through the vended resolvers (one
  /// availability walk each). These are EFFECT-boundary reads -
  /// [resolveEnvironment] and [CriticAgentEnvironment.of] use the non-binding
  /// `getInheritedSeedOfExactType` (ADR-0000 A35(6)) - so a caller that runs
  /// this inside a `build` subscribes to the same values FIRST with
  /// `dependOn*` (the D-H doctrine, ADR-0008 D3; ADR-0000 A8(3)).
  factory SeatEnvironments.of(TreeContext context) => SeatEnvironments(
    build: resolveEnvironment<BuildAgentEnvironment>(context),
    spec: resolveEnvironment<SpecAgentEnvironment>(context),
    critic: CriticAgentEnvironment.of(context),
    gather: resolveEnvironment<GatherAgentEnvironment>(context),
  );

  /// The BUILD seat's resolved environment; null when nothing is armed or
  /// nothing preferred is present (the caller falls to the ambient rung).
  final AgentEnvironment? build;

  /// The SPEC seat's resolved environment.
  final AgentEnvironment? spec;

  /// The CRITIC seat's resolved environment (the shared, laneless preference).
  final AgentEnvironment? critic;

  /// The GATHER seat's resolved environment.
  final AgentEnvironment? gather;

  /// This projection rendered with [registry]'s NAMES - the banner line. The
  /// name is restored at the boundary exactly as `resolveAgentConfig` does it
  /// ([EnvironmentRegistry.nameOf]).
  String describe(EnvironmentRegistry registry) {
    String named(AgentEnvironment? environment) =>
        environment == null ? '<ambient>' : registry.nameOf(environment);
    return 'build ${named(build)}  ·  spec ${named(spec)}  ·  '
        'critic ${named(critic)}  ·  gather ${named(gather)}';
  }

  @override
  bool operator ==(Object other) =>
      other is SeatEnvironments &&
      other.build == build &&
      other.spec == spec &&
      other.critic == critic &&
      other.gather == gather;

  @override
  int get hashCode => Object.hash(build, spec, critic, gather);

  @override
  String toString() =>
      'SeatEnvironments(build: $build, spec: $spec, critic: $critic, '
      'gather: $gather)';
}

bool _sameEntries(List<AgentEnvironment> a, List<AgentEnvironment> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameLanes(
  Map<CriticLane, List<AgentEnvironment>> a,
  Map<CriticLane, List<AgentEnvironment>> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_sameEntries(entry.value, other)) return false;
  }
  return true;
}

int _lanesHash(Map<CriticLane, List<AgentEnvironment>> lanes) =>
    Object.hashAllUnordered(
      lanes.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
    );
