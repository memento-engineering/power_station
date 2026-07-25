/// The environment REGISTRY (ADR-0002 D3, bead `pow-ebf.3`) — the station's
/// ARMING: the map from a NAME ('frontier', 'local-cheap', 'codex-frontier') to
/// the [AgentEnvironment] it MEANS on this box. The indirection that keeps beads
/// and steps PORTABLE: a step names 'local-cheap'; the station decides that means
/// swift-infer here and something else in CI.
///
/// It REPLACES `AgentHarnessRegistry` (id → `AgentHarness` impl) with
/// name → [AgentEnvironment] (a VALUE — config = VALUES in the tree, impls are
/// DI; power_station CLAUDE.md D-H doctrine / ADR-0000 A8). Per the bead it lands
/// SIDE-BY-SIDE with `AgentHarnessRegistry`; the harness collapse (bead
/// `pow-ebf.4`) deletes the old one (bd memory `no-deprecations-until-public`).
///
/// TWO-MOMENT VALIDATION (kept from ADR-0008 D10 via ADR-0002 "supersedes"):
///  - MOMENT 1 — BOOT-EAGER ([validate]) at the composition root: a misconfigured
///    machine fails BEFORE any work mounts. Returns the FIRST refusal message
///    (return-don't-throw — the posture of `AgentHarnessRegistry.validate` /
///    `SiteBinding.validate`); the composition root throws on a non-null return.
///  - MOMENT 2 — PER-WORK, fail-closed ([resolve]): an unknown / cyclic /
///    dangling name THROWS [EnvironmentRegistryError]; the engine's allocation
///    catches it and routes the ONE bad bead to supervision as a Failed. The
///    station never crashes.
///
/// The refusal MESSAGES name the environment, the missing thing, and the fix (the
/// `AgentHarnessRegistry.validate` 'unknown harness "x" (registered: …)' and gc
/// `missingRigSiteBindingWarning` precedent — a refusal that does not tell you
/// what to type is half a refusal; ADR-0000 A8 guards LOUD or GONE).
library;

import 'agent_environment.dart';
import 'model_tier.dart';
import 'site_binding.dart';

/// A LOUD, fail-closed refusal (ADR-0000 A8 "guards LOUD or GONE") thrown by
/// [EnvironmentRegistry.resolve] (moment 2): an unknown environment name, a
/// `base` cycle, or a dangling `base`. Its [message] names the environment, the
/// missing thing, and the fix. Mirrors `SiteBindingError`.
class EnvironmentRegistryError implements Exception {
  /// Creates the error over its human [message].
  const EnvironmentRegistryError(this.message);

  /// The refusal message (names the environment, the missing thing, the fix).
  final String message;

  @override
  String toString() => 'EnvironmentRegistryError: $message';
}

/// name → [AgentEnvironment], across TWO namespaces (gc's builtin-vs-custom
/// `base` grammar — [BaseScope]): [builtins] are the shipped defaults (empty
/// here; the harness collapse `pow-ebf.4` supplies claude/copilot/pi/opencode as
/// data), [custom] the box/substation authoring. A name in BOTH: [custom] is the
/// leaf and a same-named [builtins] entry layers UNDER it (the [EnvBaseUndeclared]
/// convention).
class EnvironmentRegistry {
  /// Creates the registry over its [custom] authoring and optional [builtins]
  /// (shipped defaults; empty until `pow-ebf.4` supplies them).
  const EnvironmentRegistry({required this.custom, this.builtins = const {}});

  /// The shipped-default environments (gc `builtin:` scope). Empty until the
  /// harness collapse (`pow-ebf.4`) supplies them as data.
  final Map<String, AgentEnvironment> builtins;

  /// The box/substation-authored environments (gc `provider:` scope).
  final Map<String, AgentEnvironment> custom;

  /// Every armed NAME (custom ∪ builtin), sorted for stable refusal text.
  Iterable<String> get names =>
      <String>{...builtins.keys, ...custom.keys}.toList()..sort();

  /// MOMENT 2 (per-work, fail-closed): the FLATTENED environment armed under
  /// [name], its `base` chain walked (honoring the [BaseScope] grammar and the
  /// standalone barrier) and folded via [AgentEnvironment.resolve]. THROWS
  /// [EnvironmentRegistryError] on an unknown name, a `base` cycle, or a dangling
  /// `base` — NEVER a silent default.
  AgentEnvironment resolve(String name) =>
      AgentEnvironment.resolve(_chain(name));

