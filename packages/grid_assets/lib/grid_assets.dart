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
/// the runner-built `ServiceBundle` map: [GitGridAssets] / [GitHubGridAssets]
/// (substation-scoped source control, over the ambient [GitServices] machinery
/// carrier the delegate mounts once), [HarnessProvider] (station-scoped harness
/// provision), [CircuitProvider] (the Q8 circuit provider/scope), and
/// [sourceControlOf] (bead → substation → root resolution, no string-keyed map).
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
/// mounted offline); [StationSearchService] queries each seat's `.beads/`
/// store (backlog + decision beads) through a read-only-by-construction seam;
/// [SearchCommand] is the THIN exported CLI adapter a station composes
/// (`space search <query>`) — the substrate agentic skills (`discover`) CALL
/// instead of reinventing search by inference.
///
/// The VENDED SKILLS (bead `pow-88p`, `extension/skills/`) are those agentic
/// halves: `discover` is the grid home's HITL front door — it dispatches on
/// arg shape (topic research / bead advisory / bead directed), researches via
/// the vended `search` Command, and on the human's yes files an ephemeral
/// staged bead and hands to `specify`. [kVendedSkills] enumerates them;
/// [PackagedAssetLoader.renderSkill] renders one for a composing station
/// (delivery leg: `pow-kzx`).
///
/// The DART domain (the typed `grid.dart` envelope + pub dev-time linkage +
/// `DartCommand`) lives in its sibling pack `dart_grid_assets`.
library;

export 'src/agent/agent_domain.dart';
export 'src/agent/agent_harness.dart';
export 'src/agent/usage_report.dart';
export 'src/assets/asset_loader.dart';
export 'src/assets/composition_assets.dart';
export 'src/code/code_capabilities.dart';
export 'src/code/committee.dart';
export 'src/code/landing.dart';
export 'src/code/respec.dart';
export 'src/code/specify.dart';
export 'src/compute/bounded_use.dart';
export 'src/compute/compute_command.dart';
export 'src/compute/lease_capability.dart';
export 'src/lease/bus_lease.dart';
export 'src/search/search_command.dart';
export 'src/search/station_search.dart';
