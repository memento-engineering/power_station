/// The TYPED environment lookup (epic `pow-n6n`, bead `pow-n6n.1`) - how a
/// capability asks for its inference environment by TYPE and VALUE instead of
/// by name.
///
/// Four surfaces and nothing else: [ModelPreference] (an ordered preference
/// over complete [AgentEnvironment] values), [AvailableEnvironments] (which of
/// them are PRESENT), [firstAvailable] (the ONE availability walk), and
/// [resolveEnvironment] (specific type, then the generic, then the walk). The
/// TYPE is the scope and nearest ancestor wins, so there is no invocation key,
/// no rule table and no engine hook.
///
/// VALUE-KEYED SELECTION, NAME-KEYED TRANSPORT (ADR-0006 D2; the mechanism is
/// ADR-0000 A35). Legality is not skipped - it moves to where values ENTER the
/// tree: [AvailableEnvironments] only ever holds registry members that passed
/// the boot legality check, so a value this lookup returns is validated by
/// construction. `resolveAgentConfig` converts the winner back to its registry
/// name once, via [EnvironmentRegistry.nameOf].
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'environment_registry.dart';

/// An ORDERED preference over complete [AgentEnvironment] values - "this scope
/// wants X, else Y, else Z", most-preferred FIRST (ADR-0006 D1).
///
/// A pure VALUE mounted in the tree as an `InheritedSeed` (config = VALUES in
/// the tree, impls are DI - ADR-0000 A8): it carries no behavior, reaches no
/// service, and holds no environment name.
///
/// SUBCLASSABLE ON PURPOSE - the TYPE is the scope. A capability's own type
/// (`class SpecAgentEnvironment extends ModelPreference`, bead `pow-n6n.2`)
/// mounts as `InheritedSeed<SpecAgentEnvironment>` and is found by
/// [resolveEnvironment]'s EXACT-type read (`genesis_tree` compares `T == U` in
/// `InheritedBranch.getValueAs`, so a subclass provider is NOT found by a
/// generic lookup); a bare [ModelPreference] is the generic fallback every
/// capability shares.
class ModelPreference {
  /// Creates the preference over [entries], most-preferred first. `const`, so
  /// a station cans its posture beside its arming.
  const ModelPreference(this.entries);

  /// The preferred environments, most-preferred first. Immutable by contract:
  /// authored as a `const` list literal and never mutated.
  final List<AgentEnvironment> entries;

  /// Value equality over [entries] IN ORDER, and over the RUNTIME TYPE: a
  /// subclass never equals a bare [ModelPreference] carrying the same entries,
  /// because the type IS the scope and two scopes are not one value.
  @override
  bool operator ==(Object other) =>
      other is ModelPreference &&
      other.runtimeType == runtimeType &&
      _orderedEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(entries));

  @override
  String toString() => '$runtimeType($entries)';
}

/// The environments PRESENT right now - availability as PRESENCE (ADR-0006 D3),
/// never a probe cache: an environment is available if and only if it is IN
/// this set, by value equality.
///
/// The availability seed (bead `pow-n6n.3`) mounts it as an
/// `InheritedSeed<AvailableEnvironments>` from live probes. Until then it is
/// absent, and [availableEnvironmentsOf] defaults to
/// [EnvironmentRegistry.validatedEnvironments] - every registry member that
/// validated at boot - so nothing regresses.
///
/// LEGALITY LIVES HERE (ADR-0000 A35). The typed rung does not re-check a name
/// through [EnvironmentRegistry.resolve]: this set only ever holds validated
/// registry members, so a value [resolveEnvironment] returns is validated by
/// construction.
class AvailableEnvironments {
  /// Creates the presence set over [values].
  const AvailableEnvironments(this.values);

  /// Every armed environment the registry validated at boot - the default
  /// presence set before the availability seed publishes live probes.
  factory AvailableEnvironments.fromRegistry(EnvironmentRegistry registry) =>
      AvailableEnvironments(registry.validatedEnvironments.toSet());

  /// Nothing is present (mirrors `SiteBinding.none`).
  static const AvailableEnvironments none = AvailableEnvironments(
    <AgentEnvironment>{},
  );

  /// The present environments. Unordered - presence is set membership.
  final Set<AgentEnvironment> values;

  /// Whether [environment] is present, compared in the
  /// [AgentEnvironment.flattened] NORMAL FORM, so a canned layer authored
  /// beside a station's arming matches the registry's flattened resolution of
  /// the same environment (they differ only in `base`).
  bool contains(AgentEnvironment environment) {
    final wanted = environment.flattened;
    return values.any((v) => v.flattened == wanted);
  }

  @override
  bool operator ==(Object other) =>
      other is AvailableEnvironments && _unorderedEquals(other.values, values);

  @override
  int get hashCode => Object.hashAllUnordered(values);

  @override
  String toString() => 'AvailableEnvironments($values)';
}

/// The ambient presence set: the mounted [AvailableEnvironments], or - until
/// the availability seed (bead `pow-n6n.3`) mounts one - the ambient
/// [EnvironmentRegistry]'s boot-validated members, falling back to the station
/// builtins exactly as every spawn site already does
/// (`readiness.dart:372`, `code_capabilities.dart:235`).
AvailableEnvironments availableEnvironmentsOf(TreeContext context) =>
    context.getInheritedSeedOfExactType<AvailableEnvironments>() ??
    AvailableEnvironments.fromRegistry(
      context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
          buildBuiltinEnvironmentRegistry(),
    );

/// The availability WALK: the first entry of [preference] present in the
/// ambient [AvailableEnvironments], or null when none is present.
///
/// PUBLIC because bead `pow-n6n.2`'s critic lane picks its [ModelPreference] by
/// ASPECT before the walk runs, and one walk beats two copies.
AgentEnvironment? firstAvailable(
  TreeContext context,
  ModelPreference preference,
) {
  final available = availableEnvironmentsOf(context);
  for (final candidate in preference.entries) {
    if (available.contains(candidate)) return candidate;
  }
  return null;
}

/// The EFFECTIVE typed lookup - the one function a spawn site calls (bead
/// `pow-n6n.2` wires the six of them).
///
/// Resolves, in order:
///  1. the SPECIFIC preference [TSpecific] - an exact-type, nearest-ancestor
///     read, so a seat's own type shadows the station default;
///  2. else the GENERIC [ModelPreference];
///  3. then [firstAvailable] over that preference.
///
/// Null when no preference is mounted at all, or when no entry is present: the
/// caller simply falls to the next rung (`resolveAgentConfig`'s `ambient.harness`
/// — bead `pow-n6n.4` deleted the role -> env rung that used to sit between).
///
/// THE EFFECT VERB, deliberately: `getInheritedSeedOfExactType`, not the
/// subscribing `dependOn*`. Per the D-H doctrine (ADR-0008 D3; ADR-0000 A8(3))
/// the subscribing verb is for `build`, while this is the effect-boundary
/// resolver called at a capability's `spawn`/`run` edge - exactly where
/// `sourceControlOf(TreeContext)` sits, and for the same reason.
AgentEnvironment? resolveEnvironment<TSpecific extends ModelPreference>(
  TreeContext context,
) {
  final preference =
      context.getInheritedSeedOfExactType<TSpecific>() ??
      context.getInheritedSeedOfExactType<ModelPreference>();
  return preference == null ? null : firstAvailable(context, preference);
}

bool _orderedEquals(List<AgentEnvironment> a, List<AgentEnvironment> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _unorderedEquals(Set<AgentEnvironment> a, Set<AgentEnvironment> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}
