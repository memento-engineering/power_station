/// The agent-ENVIRONMENT value type (ADR-0002 D1) — ONE complete, named
/// inference environment: which tool runs, how the brief reaches it, where
/// inference happens, on which model. VALUE ONLY: no registry (bead
/// `pow-ebf.3`), no site binding (bead `pow-ebf.6`), no harness rendering
/// (bead `pow-ebf.4`), no bead/step rungs (bead `pow-ebf.5`).
///
/// Its field set is PORTED from gc's `ProviderSpec`
/// (`com.gastownhall/gascity`, `internal/config/provider.go:39`) — the proven
/// `[providers.<name>]` table — rather than hand-rolled, so a field is never
/// silently cut and re-derived worse later. That already happened once: the
/// FT-2 `sh -c` usage wrapper was built without noticing gc's `path_check`
/// exists for exactly the shell-wrapper case (ADR-0002 D1 Rationale).
///
/// There is NO `harness` id field: gc's `command`/`args`/`prompt_mode`/
/// `path_check`/`resume_*` ARE the harness, expressed as DATA — the point of
/// the harness collapse (bead `pow-ebf.4`). The registry NAME (bead
/// `pow-ebf.3`) is an environment's external identity, not a field here.
///
/// [model] and [target] are the two the_grid ADDITIONS to gc's field set (gc
/// carries the model via its `options_schema`, not a scalar, and gc has no
/// `ModelTarget`): the role → tier → model axis (ADR-0000 A20) and ADR-0008
/// Decision 10's `ModelTarget`, both surviving into the environment per
/// ADR-0002. Per ADR-0002 D3 [target] is the URL-FREE kind — the endpoint is a
/// MACHINE FACT the site binding supplies (bead `pow-ebf.6`), never here.
///
/// ## Deferred gc `ProviderSpec` fields (the deferral audit — ADR-0002 D1)
///
/// Every gc field NOT ported, why it is out of scope today, and what would
/// bring it back (the audit prevents the silent-omission failure that hit
/// `path_check`):
///  - `options_schema_merge`, `options_schema` (`ProviderOption`/`OptionChoice`
///    with `flag_args`/`flag_aliases`/`Omit`): gc's dashboard session-creation
///    FORM (UI selects → CLI flags). the_grid has no interactive session form.
///    Back when: a dashboard authors env options as selectable choices.
///  - `display_name`: a human UI/log label; the_grid names an environment by
///    its registry key. Back when: a dashboard lists environments to a human.
///  - `ready_delay_ms`, `ready_prompt_prefix`, `process_names`: tmux/
///    interactive readiness detection (when the TUI prompt is ready). the_grid
///    runs one-turn headless subprocesses (`Lifecycle.oneTurn`) with no prompt
///    to await. Back when: an interactive/daemon harness (`GridHarness`, the
///    parked epic).
///  - `accept_startup_dialogs` (tri-state), `emits_permission_warning`
///    (tri-state): tmux startup-dialog / permission-warning handling for
///    interactive launches. the_grid launches `--dangerously-skip-permissions`
///    headless. Back when: an interactive harness that faces startup dialogs.
///  - `supports_acp`, `acp_command`, `acp_args`: the Agent Client Protocol
///    (JSON-RPC over stdio) transport plus its command/args overrides. the_grid
///    spawns one-turn argv processes, not ACP sessions. Back when: an ACP
///    (persistent-session) transport.
///  - `supports_hooks`: whether the tool has a hook mechanism (settings.json /
///    plugins). Unread by the_grid's spawn. Back when: per-environment
///    lifecycle-hook orchestration.
///  - `instructions_file` (`CLAUDE.md` vs `AGENTS.md`): which project-
///    instructions filename the tool reads. the_grid's worktrees already carry
///    the right file per repo; it is not chosen per environment. Back when: a
///    harness whose instructions filename varies by tool.
///  - `resume_command`: the full shell resume TEMPLATE (`{{.SessionKey}}`), a
///    higher-precedence alternative to `resume_flag`/`resume_style`. the_grid's
///    resume is expressible as flag+style. Back when: a tool whose resume argv
///    cannot be expressed as flag+key.
///  - `session_id_flag`: the flag to CREATE a session with a chosen id
///    (generate-and-pass). the_grid does not manage session ids (one-turn, no
///    resume yet). Back when: durable session management (create/resume by id).
///  - `permission_modes`: a name→flag table for permission-mode dropdowns,
///    consumed by external apps (no runtime reader even in gc). the_grid
///    hardcodes headless permissions. Back when: a UI exposing permission modes.
///  - `option_defaults`: overrides `options_schema` defaults without redefining
///    the schema — inert without `options_schema` (deferred). Back when: with
///    `options_schema`.
///  - `print_args`: the argv enabling one-shot non-interactive mode (`-p`,
///    `exec`). In the_grid this folds into a layer's [args]/[argsAppend] once
///    harnesses become DATA (bead `pow-ebf.4`). Back when: one-shot vs
///    interactive must toggle per environment separately from [args].
///  - `title_model`: the cheap model gc uses to auto-title a session. the_grid
///    does not title sessions. Back when: session titling.
///
/// gc's resolution machinery (`ResolvedProvider`, `ProviderProvenance`, the
/// chain-walk helpers) is not a field set — the registry (bead `pow-ebf.3`)
/// owns name→env storage + the base-name walk; this type owns the VALUE + the
/// pure fold ([AgentEnvironment.resolve]).
library;

