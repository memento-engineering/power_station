/// The **agent scope** — Theme-of-context for agentic harnesses (ADR-0008
/// Decision 10, ratified 2026-07-02; design surface
/// `the_grid/docs/SCRATCH-agent-scope.md`).
///
/// A **harness** is a turn/tool harness: it renders a brief + config into ONE
/// tool's invocation and interprets its runtime events. The seam is "Agent",
/// not "Coding" — the committee's critics ride the identical harness; coding is
/// one client.
///
/// **Config is a VALUE in the tree; impls are DI.** [AgentConfig] rides a plain
/// `InheritedSeed<AgentConfig>` mounted by the asset's `main()` (station
/// default), overridable per-substation, per-bead (the `grid.agent` domain
/// envelope — `agent_domain.dart`), and per-step (`StepArgs.params`) — the
/// D-C ladder, resolved as a pure value merge at the effect boundary
/// ([resolveAgentConfig]). Harness IMPLEMENTATIONS resolve from the
/// [AgentHarnessRegistry] wired at `main()` — behavior is never derived from a
/// service looked up in the tree.
///
/// **The MODEL splits by ROLE (bead `pow-edp`).** A spawn's model is not one
/// station-wide value: it resolves for the [AgentRole] the SPAWNING ASSET
/// declares — `bead grid.agent params.model` > the station's rung for that role
/// ([AgentConfig.stationModelFor]) > the asset's own default
/// ([defaultModelFor]: build ⇒ [kBuildModelDefault], grade ⇒
/// [kGraderModelDefault]). So the committee grades cheap while the build runs
/// strong, and the most explicit rung always wins.
///
/// **Two-moment validation (OQ-c, ratified):** the composition root validates
/// its station default eagerly ([AgentHarnessRegistry.validate] — a
/// misconfigured machine fails before any work mounts); a per-work override
/// that resolves to an illegal combo throws in [resolveAgentConfig], which the
/// engine's allocation catches and routes to supervision as a `Failed` — one
/// bad bead parks loudly, the station never crashes.
///
/// The grid's OWN harness (`GridHarness`, name reserved) is PARKED as its own
/// epic — this pass ships the four external harnesses. The registry keeps that
/// epic purely additive (a new id + impl, zero seam changes).
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

/// Where inference runs (ADR-0008 Decision 10 / D-E). Sealed — consumers
/// switch exhaustively (house style).
sealed class ModelTarget {
  const ModelTarget();
}

/// The tool owns its own auth/routing — claude via the macOS keychain (A38),
/// copilot via `gh` auth. Model *selection* for a managed tool rides
/// [AgentConfig.params] (`model: ...`), not the target.
class ProviderManaged extends ModelTarget {
  /// Const-constructible.
  const ProviderManaged();

  @override
  bool operator ==(Object other) => other is ProviderManaged;

  @override
  int get hashCode => (ProviderManaged).hashCode;

  @override
  String toString() => 'ProviderManaged()';
}

/// An OpenAI-compatible inference endpoint (e.g. a llama.cpp server).
class OpenAiCompatible extends ModelTarget {
  /// Targets the endpoint at [base].
  const OpenAiCompatible(this.base);

  /// The endpoint base url.
  final Uri base;

  @override
  bool operator ==(Object other) => other is OpenAiCompatible && other.base == base;

  @override
  int get hashCode => Object.hash(OpenAiCompatible, base);

  @override
  String toString() => 'OpenAiCompatible($base)';
}

/// A swift-infer server endpoint.
class SwiftInfer extends ModelTarget {
  /// Targets the swift-infer server at [base].
  const SwiftInfer(this.base);

  /// The endpoint base url.
  final Uri base;

  @override
  bool operator ==(Object other) => other is SwiftInfer && other.base == base;

  @override
  int get hashCode => Object.hash(SwiftInfer, base);

  @override
  String toString() => 'SwiftInfer($base)';
}

