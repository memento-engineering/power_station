/// The `grid.agent` DOMAIN — the per-bead rung of the agent-config ladder
/// (ADR-0008 Decision 10 / D-C rung 3), over the shared domain-envelope
/// machinery (`dart_grid_assets`).
///
/// A work bead may carry ONE top-level metadata key:
///
/// ```json
/// { "grid.agent": { "assets_version": "0.0.1", "payload": {
///     "harness": "opencode",
///     "params": { "model": "qwen2.5-coder" } } } }
/// ```
///
/// A bead names a COMPLETE ENVIRONMENT via `env` (the full {harness, target,
/// model} the registry resolves it to) or diverges a SINGLE axis via `harness`
/// (the tool) or `params.model` (the model); `env` outranks `harness` within a
/// rung. WHERE inference runs is the environment's own `target` bound to a
/// machine-local endpoint by the site binding (ADR-0002 D3/D4). A stale `target`
/// key in the envelope is REFUSED WHOLE — the endpoint never rides a bead.
///
/// The envelope's `params.model` is the TOP rung of the model ladder (bead
/// `pow-edp`): it overrides the station's `--model`/`--grader-model` and the
/// asset role defaults alike, for every agent that bead spawns — build and
/// grader both. A blank model is a MALFORMATION, refused whole (never a silent
/// fall-through to the role default).
///
/// Every payload field is optional (an override, not a full config). Decode is
/// FAIL-CLOSED (the envelope precedent: refuse whole, never a partial parse of
/// a newer/garbled shape) — and per OQ-c moment 2, a refused envelope fails
/// THAT work (`resolveAgentConfig` throws → the allocation reports `Failed` →
/// supervision/gate), never the station.
library;

import 'package:dart_grid_assets/dart_grid_assets.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'environment_registry.dart';

/// The `grid.agent` metadata key (one slot per domain — the top-level-key
/// merge granularity).
const String kAgentDomainKey = 'grid.agent';

/// This pack's `grid.agent` shape version (pre-1.0: minor = breaking).
const String kAgentAssetsVersion = '0.0.1';

/// A partial, per-bead override of the ambient [AgentConfig] — every field
/// optional; merged over the ambient value in ladder order.
class AgentConfigOverride {
  /// Creates the override.
  const AgentConfigOverride({this.env, this.harness, this.params});

  /// Overrides the environment NAME — the full {harness, target, model} the
  /// registry resolves it to (null ⇒ keep ambient). Names a COMPLETE
  /// environment; [harness] names only the tool. Which wins across rungs is
  /// [resolveAgentConfig]'s precedence, not this type's.
  final String? env;

  /// Overrides the harness id (null ⇒ keep ambient).
  final String? harness;

  /// Merged key-wise over the ambient params (null ⇒ keep ambient).
  final Map<String, String>? params;

  /// Applies this override onto [base]. The environment NAME (env/harness) is
  /// resolved by [resolveAgentConfig]'s rung precedence, not here; this applies
  /// the [params] merge and the legacy [harness] axis.
  AgentConfig applyTo(AgentConfig base) =>
      base.merge(harness: harness, params: params);
}

/// Decodes a bead's `grid.agent` envelope off its [metadata] — fail-closed via
/// the shared machinery ([decodeDomainEnvelope]): absent is the common case
/// (no override); an incompatible or malformed envelope REFUSES WHOLE.
DomainEnvelopeResult<AgentConfigOverride> decodeAgentEnvelope(
  Map<String, dynamic> metadata,
) => decodeDomainEnvelope<AgentConfigOverride>(
  metadata,
  domainKey: kAgentDomainKey,
  assetsVersion: kAgentAssetsVersion,
  parsePayload: _parsePayload,
);

AgentConfigOverride _parsePayload(Map<String, Object?> payload) {
  final harness = payload['harness'];
  if (harness != null && harness is! String) {
    throw const FormatException('"harness" must be a string');
  }
  if (payload.containsKey('target')) {
    throw const FormatException(
      '"target" is no longer a bead override (ADR-0002 D3/D4): a bead names an '
      'environment via "harness"; the endpoint is a machine-local site-binding '
      'fact, never a bead. Remove "target" and name a target-bound environment.',
    );
  }
  final env = payload['env'];
  if (env != null && env is! String) {
    throw const FormatException('"env" must be a string');
  }
  Map<String, String>? params;
  final rawParams = payload['params'];
  if (rawParams != null) {
    if (rawParams is! Map) {
      throw const FormatException('"params" must be an object');
    }
    params = rawParams.map((k, v) {
      if (k is! String || v is! String) {
        throw const FormatException('"params" entries must be string→string');
      }
      return MapEntry(k, v);
    });
  }
  final beadModel = params?['model'];
  if (beadModel != null && beadModel.trim().isEmpty) {
    throw const FormatException(
      '"params.model" must be a non-empty model name (a blank model would '
      'silently fall through to the role default — refused whole)',
    );
  }
  return AgentConfigOverride(
    env: env as String?,
    harness: harness as String?,
    params: params,
  );
}

