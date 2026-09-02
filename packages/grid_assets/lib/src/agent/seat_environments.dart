/// The SEAT preference types (epic `pow-n6n`, bead `pow-n6n.2`) - the four
/// `ModelPreference` subclasses the six spawn sites resolve by, plus the
/// critics' lane aspect.
///
/// `typed_environment.dart` owns the MECHANISM (bead `pow-n6n.1`); this library
/// owns the VOCABULARY. The TYPE is the scope (ADR-0006 D2): a station mounts
/// `InheritedSeed<BuildAgentEnvironment>` beside `InheritedSeed<ModelPreference>`
/// and the build seat shadows the station default without either naming a
/// string. A seat scopes by nesting under its Substation.
///
/// The critics are ONE class over many rubrics, so they get D4's aspect-scoped
/// shape: [CriticAgentEnvironment] carries a per-[CriticLane] map over its shared
/// entries, [CriticAgentEnvironment.of] picks the lane's preference at the spawn
/// edge, and [CriticEnvironmentSeed] scopes a BUILD-time dependent's
/// invalidation to its own lane over `genesis_tree`'s `InheritedModelSeed`.
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'agent_environment.dart';
import 'typed_environment.dart';

/// The SPEC seat - `SpecifyCapability` (its first-round and its respec spawn are
/// the same site). Folds `AgentRole.architect` (bead `pow-t1w`), which bead
/// `pow-n6n.4` then deletes.
class SpecAgentEnvironment extends ModelPreference {
  /// Creates the spec seat's preference, most-preferred first.
  const SpecAgentEnvironment(super.entries);
}

/// The GATHER seat - the discovery explorers (`DiscoveryLensCapability`, one
/// class over three lenses, all read-only and all one seat).
class GatherAgentEnvironment extends ModelPreference {
  /// Creates the gather seat's preference, most-preferred first.
  const GatherAgentEnvironment(super.entries);
}

/// The BUILD seat - the coding agent (`AgentCapability`).
class BuildAgentEnvironment extends ModelPreference {
  /// Creates the build seat's preference, most-preferred first.
  const BuildAgentEnvironment(super.entries);
}

/// One critic LANE: the rubric id a critic already carries
/// (`args.params['rubric']` - `coherence`, `adr-alignment`, `bead-readiness`),
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

  /// The rubric id (`coherence`, `adr-alignment`, `spec-adherence`, ...).
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
/// it per rubric (ADR-0006 D4), so a station can send `adr-alignment` somewhere
/// else without a second provider.
class CriticAgentEnvironment extends ModelPreference {
  /// Creates the critic seat's shared preference over [entries], with optional
  /// per-[lanes] overrides.
  const CriticAgentEnvironment(super.entries, {this.lanes = const {}});

  /// Per-lane overrides of [entries], keyed by the critic's own rubric id. A
  /// lane absent here rides [entries].
  final Map<CriticLane, List<AgentEnvironment>> lanes;

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