/// The ROLE an agent spawn plays — the axis the model default splits on (bead
/// `pow-edp`). Until this split, EVERY spawner — the coding agent, the
/// architect, and the committee's critics — resolved the one station-wide
/// [AgentConfig], so a station could not grade cheap while building strong: it
/// was all-or-nothing (the fable/opus incident, 2026-07-11 — pinning one model
/// hit builders and critics alike). The role is declared by the SPAWNING ASSET
/// and carries its own default model. Sealed by the enum — consumers switch
/// exhaustively (house style).
enum AgentRole {
  /// The BUILD side — the coding agent (`AgentCapability`) and the architect
  /// (`SpecifyCapability`). Strong by default: the build IS the work.
  build,

  /// The GRADE side — the committee critics (`CriticCapability` and its spec
  /// subclass `SpecCriticCapability`). Cheap by default: a critic reads a
  /// pinned diff against ONE rubric and writes a letter; it does not need a
  /// frontier model.
  grade,
}

/// The BUILD role's default model — the ASSET rung, the bottom of the model
/// ladder.
const String kBuildModelDefault = 'opus';

/// The GRADE role's default model — the ASSET rung, the bottom of the model
/// ladder.
const String kGraderModelDefault = 'sonnet';

/// The model [role] rides when nothing more explicit names one (the ASSET rung
/// of the ladder — a station flag or a bead's `grid.agent` envelope overrides
/// it).
///
/// ALWAYS an explicit model, never the harness CLI's own default: an unpinned
/// `claude` resolved to opus and then SILENTLY fell back to fable once the
/// weekly limit blew (the grid spawns ~10 agents per bead; it obliterates a
/// limit fast), eating quota nobody asked for. A role default is an EXPLICIT
/// model — every config [resolveAgentConfig] returns names one, so there is no
/// fallback surprise to guard against.
String defaultModelFor(AgentRole role) => switch (role) {
  AgentRole.build => kBuildModelDefault,
  AgentRole.grade => kGraderModelDefault,
};

/// The agent configuration — a pure VALUE the tree carries (never behavior).
/// Watched by branches (`dependOn*`), snapshot-read by effects (`get*`).
class AgentConfig {
  /// Creates the config: which [harness] runs the work, against which [target],
  /// with harness-opaque [params] tuning and the critics' own [graderModel]
  /// station rung.
  const AgentConfig({
    this.harness = 'claude',
    this.target = const ProviderManaged(),
    this.params = const {},
    this.graderModel,
  });

  /// The registry id of the harness: `claude` | `copilot` | `pi` | `opencode`.
  final String harness;

  /// Where inference runs (D-E).
  final ModelTarget target;

  /// Harness-opaque tuning, and the TRANSPORT key for the model: every harness
  /// reads `params['model']`.
  ///
  /// Two readings, by which config you hold (bead `pow-edp`):
  ///  - on the AMBIENT (station) config, `params['model']` is the station's
  ///    BUILD-role rung — what `space up --model` sets. Absent ⇒ the build
  ///    role's asset default ([kBuildModelDefault]);
  ///  - on a config RETURNED by [resolveAgentConfig], it is the fully-resolved
  ///    model of the role that asked — the ladder's winner, stamped into the
  ///    key the harness reads.
  final Map<String, String> params;

  /// The station's GRADE-role model rung — what `space up --grader-model` sets
  /// (bead `pow-edp`). Null ⇒ the grade role's asset default
  /// ([kGraderModelDefault]).
  ///
  /// Split OUT of [params] on purpose: `params['model']` is the harness
  /// transport key, so a single map cannot carry two roles' models at once.
  /// This is a LADDER INPUT, never a transport key — no harness reads it;
  /// [resolveAgentConfig] projects it into the resolved config's
  /// `params['model']` when the spawner's role is [AgentRole.grade].
  final String? graderModel;

  /// The STATION rung's model for [role] — `params['model']` for a build
  /// spawner, [graderModel] for a grader. Null ⇒ the station named no model for
  /// that role, and the ladder falls through to [defaultModelFor].
  String? stationModelFor(AgentRole role) => switch (role) {
    AgentRole.build => params['model'],
    AgentRole.grade => graderModel,
  };