/// The effect-boundary resolution (the D-C ladder as a pure value merge).
///
/// TWO ladders, resolved together for the [role] the SPAWNING ASSET declares:
///
///  - **the NAME ladder** (which environment/harness runs) — a rung names a
///    COMPLETE environment via `env`, or diverges the tool only via `harness`;
///    *step env/harness > bead env/harness > role → env
///    ([AgentConfig.roleEnvironments]; an unarmed architect tries the build
///    role's environment) > ambient.harness*, the more-specific rung winning.
///    The winner is resolved through [registry] to the full {harness,
///    target, model}. WHERE inference runs is that environment's own `target`
///    bound by the site binding (ADR-0002 D3), never a step/bead rung;
///  - **the MODEL ladder** (beads `pow-edp` / `pow-2c9`) — *bead `grid.agent`
///    `params.model` > the NAMED environment's own model (role → env's model;
///    null on every builtin) > the STATION's arming of the role's TIER
///    ([AgentConfig.modelForRole]: [tierFor] the role, then [ModelTiers] —
///    which falls through to that tier's asset default)*. The winner is STAMPED
///    into the returned config's `params['model']` — the transport key every
///    harness reads — so a grader rides the mid tier while a builder rides the
///    frontier off the same ambient config, a gatherer rides cheap, and no
///    harness needs to know a role or a tier exists.
///
/// The returned config ALWAYS names an explicit model (no silent fallback to the
/// harness CLI's own default — the fable/opus incident).
///
/// Validates the resolved config against [registry] and FAILS CLOSED (throws
/// [StateError]) on: an incompatible/malformed envelope (including a blank
/// `params.model`), an unknown environment name, or an illegal harness × target
/// combo — the engine's allocation catches the throw and routes it to
/// supervision as a per-work `Failed` (OQ-c moment 2: one bad bead parks loudly;
/// the station never crashes).
AgentConfig resolveAgentConfig({
  required AgentRole role,
  required AgentConfig ambient,
  required Map<String, dynamic> beadMetadata,
  required Map<String, String> stepParams,
  required EnvironmentRegistry registry,
}) {
  var config = ambient;
  String? beadModel;
  String? beadName; // bead env ?? bead harness (rung 3), empty-safe.

  // Rung 3 — the bead's grid.agent envelope (fail-closed, refuse whole). Its
  // `params.model` is the MOST explicit rung of the model ladder; its `env`/
  // `harness` name the environment for this bead's agents.
  switch (decodeAgentEnvelope(beadMetadata)) {
    case DomainEnvelopeDecoded<AgentConfigOverride>(config: final override):
      config = override.applyTo(config);
      beadModel = override.params?['model'];
      beadName = _nonEmpty(override.env) ?? _nonEmpty(override.harness);
    case DomainEnvelopeAbsent<AgentConfigOverride>():
      break; // the common case — no per-bead override.
    case DomainEnvelopeIncompatible<AgentConfigOverride>(:final version):
      throw StateError(
        'grid.agent envelope written by an incompatible pack version '
        '"$version" (ours: $kAgentAssetsVersion) — refused whole',
      );
    case DomainEnvelopeMalformed<AgentConfigOverride>(:final reason):
      throw StateError('grid.agent envelope malformed: $reason');
  }

  // Rung 4 — step params: `env` names the whole environment, `harness` the tool
  // only. A step diverges WHICH environment/tool runs, never the machine's
  // endpoint wiring (no `target` rung — ADR-0002 D3).
  final stepName =
      _nonEmpty(stepParams['env']) ?? _nonEmpty(stepParams['harness']);

  // Rung 5 — role → env (the station's arming; the successor to role → tier).
  // ARCHITECT is compatibility-special: an explicit architect arming wins;
  // otherwise it inherits BUILD's environment before the ambient harness, so
  // stations that armed only BUILD keep their pre-split behavior.
  final roleName = switch (role) {
    AgentRole.build => ambient.roleEnvironments[AgentRole.build],
    AgentRole.architect =>
      ambient.roleEnvironments[AgentRole.architect] ??
          ambient.roleEnvironments[AgentRole.build],
    AgentRole.grade => ambient.roleEnvironments[AgentRole.grade],
    AgentRole.gather => ambient.roleEnvironments[AgentRole.gather],
  };

  // The resolved environment NAME → config.harness (the registry key every
  // caller resolves and the site binding keys on). Most-specific rung wins;
  // TOTAL because ambient.harness is a non-null default.
  final name = stepName ?? beadName ?? roleName ?? ambient.harness;
  config = config.merge(harness: name);

  // Legality (OQ-c moment 2, fail-closed): the resolved name must be an armed,
  // self-consistent environment. resolve THROWS on unknown/cyclic/dangling; the
  // engine's allocation routes the throw to supervision as a per-work Failed.
  final AgentEnvironment env;
  try {
    env = registry.resolve(config.harness);
  } on EnvironmentRegistryError catch (e) {
    throw StateError('agent config: ${e.message}');
  }
  final selfCheck = env.validate();
  if (selfCheck != null) {
    throw StateError(
      'agent config: environment "${config.harness}" is illegal: '
      '$selfCheck',
    );
  }

  // The MODEL ladder, stamped into the harness transport key: the bead's pinned
  // model (TOP, every role of that bead) > the NAMED environment's own model
  // (role → env's model; null on every builtin) > role → tier → model
  // (ambient.modelForRole — the pre-env ladder, STILL FUNCTIONING until the
  // shim-deletion bead removes it). TOTAL: modelForRole never returns null.
  config = config.merge(
    params: {'model': beadModel ?? env.model ?? ambient.modelForRole(role)},
  );
  return config;
}

/// Null when [s] is null or empty, else [s] — an empty rung value NAMES nothing
/// (the `stepHarness.isNotEmpty` precedent), so it never shadows a lower rung.
String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
