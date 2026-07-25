// End-to-end proof of the D-A3/D-B1/D-B3 claim flow — wholly offline over two
// InMemoryBrokers (no sockets, no live network): broadcast-unclaimed (retained
// notification) → a fulfillable peer responds (request) → deterministic
// arbitration + confirm (response, correlated by id across the two brokers) →
// the owner's claimCapabilityFor resolves the confirmed peer. Mirrors the
// whiteboard sequence in docs/SCRATCH-grid-alignment.md §1 (studio.local /
// dashboard.local, Req macOS+BLE / Req Linux+BLE).
import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _linuxBle = CapabilityFacts(
  sets: {
    kSystemOs: {'linux'},
    kRadio: {'ble'},
  },
);

const _macosOnly = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
  },
);

UnclaimedRequirement _burnFollowerReq({
  String workBeadId = 'tg-burn',
  String sessionId = 'tgdog-s',
  String stepId = 'follower',
}) => UnclaimedRequirement(
  sessionId: sessionId,
  workBeadId: workBeadId,
  step: UnclaimedStep(
    nodePath: '$workBeadId/$stepId',
    stepId: stepId,
    capabilityId: 'burn-follower',
    requires: _linuxBle,
  ),
);

StepMount _mountFor(UnclaimedStep step) {
  final capabilityStep = CapabilityStep(
    stepId: step.stepId,
    capabilityId: step.capabilityId,
    params: const {'target': 'linux'},
    requires: step.requires,
  );
  return StepMount(
    step: capabilityStep,
    nodePath: step.nodePath,
    // A step always belongs to a circuit: the engine threads the member circuit
    // (+ its path) through the mount so a route can resolve a `Rewind`'s named
    // siblings, and so the host can tell whether an advance is the ROOT
    // circuit's DELIVERY TERMINAL. A claim step is the whole graph here.
    circuit: Circuit(
      id: 'claim',
      terminalStepId: step.stepId,
      steps: [capabilityStep],
    ),
    circuitPath: step.nodePath.substring(0, step.nodePath.lastIndexOf('/')),
    session: const SessionHandle('tgdog-s'),
    node: const NodeCursor(),
    key: ValueKey('${step.nodePath}#0'),
  );
}

