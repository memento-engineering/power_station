/// The MODEL TIER — the axis model selection actually varies on (bead
/// `pow-2c9`, refining ADR-0000 A20).
///
/// A20 mapped the spawn's role to a model DIRECTLY, so every new role had to
/// grow its own model field on the station config, and retuning a class of work
/// ("grading is cheap now") had to touch the roles that ride it. Selection is
/// really TWO maps: a DOMAIN policy (role → tier — `tierFor`, in
/// `agent_harness.dart`, where the role lives) and a STATION arming (tier →
/// model — this library). This half is deliberately dependency-free, so a tier
/// can be retuned without a role, a capability, or the engine ever hearing
/// about it.
library;

/// The model CLASS a spawn rides — the selection axis. Sealed by the enum:
/// consumers switch exhaustively (house style), so a new tier cannot be added
/// without every arming site naming its model.
enum AgentTier {
  /// Cheap and fast: read-only discovery, gathering, mechanical triage.
  cheap,

  /// The working middle: grading a pinned diff against ONE rubric.
  mid,

  /// The strongest model available: the build IS the work.
  frontier,
}

/// The [AgentTier.cheap] rung's asset-default model.
const String kCheapModelDefault = 'haiku';

/// The [AgentTier.mid] rung's asset-default model.
const String kMidModelDefault = 'sonnet';

/// The [AgentTier.frontier] rung's asset-default model.
const String kFrontierModelDefault = 'opus';

/// The model [tier] rides when the station arms none — the ASSET rung, the
/// bottom of the model ladder.
///
/// ALWAYS an explicit model id, never null: an unpinned `claude` resolved to
/// opus and then SILENTLY fell back to fable once the weekly limit blew
/// (2026-07-11), so no rung of this ladder is allowed to return nothing.
String defaultModelForTier(AgentTier tier) => switch (tier) {
  AgentTier.cheap => kCheapModelDefault,
  AgentTier.mid => kMidModelDefault,
  AgentTier.frontier => kFrontierModelDefault,
};

/// The STATION's arming of tier → model — a pure VALUE the tree carries
/// (config = VALUES in the tree, impls = DI). Every field is a SPARSE override:
/// null ⇒ that tier rides [defaultModelForTier].
///
/// Retuning a tier is ONE arming change here and moves every role on that tier;
/// it never touches a role, a capability, or a config field.
class ModelTiers {
  /// Arms the tiers the station names (null ⇒ that tier's asset default).
  const ModelTiers({this.cheap, this.mid, this.frontier});

  /// The station's [AgentTier.cheap] model (null ⇒ [kCheapModelDefault]).
  final String? cheap;

  /// The station's [AgentTier.mid] model (null ⇒ [kMidModelDefault]).
  final String? mid;

  /// The station's [AgentTier.frontier] model (null ⇒ [kFrontierModelDefault]).
  final String? frontier;

  /// The station's EXPLICIT arming of [tier] — null when it armed none.
  String? armed(AgentTier tier) => switch (tier) {
    AgentTier.cheap => cheap,
    AgentTier.mid => mid,
    AgentTier.frontier => frontier,
  };

  /// The model [tier] rides: the station's arming, else the tier's asset
  /// default. Never null — every tier names a real model.
  String modelFor(AgentTier tier) => armed(tier) ?? defaultModelForTier(tier);

  /// A copy with the non-null armings applied (a sparse, key-wise merge — an
  /// unnamed tier keeps its current arming).
  ModelTiers merge({String? cheap, String? mid, String? frontier}) =>
      ModelTiers(
        cheap: cheap ?? this.cheap,
        mid: mid ?? this.mid,
        frontier: frontier ?? this.frontier,
      );

  @override
  bool operator ==(Object other) =>
      other is ModelTiers &&
      other.cheap == cheap &&
      other.mid == mid &&
      other.frontier == frontier;

  @override
  int get hashCode => Object.hash(ModelTiers, cheap, mid, frontier);

  @override
  String toString() =>
      'ModelTiers(cheap: $cheap, mid: $mid, frontier: $frontier)';
}
