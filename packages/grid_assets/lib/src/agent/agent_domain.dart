/// The `grid.agent` DOMAIN — the per-bead rung of the agent-config ladder
/// (ADR-0008 Decision 10 / D-C rung 3), over the shared domain-envelope
/// machinery (`dart_grid_assets`).
///
/// A work bead may carry ONE top-level metadata key:
///
/// ```json
/// { "grid.agent": { "assets_version": "0.0.1", "payload": {
///     "harness": "opencode",
///     "target": { "kind": "openai", "base": "http://dashboard:8080/v1" },
///     "params": { "model": "qwen2.5-coder" } } } }
/// ```
///
/// Every payload field is optional (an override, not a full config). Decode is
/// FAIL-CLOSED (the envelope precedent: refuse whole, never a partial parse of
/// a newer/garbled shape) — and per OQ-c moment 2, a refused envelope fails
/// THAT work (`resolveAgentConfig` throws → the allocation reports `Failed` →
/// supervision/gate), never the station.
library;

import 'package:dart_grid_assets/dart_grid_assets.dart';

import 'agent_harness.dart';

/// The `grid.agent` metadata key (one slot per domain — the top-level-key
/// merge granularity).
const String kAgentDomainKey = 'grid.agent';

/// This pack's `grid.agent` shape version (pre-1.0: minor = breaking).
const String kAgentAssetsVersion = '0.0.1';

/// A partial, per-bead override of the ambient [AgentConfig] — every field
/// optional; merged over the ambient value in ladder order.
class AgentConfigOverride {
  /// Creates the override.
  const AgentConfigOverride({this.harness, this.target, this.params});

  /// Overrides the harness id (null ⇒ keep ambient).
  final String? harness;

  /// Overrides the model target (null ⇒ keep ambient).
  final ModelTarget? target;

  /// Merged key-wise over the ambient params (null ⇒ keep ambient).
  final Map<String, String>? params;

  /// Applies this override onto [base].
  AgentConfig applyTo(AgentConfig base) =>
      base.merge(harness: harness, target: target, params: params);
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
  ModelTarget? target;
  final rawTarget = payload['target'];
  if (rawTarget != null) {
    if (rawTarget is! Map) {
      throw const FormatException('"target" must be an object');
    }
    target = _parseTarget(rawTarget.cast<String, Object?>());
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
  return AgentConfigOverride(
    harness: harness as String?,
    target: target,
    params: params,
  );
}

ModelTarget _parseTarget(Map<String, Object?> target) {
  final kind = target['kind'];
  if (kind is! String) {
    throw const FormatException('"target.kind" must be a string');
  }
  Uri base() {
    final raw = target['base'];
    if (raw is! String || raw.isEmpty) {
      throw FormatException('"target.base" is required for kind "$kind"');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      throw FormatException('"target.base" is not an absolute url: "$raw"');
    }
    return uri;
  }

  return switch (kind) {
    'provider' => const ProviderManaged(),
    'openai' => OpenAiCompatible(base()),
    'swift' => SwiftInfer(base()),
    _ => throw FormatException(
      'unknown "target.kind" "$kind" (provider | openai | swift)',
    ),
  };
}

/// The effect-boundary resolution (the D-C ladder as a pure value merge):
/// **step params > bead envelope > ambient**. Validates the resolved config
/// against [registry] and FAILS CLOSED (throws [StateError]) on: an
/// incompatible/malformed envelope, an unknown harness, or an illegal
/// harness × target combo — the engine's allocation catches the throw and
/// routes it to supervision as a per-work `Failed` (OQ-c moment 2: one bad
/// bead parks loudly; the station never crashes).
AgentConfig resolveAgentConfig({
  required AgentConfig ambient,
  required Map<String, dynamic> beadMetadata,
  required Map<String, String> stepParams,
  required AgentHarnessRegistry registry,
}) {
  var config = ambient;

  // Rung 3 — the bead's grid.agent envelope (fail-closed, refuse whole).
  switch (decodeAgentEnvelope(beadMetadata)) {
    case DomainEnvelopeDecoded<AgentConfigOverride>(config: final override):
      config = override.applyTo(config);
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

  // Rung 4 — step params (highest precedence; harness-id only — a step
  // diverges WHICH tool runs, never the machine's endpoint wiring).
  final stepHarness = stepParams['harness'];
  if (stepHarness != null && stepHarness.isNotEmpty) {
    config = config.merge(harness: stepHarness);
  }

  // Legality — the shared OQ-c check.
  final error = registry.validate(config);
  if (error != null) throw StateError('agent config: $error');
  return config;
}
