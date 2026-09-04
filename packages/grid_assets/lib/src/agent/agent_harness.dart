/// The **agent scope** — the surviving surface after the harness collapse
/// (ADR-0002 D1, bead `pow-ebf.4`; ADR-0008 Decision 10, ratified 2026-07-02).
///
/// Harnesses are DATA. There is no per-tool class and no interface: a tool is a
/// declared [AgentEnvironment] (`agent_environment.dart`) armed by name in the
/// [EnvironmentRegistry] (`environment_registry.dart`). [spawnFor] renders a
/// one-turn environment into a process invocation; a non-null
/// [AgentEnvironment.sessionAdapter] selects an injected channel adapter that
/// owns the long-lived launch and delivers the brief after startup.
/// [kBuiltinEnvironments] ships the five first-party environments as values
/// (claude / copilot / pi / opencode / codex); [buildBuiltinEnvironmentRegistry]
/// is the station default.
///
/// **Config is a VALUE in the tree; impls are DI.** [AgentConfig] rides a plain
/// `InheritedSeed<AgentConfig>` mounted by the asset's `main()` (station
/// default), overridable per-substation, per-bead (the `grid.agent` domain
/// envelope — `agent_domain.dart`), and per-step (`StepArgs.params`) — the
/// D-C ladder, resolved as a pure value merge at the effect boundary
/// ([resolveAgentConfig]). The named environment is resolved from the
/// [EnvironmentRegistry] mounted at `main()`; behavior is never derived from a
/// service looked up in the tree.
///
/// **The MODEL resolves TIER → MODEL (beads `pow-2c9`, `pow-n6n.4`).** A spawn's
/// model is not one station-wide value: the SPAWNING ASSET declares the
/// [AgentTier] it rides (frontier for the build and the spec author, mid for the
/// committee's critics, cheap for the read-only lenses), and the station arms
/// tier → model ([AgentConfig.tiers], a [ModelTiers] value; unarmed tiers ride
/// [defaultModelForTier] — opus / sonnet / haiku). The bead's `grid.agent`
/// `params.model` and the selected environment's own model both outrank it. So
/// the committee grades cheap while the build runs strong, and a retune is one
/// arming change. WHICH environment a seat rides is the TYPED lookup
/// (`typed_environment.dart`, ADR-0006 D2) — ADR-0006 D5 retired the role
/// indirection that used to answer both questions at once.
///
/// **Two-moment validation (OQ-c, ratified)** now lives on the registry: the
/// composition root validates its station default eagerly
/// ([EnvironmentRegistry.validate] — a misconfigured machine fails before any
/// work mounts); a per-work override that resolves to an illegal environment
/// throws in [resolveAgentConfig], which the engine's allocation catches and
/// routes to supervision as a `Failed` — one bad bead parks loudly, the station
/// never crashes.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import 'agent_environment.dart';
import 'environment_registry.dart';
import 'model_tier.dart';

/// The agent configuration — a pure VALUE the tree carries (never behavior).
/// Watched by branches (`dependOn*`), snapshot-read by effects (`get*`).
class AgentConfig {
  /// Creates the config: which [harness] runs the work, with harness-opaque
  /// [params] tuning, the station's [tiers] arming, the declared [modelPrices],
  /// and the PRE-TIER [graderModel] knob. WHERE inference runs is the named
  /// environment's own `target` (ADR-0002 D3), not a config axis.
  const AgentConfig({
    this.harness = 'claude',
    this.params = const {},
    this.tiers = const ModelTiers(),
    this.modelPrices = kUsageModelPrices,
    this.graderModel,
  });

  /// The registry id of the harness: `claude` | `copilot` | `pi` | `opencode`.
  final String harness;

  /// Harness-opaque tuning, and the TRANSPORT key for the model: every harness
  /// reads `params['model']`.
  ///
  /// Two readings, by which config you hold (beads `pow-edp`, `pow-2c9`):
  ///  - on the AMBIENT (station) config, `params['model']` is the PRE-TIER BUILD
  ///    knob — what `space up --model` sets. It arms the FRONTIER tier
  ///    ([armedTiers]); absent, that tier rides [kFrontierModelDefault];
  ///  - on a config RETURNED by [resolveAgentConfig], it is the fully-resolved
  ///    model of the TIER that asked — the ladder's winner, stamped into the key
  ///    the harness reads.
  final Map<String, String> params;

  /// The station's TIER ARMING (bead `pow-2c9`) — the model-selection surface:
  /// tier → model, sparse (an unarmed tier rides its asset default). Selection
  /// reads it through the tier the SPAWNER declares, so the field count follows
  /// the TIERS and nothing else.
  final ModelTiers tiers;

