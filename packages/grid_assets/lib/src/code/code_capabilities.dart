/// The `code` extension — specify/agent/verify/land as Capability impls + the
/// linear `code` circuit (ADR-0008 D2 / M4-P1 §6, Track H; the specify stage
/// is bead `pow-6ao`, `specify.dart`).
///
/// The agent/verify/land OPINIONS live here as opaque [Capability] leaves (never
/// a `Seed`), composed into a linear [Circuit] whose always-1-wide frontier
/// reproduces the original agent→verify→land sequence. The kernel/effect core
/// references none of this — only this asset package does (the opinion-free
/// kernel invariant, ADR-0007 §1; a structural fence keeps it out of the engine).
///
/// This is the LIVE work path: `composeRunTree` wires it via the
/// [buildCodeRegistry] registry + a [CircuitResolver] that roots the `code`
/// circuit per coding bead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:meta/meta.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../../station_asset_registry.dart' show GeneratedGridAssetRegistrant;

import '../agent/agent_domain.dart';
import '../agent/acp_session_adapter.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/agent_session.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/typed_environment.dart';
import '../agent/usage_report.dart';
import '../assets/asset_loader.dart';
import '../assets/asset_resolution.dart';
import '../assets/overlay_materializer.dart';
import '../assets/overlay_provenance.dart';
import '../assets/vended_assets.dart';
import 'circuit_migration.dart';
import 'committee.dart';
import 'committee_selection.dart';
import 'committee_selection_evidence.dart';
import 'conventional_commit.dart';
import 'delivery.dart';
import 'discovery.dart';
import 'docs_committee.dart';
import 'fix_in_flight.dart';
import 'landing.dart';
import 'pr_composition.dart';
import 'pr_describe.dart';
import 'readiness.dart';
import 'respec.dart';
import 'specify.dart';

/// spec_review → agent → review → land — the live `code` circuit (M5 "The
/// Circuit" Track E; the spec stage is bead `pow-6ao`, the `land` step is itself
/// the landing circuit as of bead `tg-rm5`).
///
/// **The spec stage (beads `pow-6ao` + `pow-ui8` + `pow-q7n`)**: the worktree
/// drive loop opens with the spec circuit — [READINESS LADDER → specify agent →
/// SPEC committee → advance | RESPEC | escalate] — UPSTREAM of the build. The
/// ladder ([IntakeCapability] → [ReadinessCriticCapability] →
/// [ReadinessRouteCapability], bead `pow-q7n`) is the CHEAP pre-specify lens: it
/// grades the BEAD and HOLDS one that is not spec-ready, so `specify` and the
/// 4-critic committee never run on a coarse brief. `specify` ([SpecifyCapability])
/// is the architect-equivalent harness ride that writes the implementation-ready
/// spec INTO the bead (acceptance / plan / touches / ADR alignment / validation
/// plan, via the bd CLI); it is a STEP OF [kSpecReviewCircuit] (folded in by
/// `pow-ui8` so the route can name it in a `validates` edge — such an edge may
/// only name siblings in the source's own circuit), not of this circuit.
/// `agent`'s `dependsOn: {'spec_review'}` resolves — through the engine's
/// existing one-hop terminal resolution, no new machinery — to
/// `<bead>/spec_review/route`'s positive terminal, so ONLY a spec that passes its
/// committee proceeds to the build; a FIXABLE spec INVALIDATES the spec sub-DAG
/// in place (no human, no gate bead) — the route itself is inside that closure,
/// so the build's dep stays unresolved across the wave — and only an ESCALATION
/// parks the bead in the SAME `gated` state the code committee uses.
///
/// NOTE (bead `pow-3p4`): the fold MOVED the persisted cursor key
/// `<bead>/specify` → `<bead>/spec_review/specify`, so a session minted under
/// either older shape has no key at the new path and the frontier would read it
/// `pending`. Bouncing onto this circuit is GUARDED by `circuit_migration.dart`:
/// [CodeCircuitResolver] roots the frozen [kLegacyCodeCircuit] /
/// [kSpecHeadCodeCircuit] for such a survivor, so it never re-enters `specify`.
///
/// The toy `verify` step (`sh -c 'melos test'`) is GONE: `verify` is now the
/// adversarial code-committee, a [SubCircuitStep] the engine inflates one level
/// down ([kCodeReviewCircuit] — four critics in parallel → a `route` join). A
/// `dependsOn` on `review` resolves to its terminal-step descendant
/// (`<bead>/review/route`'s positive terminal), so `land` waits for the route to
/// advance; a route [Escalate] parks the work instead.
///
/// `land` is likewise a [SubCircuitStep] (`tg-rm5`, `landing.dart`'s
/// [kLandingCircuit]), and it PREPARES: `rebase → revalidate` — rebase the bead
/// branch onto the CURRENT base before re-running the bead's OWN Validation Plan
/// against the rebased tree (closing the stale-base hole: with N parallel beads
/// on one repo, the second-to-land would otherwise validate against a `main` that
/// already moved).
///
/// `deliver` is the TERMINAL ROUTE ([DeliverRouteCapability], `delivery.dart`)
/// whose [Advance] ACTUATES the substation's bound [DeliveryMethod] (M5 D-4a) —
/// commit residue, push, open or reuse the PR. It MUST be a FLAT route step:
/// [isDeliveryTerminal] is false at a [SubCircuitStep], and a sub-circuit's own
/// terminal advance never delivers, so a sub-circuit tail would silently degrade
/// the station to commit-only.
const Circuit kCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: kDeliverStep,
  steps: [
    SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review'),
    CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      dependsOn: {'spec_review'},
    ),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
    CapabilityStep(
      stepId: kDeliverStep,
      capabilityId: kDeliverStep,
      dependsOn: {'land'},
    ),
  ],
);

typedef _ResolvedAgentSelection = ({
  Bead bead,
  AgentEnvironment environment,
  String? model,
  Uri? endpoint,
});

typedef _ResolvedAgentRun = ({
  AgentEnvironment environment,
  Workspace workspace,
  AgentBrief brief,
  String? model,
  Uri? endpoint,
});

/// The IMPLEMENT capability — spawn the coding agent in the bead's workspace,
/// parameterized over the AMBIENT agent scope (ADR-0008 Decision 10): it reads
/// the work `Bead`, the `Workspace`, the station's `AgentConfig` default, and
/// the `AgentHarnessRegistry` with the effect verb, resolves the effective
/// config through the ladder ([resolveAgentConfig] — step params > bead
/// `grid.agent` envelope > ambient; fail-closed → a per-work `Failed`), and
/// delegates the INVOCATION to the resolved harness.
///
/// It declares the **FRONTIER tier** ([AgentTier.frontier], beads `pow-2c9` /
/// `pow-n6n.4`): absent a bead or station override, the coding agent rides
/// [kFrontierModelDefault] (`opus`) — the committee's critics declare the
/// cheaper MID tier off the same ambient config. WHICH environment it rides is
/// its typed [BuildAgentEnvironment] seat (ADR-0006 D2), never a name.
///
/// The POLICY stays here:
/// [buildAgentBrief] renders the full bead (a title-only brief starves the
/// agent, A36) + the **local-first working agreement**: work in the worktree,
/// COMMIT, do NOT push, do NOT open a PR. Landing is an explicit OPT-IN
/// (`--land`; ADR-0006 D3) and OFF by default. (claude's auth seam is the
/// macOS keychain — A38; no token rides argv.)
///
/// Also materializes the bead's declared `grid.dart` pub linkage into the
/// worktree ([_linkWorkspace] — ADR-0000 A1): the DART domain's envelope is
/// part of the work DEFINITION, read here alongside the rest of the bead, and
/// applied via the [DartLinkService] the_grid's dart_grid_assets pack ships
/// (grid_assets → dart_grid_assets, the pub-subordinate-to-Dart direction).
class AgentCapability extends ProcessCapability {
  /// Creates the agent capability. [devRoot] is the station's registered root
  /// checkout path ([RootCheckout.path] — "the registered root checkout's
  /// path") relative `grid.dart` dev-path links absolutize against in the
  /// per-bead worktree; null in an offline/dry-run build (no root
  /// registered — a relative link then refuses, never silently applies a
  /// broken override). [linkService] is injectable for tests.
  ///
  /// [materializer]/[assetRegistry]/[assetRosterOverride]/[overlayArgs] are the
  /// asset delivery seam (bead `pow-kzx`, re-homed onto the one resolution by
  /// `pow-4peu`): the SELECTED vended skills materialized into the per-bead
  /// worktree at provision, so the spawned `claude -p` can `/invoke` them. A
  /// NULL [assetRegistry] disables materialization outright — the explicit
  /// posture an isolated capability test (a session-adapter suite) takes so a
  /// spawn touches no asset tree at all.
  const AgentCapability({
    String? devRoot,
    DartLinkService linkService = const DartLinkService(),
    OverlayMaterializer materializer = const OverlayMaterializer(),
    sdk.GridAssetRegistry? assetRegistry,
    GridAssetRosterOverride? assetRosterOverride,
    String overlaySourceRef = kUnknownSourceRef,
    Map<String, String> overlayArgs = const {},
    AgentSessionAdapterRegistry sessionAdapters = kBuiltinAgentSessionAdapters,
    AgentSteerSource steers = const NoAgentSteerSource(),
  }) : _sessionAdapters = sessionAdapters,
       _steers = steers,
       _devRoot = devRoot,
       _linkService = linkService,
       _materializer = materializer,
       _assetRegistry = assetRegistry,
       _assetRosterOverride = assetRosterOverride,
       _overlaySourceRef = overlaySourceRef,
       _overlayArgs = overlayArgs;

