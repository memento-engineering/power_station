/// The_grid's opinion assets — the agent/verify/land [Capability] impls + the
/// `code` [Circuit] + the git [SourceControl] (ADR-0008 D2 / M4-P1 §6).
///
/// These are the OPINIONS the opinion-free engine (grid_engine) must not carry
/// (ADR-0007 §1): the coding agent it spawns (`claude`), the check it runs, the
/// PR it opens. A station runner wires them via [buildCodeRegistry] + a
/// `CircuitResolver` (RS-8 retired the transitional `CodeRunCommand` — the
/// resident composition is the only consumer now). The `power_station` home of
/// the first-party assets (extracted from the_grid at the repo split).
///
/// The v3 COMPOSITION ASSETS (Track F, `tg-5r9`, `composition_assets.dart`) are
/// how those opinions mount into the grid tree at a SCOPE — the replacement for
/// the runner-built `ServiceBundle` map: GitGridAssets plus a domain delivery
/// asset
/// (substation-scoped source control, over the ambient [GitServices] machinery
/// carrier the delegate mounts once), [HarnessProvider] (station-scoped harness
/// provision), [CircuitProvider] (the Q8 circuit provider/scope), and
/// [sourceControlOf] (bead → substation → root resolution, no string-keyed map).
///
/// The AGENT SCOPE's model resolution is ROLE → TIER → MODEL (beads `pow-edp`,
/// `pow-2c9`): a spawner declares its [AgentRole]; the role points at an
/// [AgentTier] ([tierFor] — build and architect ⇒ frontier, grade ⇒ mid,
/// gather ⇒ cheap); and the STATION arms tier → model ([AgentConfig.tiers], a
/// [ModelTiers] value — an unarmed tier rides [defaultModelForTier]:
/// [kFrontierModelDefault] `opus`, [kMidModelDefault] `sonnet`,
/// [kCheapModelDefault] `haiku`).
/// [resolveAgentConfig] resolves *bead `grid.agent` `params.model` > the
/// station's arming of the role's tier*, stamping the winner into the harness
/// transport key. So the committee grades cheap while the build runs strong, a
/// NEW role costs one `tierFor` case (never a new config field), and a retune is
/// one arming change. The resolved model is ALWAYS explicit — never the harness
/// CLI's own default (which silently fell back to fable when a weekly limit
/// blew) — and [UsageReport.model] captures the id(s) that ACTUALLY ran, so
/// `grid.result.<node>.model` proves it from the ledger (subsuming bead
/// `pow-efv`).
///
/// The COMPUTE asset domain (ADR-0011 D2/D3, M6 Track D) also lives here: the
/// `DispatchCommand`/`CommandResult` payloads + the bounded "use" + the capacity
/// predicate moved OUT of the kind-agnostic `grid_federation` core, and the
/// `LeaseCapability` wraps a federation lease as an engine [Capability]
/// (mount = acquire + dispatch, unmount = release).
///
/// The SEARCH domain (bead `pow-ovh`, the first coupled skill+command pair)
/// also lives here: deterministic, READ-ONLY (A37) cross-store search over the
/// station's attached substations. [mountedRosterOf] resolves the roster from
/// the resident-station context (the composing station's `GridDelegate` tree,
/// mounted offline), while [codedRosterOf] owns and disposes a fresh delegate
/// around that enumeration; [StationSearchService] queries each seat's `.beads/`
/// store (backlog + decision beads) through a read-only-by-construction seam;
/// [SearchCommand] is the THIN exported CLI adapter a station composes
/// (`space search <query>`) — the substrate agentic skills (`discover`) CALL
/// instead of reinventing search by inference.
/// Semantic vectors live in the grid-home-owned, derived
/// [DoltEmbeddingIndex] at `.grid/embeddings`; [DoltEmbeddingIndex.open]
/// provisions its `VECTOR(N)` width from [EmbeddingIndexIdentity], rejects a
/// provider/model/dimension mismatch before use, and is the sole storage API
/// shared by the indexing and semantic-read paths. It never writes a
/// substation work store or the resident tranquility store.
/// [IndexCommand] is the only embedding writer: it calls [EmbeddingClient]
/// before writing the grid-home-owned [DoltEmbeddingIndex]. [SearchCommand]
/// remains inference-free and write-free.
///
/// The FILING pair is the front-door completeness counterpart: [FilingService]
/// reads one bead through [ExactSubstationBeadSource], [FilingContract]
/// deterministically evaluates its four mechanical authoring requirements,
/// and [FilingCommand] is the thin CLI adapter the `discover` skill calls.
/// Description and acceptance usefulness remain with the agentic half.
///
/// The VENDED SKILLS (bead `pow-88p`, `extension/station_overlay/skills/`) are
/// those agentic halves: `discover` is the grid home's HITL front door — it
/// dispatches on arg shape (topic research / bead advisory / bead directed),
/// researches via the vended `search` Command, and on the human's yes files an
/// ephemeral staged bead and hands to `specify`. [kVendedSkills] enumerates
/// them; [PackagedAssetLoader.renderSkill] renders one by id.
///
/// The DELIVERY leg is [OverlayMaterializer]: the CLI-free lib that expands a
/// `station_overlay` tree onto a target ROOT, PATH-PRESERVING. The overlay is
/// ROOT-RELATIVE — its internal layout MIRRORS the target, so
/// `station_overlay/claude/skills/discover/SKILL.md` lands at
/// `<root>/.claude/skills/discover/SKILL.md` with no kind mapping anywhere: the
/// overlay AUTHOR decides where an asset lands by where it sits in the tree.
/// ONE root-parametric materializer, two callers, two roots — this package's OWN
/// provision-time wire ([AgentCapability], onto a per-bead WORKTREE root, so a
/// station-spawned `claude -p` can `/invoke` a vended skill; SCOPED to
/// [kClaudeSkillsSubtree], because a loose `.claude/settings.json` is repo-owned
/// territory) and the operator install Command (onto a STATION repo root, whole
/// tree). It renders each file, REFUSES to install one whose holes are unbound,
/// and NEVER clobbers a file it did not generate.
///
/// The OPERATOR leg of that delivery is [AssetsCommand] over
/// `src/assets/overlay_install.dart`: `<cli> assets install` resolves the
/// in-scope overlay roots NON-PRESCRIPTIVELY ([resolveStationOverlayRoots] —
/// `package:extension_discovery` over the grid home's package config; every pack
/// shipping the asset manifest AND a `station_overlay/` is in scope, none is
/// hardcoded), expands them onto a repo root ([OverlayInstallService]), and
/// prints the DIFF ([renderInstallReport]). It COMMITS NOTHING — the operator
/// reviews and commits. Each installed file carries a PROVENANCE stamp
/// (`overlay_provenance.dart`) naming the grid_assets ref it came from, which is
/// what lets the vended assets be COMMITTED rather than gitignored: the stamp
/// tells a generated file from a hand-authored one, and `assets install --check`
/// FAILS on any file that is missing or has drifted from source. [mountedValuesOf]
/// is the one offline delegate-mount walker both this leg (for the grid home) and
/// [mountedRosterOf] (for the substation roster) ride.
///
/// The SPEC-READINESS INTAKE LENS (bead `pow-q7n`, `src/code/readiness.dart`)
/// heads that spec circuit: a deterministic intake contract ([IntakeCapability]
/// — a driveable type + a real brief, ZERO agents) then ONE cheap agent grading
/// the BEAD ([ReadinessCriticCapability], the `bead-readiness` rubric) and a
/// decision point ([ReadinessRouteCapability]). A bead that is not spec-ready is
/// HELD for refinement BEFORE `specify` spawns, so a coarse brief never burns the
/// architect + the 4-critic committee — the ~18-agent round the 2026-07-11 wide
/// run spent discovering that at the committee.
///
/// The DISCOVERY circuit (`src/code/discovery.dart`) is the spec circuit's second
/// head, nested between that ladder and `specify` — a gather AND a gate. The
/// gather is deterministic ([AnchorsCapability], ZERO agents): the committee's own
/// grading rubrics, the bead's code anchors resolved against the worktree, and
/// prior art through the read-only [StationSearchService] the `search` Command
/// already vends. Three READ-ONLY explorers ([DiscoveryLensCapability]) then run
/// in parallel on the CHEAP tier — the [AgentRole.gather] role's first spawner —
/// and, because that role DECIDES NOTHING, a lens emits no letter: it emits a
/// [LensReport] of context notes and CITED violations. [DiscoveryRouteCapability]
/// makes the call, deterministically ([decideDiscovery]): a bead that contradicts
/// a ratified ADR or an applicable skill WITHOUT acknowledging the departure is
/// HELD with the offence CITED, so no architect and no committee ever runs on it;
/// a clean bead ADVANCES with a curated [DiscoveryDossier] that
/// [buildSpecifyBrief] renders — the architect specs against the rubrics it will
/// be graded by. The gate is CITE-THE-OFFENCE by construction ([gatesTheBead]): no
/// citation is a vibe and can never hold a bead, a DECLARED departure passes, and
/// a pattern deviation needs a NAMED precedent.
///
/// The DART domain (the typed `grid.dart` envelope + pub dev-time linkage +
/// `DartCommand`) lives in its sibling pack `dart_grid_assets`.
library;

