/// The_grid's opinion assets — the agent/verify/land [Capability] impls + the
/// `code` [Circuit] + the git [SourceControl] (ADR-0008 D2 / M4-P1 §6).
///
/// These are the OPINIONS the opinion-free engine (grid_engine) must not carry
/// (ADR-0007 §1): the coding agent it spawns (`claude`), the check it runs, the
/// PR it opens. A station runner wires them via [buildCodeRegistry] + a
/// `CircuitResolver` — or just assembles the asset's exported [CodeRunCommand]
/// (the CLI-SDK model: an asset's offering = {domain components + CLI
/// components}). The `power_station` home of the first-party assets (extracted
/// from the_grid at the repo split).
///
/// The COMPUTE asset domain (ADR-0011 D2/D3, M6 Track D) also lives here: the
/// `DispatchCommand`/`CommandResult` payloads + the bounded "use" + the capacity
/// predicate moved OUT of the kind-agnostic `grid_federation` core, and the
/// `LeaseCapability` wraps a federation lease as an engine [Capability]
/// (mount = acquire + dispatch, unmount = release).
///
/// The DART domain (the typed `grid.dart` envelope + pub dev-time linkage +
/// `DartCommand`) lives in its sibling pack `dart_grid_assets`.
library;

export 'src/agent/agent_domain.dart';
export 'src/agent/agent_harness.dart';
export 'src/agent/usage_report.dart';
export 'src/assets/asset_loader.dart';
export 'src/code/code_capabilities.dart';
export 'src/code/code_run_command.dart';
export 'src/code/committee.dart';
export 'src/compute/bounded_use.dart';
export 'src/compute/compute_command.dart';
export 'src/compute/lease_capability.dart';
export 'src/lease/bus_lease.dart';