Future<void> _settle() async {
  // Flushes the microtask chain a claim round-trip drives (ad delivery →
  // respond publish → confirm delivery) — every hop in this protocol is
  // synchronous callback code over StreamControllers, so one macrotask tick
  // drains the whole chain.
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('the claim flow (offline, two InMemoryBrokers)', () {
    test('a fulfillable peer is confirmed; claimCapabilityFor resolves it; the '
        'retained ad is cleared', () async {
      final studio = InMemoryBroker(station: 'studio');
      final dashboard = InMemoryBroker(station: 'dashboard');
      addTearDown(studio.close);
      addTearDown(dashboard.close);

      final owner = ClaimBroadcaster(broker: studio, onLog: (_) {});
      owner.listenToPeer('dashboard', dashboard);

      final confirmations = <(String, bool)>[];
      final responder = ClaimResponder(
        broker: dashboard,
        station: 'dashboard',
        stationFacts: _linuxBle,
        myAddress: const Peer(id: 'dashboard', host: '10.0.0.2', port: 8080),
        onConfirmed: (claimId, confirmed) =>
            confirmations.add((claimId, confirmed)),
      );
      responder.listenToBroadcaster('studio', studio);

      final req = _burnFollowerReq();
      final claimId = claimIdFor(req);

      // Before the broadcast: nothing to resolve.
      expect(owner.claimCapabilityFor(_mountFor(req.step)), isNull);

      owner.onUnclaimedFrontier([req]);
      await _settle();

      expect(confirmations, [(claimId, true)]);
      expect(owner.confirmed.keys, [claimId]);
      expect(owner.pending, isEmpty);

      final cap = owner.claimCapabilityFor(_mountFor(req.step));
      expect(cap, isA<ClaimLeaseCapability>());
      final claimCap = cap! as ClaimLeaseCapability;
      expect(claimCap.kind, 'burn-follower'); // kind == capabilityId
      expect(claimCap.capabilityId, 'burn-follower');
      expect(claimCap.client, isA<HttpStationClient>());
      final http = claimCap.client as HttpStationClient;
      expect(http.host, '10.0.0.2');
      expect(http.port, 8080);

      // The retained ad was cleared EAGERLY at confirm time — a fresh
      // subscriber sees nothing.
      final late = <String>[];
      final sub = studio
          .subscribe(BusTopics.claimUnclaimed(claimId))
          .listen((m) => late.add(m.topic));
      await _settle();
      expect(late, isEmpty);
      await sub.cancel();

      await owner.dispose();
      await responder.dispose();
    });

    test('an UNFULFILLABLE peer (CapabilityFacts mismatch) never responds — '
        'the requirement stays pending', () async {
      final studio = InMemoryBroker(station: 'studio');
      final dashboard = InMemoryBroker(station: 'dashboard');
      addTearDown(studio.close);
      addTearDown(dashboard.close);

      final owner = ClaimBroadcaster(broker: studio);
      owner.listenToPeer('dashboard', dashboard);
      final responder = ClaimResponder(
        broker: dashboard,
        station: 'dashboard',
        stationFacts: _macosOnly, // does NOT satisfy linux+ble
        myAddress: const Peer(id: 'dashboard', host: '10.0.0.2', port: 8080),
      );
      responder.listenToBroadcaster('studio', studio);

      final req = _burnFollowerReq();
      owner.onUnclaimedFrontier([req]);
      await _settle();

      expect(owner.confirmed, isEmpty);
      expect(owner.pending, [claimIdFor(req)]);
      expect(owner.claimCapabilityFor(_mountFor(req.step)), isNull);

      await owner.dispose();
      await responder.dispose();
    });

    test('deterministic arbitration: the FIRST responder wins; a later '
        'responder for the SAME claim is denied', () async {
      final studio = InMemoryBroker(station: 'studio');
      final dashboardA = InMemoryBroker(station: 'dashboard-a');
      final dashboardB = InMemoryBroker(station: 'dashboard-b');
      addTearDown(studio.close);
      addTearDown(dashboardA.close);
      addTearDown(dashboardB.close);

      final owner = ClaimBroadcaster(broker: studio);
      owner.listenToPeer('dashboard-a', dashboardA);
      owner.listenToPeer('dashboard-b', dashboardB);

      final resultsA = <bool>[];
      final resultsB = <bool>[];
      final responderA = ClaimResponder(
        broker: dashboardA,
        station: 'dashboard-a',
        stationFacts: _linuxBle,
        myAddress: const Peer(id: 'dashboard-a', host: '10.0.0.2', port: 1),
        onConfirmed: (_, confirmed) => resultsA.add(confirmed),
      )..listenToBroadcaster('studio', studio);
      final responderB = ClaimResponder(
        broker: dashboardB,
        station: 'dashboard-b',
        stationFacts: _linuxBle,
        myAddress: const Peer(id: 'dashboard-b', host: '10.0.0.3', port: 2),
        onConfirmed: (_, confirmed) => resultsB.add(confirmed),
      )..listenToBroadcaster('studio', studio);

      final req = _burnFollowerReq();
      owner.onUnclaimedFrontier([req]);
      await _settle();

      // Exactly one of the two won — never both, never neither.
      final winners = [
        if (resultsA.contains(true)) 'a',
        if (resultsB.contains(true)) 'b',
      ];
      expect(winners, hasLength(1));
      expect(resultsA.contains(false) || resultsA.contains(true), isTrue);
      expect(resultsB.contains(false) || resultsB.contains(true), isTrue);
      expect(owner.confirmed, hasLength(1));

      await owner.dispose();
      await responderA.dispose();
      await responderB.dispose();
    });

    test('a requirement that disappears (locally satisfied elsewhere) is '
        'RETRACTED — the retained ad clears', () async {
      final studio = InMemoryBroker(station: 'studio');
      addTearDown(studio.close);
      final owner = ClaimBroadcaster(broker: studio);

      final req = _burnFollowerReq();
      owner.onUnclaimedFrontier([req]);
      expect(owner.pending, [claimIdFor(req)]);

      owner.onUnclaimedFrontier(const []); // no longer unclaimed
      expect(owner.pending, isEmpty);

      final late = <String>[];
      final sub = studio
          .subscribe(BusTopics.claimUnclaimed(claimIdFor(req)))
          .listen((m) => late.add(m.topic));
      await _settle();
      expect(late, isEmpty);
      await sub.cancel();
    });

    test('the SAME still-unclaimed requirement is never re-broadcast on a '
        'later scan (no retained churn)', () async {
      final studio = InMemoryBroker(station: 'studio');
      addTearDown(studio.close);
      final owner = ClaimBroadcaster(broker: studio);

      final publishes = <String>[];
      final sub = studio
          .subscribe(BusTopics.claimUnclaimedAll)
          .listen((m) => publishes.add(m.topic));

      final req = _burnFollowerReq();
      owner.onUnclaimedFrontier([req]);
      owner.onUnclaimedFrontier([req]); // the SAME requirement, next scan
      await _settle();

      expect(publishes, [BusTopics.claimUnclaimed(claimIdFor(req))]);
      await sub.cancel();
    });
  });
}