  /// MOMENT 1 (boot-eager): the FIRST refusal message across the whole armed set,
  /// or null when the box is legally configured. Checks, in order:
  ///  1. every armed name RESOLVES (no cycle, no dangling `base`);
  ///  2. every resolved environment is a LEGAL harness×target combo — with the
  ///     harness now DATA there is no `supports(target)` table, so legality is the
  ///     environment's own self-consistency ([AgentEnvironment.validate], the
  ///     direct successor to `AgentHarness.supports`) plus a `command` to spawn;
  ///  3. every name a ROLE maps to is ARMED ([roleEnvironments] — the role→name
  ///     values the ladder `pow-ebf.5` supplies; role-agnostic here);
  ///  4. every machine fact an armed environment needs is BOUND
  ///     ([SiteBinding.validate], bead `pow-ebf.6`).
  /// The composition root throws on a non-null return.
  String? validate({
    Map<String, String> roleEnvironments = const {},
    SiteBinding siteBinding = SiteBinding.none,
  }) {
    final resolved = <String, AgentEnvironment>{};
    for (final name in names) {
      final AgentEnvironment env;
      try {
        env = resolve(name);
      } on EnvironmentRegistryError catch (e) {
        return e.message;
      }
      final illegal = _legalityRefusal(name, env);
      if (illegal != null) return illegal;
      resolved[name] = env;
    }
    for (final entry in roleEnvironments.entries) {
      final env = resolved[entry.value];
      if (env == null) {
        return 'role "${entry.key}" names environment "${entry.value}" but it '
            'is not armed (armed: ${_armedList()}) — arm "${entry.value}" in '
            'the environment registry, or point the role at an armed environment';
      }
      // A claude-native tier default (opus/sonnet/haiku) is CLAUDE's model
      // name; it 400s in any other tool's argv (`codex --model opus` is
      // rejected on a ChatGPT account). An environment that PINS such a name
      // yet does not spawn claude is a cross-environment composition error —
      // refuse LOUD at boot (ADR-0000 A8), never at 400-per-spawn. A model-less
      // non-claude env is NOT refused: it resolved to spawn before this guard
      // and still does (copilot/opencode/pi stay armable). The codex pin's own
      // regression to null is fenced by its builtin golden test, since at boot
      // a model-less env cannot be told apart from a grandfathered one.
      final crossing = env.model;
      if (crossing != null &&
          kClaudeNativeDefaults.contains(crossing) &&
          env.command != kTierDefaultCommand) {
        return 'role "${entry.key}" names environment "${entry.value}" '
            '(command "${env.command}") but pins the claude-native model '
            '"$crossing" — a claude tier default '
            '(${kClaudeNativeDefaults.join('/')}) 400s in a non-claude argv '
            '(a "${env.command} --model $crossing" is rejected). Pin a model '
            'native to "${env.command}" on "${entry.value}" '
            '(its AgentEnvironment.model), or arm the role at the claude '
            'environment.';
      }
    }
    return siteBinding.validate(resolved);
  }

  /// The legal-combo refusal for a RESOLVED [env] armed as [name], or null when
  /// legal. With the harness expressed as DATA there is no harness×target table;
  /// legality is the environment's own self-consistency
  /// ([AgentEnvironment.validate]) plus a `command` to spawn.
  String? _legalityRefusal(String name, AgentEnvironment env) {
    final command = env.command;
    if (command == null || command.isEmpty) {
      return 'environment "$name" is not spawnable: no command resolved — '
          'declare a command in "$name" or one of its base ancestors';
    }
    final selfCheck = env.validate();
    if (selfCheck != null) {
      return 'environment "$name" is an illegal harness×target combo: '
          '$selfCheck — fix "$name" or its base chain';
    }
    return null;
  }

  /// Walks [name]'s `base` chain into a ROOT-first layer list for
  /// [AgentEnvironment.resolve]. THROWS [EnvironmentRegistryError] on an unknown
  /// leaf, a `base` cycle, or a dangling `base`.
  List<AgentEnvironment> _chain(String name) {
    final leaf = custom[name] ?? builtins[name];
    if (leaf == null) {
      throw EnvironmentRegistryError(
        'unknown environment "$name" (armed: ${_armedList()}) — arm it in the '
        'environment registry, or point the work at an armed environment',
      );
    }
    final layers = <AgentEnvironment>[];
    final seen = <String>{};
    final path = <String>[];
    var current = leaf;
    var currentName = name;
    var fromCustom = custom.containsKey(name);
    while (true) {
      final id = '${fromCustom ? 'custom' : 'builtin'}:$currentName';
      if (!seen.add(id)) {
        final cycle = [...path, currentName].join(' → ');
        throw EnvironmentRegistryError(
          'environment "$name" has a base cycle ($cycle) — break the cycle in '
          'the environment set',
        );
      }
      path.add(currentName);
      layers.add(current);

      final base = current.base;
      final ({AgentEnvironment env, bool fromCustom})? parent = switch (base) {
        EnvBaseStandalone() => null,
        EnvBaseUndeclared() =>
          (fromCustom && builtins.containsKey(currentName))
              ? (env: builtins[currentName]!, fromCustom: false)
              : null,
        EnvBaseRef(name: final refName, scope: final refScope) => _lookup(
          refName,
          refScope,
          excludeSelf: fromCustom ? currentName : null,
        ),
      };

      if (parent == null) {
        if (base is EnvBaseRef) {
          throw EnvironmentRegistryError(
            'environment "$currentName" bases on "${base.name}" but no such '
            'environment is armed (armed: ${_armedList()}) — arm "${base.name}", '
            'or fix the base of "$currentName"',
          );
        }
        break;
      }
      current = parent.env;
      currentName = base is EnvBaseRef ? base.name : currentName;
      fromCustom = parent.fromCustom;
    }
    return layers.reversed.toList();
  }

  /// Resolves [name] under [scope] (gc grammar): `builtin:` forces [builtins],
  /// `provider:` forces [custom], bare `auto` is [custom] first (SELF-EXCLUDED via
  /// [excludeSelf]) then [builtins]. Null when no such environment is armed (a
  /// dangling `base`).
  ({AgentEnvironment env, bool fromCustom})? _lookup(
    String name,
    BaseScope scope, {
    String? excludeSelf,
  }) {
    ({AgentEnvironment env, bool fromCustom})? inCustom() {
      final c = custom[name];
      return c == null ? null : (env: c, fromCustom: true);
    }

    ({AgentEnvironment env, bool fromCustom})? inBuiltin() {
      final b = builtins[name];
      return b == null ? null : (env: b, fromCustom: false);
    }

    return switch (scope) {
      BaseScope.builtin => inBuiltin(),
      BaseScope.provider => inCustom(),
      BaseScope.auto =>
        (name == excludeSelf ? null : inCustom()) ?? inBuiltin(),
    };
  }

  /// The armed-name list for a refusal ('a, b, c'), or `'<none>'`.
  String _armedList() {
    final all = names.toList();
    return all.isEmpty ? '<none>' : all.join(', ');
  }
}
