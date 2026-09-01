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
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/acp_session_adapter.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/agent_session.dart';
import '../agent/environment_registry.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import '../assets/asset_loader.dart';
import '../assets/overlay_materializer.dart';
import '../assets/overlay_manifest.dart';
import '../assets/overlay_provenance.dart';
import 'circuit_migration.dart';
import 'committee.dart';
import 'conventional_commit.dart';
import 'delivery.dart';
import 'discovery.dart';
import 'docs_committee.dart';
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
/// It spawns in the **BUILD role** ([AgentRole.build], bead `pow-edp`): absent a
/// bead or station override, the coding agent rides the FRONTIER tier ([tierFor]
/// — [kFrontierModelDefault], `opus`) — the committee's critics resolve their
/// own, cheaper tier off the same ambient config.
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
  /// [materializer]/[overlayRoot]/[overlayArgs] are the station_overlay delivery
  /// seam (bead `pow-kzx`): the vended skills materialized into the per-bead
  /// worktree at provision, so the spawned `claude -p` can `/invoke` them.
  const AgentCapability({
    String? devRoot,
    DartLinkService linkService = const DartLinkService(),
    OverlayMaterializer materializer = const OverlayMaterializer(),
    String? overlayRoot,
    String overlaySourceRef = kUnknownSourceRef,
    Map<String, String> overlayArgs = const {},
    AgentSessionAdapterRegistry sessionAdapters = kBuiltinAgentSessionAdapters,
    AgentSteerSource steers = const NoAgentSteerSource(),
  }) : _sessionAdapters = sessionAdapters,
       _steers = steers,
       _devRoot = devRoot,
       _linkService = linkService,
       _materializer = materializer,
       _overlayRoot = overlayRoot,
       _overlaySourceRef = overlaySourceRef,
       _overlayArgs = overlayArgs;

  final AgentSessionAdapterRegistry _sessionAdapters;
  final AgentSteerSource _steers;

  final String? _devRoot;
  final DartLinkService _linkService;
  final OverlayMaterializer _materializer;

  /// The `station_overlay` dir [_linkWorkspace] expands into every provisioned
  /// worktree (bead `pow-kzx`); null ⇒ this package's OWN vended overlay
  /// (`<PackagedAssetLoader.root>/station_overlay`). Tests inject a fixture so
  /// the wire is provable without the live tree.
  final String? _overlayRoot;

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
      role: AgentRole.build,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
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
    final skills = _linkWorkspace(selected.bead, workspace);
    // The commit policy the brief teaches rides the station's composition knob
    // (bead `pow-8dx`) — read with the effect verb at the spawn edge (ADR-0008
    // D3); absent ⇒ the default `Refs` token.
    final composition =
        context.getInheritedSeedOfExactType<PrComposition>() ??
        const PrComposition();
    return (
      environment: selected.environment,
      workspace: workspace,
      brief: buildAgentBrief(
        selected.bead,
        workspace,
        trailerToken: composition.trailerToken,
        skills: skills,
      ),
      model: selected.model,
      endpoint: selected.endpoint,
    );
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final run = _resolveRun(context, args);
    final adapterId = run.environment.sessionAdapter;
    if (adapterId == null) {
      return spawnFor(
        environment: run.environment,
        model: run.model,
        endpoint: run.endpoint,
        brief: run.brief,
        workspace: run.workspace,
        usageOut: usageReportPath(args.nodePath),
      );
    }
    final config = _sessionAdapters
        .require(adapterId)
        .launch(
          environment: run.environment,
          workspace: run.workspace,
          model: run.model,
          endpoint: run.endpoint,
        );
    if (config.lifecycle != Lifecycle.longLived) {
      throw StateError('channel adapter "$adapterId" must launch longLived');
    }
    return config;
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
  List<String> _linkWorkspace(Bead bead, Workspace workspace) {
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
    return _materializeStationOverlay(workspace);
  }

  /// Expands the vended `station_overlay` into the worktree ROOT — PATH-
  /// PRESERVING, so the overlay's own `.claude/skills/<id>/` lands at
  /// `<workspaceDir>/.claude/skills/<id>/` with no mapping in this wire — and
  /// returns the skill ids now installed there (ADR-0001's delivery leg:
  /// `claude --dangerously-skip-permissions -p` is NON-bare, so it discovers
  /// `.claude/skills/`, and print mode invokes a skill only when the brief names
  /// it explicitly — hence the returned ids ride [buildAgentBrief]).
  ///
  /// SCOPED to [kClaudeSkillsSubtree]: the overlay is ONE tree with two
  /// consumers, but a per-bead worktree gets the SKILL tree only. The
  /// operator-seat assets (`.claude/agents/governor.md`, `.claude/settings.json`)
  /// belong to the human's seat, and a LOOSE file under `.claude/` cannot be
  /// git-fenced per-asset-dir — A23(6) rejected a shared `.claude/.gitignore`
  /// precisely because `.claude/` is repo-owned territory in the repos the grid
  /// cuts worktrees from (power_station and lenny TRACK `.claude/settings.json`).
  /// Installing one there would either leak into the bead's PR or overwrite a
  /// tracked repo file from a provision hook.
  ///
  /// Same synchronous constraint as the pub-link write above, and the same
  /// never-clobber posture ([OverlayMaterializer] refuses to overwrite a file it
  /// did not generate, and REFUSES to install one whose holes are unbound rather
  /// than shipping literal `{{runner}}` text to an agent). A missing overlay dir
  /// contributes nothing rather than erroring — the empty-overlay case, not a
  /// violated invariant.
  List<String> _materializeStationOverlay(Workspace workspace) {
    final loader = PackagedAssetLoader();
    final overlayRoot = _overlayRoot ?? p.join(loader.root, 'station_overlay');
    if (!Directory(overlayRoot).existsSync()) return const [];
    final source = _overlayRoot == null
        ? loader.loadStationOverlaySource()
        : StationOverlaySource(
            root: overlayRoot,
            mappings: kDefaultStationOverlayMappings,
          );
    final report = _materializer.materializeSync(
      overlaySources: [source],
      targetRoot: workspace.workspaceDir,
      sourceRef: _overlaySourceRef,
      subtrees: kWorktreeOverlaySubtrees,
      args: {
        'runner': kDefaultOverlayRunner,
        // The station's registered root checkout is the closest thing this
        // capability holds to a grid home; a station that knows its real one
        // overrides it (`buildCodeRegistry(overlayArgs:)`). Never null — an
        // unbound hole would REFUSE the skill instead of installing it.
        'gridHome': _devRoot ?? workspace.workspaceDir,
        ..._overlayArgs,
      },
    );
    _excludeOverlayFromGit(
      workspace.workspaceDir,
      report.writtenAssetDirsUnder(kClaudeSkillsSubtree),
    );
    // AUDIENCE: the overlay is ONE tree with two consumers, so a worktree gets
    // the operator skills too — but the brief must not OFFER them.
    // `harvest-review` pushes and opens PRs; this brief forbids both. A skill
    // the brief never names cannot be invoked (print mode selects none on its
    // own — ADR-0001), so withholding the name is the whole guard.
    return [
      for (final id in report.installedSkillIdsUnder(kClaudeSkillsSubtree))
        if (!kOperatorSkills.contains(id)) id,
    ];
  }

  /// Keeps what we just materialized OUT of the bead's commit: the bound
  /// `DeliveryMethod` commits residue with `git add -A` (`GitOps.commitAll`), so
  /// an untracked
  /// `.claude/skills/**` would ride every bead's PR into whatever repo the bead
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
    final usage = readUsageFields(workspace.workspaceDir, args.nodePath);
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
  final agreement = StringBuffer()
    ..writeln(
      '- Work ONLY inside this worktree (${workspace.workspaceDir}); it is on '
      'branch `${workspace.branch}`, a throwaway branch the_grid provisioned '
      'for this bead.',
    )
    ..writeln('- Implement the task and COMMIT your work on that branch.')
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
  /// Wraps the optional provisioning seam ([provisioner]/[root]).
  const GitSourceControl({StationGitService? provisioner, RootCheckout? root})
    : _provisioner = provisioner,
      _root = root;

  final StationGitService? _provisioner;
  final RootCheckout? _root;

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
      _restoreWorkspaceAfterProvisionFailure(
        workspace: workspace,
        stash: stash,
        beadId: beadId,
        error: error,
      );
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

  static void _restoreStashedEntries({
    required Directory stash,
    required Directory workspace,
    required String beadId,
  }) {
    final entries = stash.listSync(followLinks: false);
    for (final entry in entries) {
      final target = p.join(workspace.path, p.basename(entry.path));
      if (FileSystemEntity.typeSync(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError(
          'provisionWorkspace: scaffold path collision for $beadId at '
          '"$target"',
        );
      }
    }
    for (final entry in entries) {
      entry.renameSync(p.join(workspace.path, p.basename(entry.path)));
    }
    stash.deleteSync();
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
/// [specifyBdRunnerFor] controls only the specify step's post-exit work-bead
/// read-back. It defaults to [ProcessBdRunner] and lets offline suites inject
/// Fakes instead of spawning `bd`.
DefaultCapabilityRegistry buildCodeRegistry({
  DateTime Function()? clock,
  RubricSource? rubrics,
  String? devRoot,
  GitRunner? gitRunner,
  ShellRunner? shellRunner,
  DirectoryClearer? critiqueDirClearer,
  InferenceRunner? inference,
  AnchorResolver? anchorResolver,
  PriorArtSource? priorArt,
  BdRunner Function(String workspaceRoot)? specifyBdRunnerFor,
  String? overlaySourceRef,
  Map<String, String> overlayArgs = const {},
  AgentSessionAdapterRegistry sessionAdapters = kBuiltinAgentSessionAdapters,
  AgentSteerSource steers = const NoAgentSteerSource(),
}) {
  final loader = PackagedAssetLoader();
  final rubricSource = rubrics ?? loader.rubricSource;
  final stationOverlayRoot = p.join(loader.root, 'station_overlay');
  final resolvedOverlaySourceRef =
      overlaySourceRef ?? resolveOverlaySourceRefSync(stationOverlayRoot);
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
        clearer: critiqueDirClearer,
      ),
      // ONE capability, three lens lanes (`params['lens']`) — the id is the
      // circuit's own, so a lens step reads `capabilityId: 'discovery'`.
      kDiscoveryCircuitId: const DiscoveryLensCapability(),
      kDiscoveryRouteStep: const DiscoveryRouteCapability(),
      // The spec stage + its committee lanes (bead `pow-6ao`; `specify` folded
      // into the spec circuit by `pow-ui8`).
      kSpecifyStep: specifyBdRunnerFor == null
          ? const SpecifyCapability()
          : SpecifyCapability(runnerFor: specifyBdRunnerFor),
      'spec-critic': SpecCriticCapability(rubrics: rubricSource),
      kSpecGatingRubric: const SpecValidationCapability(),
      // The SPEC committee's own route (bead `pow-7nm`) — the three-way
      // advance | RESPEC | escalate matrix. The code committee keeps the binary
      // `route` below; the two matrices are now independent (ADR-0000 A14,
      // which departs from A13(5)'s shared-route posture).
      'spec-route': const SpecRouteCapability(),
      'agent': AgentCapability(
        devRoot: devRoot,
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
      'route': const CodeRouteCapability(),
      'rebase': RebaseCapability(runner: gitRunner),
      'revalidate': RevalidateCapability(runner: shellRunner),
      kClearCritiqueStep: ClearCritiqueCapability(clearer: critiqueDirClearer),
      // The diff-pinning pre-critic step (bead `pow-6wo`) shares the `code`
      // registry's git seam ([gitRunner]) — the SAME recording fake `rebase`
      // rides offline; absent ⇒ the real [SystemGitRunner].
      kPinDiffStep: PinDiffCapability(runner: gitRunner),
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