/// How the brief is DELIVERED to the tool (gc `prompt_mode`) — transport, as
/// DATA. Sealed by the enum: consumers switch exhaustively (house style).
enum PromptMode {
  /// The brief rides as a positional argv argument (gc's default).
  arg,

  /// The brief rides behind a named flag ([AgentEnvironment.promptFlag]).
  flag,

  /// No brief on argv (a stdin / workspace-file transport).
  none,
}

/// How [AgentEnvironment.resumeFlag] is applied (gc `resume_style`). Sealed by
/// the enum: consumers switch exhaustively (house style).
enum ResumeStyle {
  /// `command --resume <key>` (claude). gc's default.
  flag,

  /// `command resume <key>` (codex) — a subcommand, not a flag. Codex's argv
  /// grammar is not claude's (gc's own doc comment).
  subcommand,
}

/// WHERE inference runs (ADR-0002 D3) — the KIND only; the endpoint URL is a
/// MACHINE FACT the site binding supplies (bead `pow-ebf.6`), never here. The
/// URL-FREE successor to `agent_harness.dart`'s `ModelTarget` (which fused
/// kind+URL) — ADR-0002: "ModelTarget survives as the target field; the
/// endpoint URL it carried moves to the site binding." Sealed by the enum:
/// consumers switch exhaustively (house style).
enum InferenceTarget {
  /// The tool owns its own auth/routing (claude via keychain, copilot via
  /// `gh`). Needs no site endpoint.
  providerManaged,

  /// An OpenAI-compatible endpoint (e.g. a llama.cpp server). Needs a site
  /// endpoint.
  openAiCompatible,

  /// A swift-infer server endpoint. Needs a site endpoint.
  swiftInfer,
}

/// Whether [target] requires a machine endpoint the site binding must supply
/// (ADR-0002 D3 — an environment whose machine fact is UNBOUND on this box
/// REFUSES at boot). Exhaustive switch (house style).
bool inferenceTargetNeedsEndpoint(InferenceTarget target) => switch (target) {
  InferenceTarget.providerManaged => false,
  InferenceTarget.openAiCompatible => true,
  InferenceTarget.swiftInfer => true,
};

/// Which lookup scope an [EnvBaseRef] resolves against (gc's `base` prefix
/// grammar). Sealed by the enum: consumers switch exhaustively (house style).
enum BaseScope {
  /// Bare `<name>`: custom first (SELF-EXCLUDED), then builtin. gc's default.
  auto,

  /// `builtin:<name>`: force the builtin lookup.
  builtin,

  /// `provider:<name>`: force the custom lookup.
  provider,
}

