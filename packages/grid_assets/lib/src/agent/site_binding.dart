/// The **site binding** — a box's MACHINE FACTS as a value (ADR-0002 D3): the
/// inference endpoint each NAMED environment reaches on THIS box. The
/// machine-local half of the split gc draws between committed `city.toml`
/// (rigs by NAME) and machine-local `.gc/site.toml` (name -> path on this box),
/// applied to INFERENCE ENDPOINTS.
///
/// `InferenceTarget` (bead `pow-ebf.2`) names the KIND (providerManaged /
/// openAiCompatible / swiftInfer) — endpoint-free and portable. This binds the
/// WHERE: the endpoint url leaves committed source, argv, and beads (ADR-0002
/// D3/D4) and lives ONLY here. An environment whose machine fact is UNBOUND on
/// this box REFUSES at boot — loud, naming the environment, the missing fact,
/// and the fix; NEVER a silent fallback default (ADR-0000 A20 no-wedge; A8
/// guards LOUD or GONE).
///
/// A VALUE only (power_station CLAUDE.md D-H doctrine "config = VALUES in the
/// tree; impls are DI"): the MOUNT as an `InheritedSeed<SiteBinding>` and the
/// boot-time throw of its refusal are the composition root's (bead `pow-ebf.5`);
/// the registry boot-eager check (bead `pow-ebf.3`) calls [SiteBinding.validate].
/// This library carries no `build`, no tree read, and no I/O beyond
/// [SiteBinding.loadJsonFile].
///
/// The file FORMAT is an implementation detail (ADR-0002 D2): the simplest thing
/// that works — a version-stamped JSON object decoded by `dart:convert`,
/// mirroring `RespecLedger` (`lib/src/code/respec.dart`).
library;

import 'dart:convert';
import 'dart:io';

import 'agent_environment.dart';

/// This pack's site-binding wire version (pre-1.0: a bump is breaking). A
/// document written by any other version REFUSES rather than mis-parsing (the
/// envelope precedent — fail closed on a shape you do not own).
const int kSiteBindingVersion = 1;

/// The conventional machine-local site-binding file, under the already-gitignored
/// `.grid/` (never committed — the endpoint never enters version control). Named
/// in refusals so "the fix" points at a real path; WHERE the composition root
/// reads it from is its call (bead `pow-ebf.5`) — this only names the convention.
const String kSiteBindingFile = '.grid/site.json';

/// A LOUD refusal (ADR-0000 A8 "guards LOUD or GONE"): an armed environment's
/// inference endpoint is UNBOUND on this box. Thrown by [SiteBinding.endpointFor];
/// its [message] names the environment, the missing fact, and the fix.
class SiteBindingError implements Exception {
  /// Creates the error over its human [message].
  const SiteBindingError(this.message);

  /// The refusal message (names the environment, the missing fact, the fix).
  final String message;

  @override
  String toString() => 'SiteBindingError: $message';
}

/// A box's machine facts: environment NAME -> the inference endpoint it reaches
/// on THIS box. See the library doc.
class SiteBinding {
  /// Creates a binding over [endpoints] (environment name -> endpoint url).
  const SiteBinding(this.endpoints);

  /// The empty binding — no environment reaches a machine endpoint here (a box
  /// running only provider-managed tools). Distinct from "unbound for X": an
  /// endpoint-needing environment armed against [none] REFUSES.
  static const SiteBinding none = SiteBinding(<String, Uri>{});

  /// Environment NAME -> the endpoint it reaches on this box. A name ABSENT from
  /// this map is UNBOUND (a refusal for an endpoint-needing target — never a
  /// silent default).
  final Map<String, Uri> endpoints;

