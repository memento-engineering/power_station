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
/// A bead names an ENVIRONMENT via `harness`; WHERE inference runs is the
/// environment's own `target` bound to a machine-local endpoint by the site
/// binding (ADR-0002 D3/D4). A stale `target` key in the envelope is REFUSED
/// WHOLE — the endpoint never rides a bead.
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
  const AgentConfigOverride({this.harness, this.params});

  /// Overrides the harness id (null ⇒ keep ambient).
  final String? harness;

  /// Merged key-wise over the ambient params (null ⇒ keep ambient).
  final Map<String, String>? params;

  /// Applies this override onto [base].
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
    harness: harness as String?,
    params: params,
  );
}

/// The effect-boundary resolution (the D-C ladder as a pure value merge).
///
/// TWO ladders, resolved together for the [role] the SPAWNING ASSET declares:
///
///  - **the config ladder** (harness / target / params) — *step params > bead
///    envelope > ambient*, unchanged;
///  - **the MODEL ladder** (beads `pow-edp` / `pow-2c9`) — *bead `grid.agent`
///    `params.model` > the STATION's arming of the role's TIER
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
/// `params.model`), an unknown harness, or an illegal harness × target combo —
/// the engine's allocation catches the throw and routes it to supervision as a
/// per-work `Failed` (OQ-c moment 2: one bad bead parks loudly; the station
/// never crashes).
AgentConfig resolveAgentConfig({
  required AgentRole role,
  required AgentConfig ambient,
  required Map<String, dynamic> beadMetadata,
  required Map<String, String> stepParams,
  required EnvironmentRegistry registry,
}) {
  var config = ambient;
  String? beadModel;

  // Rung 3 — the bead's grid.agent envelope (fail-closed, refuse whole). Its
  // `params.model` is the MOST explicit rung of the model ladder: it overrides
  // the station AND the asset default, for BOTH roles of that bead's agents.
  switch (decodeAgentEnvelope(beadMetadata)) {
    case DomainEnvelopeDecoded<AgentConfigOverride>(config: final override):
      config = override.applyTo(config);
      beadModel = override.params?['model'];
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

  // Rung 4 — step params (harness-id only — a step diverges WHICH tool runs,
  // never the machine's endpoint wiring).
  final stepHarness = stepParams['harness'];
  if (stepHarness != null && stepHarness.isNotEmpty) {
    config = config.merge(harness: stepHarness);
  }

  // The MODEL ladder, resolved for the spawner's ROLE through the TIER axis
  // (bead `pow-2c9`) and stamped into the harness transport key: the bead's
  // pinned model, else the STATION's arming of the role's tier — which itself
  // falls through to that tier's asset default, so the result is TOTAL (there
  // is no third `??` and no unpinned spawn). Read off the AMBIENT: a bead
  // envelope carries no tier arming, and its model — when present — already won
  // above.
  config = config.merge(
    params: {'model': beadModel ?? ambient.modelForRole(role)},
  );

  // Legality (OQ-c moment 2, fail-closed): the resolved harness must name an armed,
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
    throw StateError('agent config: environment "${config.harness}" is illegal: '
        '$selfCheck');
  }
  return config;
}