/// The `base` inheritance pointer (gc `ProviderSpec.Base`, a `*string` whose
/// tri-state is LOAD-BEARING). Sealed — consumers switch exhaustively (house
/// style). The three states are OBSERVABLY distinct:
///  - [EnvBaseUndeclared] — the field was ABSENT (gc `nil`): inherit by
///    convention (the registry may layer a same-named builtin under it).
///  - [EnvBaseStandalone] — the field was EMPTY (`''`): an EXPLICIT opt-out —
///    inherit from NOTHING, even a same-named builtin. The barrier
///    [AgentEnvironment.resolve] honors.
///  - [EnvBaseRef] — a NAMED parent with its [BaseScope].
///
/// absent (`undeclared`) != empty (`standalone`) is the whole point. The
/// registry (bead `pow-ebf.3`) consumes [EnvBaseRef.name]/[EnvBaseRef.scope]
/// to WALK; this type only REPRESENTS the pointer and honors the standalone
/// barrier in the fold.
sealed class EnvBase {
  /// Const-constructible (sealed base).
  const EnvBase();

  /// Parses gc's `base` string grammar into the tri-state: [raw] `null` =>
  /// [EnvBaseUndeclared]; `''` => [EnvBaseStandalone]; `builtin:x` =>
  /// [EnvBaseRef]`(x, builtin)`; `provider:x` => `(x, provider)`; any other
  /// `x` => `(x, auto)`.
  factory EnvBase.parse(String? raw) {
    if (raw == null) return const EnvBaseUndeclared();
    if (raw.isEmpty) return const EnvBaseStandalone();
    const builtinPrefix = 'builtin:';
    const providerPrefix = 'provider:';
    if (raw.startsWith(builtinPrefix)) {
      return EnvBaseRef(
        raw.substring(builtinPrefix.length),
        scope: BaseScope.builtin,
      );
    }
    if (raw.startsWith(providerPrefix)) {
      return EnvBaseRef(
        raw.substring(providerPrefix.length),
        scope: BaseScope.provider,
      );
    }
    return EnvBaseRef(raw);
  }
}

/// `base` ABSENT (gc `nil`) — inherit by convention. See [EnvBase].
class EnvBaseUndeclared extends EnvBase {
  /// Const-constructible.
  const EnvBaseUndeclared();

  @override
  bool operator ==(Object other) => other is EnvBaseUndeclared;

  @override
  int get hashCode => (EnvBaseUndeclared).hashCode;

  @override
  String toString() => 'EnvBaseUndeclared()';
}

/// `base` EMPTY (`''`) — explicit standalone opt-out. See [EnvBase].
class EnvBaseStandalone extends EnvBase {
  /// Const-constructible.
  const EnvBaseStandalone();

  @override
  bool operator ==(Object other) => other is EnvBaseStandalone;

  @override
  int get hashCode => (EnvBaseStandalone).hashCode;

  @override
  String toString() => 'EnvBaseStandalone()';
}

/// `base` = a NAMED parent, resolved against [scope]. See [EnvBase].
class EnvBaseRef extends EnvBase {
  /// References parent [name] under [scope] (default [BaseScope.auto]).
  const EnvBaseRef(this.name, {this.scope = BaseScope.auto});

  /// The parent environment name (without any `builtin:`/`provider:` prefix).
  final String name;

  /// The lookup scope the registry resolves [name] against.
  final BaseScope scope;

  @override
  bool operator ==(Object other) =>
      other is EnvBaseRef && other.name == name && other.scope == scope;

  @override
  int get hashCode => Object.hash(EnvBaseRef, name, scope);

  @override
  String toString() => 'EnvBaseRef($name, $scope)';
}