export 'src/agent/acp_session_adapter.dart';
export 'src/agent/agent_session.dart';

export 'src/code/mount_eligibility.dart';

export 'src/agent/agent_domain.dart';
export 'src/agent/agent_environment.dart';
export 'src/agent/agent_harness.dart';
export 'src/agent/environment_registry.dart';
export 'src/agent/model_tier.dart';
export 'src/agent/path_check.dart';
export 'src/agent/site_binding.dart';
export 'src/agent/typed_environment.dart';
export 'src/agent/usage_report.dart';
export 'src/assets/asset_loader.dart';
export 'src/assets/assets_command.dart';
export 'src/assets/composition_assets.dart';
export 'src/assets/mounted_tree.dart';
export 'src/assets/overlay_install.dart';
export 'src/assets/overlay_manifest.dart';
export 'src/assets/overlay_materializer.dart';
export 'src/assets/overlay_provenance.dart';
export 'src/code/circuit_migration.dart';
export 'src/code/code_capabilities.dart';
export 'src/code/committee.dart';
export 'src/code/conventional_commit.dart';
export 'src/code/decision_register.dart';
export 'src/code/delivery.dart';
export 'src/code/discovery.dart';
export 'src/code/docs_committee.dart';
export 'src/code/landing.dart';
export 'src/code/pr_composition.dart';
export 'src/code/pr_describe.dart';
export 'src/code/readiness.dart';
export 'src/code/respec.dart';
export 'src/code/route_failure.dart';
export 'src/code/specify.dart';
export 'src/compute/bounded_use.dart';
export 'src/compute/compute_command.dart';
export 'src/compute/compute_commands.dart';
export 'src/compute/lease_capability.dart';
export 'src/filing/approval_stamp.dart';
export 'src/filing/approve_command.dart';
export 'src/filing/filing_command.dart';
export 'src/filing/filing_contract.dart';
export 'src/lease/bus_lease.dart';
export 'src/search/embedding_index.dart';
export 'src/search/embedding_change_key.dart';
export 'src/search/embedding_provider.dart';
export 'src/search/index_command.dart';
export 'src/search/search_recall.dart';
export 'src/search/search_command.dart';
export 'src/search/semantic_search.dart';
export 'src/search/station_index.dart';
export 'src/search/station_search.dart';