  /// A copy with the non-null overrides applied (the D-C ladder's merge —
  /// params MERGE key-wise, they don't replace whole).
  AgentConfig merge({
    String? harness,
    ModelTarget? target,
    Map<String, String>? params,
    String? graderModel,
  }) => AgentConfig(
    harness: harness ?? this.harness,
    target: target ?? this.target,
    params: params == null ? this.params : {...this.params, ...params},
    graderModel: graderModel ?? this.graderModel,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentConfig &&
      other.harness == harness &&
      other.target == target &&
      other.graderModel == graderModel &&
      _mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(
    harness,
    target,
    graderModel,
    Object.hashAllUnordered(
      params.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'AgentConfig($harness → $target, params: $params'
      '${graderModel == null ? '' : ', graderModel: $graderModel'})';
}

/// The harness-agnostic WORK CONTENT handed to an agent (OQ-a, ratified):
/// the rendered task, the working agreement (grid policy — commit, don't
/// push), and optional labeled extra-context blocks. Model/parameters are
/// [AgentConfig], NOT brief — so one brief replays across harnesses
/// (supervision may retry the same work on a different harness without
/// re-rendering policy). TRANSPORT is harness-owned (argv / stdin / workspace
/// file).
class AgentBrief {
  /// Creates the brief from the rendered [task], the [workingAgreement]
  /// policy, and optional labeled [context] blocks.
  const AgentBrief({
    required this.task,
    this.workingAgreement = '',
    this.context = const {},
  });

  /// The rendered task content (title + description + design + acceptance +
  /// notes — the full bead; a title-only brief starves the agent, A36).
  final String task;

  /// The grid's policy rules (local-first working agreement). Empty for a
  /// self-contained brief (e.g. a critic prompt).
  final String workingAgreement;

  /// Optional labeled extra-context blocks (label → text), appended in order.
  final Map<String, String> context;

  /// The canonical single-document rendering (what an argv/stdin transport
  /// sends). Sections are appended only when non-empty.
  String render() {
    final b = StringBuffer(task);
    if (workingAgreement.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Working agreement')
        ..write(workingAgreement.trim());
      b.writeln();
    }
    context.forEach((label, text) {
      if (text.trim().isEmpty) return;
      b
        ..writeln()
        ..writeln('## $label')
        ..writeln(text.trim());
    });
    return b.toString();
  }
}

/// A turn/tool harness — renders ([AgentConfig], [AgentBrief]) into one tool's
/// invocation and interprets its runtime events. Pure description
/// (delegate-class): no I/O, no state; the engine's allocation owns the spawn.
abstract interface class AgentHarness {
  /// Whether this harness can reach [target] (the legality half the registry
  /// validates — OQ-c).
  bool supports(ModelTarget target);

  /// Maps the resolved [config] + rendered [brief] into the process invocation
  /// rooted at [workspace]. The harness owns the brief TRANSPORT (argv today;
  /// stdin / a workspace file are per-impl choices).
  ///
  /// [usageOut] is the workspace-relative file the harness should redirect its
  /// run's usage/cost telemetry into (FT-2 flow telemetry — CAPTURE-ONLY). A
  /// harness that has a JSON usage surface ([ClaudeHarness]) wraps its
  /// invocation so the envelope lands there; a harness with no such surface
  /// IGNORES it (its `result()` merges no usage). Null ⇒ no capture requested
  /// (the plain, byte-identical invocation).
  RuntimeConfig spawnFor({
    required AgentConfig config,
    required AgentBrief brief,
    required Workspace workspace,
    String? usageOut,
  });

  /// Maps a runtime [event] to a step signal. All four shipped harnesses are
  /// one-turn jobs (clean exit → complete); a future daemon/interactive
  /// harness overrides this with its own semantics.
  StepSignal interpret(RuntimeEvent event);
}

/// The harness DI registry — wired at the asset's `main()`, mounted as a plain
/// `InheritedSeed<AgentHarnessRegistry>` (a fixed-at-mount handle). Impls
/// resolve by [AgentConfig.harness] at the effect boundary.
class AgentHarnessRegistry {
  /// Creates the registry over [harnesses] (id → impl).
  const AgentHarnessRegistry(Map<String, AgentHarness> harnesses)
    : _harnesses = harnesses;

  final Map<String, AgentHarness> _harnesses;

  /// The registered harness ids.
  Iterable<String> get ids => _harnesses.keys;

  /// Resolves [id]; null when unregistered (callers fail closed).
  AgentHarness? harness(String id) => _harnesses[id];

  /// Validates [config] against the registry — the OQ-c legality check,
  /// shared by BOTH moments: the composition root calls it eagerly on the
  /// station default (boot fails loud); [resolveAgentConfig] calls it on every
  /// per-work resolution (an illegal override fails THAT work). Returns the
  /// human-readable error, or null when legal.
  String? validate(AgentConfig config) {
    final h = _harnesses[config.harness];
    if (h == null) {
      return 'unknown harness "${config.harness}" '
          '(registered: ${_harnesses.keys.join(', ')})';
    }
    if (!h.supports(config.target)) {
      return 'harness "${config.harness}" cannot reach ${config.target} '
          '(fail-closed — pick a target the harness supports, or another '
          'harness)';
    }
    return null;
  }
}

/// Builds the standard four-harness registry (ADR-0008 Decision 10):
/// claude, copilot, pi, opencode. The grid's own harness is a PARKED epic —
/// when it lands it is one more entry here, zero seam changes.
AgentHarnessRegistry buildAgentHarnessRegistry() => const AgentHarnessRegistry({
  'claude': ClaudeHarness(),
  'copilot': CopilotHarness(),
  'pi': PiHarness(),
  'opencode': OpencodeHarness(),
});

/// A job's terminal mapping shared by the one-turn harnesses: a clean
/// `Exited(0)` completes; any other terminal fails (routes to supervision).
StepSignal jobSignal(RuntimeEvent event) => switch (event) {
  Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
  Exited() || Died() => StepSignal.failed,
  _ => StepSignal.none,
};

/// The env a harness layers for a [ModelTarget] it reaches over an endpoint.
/// A [ProviderManaged] tool needs nothing (it owns its auth/routing).
Map<String, String> _targetEnv(ModelTarget target) => switch (target) {
  ProviderManaged() => const {},
  OpenAiCompatible(:final base) => {'OPENAI_BASE_URL': '$base'},
  SwiftInfer(:final base) => {'SWIFT_INFER_BASE_URL': '$base'},
};

/// `claude` — the proven live harness (A36/A38): print mode, headless
/// permissions, keychain auth, one-turn. Brief transport: argv.
///
/// The operative harness for the code circuit's runs, so it is the one that
/// captures usage telemetry (FT-2). When a [usageOut] path is supplied the
/// invocation is WRAPPED (the gating lane's `sh -c` rc-file precedent): claude
/// runs with `--output-format json` and its result envelope is redirected to
/// that file, from which `AgentCapability`/`CriticCapability`'s `result()` parse
/// tokens/cost/turns/duration. The claude argv — INCLUDING the byte-identical
/// rendered brief — rides as sh positional params (`"$@"`), so nothing about the
/// brief or the behavior contract is re-quoted; only the output format and the
/// stdout redirection change. `exec` makes claude's exit code the process exit
/// code, so [interpret] is byte-identical to the unwrapped run.
class ClaudeHarness implements AgentHarness {
  /// Const-constructible.
  const ClaudeHarness();

  @override
  bool supports(ModelTarget target) => target is ProviderManaged;

  @override
  RuntimeConfig spawnFor({
    required AgentConfig config,
    required AgentBrief brief,
    required Workspace workspace,
    String? usageOut,
  }) {
    final model = config.params['model'];
    if (usageOut == null) {
      // No usage capture requested — the plain, direct invocation.
      return RuntimeConfig(
        workDir: workspace.workspaceDir,
        command: 'claude',
        args: [
          '--dangerously-skip-permissions',
          if (model != null) ...['--model', model],
          '-p',
          brief.render(),
        ],
        lifecycle: Lifecycle.oneTurn,
      );
    }
    // Usage capture (FT-2): claude with the JSON result envelope, redirected to
    // the per-step telemetry file. The claude argv rides as sh positionals so
    // `exec "$@"` runs it verbatim (the rendered brief is byte-identical).
    final claudeArgs = <String>[
      '--dangerously-skip-permissions',
      if (model != null) ...['--model', model],
      '--output-format', 'json',
      '-p',
      brief.render(),
    ];
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: 'sh',
      args: [
        '-c',
        _usageWrapperScript(usageOut),
        'grid-claude',
        'claude',
        ...claudeArgs,
      ],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpret(RuntimeEvent event) => jobSignal(event);
}

/// The `sh -c` script that captures a harness run's usage: ensure the telemetry
/// dir, then `exec` the claude argv (passed as positionals `"$@"`) with its
/// stdout redirected to [usageOut]. `exec` (not a pipe) preserves the child's
/// exit code, so the step's terminal mapping is unchanged. [usageOut] is a
/// sanitized workspace-relative path ([usageReportPath]) — only `[A-Za-z0-9._-]`
/// + `/`, so single-quoting is safe.
String _usageWrapperScript(String usageOut) =>
    'mkdir -p ${_sq(p.dirname(usageOut))}; exec "\$@" > ${_sq(usageOut)}';

/// Single-quotes [s] for the shell. Safe without an inner-quote escaper because
/// its only caller passes a [usageReportPath], which contains no single quote.
String _sq(String s) => "'$s'";

/// `copilot` — GitHub Copilot CLI: provider-managed (auth rides `gh`), print
/// mode, tools allowed headless. Brief transport: argv. (Exact flag shape
/// confirmed at the live arm — the human gate; the SEAM is what this pass
/// ships.)
///
/// Usage-telemetry SKIP (FT-2): the Copilot CLI exposes no confirmed JSON usage
/// surface, so [usageOut] is ignored — claude is the operative harness for the
/// code circuit's runs. Wire capture here once its flag shape is confirmed.
class CopilotHarness implements AgentHarness {
  /// Const-constructible.
  const CopilotHarness();

  @override
  bool supports(ModelTarget target) => target is ProviderManaged;

  @override
  RuntimeConfig spawnFor({
    required AgentConfig config,
    required AgentBrief brief,
    required Workspace workspace,
    String? usageOut,
  }) {
    final model = config.params['model'];
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: 'copilot',
      args: [
        if (model != null) ...['--model', model],
        '--allow-all-tools',
        '-p',
        brief.render(),
      ],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpret(RuntimeEvent event) => jobSignal(event);
}

/// `pi` — the python coding agent, over an endpoint target (llama.cpp /
/// swift-infer via the OpenAI-compatible env). Brief transport: argv. (Exact
/// flag shape confirmed at the live arm.)
///
/// Usage-telemetry SKIP (FT-2): no confirmed JSON usage surface, so [usageOut]
/// is ignored (claude is the operative harness for the code circuit's runs).
class PiHarness implements AgentHarness {
  /// Const-constructible.
  const PiHarness();

  @override
  bool supports(ModelTarget target) =>
      target is OpenAiCompatible || target is SwiftInfer;

  @override
  RuntimeConfig spawnFor({
    required AgentConfig config,
    required AgentBrief brief,
    required Workspace workspace,
    String? usageOut,
  }) {
    final model = config.params['model'];
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: 'pi',
      args: [
        if (model != null) ...['--model', model],
        '-p',
        brief.render(),
      ],
      env: _targetEnv(config.target),
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpret(RuntimeEvent event) => jobSignal(event);
}

/// `opencode` — provider-pluggable: managed auth or an OpenAI-compatible
/// endpoint (llama.cpp). Brief transport: argv (`run`). (Exact flag shape
/// confirmed at the live arm.)
///
/// Usage-telemetry SKIP (FT-2): no confirmed JSON usage surface, so [usageOut]
/// is ignored (claude is the operative harness for the code circuit's runs).
class OpencodeHarness implements AgentHarness {
  /// Const-constructible.
  const OpencodeHarness();

  @override
  bool supports(ModelTarget target) =>
      target is ProviderManaged || target is OpenAiCompatible;

  @override
  RuntimeConfig spawnFor({
    required AgentConfig config,
    required AgentBrief brief,
    required Workspace workspace,
    String? usageOut,
  }) {
    final model = config.params['model'];
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: 'opencode',
      args: [
        'run',
        if (model != null) ...['--model', model],
        brief.render(),
      ],
      env: _targetEnv(config.target),
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpret(RuntimeEvent event) => jobSignal(event);
}