  /// The station's declared per-model TOKEN PRICES (bead `pow-zetn`) — read
  /// ONLY where a harness reports tokens but no billed cost, so a
  /// subscription-billed lane still has a cost in the ledger. Config = VALUES
  /// in the tree: this rides the ambient [AgentConfig] the tree already mounts,
  /// so a station retunes prices by arming a value, never by injecting a
  /// pricing service. An unpriced model FLARES and stays cost-null — never a
  /// silent zero.
  final ModelPriceTable modelPrices;

  /// The PRE-TIER grade knob (`space up --grader-model` — ADR-0000 A20's GRADE
  /// rung). Kept so an UNMIGRATED station keeps arming its critics: it projects
  /// onto the MID tier ([armedTiers]). No harness reads it; it is a ladder
  /// INPUT. A station migrates by arming [tiers] directly, and it retires here
  /// at that point.
  final String? graderModel;

  /// The tier map this station ACTUALLY arms: [tiers], with the two PRE-TIER
  /// knobs projected onto the tiers they arm — `params['model']` (`space up
  /// --model`, A20's BUILD rung) onto [AgentTier.frontier], and [graderModel]
  /// onto [AgentTier.mid].
  ///
  /// A pre-tier knob OUT-RANKS an armed tier on purpose: an operator who passes
  /// `--model X` to a station must never be SILENTLY ignored (A20(2)'s no-wedge
  /// rule — the flag regression that would wedge the live station); a migrated
  /// station simply stops setting the knob and arms [tiers].
  ModelTiers get armedTiers =>
      tiers.merge(frontier: params['model'], mid: graderModel);