  final AgentSessionAdapterRegistry _sessionAdapters;
  final AgentSteerSource _steers;

  final String? _devRoot;
  final DartLinkService _linkService;
  final OverlayMaterializer _materializer;

  /// The STATION-GENERATED registry [_linkWorkspace] resolves against for every
  /// provisioned worktree; null ⇒ no materialization at all (the explicit
  /// disabled posture — see the constructor).
  final sdk.GridAssetRegistry? _assetRegistry;

  /// The station's explicit include/exclude exceptions to what the selectors
  /// decide.
  final GridAssetRosterOverride? _assetRosterOverride;

  /// The grid_assets ref every materialized file's provenance header records.
  /// The code registry resolves this once at station composition; direct
  /// constructor use records [kUnknownSourceRef] unless a test/station injects a
  /// fixed value.
  final String _overlaySourceRef;

  /// The station's overrides for the overlay's template args — merged OVER the
  /// wire's own binding (`runner`/`gridHome`), so a station with a different
  /// runner verb or a real grid home wins.
  final Map<String, String> _overlayArgs;

  _ResolvedAgentSelection _resolveAgentSelection(
    TreeContext context,
    StepArgs args,
  ) {
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      throw StateError(
        'AgentCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      tier: AgentTier.frontier,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      typedEnvironment: resolveEnvironment<BuildAgentEnvironment>(context),
    );
    final environment = registry.resolve(config.harness);
    return (
      bead: bead,
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
    );
  }