  /// Parses a decoded machine-local document — a `version` int and an
  /// `endpoints` object of environment-name-to-url string pairs. LOUD (ADR-0000
  /// A23 "RENDERS and REFUSES"): an unsupported version, a non-object
  /// `endpoints`, a blank/non-string name or url, or a non-absolute url throws
  /// [FormatException] — a malformed machine fact refuses rather than binding a
  /// garbage endpoint.
  factory SiteBinding.parse(Map<String, Object?> raw) {
    final version = raw['version'];
    if (version is! int || version != kSiteBindingVersion) {
      throw FormatException(
        'site binding "version" is "$version" — this pack reads '
        '$kSiteBindingVersion only (refused whole)',
      );
    }
    final rawEndpoints = raw['endpoints'];
    if (rawEndpoints is! Map) {
      throw const FormatException('site binding "endpoints" must be an object');
    }
    final endpoints = <String, Uri>{};
    rawEndpoints.forEach((key, value) {
      if (key is! String || key.isEmpty) {
        throw const FormatException(
          'site binding endpoint name must be a non-empty string',
        );
      }
      if (value is! String || value.trim().isEmpty) {
        throw FormatException(
          'site binding "$key" endpoint must be a non-empty url string',
        );
      }
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw FormatException(
          'site binding "$key" endpoint is not an absolute url: "$value"',
        );
      }
      endpoints[key] = uri;
    });
    return SiteBinding(endpoints);
  }

  /// Decodes a JSON site-binding document (the simplest format that works —
  /// ADR-0002 D2). Delegates shape validation to [SiteBinding.parse].
  factory SiteBinding.fromJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('site binding must be a JSON object');
    }
    return SiteBinding.parse(decoded.cast<String, Object?>());
  }

  /// Loads the machine-local binding at [path], or [none] when the file is
  /// ABSENT — a box with only provider-managed environments needs no site file;
  /// absence is legal, and an armed endpoint-needing environment is what refuses,
  /// not the missing file. THROWS on a file that EXISTS but is malformed (ADR-0000
  /// A23 REFUSES). The composition root chooses [path] (conventionally
  /// [kSiteBindingFile]); this reads it.
  static SiteBinding loadJsonFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return none;
    return SiteBinding.fromJson(file.readAsStringSync());
  }

  /// The refusal MESSAGE for environment [name] with its resolved [environment],
  /// or null when legal (a provider-managed target needs no fact; a bound
  /// endpoint is legal). Return-don't-throw — the boot-eager half of two-moment
  /// validation (ADR-0002 D3; the posture of `AgentEnvironment.validate`): the
  /// composition root throws on non-null so a misconfigured box fails BEFORE any
  /// work mounts. Names the environment, the missing fact, and the fix.
  String? refusalFor({
    required String name,
    required AgentEnvironment environment,
  }) {
    if (!environment.needsSiteEndpoint) return null;
    if (endpoints.containsKey(name)) return null;
    final fact = _factLabel(
      environment.target ?? InferenceTarget.providerManaged,
    );
    return 'environment "$name" needs a $fact endpoint but none is bound on '
        'this box — bind it in the machine-local site binding '
        '($kSiteBindingFile), e.g. {"version": $kSiteBindingVersion, '
        '"endpoints": {"$name": "<url>"}}. An unbound machine fact REFUSES '
        'rather than silently defaulting to a fallback endpoint.';
  }

  /// The endpoint environment [name] reaches on this box, or null when its
  /// resolved [environment] is provider-managed (needs no machine fact). THROWS
  /// [SiteBindingError] (LOUD — ADR-0000 A8 guards LOUD or GONE; A20 no-wedge)
  /// when the target needs an endpoint UNBOUND here: never a silent default.
  Uri? endpointFor({
    required String name,
    required AgentEnvironment environment,
  }) {
    final refusal = refusalFor(name: name, environment: environment);
    if (refusal != null) throw SiteBindingError(refusal);
    return environment.needsSiteEndpoint ? endpoints[name] : null;
  }

  /// The BOOT-EAGER check (two-moment validation, moment 1 — ADR-0002 D3): the
  /// FIRST armed environment whose machine fact is unbound, as its refusal
  /// message, or null when every armed environment is bound. The registry (bead
  /// `pow-ebf.3`) and the ladder (bead `pow-ebf.5`) call this at the composition
  /// root and throw on non-null — a misconfigured box fails before work mounts.
  /// [armed] is the station's arming (environment name -> resolved environment).
  String? validate(Map<String, AgentEnvironment> armed) {
    for (final entry in armed.entries) {
      final refusal = refusalFor(name: entry.key, environment: entry.value);
      if (refusal != null) return refusal;
    }
    return null;
  }

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`;
  /// mirrors `RespecLedger.toJson`). Round-trips through [SiteBinding.fromJson].
  Map<String, Object?> toJson() => {
    'version': kSiteBindingVersion,
    'endpoints': {for (final e in endpoints.entries) e.key: e.value.toString()},
  };

  @override
  bool operator ==(Object other) =>
      other is SiteBinding && _endpointsEq(other.endpoints, endpoints);

  @override
  int get hashCode => Object.hashAllUnordered(
    endpoints.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'SiteBinding($endpoints)';
}

/// A human label for the missing machine fact in a refusal. `providerManaged`
/// never reaches here (it needs no endpoint) but is total for the exhaustive
/// switch (house style).
String _factLabel(InferenceTarget target) => switch (target) {
  InferenceTarget.providerManaged => 'provider-managed',
  InferenceTarget.openAiCompatible => 'OpenAI-compatible',
  InferenceTarget.swiftInfer => 'swift-infer',
};

bool _endpointsEq(Map<String, Uri> a, Map<String, Uri> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