  /// A copy with the non-null overrides applied (the D-C ladder's merge — both
  /// [params] and [tiers] merge key-wise, they don't replace whole).
  AgentConfig merge({
    String? harness,
    Map<String, String>? params,
    ModelTiers? tiers,
    ModelPriceTable? modelPrices,
    String? graderModel,
  }) => AgentConfig(
    harness: harness ?? this.harness,
    params: params == null ? this.params : {...this.params, ...params},
    tiers: tiers == null
        ? this.tiers
        : this.tiers.merge(
            cheap: tiers.cheap,
            mid: tiers.mid,
            frontier: tiers.frontier,
          ),
    modelPrices: modelPrices ?? this.modelPrices,
    graderModel: graderModel ?? this.graderModel,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentConfig &&
      other.harness == harness &&
      other.tiers == tiers &&
      other.graderModel == graderModel &&
      _mapEquals(other.modelPrices, modelPrices) &&
      _mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(
    harness,
    tiers,
    graderModel,
    Object.hashAllUnordered(
      modelPrices.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      params.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'AgentConfig($harness, params: $params, tiers: $tiers, '
      'modelPrices: ${modelPrices.keys}'
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

/// The one-turn spawn renderer (ADR-0002 D1; the harness collapse, bead
/// `pow-ebf.4`): render one resolved [environment] + [brief] into the process
/// invocation rooted at [workspace], reading the environment's DATA. Channel
/// environments instead select an injected [AgentEnvironment.sessionAdapter];
/// there is still no per-tool class.
///
/// [model] is the ladder's resolved model; it OVERRIDES [AgentEnvironment.model]
/// and renders as `--model <model>` in the slot BETWEEN [AgentEnvironment.args]
/// (REPLACE) and [AgentEnvironment.argsAppend] (ACCUMULATE) — the byte-identical
/// position the four deleted classes emitted. [endpoint] is the site-binding
/// machine fact (ADR-0002 D3) injected into `OPENAI_BASE_URL`/`SWIFT_INFER_BASE_URL`
/// per [AgentEnvironment.target] (the `_targetEnv` successor). [usageOut] triggers
/// the FT-2 wrapper ONLY when the environment declares a surface
/// ([AgentEnvironment.usageJsonArgs] != null); a tool with no surface IGNORES it.
RuntimeConfig spawnFor({
  required AgentEnvironment environment,
  required AgentBrief brief,
  required Workspace workspace,
  String? model,
  String? usageOut,
  Uri? endpoint,
}) {
  final command = environment.command;
  if (command == null || command.isEmpty) {
    throw StateError(
      'environment is not spawnable: no command resolved '
      '(declare a command in the environment or a base ancestor)',
    );
  }
  final effectiveModel = model ?? environment.model;
  final promptSegment = switch (environment.promptMode ?? PromptMode.arg) {
    PromptMode.arg => [brief.render()],
    PromptMode.flag => [environment.promptFlag!, brief.render()],
    PromptMode.none => const <String>[],
  };
  final wantUsage = usageOut != null && environment.usageJsonArgs != null;
  final inner = <String>[
    ...?environment.args,
    if (effectiveModel != null) ...['--model', effectiveModel],
    ...environment.argsAppend,
    if (wantUsage) ...environment.usageJsonArgs!,
    ...promptSegment,
  ];
  final processEnv = agentProcessEnvironment(
    environment: environment,
    endpoint: endpoint,
  );
  if (!wantUsage) {
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
      command: command,
      args: inner,
      env: processEnv,
      lifecycle: Lifecycle.oneTurn,
    );
  }
  // FT-2 usage capture (uniform, spec-driven): wrap in `sh -c`, redirecting the
  // JSON usage envelope to [usageOut]. `exec "$@"` preserves the child exit code
  // (the step's terminal mapping is unchanged) and the real argv rides as
  // positionals byte-identically — gc's `path_check` shell-wrapper case.
  return RuntimeConfig(
    workDir: workspace.workspaceDir,
    command: 'sh',
    args: [
      '-c',
      _usageWrapperScript(usageOut),
      'grid-$command',
      command,
      ...inner,
    ],
    env: processEnv,
    lifecycle: Lifecycle.oneTurn,
  );
}

/// The env a resolved [target] layers over its site [endpoint] (the `_targetEnv`
/// successor — ADR-0002 D3: the URL is a MACHINE FACT the site binding supplies,
/// never in code/argv/bead). Provider-managed needs nothing; an endpoint-needing
/// target with a null [endpoint] injects nothing (the LOUD refusal for an unbound
/// fact is `SiteBinding.endpointFor`'s at the spawn edge, not this pure fold).
/// Exhaustive switch (house style).
Map<String, String> agentProcessEnvironment({
  required AgentEnvironment environment,
  Uri? endpoint,
}) => <String, String>{
  ...environment.env,
  ...switch (environment.target ?? InferenceTarget.providerManaged) {
    InferenceTarget.providerManaged => const {},
    InferenceTarget.openAiCompatible =>
      endpoint == null ? const {} : {'OPENAI_BASE_URL': '$endpoint'},
    InferenceTarget.swiftInfer =>
      endpoint == null ? const {} : {'SWIFT_INFER_BASE_URL': '$endpoint'},
  },
};

/// The first-party inference environments as DATA (ADR-0002 D1). Claude, Pi,
/// and OpenCode retain their one-turn argv transports. Copilot and Codex select
/// the ACP channel adapter while keeping their command, args, and tool posture
/// as values. Codex alone pins its native `gpt-5.6-sol`; the ACP adapter resolves
/// that base against the qualified ids offered by the live session.
const Map<String, AgentEnvironment> kBuiltinEnvironments = {
  'claude': AgentEnvironment(
    command: 'claude',
    args: ['--dangerously-skip-permissions'],
    promptMode: PromptMode.flag,
    promptFlag: '-p',
    target: InferenceTarget.providerManaged,
    usageJsonArgs: ['--output-format', 'json'],
    resumeFlag: '--resume',
  ),
  'copilot': AgentEnvironment(
    command: 'copilot',
    args: ['--acp', '--allow-all-tools'],
    promptMode: PromptMode.none,
    target: InferenceTarget.providerManaged,
    sessionAdapter: 'acp',
  ),
  'pi': AgentEnvironment(
    command: 'pi',
    promptMode: PromptMode.flag,
    promptFlag: '-p',
    target: InferenceTarget.openAiCompatible,
  ),
  'opencode': AgentEnvironment(
    command: 'opencode',
    args: ['run'],
    promptMode: PromptMode.arg,
    target: InferenceTarget.providerManaged,
  ),
  'codex': AgentEnvironment(
    command: 'npx',
    args: ['-y', '@agentclientprotocol/codex-acp@1.6.2'],
    env: {'INITIAL_AGENT_MODE': 'agent-full-access'},
    promptMode: PromptMode.none,
    target: InferenceTarget.providerManaged,
    model: 'gpt-5.6-sol',
    sessionAdapter: 'acp',
  ),
};

/// The station-default environment registry — the five builtins as `builtins`,
/// no custom authoring (a station/substation adds `custom` at its `HarnessProvider`).
/// The station-default arming (bead `pow-ebf.3` reserved
/// `EnvironmentRegistry.builtins` for exactly this).
EnvironmentRegistry buildBuiltinEnvironmentRegistry() =>
    const EnvironmentRegistry(custom: {}, builtins: kBuiltinEnvironments);