  _ResolvedAgentRun _resolveRun(
    TreeContext context,
    StepArgs args, {
    _ResolvedAgentSelection? selection,
  }) {
    final selected = selection ?? _resolveAgentSelection(context, args);
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) {
      throw StateError(
        'AgentCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    final skills = _linkWorkspace(context, selected.bead, workspace);
    // The commit policy the brief teaches rides the station's composition knob
    // (bead `pow-8dx`) — read with the effect verb at the spawn edge (ADR-0008
    // D3); absent ⇒ the default `Refs` token.
    final composition =
        context.getInheritedSeedOfExactType<PrComposition>() ??
        const PrComposition();
    // The spec route may have advanced this bead carrying ONE open finding
    // (bead `pow-bhm`). Read it at the SPAWN edge, best-effort: a missing or
    // corrupt carry degrades to no block, never a throw into a spawn.
    final carried = Directory(workspace.workspaceDir).existsSync()
        ? readFixInFlight(workspace.workspaceDir)
        : null;
    return (
      environment: selected.environment,
      workspace: workspace,
      brief: buildAgentBrief(
        selected.bead,
        workspace,
        trailerToken: composition.trailerToken,
        skills: skills,
        fixInFlight: carried,
      ),
      model: selected.model,
      endpoint: selected.endpoint,
    );
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final run = _resolveRun(context, args);
    return spawnThroughSessionAdapter(
      adapters: _sessionAdapters,
      environment: run.environment,
      brief: run.brief,
      workspace: run.workspace,
      model: run.model,
      endpoint: run.endpoint,
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  ProcessSession? createSession({
    required RuntimeProvider runtime,
    required String name,
    required String attemptId,
    required String instanceFence,
    required TreeContext context,
    required StepArgs args,
  }) {
    final selection = _resolveAgentSelection(context, args);
    final adapterId = selection.environment.sessionAdapter;
    if (adapterId == null) return null;
    final run = _resolveRun(context, args, selection: selection);
    return AgentSession(
      runtime: runtime,
      name: name,
      adapter: _sessionAdapters.require(adapterId),
      brief: run.brief,
      commands: _steers.watch(args.beadId),
      attemptId: attemptId,
      instanceFence: instanceFence,
      // The out-of-band flare sink, read at this EFFECT edge with the
      // non-binding verb (ADR-0008 D3); absent => no flares, never a failure —
      // except for an AUTHORIZATION, where absent means no durable record and
      // so no grant at all ([decideAgentPermission]).
      transport: context
          .getInheritedSeedOfExactType<ServiceBundle>()
          ?.transport,
      // The station's authorization boundary, resolved the same way: an
      // explicitly mounted policy wins, else this seat's own ARMING is the
      // channel's admitted identity, else nothing is authorized.
      policy: seatChannelPolicy<BuildAgentEnvironment>(
        context,
        seatId: kBuildSeatPolicyId,
      ),
    );
  }

  /// Decodes [bead]'s `grid.dart` envelope and applies its pub linkage into
  /// [workspace] — right after [GitSourceControl.provisionWorkspace] cut the
  /// worktree (ADR-0008 D5: provisioning is this asset's opinion; the_grid
  /// engine carries no pub/dart-domain concept, so this lives here rather
  /// than in grid_engine). A SYNCHRONOUS [DartLinkService] call
  /// ([ProcessCapability.spawn] returns a `RuntimeConfig` directly, not a
  /// `Future` — it cannot await).
  ///
  /// A worktree dir that does not yet exist (offline/dry-run —
  /// [GitSourceControl] never materializes one there) skips silently, same
  /// posture as `GitSourceControl.provisionWorkspace`'s own offline no-op. A
  /// breaking `grid.dart` envelope THROWS, which [ProcessAllocation] (the
  /// existing `capability.spawn` fail-closed contract, ADR-0008 Decision 10)
  /// routes to supervision as a per-work `Failed` — never a half-applied
  /// override file.
  /// Returns the vended skill ids [_materializeStationOverlay] left installed in
  /// the worktree (empty when there is no worktree on disk yet).
  List<String> _linkWorkspace(
    TreeContext context,
    Bead bead,
    Workspace workspace,
  ) {
    if (!Directory(workspace.workspaceDir).existsSync()) return const [];
    final outcome = _linkService.applySync(
      metadata: bead.metadata,
      context: PubLinkContext.worktree,
      workspaceDir: workspace.workspaceDir,
      devRoot: _devRoot,
    );
    if (outcome is LinkRefused) {
      throw StateError(
        'AgentCapability: grid.dart pub linkage refused (fail-closed): '
        '${outcome.reason}',
      );
    }
    return _materializeStationOverlay(context, workspace);
  }

  /// Resolves what THIS substation's assets actually are — the one pure
  /// [resolveGridAssets] evaluation every other consumer runs — at the SPAWN
  /// edge, so a provision cannot select a different set than the substation
  /// tree mounted.
  ///
  /// The ambient pair is read with the EFFECT verb through
  /// [ambientAssetFactsOrFlare] (ADR-0008 D3): this is a spawn, not a build, so
  /// it takes the latest facts WITHOUT subscribing.
  ///
  /// NULL when the station has not mounted the projection yet — a MIGRATION
  /// state, not a violated invariant. A station composed before this projection
  /// existed still spawns: its worktrees keep whatever `.claude`/`.agents`
  /// assets the repository itself provides, and the one
  /// [kAssetFactsUnavailableFlare] the helper raised is how an operator sees
  /// that it is running on the pre-projection path. Selection stays STRICT once
  /// both values are mounted: a snapshot without this substation's own key
  /// still refuses loudly from [resolveGridAssets].
  GridAssetResolution? _resolveWorktreeAssets(
    TreeContext context,
    sdk.GridAssetRegistry registry,
    Workspace workspace,
  ) {
    final ambient = ambientAssetFactsOrFlare(context, consumer: 'agent');
    if (ambient == null) return null;
    return resolveGridAssets(
      registry: registry,
      snapshot: ambient.snapshot,
      substation: ambient.substation,
      rosterOverride: _assetRosterOverride,
      renderArguments: {
        'runner': kDefaultOverlayRunner,
        // The station's registered root checkout is the closest thing this
        // capability holds to a grid home; a station that knows its real one
        // overrides it (`buildCodeRegistry(overlayArgs:)`). Never null — an
        // unbound hole would REFUSE the skill instead of installing it.
        'gridHome': _devRoot ?? workspace.workspaceDir,
        ..._overlayArgs,
      },
    );
  }

  /// Materializes the RESOLVED assets into the worktree ROOT — each selected
  /// artifact at its declared root-relative path — and returns the skill ids now
  /// installed there (ADR-0001's delivery leg:
  /// `claude --dangerously-skip-permissions -p` is NON-bare, so it discovers
  /// `.claude/skills/`, and print mode invokes a skill only when the brief names
  /// it explicitly — hence the returned ids ride [buildAgentBrief]).
  ///
  /// SCOPED to [kWorktreeOverlaySubtrees]: one resolution, two consumers, but a
  /// per-bead worktree gets the per-harness SKILL trees only (`.claude/skills`
  /// for Claude Code, `.agents/skills` for Codex — which Copilot CLI reads as
  /// well, so both legs together reach every harness the station arms). The
  /// operator-seat assets (`.claude/agents/governor.md`, `.claude/settings.json`)
  /// belong to the human's seat, and a LOOSE file under a repo-owned dir cannot
  /// be git-fenced per-asset-dir — A23(6) rejected a shared `.claude/.gitignore`
  /// precisely because `.claude/` is repo-owned territory in the repos the grid
  /// cuts worktrees from (power_station and lenny TRACK
  /// `.claude/settings.json`; `bd init` tracks `.agents/skills/beads/`).
  /// Installing one there would either leak into the bead's PR or overwrite a
  /// tracked repo file from a provision hook.
  ///
  /// Same synchronous constraint as the pub-link write above, and the same
  /// never-clobber posture ([OverlayMaterializer] refuses to overwrite a file it
  /// did not generate, and REFUSES to install one whose holes are unbound rather
  /// than shipping literal `{{runner}}` text to an agent). A null registry
  /// materializes nothing at all — the explicit disabled posture, not a
  /// violated invariant.
  List<String> _materializeStationOverlay(
    TreeContext context,
    Workspace workspace,
  ) {
    final registry = _assetRegistry;
    if (registry == null) return const [];
    final resolution = _resolveWorktreeAssets(context, registry, workspace);
    // Un-migrated station: it flared, and the worktree keeps the repository's
    // own assets. Writing a fabricated set would be the very drift this
    // resolution exists to end.
    if (resolution == null) return const [];
    final report = _materializer.materializeSync(
      resolution: resolution,
      targetRoot: workspace.workspaceDir,
      sourceRef: _overlaySourceRef,
      subtrees: kWorktreeOverlaySubtrees,
    );
    for (final subtree in kWorktreeOverlaySubtrees) {
      _excludeOverlayFromGit(
        workspace.workspaceDir,
        report.writtenAssetDirsUnder(subtree),
      );
    }
    // AUDIENCE: the overlay is ONE tree with two consumers, so a worktree gets
    // the operator skills too — but the brief must not OFFER them.
    // `harvest-review` pushes and opens PRs; this brief forbids both. A skill
    // the brief never names cannot be invoked (print mode selects none on its
    // own — ADR-0001), so withholding the name is the whole guard.
    //
    // ONE leg answers for both: the agents leg is pinned byte-identical to the
    // claude leg (`overlay_codex_leg_test.dart`), so its id set is the same
    // set. Reading both would just deduplicate what one read already gives.
    //
    // The deny-list is DERIVED from the SAME station-generated registry the
    // resolution and materializer consume. That registry is the resolved
    // package closure, so a downstream pack's `audience: human` declaration
    // has the same force as grid_assets's own declaration — reading only this
    // package's pack would install a downstream operator skill and then OFFER
    // it
    // (`power_station#station-operator-audiences-derive-from-the-resolved-registry`).
    final withheld = operatorSkillIds(registry);
    return [
      for (final id in report.installedSkillIdsUnder(kClaudeSkillsSubtree))
        if (!withheld.contains(id)) id,
    ];
  }

  /// Keeps what we just materialized OUT of the bead's commit: the bound
  /// `DeliveryMethod` commits residue with `git add -A` (`GitOps.commitAll`), so
  /// an untracked
  /// `.claude/skills/**` or `.agents/skills/**` would ride every bead's PR into
  /// whatever repo the bead
  /// belongs to. Writes a SELF-IGNORING `.gitignore` — a single `*` — INSIDE
  /// each asset dir this call wrote into: `*` matches every file in that dir
  /// INCLUDING the `.gitignore` itself, so the whole vended asset is invisible
  /// to git (`git status --porcelain` stays EMPTY there and `git add -A` stages
  /// none of it), and the exclusion file is not residue either.
  ///
  /// SCOPED to the asset dirs, never a blanket `.claude/` ignore, and never a
  /// shared `.claude/.gitignore`: `.claude/` is repo-owned territory in the very
  /// repos the grid provisions worktrees from (the_grid TRACKS
  /// `.claude/skills/grid-porting/`; power_station and lenny track
  /// `.claude/settings.json`), so a shared file could be one the repo already
  /// owns. Per-asset-dir files cannot collide with it. Because a git ignore
  /// cannot hide TRACKED files, and because nothing outside the materialized
  /// asset dirs is ignored, delivery's post-commit residue fence
  /// (`GitOps.hasUncommittedWork` → plain `git status --porcelain`, ADR-0000 A5)
  /// still detects every other change in the worktree — including new files the
  /// coding agent itself writes under `.claude/`.
  void _excludeOverlayFromGit(String workspaceDir, List<String> assetDirs) {
    for (final assetDir in assetDirs) {
      final ignore = File(p.join(workspaceDir, assetDir, '.gitignore'));
      if (ignore.existsSync()) continue;
      ignore.writeAsStringSync(
        '# Per-worktree AGENT CONTEXT materialized at provision by the vended\n'
        '# station_overlay (grid_assets) — never repo content.\n'
        "# `*` ignores this whole asset dir INCLUDING this file, so land's\n"
        "# `git add -A` cannot carry it into the bead's PR.\n"
        '*\n',
      );
    }
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => _jobSignal(event);

  /// The CAPTURE-ONLY usage telemetry (FT-2): on a clean completion, read the
  /// resolved harness's declared JSON usage envelope and contribute
  /// tokensIn/tokensOut/costUsd/premiumRequests/numTurns/harnessDurationMs/model
  /// to `grid.result.<nodePath>.*`. FAIL-SAFE: an absent, malformed, or
  /// harness-without-usage envelope yields no fields (null), NEVER a throw —
  /// telemetry can never fail, gate, or delay the agent step.
  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return null;
    // The declared prices ride the ambient config VALUE, the flare sink is the
    // injected transport IMPL — both read with the NON-BINDING verb, because
    // `result()` is an effect edge, not a build (ADR-0008 D3).
    final prices =
        (context.getInheritedSeedOfExactType<AgentConfig>() ??
                const AgentConfig())
            .modelPrices;
    final usage = readUsageFields(
      workspace.workspaceDir,
      args.nodePath,
      modelPrices: prices,
      flare: context
          .getInheritedSeedOfExactType<ServiceBundle>()
          ?.transport
          ?.flare,
    );
    return usage.isEmpty ? null : usage;
  }
}

/// Assembles the agent's full-bead brief + local-first working agreement (the
/// live dogfood contract — exposed for unit tests). The agreement closes with
/// the **D-H genesis_tree doctrine** (ADR-0008; companion to the_grid
/// `GridDelegate` D-H fix): watch deps / no sync accessor over `StateNotifier`
/// state / config = values, impls = DI / guards LOUD or GONE — every coding
/// agent this station spawns carries it. Model/params are AgentConfig, NOT brief
/// (OQ-a) — one brief replays across harnesses. One-turn completion is OBSERVED
/// via process exit; channel completion is OBSERVED in the adapter's structured
/// protocol event — the agent never DECLARES a grid cursor transition (tg-p9q).
///
/// The agreement also carries the **commit policy** (bead `pow-8dx`): every
/// commit is Conventional Commits v1.0.0, its subject describes WHAT CHANGED IN
/// THIS REPO, and the bead id rides ONE git TRAILER (`<trailerToken>: <bead>`)
/// at the bottom — never the subject, never the body prose. The git log is the
/// primary artifact; a reader must learn what changed and why WITHOUT leaving
/// the repo. (What agents write today — `feat(scope): <bead> — …` — is the exact
/// anti-pattern.)
///
/// [skills] are the vended skill ids the provision wire actually materialized
/// into this worktree's `.claude/skills/` ([AgentCapability], bead `pow-kzx`).
/// The agreement NAMES them, because a print-mode `claude -p` selects no skill
/// on its own — only an explicit `/skill-name` invocation reaches one (ADR-0001).
/// Empty ⇒ no skills paragraph at all: the brief only ever names what is there.
AgentBrief buildAgentBrief(
  Bead bead,
  Workspace workspace, {
  String trailerToken = kDefaultTrailerToken,
  List<String> skills = const [],
  FixInFlight? fixInFlight,
}) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final task = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(
      substation is String && substation.isNotEmpty
          ? 'Bead `${bead.id}` (substation `$substation`).'
          : 'Bead `${bead.id}`.',
    );
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    task
      ..writeln()
      ..writeln('## $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  // The BINDING carry (bead `pow-bhm`, ratified 2026-07-18): the spec committee
  // advanced this spec with ONE open finding, so the builder closes it in
  // flight. Absent ⇒ a brief byte-identical to the pre-`pow-bhm` one.
  if (fixInFlight != null) {
    task
      ..writeln()
      ..writeln(renderFixInFlightGuidance(fixInFlight).trim());
  }
  final agreement = StringBuffer()
    ..writeln(
      '- Work ONLY inside this worktree (${workspace.workspaceDir}); it is on '
      'branch `${workspace.branch}`, a throwaway branch the_grid provisioned '
      'for this bead.',
    )
    ..writeln('- Implement the task and COMMIT your work on that branch.')
    ..writeln(
      '- Before you commit, run `dart format` on every changed Dart file; the '
      'review circuit refuses an unformatted diff.',
    )
    ..writeln(
      '- Every commit message is CONVENTIONAL COMMITS v1.0.0: '
      '`<type>[(scope)][!]: <description>`, type one of '
      '${kConventionalTypes.join(' | ')}. The description is IMPERATIVE, '
      'lowercase, carries NO trailing period, and the whole subject line stays '
      'under $kMaxSubjectChars characters.',
    )
    ..writeln(
      '- The subject says WHAT CHANGED IN THIS REPO, in the repo\'s own terms. '
      'NEVER put the bead id (`${bead.id}`) — or any other foreign reference — '
      'in the subject or in the body prose. The git log is the primary '
      'artifact: a reader must learn what changed and why WITHOUT leaving the '
      'repo.',
    )
    ..writeln(
      '- The bead id rides ONE git TRAILER at the very bottom, after a blank '
      'line: `$trailerToken: ${bead.id}`. That is the ONLY place it may appear.',
    )
    ..writeln(
      '- The body (optional, after a blank line) explains WHAT changed and a '
      'HIGH-LEVEL WHY — self-contained, no ticket narrative.',
    )
    ..writeln(
      '- A BREAKING change puts `!` after the type/scope AND a '
      '`BREAKING CHANGE: <what breaks>` footer at the bottom.',
    )
    ..writeln('- The shape, end to end:')
    ..writeln()
    ..writeln('      feat(landing): infer the pr title from the branch diff')
    ..writeln()
    ..writeln('      The land step templated its title off the bead, so every')
    ..writeln('      PR read `grid: <id>`. It now describes the actual diff.')
    ..writeln()
    ..writeln('      $trailerToken: ${bead.id}')
    ..writeln()
    ..writeln(
      '- Do NOT push and do NOT open a pull request — leave the commit for '
      'human review.',
    )
    ..writeln(
      '- Your ONE deliverable is the COMMIT. It is how you report completion, '
      'and it is the only thing this turn is graded on — so spend the whole '
      'turn on the code.',
    )
    ..writeln(
      '- The bead above is INPUT, and the tracker is the STATION\'s: the '
      'station opened this session against that bead, and it is the station '
      'that advances the bead once the committee has graded your commit. Read '
      'the bead; leave the tracker to the station.',
    )
    ..writeln('- When the work is committed you are done; exit.')
    ..writeln()
    ..writeln(
      'When you touch genesis_tree / grid code, hold the D-H doctrine '
      '(ADR-0008):',
    )
    ..writeln(
      '- Always watch deps: read ambient tree values in `build` via '
      '`dependOn*`; never snapshot-and-`??=`-cache reactive state.',
    )
    ..writeln(
      '- No public synchronous accessor over `StateNotifier` state — `.state`/'
      '`current` never escapes; re-project it as an `InheritedSeed` and observe '
      'it in `build`.',
    )
    ..writeln(
      '- Config = VALUES in the tree; impls = DI (no services in a branch '
      'except injected).',
    )
    ..write(
      '- Guards LOUD or GONE: a guard exists only if it protects a NAMED '
      'invariant and is loud (throws/refuses) when violated — otherwise delete '
      'it.',
    );
  if (skills.isNotEmpty) {
    agreement
      ..writeln()
      ..writeln()
      ..writeln(
        "The station materialized these VENDED skills into this worktree's "
        '`.claude/skills/` at provision — invoke one EXPLICITLY by name when '
        'the task calls for it (print mode selects no skill on its own). They '
        'are per-worktree agent context, not repo content — already '
        'git-excluded, never commit them:',
      )
      ..write(skills.map((id) => '- `/$id`').join('\n'));
  }
  return AgentBrief(
    task: task.toString(),
    workingAgreement: agreement.toString(),
  );
}

// The toy VERIFY capability (a fixed test command) was DELETED in M5 Track E:
// `verify` is now the adversarial code-committee ([kCodeReviewCircuit]), whose
// gating `code-validation` lane runs the bead's OWN Validation Plan — real
// verification, not one hard-coded command. (The opinion-free engine names no
// build tool at all; the structural fence guards it.)

/// A job's terminal mapping: a clean `Exited(0)` completes; any other terminal
/// (non-zero exit or a `Died`) fails (routes to supervision).
StepSignal _jobSignal(RuntimeEvent event) => switch (event) {
  Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
  Exited() || Died() => StepSignal.failed,
  _ => StepSignal.none,
};

/// The git [SourceControl] impl over grid_runtime — WORKSPACE PROVISIONING ONLY
/// (the detail the engine knows only in CONCEPT — ADR-0008 D5; ships in the asset
/// package).
///
/// M5 D-4a stripped commit/push/PR off the [SourceControl] interface: that is
/// DELIVERY detail, and it lives behind the substation's bound [DeliveryMethod]
/// (`delivery.dart`'s the GitHub PR delivery method). What remains here is provisioning —
/// [provisioner] ([StationGitService]) + [root] ([RootCheckout]) cut the per-bead
/// worktree, so the host can materialize the workspace before the agent spawns.
/// Absent ⇒ [provisionWorkspace] no-ops (the offline/dry-run build), while
/// `workspaceFor`/`branchFor`/`baseBranch` still resolve — the layout is
/// deterministic + pure.
///
/// The layout ("one git worktree per bead, cut from the substation's root") is
/// THIS impl's opinion, not the engine's — the engine's concept is "a workspace".
class GitSourceControl implements SourceControl {
  /// Wraps the optional provisioning seam ([provisioner]/[root]) plus the git
  /// seam the failed-provision unwind runs on ([gitRunner]; absent ⇒ the real
  /// [SystemGitRunner], the posture every other git consumer in this pack
  /// takes — the offline suite injects a fake, Fakes not mocks).
  const GitSourceControl({
    StationGitService? provisioner,
    RootCheckout? root,
    GitRunner? gitRunner,
  }) : _provisioner = provisioner,
       _root = root,
       _gitRunner = gitRunner;

  final StationGitService? _provisioner;
  final RootCheckout? _root;
  final GitRunner? _gitRunner;

  @override
  String workspaceFor(String beadId) {
    final root = _root;
    // The git layout is THIS impl's opinion (ADR-0008 D5): a per-bead worktree
    // under the root checkout. No root — or an EMPTY-path root (the dry-run
    // synthetic) — ⇒ the absolute synthetic placeholder, byte-identical to the
    // old EffectContext.worktreeFor null-branch. Guarding only `root == null`
    // would let an empty path produce a CWD-RELATIVE `.grid/worktrees/...`
    // (p.join drops the empty leading segment) — a latent spawn-against-CWD risk.
    return (root == null || root.path.isEmpty)
        ? '/grid/worktrees/$beadId'
        : WorktreeLayout.worktreePath(root.path, root.substation, beadId);
  }

  @override
  String branchFor(String beadId) => WorktreeLayout.branchFor(beadId);

  @override
  String get baseBranch => _root?.defaultBranch ?? 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    final provisioner = _provisioner;
    final root = _root;
    // Provisioning not wired (offline) — nothing to do.
    if (provisioner == null || root == null) return;
    // Idempotent only when the directory is already a git checkout — but an
    // ADOPTED worktree's bead store must still be verified (tg-v7qq): a
    // leftover dir from a prior station arm can carry a SELF-HOSTED dolt
    // store (its own `dolt/` + `dolt-server-*` sidecar) instead of the
    // proxied redirect to the substation root's `.beads/proxieddb`. Every
    // in-worktree `bd update` (the specify stage's spec write-back) then
    // lands in that isolated clone and NEVER reaches the root store the
    // station and the critique lanes read — a structurally perfect spec
    // round hard-blocks at spec-validation ("no ## Implementation Plan
    // section" on a bead whose worktree copy carries all four). Repair the
    // stranded store BEFORE reusing the workspace.
    if (_hasGitEntry(workspaceDir)) {
      repairStrandedWorktreeStore(
        workspaceDir: workspaceDir,
        rootRepoPath: root.path,
        beadId: beadId,
      );
      return;
    }

    final workspace = Directory(workspaceDir);
    if (!workspace.existsSync()) {
      await provisioner.provisionWorktree(root: root, beadId: beadId);
      _assertGitCheckout(workspaceDir, beadId);
      return;
    }

    final stash = Directory('$workspaceDir.scaffold-stash');
    if (stash.existsSync()) {
      throw StateError(
        'provisionWorkspace: scaffold stash already exists for $beadId at '
        '"${stash.path}"',
      );
    }

    // The unwind seam. `branchExists` is probed BEFORE the provision because
    // only a branch THIS call mints may be deleted on rollback — an adopted
    // `grid/<beadId>` can carry a prior arm's commits.
    final gitRunner = _gitRunner ?? SystemGitRunner();
    final branch = WorktreeLayout.branchFor(beadId);
    final branchPreexisted = await GitOps(
      gitRunner,
    ).branchExists(root.path, branch);

    workspace.renameSync(stash.path);
    try {
      await provisioner.provisionWorktree(root: root, beadId: beadId);
      _assertGitCheckout(workspaceDir, beadId);
      _restoreStashedEntries(
        stash: stash,
        workspace: workspace,
        beadId: beadId,
      );
    } catch (error, stackTrace) {
      // Unwind BEFORE the filesystem restore (git needs the worktree it
      // registered), but let the restore run either way: the scaffold must
      // come back even when the unwind itself could not be verified.
      final leftover = await _unwindProvisionedWorktree(
        runner: gitRunner,
        root: root,
        beadId: beadId,
        branch: branch,
        deleteBranch: !branchPreexisted,
      );
      _restoreWorkspaceAfterProvisionFailure(
        workspace: workspace,
        stash: stash,
        beadId: beadId,
        error: error,
      );
      if (leftover != null) {
        throw StateError(
          'provisionWorkspace: failed to unwind the discarded provision for '
          '$beadId after provisioning failed with $error: $leftover',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static bool _hasGitEntry(String workspaceDir) {
    final gitEntry = p.join(workspaceDir, '.git');
    return FileSystemEntity.typeSync(gitEntry, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  /// Repairs an adopted worktree whose `.beads` store is STRANDED — a prior
  /// arm's self-hosted dolt store instead of the proxied redirect to the
  /// substation root's `.beads/proxieddb` (tg-v7qq).
  ///
  /// Stranded signature (any of):
  /// - an independent `.beads/dolt/` database directory;
  /// - a `.beads/dolt-server-config.yaml` (the self-hosted sidecar's config);
  /// - a `.beads/proxied_server_client_info.json` whose `root_path` resolves
  ///   anywhere but the root repo's `.beads/proxieddb`.
  ///
  /// Repair: best-effort SIGTERM of a still-running stranded sidecar (its
  /// `dolt-server.pid`), then delete the self-hosted artifacts so the next
  /// in-worktree `bd` invocation re-establishes the proxied redirect exactly
  /// as it does on a FRESH worktree (the committed `.beads` scaffold —
  /// `metadata.json`, `config.yaml`, `identity.toml` — is untouched). A
  /// receipt line is appended to `.beads/store-repair.log` so the repair is
  /// visible in the worktree the operator inspects.
  ///
  /// A healthy proxied worktree (client info pointing at the root proxieddb,
  /// no self-hosted artifacts) is left byte-untouched.
  @visibleForTesting
  static void repairStrandedWorktreeStore({
    required String workspaceDir,
    required String rootRepoPath,
    required String beadId,
  }) {
    final beadsDir = p.join(workspaceDir, '.beads');
    if (!Directory(beadsDir).existsSync()) return;

    final rootProxy = p.canonicalize(
      p.join(rootRepoPath, '.beads', 'proxieddb'),
    );

    final doltDir = Directory(p.join(beadsDir, 'dolt'));
    final serverConfig = File(p.join(beadsDir, 'dolt-server-config.yaml'));
    var stranded = doltDir.existsSync() || serverConfig.existsSync();

    final clientInfo = File(
      p.join(beadsDir, 'proxied_server_client_info.json'),
    );
    if (!stranded && clientInfo.existsSync()) {
      var pointsAtRoot = false;
      try {
        final decoded = jsonDecode(clientInfo.readAsStringSync());
        if (decoded is Map<String, Object?>) {
          final rootPath = decoded['root_path'];
          if (rootPath is String && rootPath.isNotEmpty) {
            final resolved = p.isAbsolute(rootPath)
                ? rootPath
                : p.join(beadsDir, rootPath);
            pointsAtRoot = p.canonicalize(resolved) == rootProxy;
          }
        }
      } on Object {
        // Malformed client info: treat as stranded — repair re-derives it.
      }
      stranded = !pointsAtRoot;
    }
    if (!stranded) return;

    // Stop a still-running stranded sidecar before deleting its store.
    final pidFile = File(p.join(beadsDir, 'dolt-server.pid'));
    if (pidFile.existsSync()) {
      final pid = int.tryParse(pidFile.readAsStringSync().trim());
      if (pid != null && pid > 0) {
        try {
          Process.killPid(pid);
        } on Object {
          // Already gone — the reboot case.
        }
      }
    }

    final removed = <String>[];
    if (doltDir.existsSync()) {
      doltDir.deleteSync(recursive: true);
      removed.add('dolt/');
    }
    for (final name in const [
      'dolt-server-config.yaml',
      'dolt-server.lock',
      'dolt-server.pid',
      'dolt-server.port',
      'dolt-server.log',
      'proxied_server_client_info.json',
      'last-touched',
    ]) {
      final f = File(p.join(beadsDir, name));
      if (f.existsSync()) {
        f.deleteSync();
        removed.add(name);
      }
    }

    File(p.join(beadsDir, 'store-repair.log')).writeAsStringSync(
      'repaired stranded self-hosted bead store for $beadId on adopt '
      '(tg-v7qq): removed ${removed.join(', ')}; next bd invocation '
      're-establishes the proxied redirect to $rootProxy\n',
      mode: FileMode.append,
    );
  }

  static void _assertGitCheckout(String workspaceDir, String beadId) {
    if (_hasGitEntry(workspaceDir)) return;
    throw StateError(
      'provisionWorkspace: provisioner completed for $beadId but '
      '"$workspaceDir" is not a git checkout (missing .git entry)',
    );
  }

  /// Unwinds the provision the caller is DISCARDING.
  ///
  /// [_restoreWorkspaceAfterProvisionFailure] deletes the freshly added
  /// worktree DIRECTORY, which leaves git's registration under
  /// `.git/worktrees/<beadId>` and the just-minted `grid/<beadId>` branch
  /// behind. The next mount then finds the branch, takes
  /// [StationGitService.provisionWorktree]'s adopt path, and git refuses with
  /// "is a missing but already registered worktree" — a wedge no retry can
  /// clear. So the discard is COMPLETED: `git worktree remove --force`, run
  /// from the ROOT repo and never from inside the worktree (ADR-0006
  /// Decision 3), then `git worktree prune` in case the registration outlived
  /// its directory, then `git branch -D` only when [deleteBranch] — an ADOPTED
  /// branch is never deleted.
  ///
  /// The target path is derived with the SAME [WorktreeLayout] the provisioner
  /// used, not the caller's `workspaceDir`: git registered that path.
  ///
  /// Returns null when the unwind VERIFIES clean, or a one-line description of
  /// what survived (an unverifiable probe included) so the caller refuses
  /// LOUDLY. Never throws — [GitRunner] reports failure as a result.
  static Future<String?> _unwindProvisionedWorktree({
    required GitRunner runner,
    required RootCheckout root,
    required String beadId,
    required String branch,
    required bool deleteBranch,
  }) async {
    final ops = GitOps(runner);
    final provisioned = WorktreeLayout.worktreePath(
      root.path,
      root.substation,
      beadId,
    );
    await ops.worktreeRemove(
      rootRepo: root.path,
      path: provisioned,
      force: true,
    );
    // `remove` refuses once the directory is gone; prune drops exactly that
    // stale registration. Both are best-effort — the verify below is the guard.
    await runner.run(
      workingDirectory: root.path,
      args: const <String>['worktree', 'prune'],
    );
    if (deleteBranch) {
      await ops.branchDelete(rootRepo: root.path, branch: branch);
    }
    final listed = await ops.worktreeList(root.path);
    if (listed == null) {
      return 'could not verify the unwind — `git worktree list --porcelain` '
          'failed in "${root.path}"';
    }
    // Compared by DIR NAME, not by path: git reports symlink-RESOLVED paths
    // (macOS `/private/var` for a `/var` root), so a raw path compare would
    // read clean on a surviving registration. The per-bead worktree dir name
    // IS the bead id ([WorktreeLayout]).
    if (listed.any((wt) => p.basename(wt.path) == beadId)) {
      return 'a worktree registration for "$provisioned" survived';
    }
    if (deleteBranch && await ops.branchExists(root.path, branch)) {
      return 'the minted branch "$branch" survived';
    }
    return null;
  }

  /// Moves the stashed scaffold back into the freshly provisioned checkout,
  /// MERGING directories.
  ///
  /// A fresh checkout can legitimately TRACK a path the scaffold also occupies:
  /// the_grid tracks `.grid/seats/` while the engine scaffolds `.grid/critique/`
  /// into the same dir. Refusing on the shared DIRECTORY name discarded every
  /// fresh the_grid provision, so a directory meeting a directory RECURSES, and
  /// only a FILE meeting an existing path is a collision.
  ///
  /// Collisions are detected over the WHOLE tree before ANY entry moves: a
  /// half-moved scaffold is lost by [_restoreWorkspaceAfterProvisionFailure]
  /// (which deletes the workspace and renames the stash back), so the
  /// refuse-before-moving guarantee holds at every depth.
  static void _restoreStashedEntries({
    required Directory stash,
    required Directory workspace,
    required String beadId,
  }) {
    _assertNoFileCollisions(source: stash, target: workspace, beadId: beadId);
    _moveChildren(source: stash, target: workspace);
    stash.deleteSync();
  }

  /// Throws [StateError] when any entry under [source] would land on an
  /// EXISTING path in [target] that is not a directory-onto-directory merge.
  /// Reads only; moves nothing.
  static void _assertNoFileCollisions({
    required Directory source,
    required Directory target,
    required String beadId,
  }) {
    for (final entry in source.listSync(followLinks: false)) {
      final targetPath = p.join(target.path, p.basename(entry.path));
      final targetType = FileSystemEntity.typeSync(
        targetPath,
        followLinks: false,
      );
      if (targetType == FileSystemEntityType.notFound) continue;
      if (entry is Directory && targetType == FileSystemEntityType.directory) {
        _assertNoFileCollisions(
          source: entry,
          target: Directory(targetPath),
          beadId: beadId,
        );
        continue;
      }
      throw StateError(
        'provisionWorkspace: scaffold path collision for $beadId at '
        '"$targetPath"',
      );
    }
  }

  /// Moves every child of [source] into [target], recursing where BOTH sides
  /// are directories and deleting each emptied source dir behind it. A symlink
  /// is moved whole (`listSync(followLinks: false)` yields a [Link], never a
  /// [Directory]). Callers run [_assertNoFileCollisions] first.
  static void _moveChildren({
    required Directory source,
    required Directory target,
  }) {
    for (final entry in source.listSync(followLinks: false)) {
      final targetPath = p.join(target.path, p.basename(entry.path));
      if (entry is Directory &&
          FileSystemEntity.typeSync(targetPath, followLinks: false) ==
              FileSystemEntityType.directory) {
        _moveChildren(source: entry, target: Directory(targetPath));
        entry.deleteSync();
        continue;
      }
      entry.renameSync(targetPath);
    }
  }

  static void _restoreWorkspaceAfterProvisionFailure({
    required Directory workspace,
    required Directory stash,
    required String beadId,
    required Object error,
  }) {
    if (!stash.existsSync()) return;
    try {
      if (workspace.existsSync()) {
        workspace.deleteSync(recursive: true);
      }
      stash.renameSync(workspace.path);
    } on Object catch (restoreError) {
      throw StateError(
        'provisionWorkspace: failed to restore scaffold for $beadId after '
        'provisioning failed with $error: $restoreError',
      );
    }
  }
}

/// Builds the `code` registry: the SPEC-READINESS INTAKE LENS
/// (`intake`/`readiness`/`readiness-route`, bead `pow-q7n` — the cheap
/// pre-specify ladder that HOLDS a bead that is not ready to specify) + the
/// specify stage + spec-readiness committee
/// (`specify`/`spec-critic`/`spec-validation` + the `spec_review` circuit,
/// bead `pow-6ao`) + the agent/land capabilities + the adversarial committee
/// (`critic`/`route` + the `code_review` circuit) + the landing
/// circuit (`rebase`/`revalidate` + the `landing` circuit, `tg-rm5`), with an
/// optional injected [clock] (the backoff seam). The composer provides it as a
/// stable `InheritedSeed<CapabilityRegistry>` above `Station`, alongside a
/// `CircuitResolver((_) => kCodeCircuit)`. The spec critics share [rubrics]
/// with the code critics — ONE RubricSource serves both committees (the
/// loader resolves any `extension/rubrics/<id>.md` by id).
///
/// The `code` circuit's `verify` step is the committee (M5 Track E): the toy
/// `verify` capability is gone, and the `critic` capability is wired to the
/// Packaged-AI-Asset rubric loader (D-9) — [rubrics] overrides it for a test
/// that wants inline rubric text (absent ⇒ the on-disk `extension/rubrics/`).
/// [devRoot] threads the station's registered root checkout path into
/// [AgentCapability] (the `grid.dart` pub-link worktree absolutize root; null
/// ⇒ offline/dry-run, no root registered). [gitRunner]/[shellRunner] override
/// `rebase`/`revalidate`'s real git/shell seams (tests inject recording fakes —
/// Fakes, not mocks; absent ⇒ the real [SystemGitRunner]/[SystemShellRunner]).
/// [dartFormatService] overrides [FormatCleanCapability]'s real Dart formatter
/// probe (bead `pow-jicn`); absent ⇒ the real [DartFormatService], which the
/// offline suite never reaches (no worktree on disk ⇒ no process at all).
/// [critiqueDirClearer] overrides [ClearCritiqueCapability]'s real
/// delete+recreate (gate-integrity #3, bead `tg-bns`) — tests inject a no-op
/// so the offline suite never touches a real filesystem at a synthetic
/// workspace path.
///
/// [inference] overrides the land step's one-shot describe runner (bead
/// `pow-8dx`; tests inject a fake — Fakes, not mocks); absent ⇒ the real
/// [SystemInferenceRunner]. The describe pass is doubly fail-safe (no worktree
/// on disk ⇒ no call at all), so the offline suite never reaches a real `claude`
/// even under the live default.
///
/// [overlayArgs] overrides the template args the station_overlay's vended skills
/// render against in each provisioned worktree ([AgentCapability], bead
/// `pow-kzx`) — a station whose runner verb is not [kDefaultOverlayRunner], or
/// which knows its real grid-home root, passes them here.
///
/// [overlaySourceRef] overrides the provenance ref stamped into each
/// materialized overlay file. Null resolves this package's own station overlay
/// ref once while the code registry is composed, then threads that stable value
/// into [AgentCapability], so per-bead agent spawn never shells out for it.
///
/// [discoveryDecisions]/[discoveryHistory] override the deterministic gather's
/// roster-mode decision-index and git-history seams (bead-level Fakes; absent ⇒
/// [commandDecisionIndexSource]/[gitHistorySource] over this registry's own
/// [shellRunner]/[gitRunner]).
///
/// An injected [discoveryDecisions] is AUTHORITATIVE — it is the seam an
/// in-process `decisions index` composition rides. The shell fallback executes
/// nothing but `overlayArgs['runner']`, so this pack never names a decisions
/// binary: a missing or blank runner records every surface `unavailable`
/// WITHOUT touching [SystemShellRunner].
///
/// [specifyBdRunnerFor] controls only the specify step's post-exit work-bead
/// read-back. It defaults to [ProcessBdRunner] and lets offline suites inject
/// Fakes instead of spawning `bd`.
DefaultCapabilityRegistry buildCodeRegistry({
  DateTime Function()? clock,
  RubricSource? rubrics,
  String? devRoot,
  GitRunner? gitRunner,
  ShellRunner? shellRunner,
  DartFormatService? dartFormatService,
  DirectoryClearer? critiqueDirClearer,
  InferenceRunner? inference,
  AnchorResolver? anchorResolver,
  PriorArtSource? priorArt,
  DecisionIndexSource? discoveryDecisions,
  HistorySource? discoveryHistory,
  BdRunner Function(String workspaceRoot)? specifyBdRunnerFor,
  sdk.GridAssetRegistry? assetRegistry,
  GridAssetRosterOverride? assetRosterOverride,
  InferenceRunner? committeeClassifier,
  CommitteeSelectionStore? committeeSelectionStore,
  String? overlaySourceRef,
  Map<String, String> overlayArgs = const {},
  AgentSessionAdapterRegistry sessionAdapters = kBuiltinAgentSessionAdapters,
  AgentSteerSource steers = const NoAgentSteerSource(),
}) {
  final loader = PackagedAssetLoader();
  // The COMPOSING STATION's verb, resolved ONCE from the same `overlayArgs` map
  // the vended skills render against (A23(4)). Everything the spec path tells an
  // agent to RUN is rendered from it: the roster-lookup block and the register
  // read rule (`SpecifyCapability`/`SpecCriticCapability`), and the `{{runner}}`
  // hole the packaged `decision-alignment` bands carry. A downstream station
  // whose verb is not `space` was otherwise handed a command that exits 127.
  final decisionRunner = overlayArgs['runner'] ?? kDefaultOverlayRunner;
  // The COMPOSING STATION's grid home, from the SAME in-store binding A23(4)
  // gives `runner` — the cwd the station's JIT verb actually resolves from.
  // Unlike `decisionRunner` this takes no `kDefaultOverlayRunner`-style
  // fallback beyond the registered root checkout: an unbound grid home records
  // honest absence rather than running the verb somewhere it cannot resolve.
  final decisionGridHome = overlayArgs['gridHome'] ?? devRoot;
  final rubricSource =
      rubrics ?? loader.boundRubricSource(args: {'runner': decisionRunner});
  final stationOverlayRoot = p.join(loader.root, 'station_overlay');
  final resolvedOverlaySourceRef =
      overlaySourceRef ?? resolveOverlaySourceRefSync(stationOverlayRoot);
  // ONE registry object for the whole composition: the provision writer and the
  // landing guard resolve against the SAME value, so they cannot select
  // different asset sets. Absent ⇒ the station's own GENERATED registrant
  // (`power_station#station-registries-use-resolved-package-closures`) — this
  // composes the generated closure, it never builds a second catalog.
  final resolvedAssetRegistry =
      assetRegistry ?? GeneratedGridAssetRegistrant.registry;
  // The SHADOW committee selector's three seams (bead `pow-1nl.1.1`), composed
  // ONCE so the selector and both wrapped routes share one store.
  final selectionStore =
      committeeSelectionStore ?? const FileCommitteeSelectionStore();
  final selectionInference =
      committeeClassifier ?? const SystemInferenceRunner();
  Future<({bool ok, String output})> classify(RuntimeConfig config) async {
    final run = await selectionInference.run(config);
    return (ok: run.ok, output: run.output);
  }

  return DefaultCapabilityRegistry(
    capabilities: {
      // The SPEC-READINESS INTAKE LENS (bead `pow-q7n`) — the cheap ladder at
      // the head of the spec circuit. `intake` shares the [critiqueDirClearer]
      // seam with the hygiene step: it owns the readiness lane's round-freshness
      // (clear-critique only wipes DOWNSTREAM of specify), and the offline suite
      // injects the same no-op clearer for both.
      kIntakeStep: IntakeCapability(clearer: critiqueDirClearer),
      kReadinessStep: ReadinessCriticCapability(rubrics: rubricSource),
      kReadinessRouteStep: const ReadinessRouteCapability(),
      // The DISCOVERY circuit (`discovery.dart`) — the nested gather + violation
      // gate between the readiness ladder and `specify`. `anchors` shares the
      // [critiqueDirClearer] seam (it owns the discovery round's freshness wipe,
      // the A17(8) posture one level down) and the [rubrics] source, and it is
      // handed the spec committee's OWN rubric ids: the architect is shown the
      // FULL rubrics its spec is graded by (ADR-0000 A19's Status footer names
      // this circuit as the generalization of that principle). The ids arrive as
      // a VALUE, which is what keeps `discovery.dart` free of `specify.dart`.
      kAnchorsStep: AnchorsCapability(
        rubricIds: kSpecCommitteeRubrics,
        rubrics: rubricSource,
        resolver: anchorResolver,
        priorArt: priorArt,
        // The gather runs the roster-mode decision index and the surfaces' git
        // history ONCE per round, through the registry's OWN shell/git seams —
        // no second runner abstraction, and the same recording fakes ride
        // offline.
        //
        // The decision index is the station's OWN verb, so this pack never
        // names an executable: an injected [DecisionIndexSource] (the
        // in-process composition seam) wins, and the shell fallback runs ONLY
        // the invocation the station composed into `overlayArgs['runner']`.
        // Absent ⇒ no shell call and an honest `unavailable` record. A23(4)'s
        // in-store `kDefaultOverlayRunner` still binds the RENDERED skill arg
        // above; it deliberately does not bind this EXECUTING path, where a
        // guessed verb is exit 127 rather than legible prose.
        //
        // The verb runs at the station's GRID HOME (`overlayArgs['gridHome']`,
        // else the registered root checkout), never at the per-bead worktree:
        // a JIT runner resolves only where its package is.
        decisions:
            discoveryDecisions ??
            commandDecisionIndexSource(
              shellRunner ?? const SystemShellRunner(),
              runnerInvocation: overlayArgs['runner'],
              gridHome: decisionGridHome,
            ),
        history:
            discoveryHistory ??
            gitHistorySource(gitRunner ?? SystemGitRunner()),
        clearer: critiqueDirClearer,
      ),
      // ONE capability, three lens lanes (`params['lens']`) — the id is the
      // circuit's own, so a lens step reads `capabilityId: 'discovery'`.
      kDiscoveryCircuitId: const DiscoveryLensCapability(),
      kDiscoveryRouteStep: const DiscoveryRouteCapability(),
      // The spec stage + its committee lanes (bead `pow-6ao`; `specify` folded
      // into the spec circuit by `pow-ui8`).
      kSpecifyStep: specifyBdRunnerFor == null
          ? SpecifyCapability(
              sessionAdapters: sessionAdapters,
              steers: steers,
              decisionRunner: decisionRunner,
            )
          : SpecifyCapability(
              runnerFor: specifyBdRunnerFor,
              sessionAdapters: sessionAdapters,
              steers: steers,
              decisionRunner: decisionRunner,
            ),
      'spec-critic': SpecCriticCapability(
        rubrics: rubricSource,
        decisionRunner: decisionRunner,
      ),
      kSpecGatingRubric: const SpecValidationCapability(),
      // The SPEC committee's own route (bead `pow-7nm`) — the three-way
      // advance | RESPEC | escalate matrix. The code committee keeps the binary
      // `route` below; the two matrices are now independent (ADR-0000 A14,
      // which departs from A13(5)'s shared-route posture).
      // The SPEC route, WRAPPED in shadow bookkeeping (bead `pow-1nl.1.1`).
      // The delegate and its matrix are untouched: the wrapper returns the
      // delegate's exact verdict object and only writes a receipt beside it.
      'spec-route': CommitteeShadowRouteCapability(
        delegate: const SpecRouteCapability(),
        store: selectionStore,
      ),
      'agent': AgentCapability(
        devRoot: devRoot,
        assetRegistry: resolvedAssetRegistry,
        assetRosterOverride: assetRosterOverride,
        overlaySourceRef: resolvedOverlaySourceRef,
        overlayArgs: overlayArgs,
        sessionAdapters: sessionAdapters,
        steers: steers,
      ),
      // The old `land` binding is GONE: the PR is no longer a step. The TERMINAL
      // route advances and the engine actuates the substation's bound
      // DeliveryMethod (M5 D-4a).
      kDeliverStep: DeliverRouteCapability(
        gitRunner: gitRunner,
        inference: inference ?? const SystemInferenceRunner(),
      ),
      'critic': CriticCapability(rubrics: rubricSource),
      // The declared-tests gate reads the PINNED BASE's file list to tell a
      // `Test:` run reference from a promise (bead `pow-0jc`), so it shares the
      // registry's one git seam ([gitRunner]) — the same fake `rebase` and
      // `pin-diff` ride offline; absent ⇒ the real [SystemGitRunner] (A9(5)).
      kDeclaredTestsRubric: DeclaredTestsCapability(runner: gitRunner),
      // The DOCS committee's three deterministic lanes — ONE capability, three
      // lanes selected by `params['rubric']`, mirroring `critic`. No rubric
      // source: the checks are mechanical, so the prose in `extension/rubrics/`
      // documents the contract rather than feeding a model.
      kDocsCheckCapabilityId: const DocsCheckCapability(),
      // The CODE/DOCS route, WRAPPED in the same shadow bookkeeping.
      'route': CommitteeShadowRouteCapability(
        delegate: const CodeRouteCapability(),
        store: selectionStore,
      ),
      // The shadow selector itself — one capability, three circuits, selected
      // by `params['committeeStage']`. It depends on nothing priced and
      // nothing depends on it.
      kCommitteeSelectionStep: CommitteeSelectionCapability(
        classifier: classify,
        evidenceSource: const DiscoveryCommitteeSelectionEvidenceSource(
          pinnedDiffPathFor: pinnedDiffPath,
        ),
        store: selectionStore,
      ),
      'rebase': RebaseCapability(
        runner: gitRunner,
        assetRegistry: resolvedAssetRegistry,
        assetRosterOverride: assetRosterOverride,
      ),
      'revalidate': RevalidateCapability(runner: shellRunner),
      kClearCritiqueStep: ClearCritiqueCapability(clearer: critiqueDirClearer),
      // The diff-pinning pre-critic step (bead `pow-6wo`) shares the `code`
      // registry's git seam ([gitRunner]) — the SAME recording fake `rebase`
      // rides offline; absent ⇒ the real [SystemGitRunner].
      kPinDiffStep: PinDiffCapability(runner: gitRunner),
      // The formatting gate (bead `pow-jicn`) reads the SAME pinned scope and
      // composes the DART domain's own formatter probe by id, so a substation
      // whose domain is not Dart composes nothing. [dartFormatService] injects
      // a canned Fake offline; absent ⇒ the real [DartFormatService].
      kFormatCleanStep: FormatCleanCapability(
        formatter: dartFormatService ?? const DartFormatService(),
      ),
    },
    circuits: const {
      'code': kCodeCircuit,
      'spec_review': kSpecReviewCircuit,
      kDiscoveryCircuitId: kDiscoveryCircuit,
      'code_review': kCodeReviewCircuit,
      kDocsReviewCircuitId: kDocsReviewCircuit,
      'landing': kLandingCircuit,
      // The FROZEN old-shape spec circuits (bead `pow-3p4`, extended by
      // `pow-q7n`): `spec_review_v1` (pre-fold) is reachable ONLY from
      // [kSpecHeadCodeCircuit], `spec_review_v2` (pre-ladder) ONLY from
      // [kFoldedCodeCircuit] — the roots the migration guard picks for a shape-2
      // / shape-3 survivor. Unreachable from [kCodeCircuit]; delete them with
      // the guard.
      ...kMigrationCircuits,
    },
    clock: clock,
  );
}