/// One inheritance LAYER of a named inference environment (ADR-0002 D1). A
/// pure VALUE (config = VALUES in the tree — ADR-0000 A8); it carries no
/// behavior and reaches no service. Nullable scalars mean "this layer does not
/// declare it — INHERIT"; [resolve] folds a chain of layers into one flattened
/// environment.
class AgentEnvironment {
  /// Creates a layer. Every field is optional: an undeclared field INHERITS
  /// (scalars/[args]) or contributes nothing ([argsAppend]/[env]).
  const AgentEnvironment({
    this.base = const EnvBaseUndeclared(),
    this.command,
    this.args,
    this.argsAppend = const [],
    this.promptMode,
    this.promptFlag,
    this.env = const {},
    this.model,
    this.target,
    this.pathCheck,
    this.resumeFlag,
    this.resumeStyle,
  });

  /// The inheritance pointer (gc `base`) — tri-state, LOAD-BEARING. Default
  /// [EnvBaseUndeclared] (absent).
  final EnvBase base;

  /// The executable to run (gc `command`). `null` INHERITS; a value REPLACES.
  final String? command;

  /// Default argv (gc `args`). REPLACE: a non-null [args] replaces the
  /// inherited list wholesale (`null` inherits). Deliberately asymmetric with
  /// [argsAppend] — gc keeps this asymmetry.
  final List<String>? args;

  /// Extra argv (gc `args_append`). ACCUMULATE: every layer's [argsAppend] is
  /// concatenated root->leaf after the resolved [args].
  final List<String> argsAppend;

  /// How the brief is delivered (gc `prompt_mode`). `null` inherits; the
  /// default when none is declared anywhere is [PromptMode.arg] (gc's default).
  final PromptMode? promptMode;

  /// The flag used when [promptMode] is [PromptMode.flag] (gc `prompt_flag`).
  final String? promptFlag;

  /// Process env layered for this environment (gc `env`). Key-wise merge: the
  /// leaf wins per key.
  final Map<String, String> env;

  /// The model id (the role -> tier -> model axis — ADR-0000 A20; a the_grid
  /// ADDITION, gc carries the model via `options_schema`). `null` inherits.
  final String? model;

  /// WHERE inference runs — the KIND only (ADR-0002 D3; a the_grid ADDITION
  /// from ADR-0008 `ModelTarget`). `null` inherits; the default is
  /// [InferenceTarget.providerManaged].
  final InferenceTarget? target;

  /// The real binary to PATH-check when [command] is a shell wrapper (gc
  /// `path_check` — the FT-2 `sh -c` case). `null` checks [command] itself.
  final String? pathCheck;

  /// The CLI token that resumes a session by id (gc `resume_flag`, e.g.
  /// `--resume` / `resume`). `null` means the tool has no resume.
  final String? resumeFlag;

  /// How [resumeFlag] is applied (gc `resume_style`). `null` inherits; the
  /// default when [resumeFlag] is set is [ResumeStyle.flag].
  final ResumeStyle? resumeStyle;

  /// A NAMED-invariant guard (guards LOUD or GONE — ADR-0000 A8): a
  /// [PromptMode.flag] transport with no [promptFlag] is unspawnable, and a
  /// [resumeStyle] set with no [resumeFlag] is meaningless. Returns the human
  /// error or `null` when legal — the two-moment posture of
  /// `AgentHarnessRegistry.validate` (return, don't throw; the caller fails
  /// the boot or the work).
  String? validate() {
    final needsFlag = switch (promptMode) {
      PromptMode.flag => true,
      PromptMode.arg || PromptMode.none || null => false,
    };
    final flag = promptFlag;
    if (needsFlag && (flag == null || flag.isEmpty)) {
      return 'promptMode is flag but promptFlag is unset';
    }
    if (resumeStyle != null && resumeFlag == null) {
      return 'resumeStyle is set but resumeFlag is unset';
    }
    return null;
  }

  /// Whether [target] requires a site endpoint (ADR-0002 D3). A `null` target
  /// is the default [InferenceTarget.providerManaged] => false.
  bool get needsSiteEndpoint =>
      inferenceTargetNeedsEndpoint(target ?? InferenceTarget.providerManaged);

