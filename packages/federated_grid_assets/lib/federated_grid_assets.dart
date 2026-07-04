/// Cross-station federation: resource leasing over a pluggable bus (ADR-0011).
///
/// The TRANSPORT-FREE contracts — [Presence]/[LeaseRequest]/[LeaseGrant]/the
/// `Federation*Exception`s, the [StationClient] bus-seam interface, and the
/// [CapabilityFacts] model (+ [CapabilityProbe]/[CapabilityRevalidator]) — live
/// in `grid_engine`'s SDK (the honesty-pass D-A9/D-B5 split, 2026-07-03: "the
/// engine knows federation in CONCEPT, not detail") and are re-exported here so
/// every existing consumer keeps compiling. This package is IMPLS-ONLY over
/// those types, moved out of the_grid's `grid_federation` (AL-5b, D-A9): it
/// dissolved into the_grid's engine contracts + this power_station pack.
///
/// A station OFFERS capacity ([StationServer]); a peer LEASES a slot
/// ([StationClient]/[HttpStationClient]) and dispatches an OPAQUE payload (what
/// it means + what "use" runs is defined by the asset domain that owns the kind,
/// shipped in `grid_assets`), collecting a result. Capacity is
/// arbitrated by the owner-authoritative [LeaseManager], which bakes in the
/// ADR-0011 hazards: a monotonic fencing token, a max lease lifetime + a FIFO
/// wait-queue, owner-clock reaping, and request idempotency. HTTP is impl #1 of
/// the kind-agnostic bus seam; MQTT/WS drop in behind [StationClient] later.
///
/// Membership is **static** ([Membership]/[Peer]/[MembershipLoader], ADR-0011
/// D4): a station declares its peers in config; discovery is a later asset
/// (`zero_conf_grid_assets`). [Presence] carries the gossip split — the durable
/// capability profile + the ephemeral capacity — and a lessee
/// [StationClient.heartbeat]s so the owner reaps a disconnected lease by its own
/// clock (a missed-heartbeat threshold).
///
/// SYNC is a SEPARATE channel from the lease bus (ADR-0011 D7): [GitSyncService]
/// distributes code/assets to a peer's bare repo over a git remote
/// ([GitSyncService.ensureRemote]/[GitSyncService.push]/[GitSyncService.distribute]),
/// SSH for real and a local file-path remote offline. The bus carries
/// coordination; git carries the code.
///
/// [ServeCommand]/[LeaseCommand] are the asset-exported CLI Commands (the
/// CLI-SDK model): a station runner composes them alongside its own domain
/// Commands (`..addCommand(ServeCommand(...))`) — moved out of `grid_cli`
/// because the seam stays core (the engine SDK), the Commands are asset surface.
///
/// **The bus** (AL-6b, `docs/SCRATCH-grid-alignment.md` D-B1/D-B2/D-B3,
/// 2026-07-03) — layered ABOVE the lease bus above, for the D-A3 claim flow
/// (whatever is unclaimed locally at the end of a reconciliation phase gets
/// broadcast for pickup): [Broker] is the abstract, single-writer
/// publish-own seam (`src/broker/broker.dart`'s doc records the pub.dev vet —
/// none adequate), [InMemoryBroker] its offline discharge. The wire envelope
/// (`src/protocol/`) is ACP-shaped (agentclientprotocol.com's JSON-RPC 2.0 +
/// method namespacing — NOT MCP): [AcpRequest]/[AcpNotification]/
/// [AcpResultResponse]/[AcpErrorResponse] over [BusMethods]/[BusTopics].
/// [ClaimBroadcaster] is the claim's OWNER role (consumes `grid_engine`'s
/// AL-6a `onUnclaimedFrontier` hook, arbitrates, confirms, and IS
/// `DefaultCapabilityRegistry`'s `claimCapabilityFor`); [ClaimResponder] is
/// the PEER role (evaluates an advertisement by [CapabilityFacts] containment,
/// responds). [ClaimLeaseCapability] is the confirmed claim's dispatch — a
/// kind-agnostic [LeaseCapability] over the SAME lease bus above ("claim →
/// lease is two-phase," D-A4).
library;

export 'package:grid_engine/grid_engine.dart'
    show
        CapabilityFacts,
        CapabilityProbe,
        CapabilityRevalidator,
        FakeProbe,
        FederationException,
        LeaseDeniedException,
        LeaseGrant,
        LeaseInvalidException,
        LeaseRequest,
        Presence,
        RevalidationResult,
        StationClient,
        ToolchainProbe,
        ToolchainQuery,
        kDartTarget,
        kDefaultKind,
        kFlutterTarget,
        kRadio,
        kSetFactKeys,
        kSystemOs,
        kTargetChain,
        parseToolchainOs;

export 'src/broker/broker.dart';
export 'src/broker/in_memory_broker.dart';
export 'src/claim/claim_broadcaster.dart';
export 'src/claim/claim_lease_capability.dart';
export 'src/claim/claim_responder.dart';
export 'src/claim/claim_types.dart';
export 'src/git_sync.dart';
export 'src/lease_command.dart';
export 'src/lease_manager.dart';
export 'src/membership.dart';
export 'src/protocol/acp_envelope.dart';
export 'src/protocol/bus_protocol.dart';
export 'src/serve_command.dart';
export 'src/station_client.dart';
export 'src/station_server.dart';