  /// Folds an inheritance [chain] — ROOT at index 0, LEAF last — into one
  /// flattened environment:
  ///  - scalars ([command], [promptMode], [promptFlag], [model], [target],
  ///    [pathCheck], [resumeFlag], [resumeStyle]) — LAST non-null wins;
  ///  - [args] — REPLACE: the last layer declaring a non-null [args] wins;
  ///  - [argsAppend] — ACCUMULATE: concatenated over every effective layer,
  ///    root->leaf, after the resolved [args];
  ///  - [env] — key-wise merge, the leaf winning per key.
  ///
  /// The tri-state [base] is HONORED as an inheritance BARRIER: a layer whose
  /// [base] is [EnvBaseStandalone] (gc `''`) inherits from NOTHING, so every
  /// ancestor strictly more-root than the LAST standalone layer is DROPPED
  /// before folding. [EnvBaseUndeclared] (absent) and [EnvBaseRef] do NOT
  /// truncate — the observable absent-vs-empty difference. The result is
  /// [EnvBaseStandalone] (fully flattened; no ancestor remains). ASSEMBLING a
  /// chain by walking [EnvBaseRef] names is the registry's job (bead
  /// `pow-ebf.3`); this is the fold it calls.
  static AgentEnvironment resolve(List<AgentEnvironment> chain) {
    if (chain.isEmpty) {
      return const AgentEnvironment(base: EnvBaseStandalone());
    }
    var start = 0;
    for (var i = 0; i < chain.length; i++) {
      final isBarrier = switch (chain[i].base) {
        EnvBaseStandalone() => true,
        EnvBaseUndeclared() || EnvBaseRef() => false,
      };
      if (isBarrier) start = i;
    }
    final effective = chain.sublist(start);

    String? command;
    List<String>? args;
    final argsAppend = <String>[];
    PromptMode? promptMode;
    String? promptFlag;
    final env = <String, String>{};
    String? model;
    InferenceTarget? target;
    String? pathCheck;
    String? resumeFlag;
    ResumeStyle? resumeStyle;

    for (final layer in effective) {
      command = layer.command ?? command;
      if (layer.args != null) args = layer.args;
      argsAppend.addAll(layer.argsAppend);
      promptMode = layer.promptMode ?? promptMode;
      promptFlag = layer.promptFlag ?? promptFlag;
      env.addAll(layer.env);
      model = layer.model ?? model;
      target = layer.target ?? target;
      pathCheck = layer.pathCheck ?? pathCheck;
      resumeFlag = layer.resumeFlag ?? resumeFlag;
      resumeStyle = layer.resumeStyle ?? resumeStyle;
    }

    return AgentEnvironment(
      base: const EnvBaseStandalone(),
      command: command,
      args: args,
      argsAppend: argsAppend,
      promptMode: promptMode,
      promptFlag: promptFlag,
      env: env,
      model: model,
      target: target,
      pathCheck: pathCheck,
      resumeFlag: resumeFlag,
      resumeStyle: resumeStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentEnvironment &&
      other.base == base &&
      other.command == command &&
      _listEq(other.args, args) &&
      _listEq(other.argsAppend, argsAppend) &&
      other.promptMode == promptMode &&
      other.promptFlag == promptFlag &&
      _mapEq(other.env, env) &&
      other.model == model &&
      other.target == target &&
      other.pathCheck == pathCheck &&
      other.resumeFlag == resumeFlag &&
      other.resumeStyle == resumeStyle;

  @override
  int get hashCode {
    final argsHash = args == null ? null : Object.hashAll(args!);
    return Object.hash(
      base,
      command,
      argsHash,
      Object.hashAll(argsAppend),
      promptMode,
      promptFlag,
      Object.hashAllUnordered(
        env.entries.map((e) => Object.hash(e.key, e.value)),
      ),
      model,
      target,
      pathCheck,
      resumeFlag,
      resumeStyle,
    );
  }

  @override
  String toString() =>
      'AgentEnvironment(base: $base, command: $command, args: $args, '
      'argsAppend: $argsAppend, promptMode: $promptMode, '
      'promptFlag: $promptFlag, env: $env, model: $model, target: $target, '
      'pathCheck: $pathCheck, resumeFlag: $resumeFlag, '
      'resumeStyle: $resumeStyle)';
}

bool _listEq(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
