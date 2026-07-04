// Proof of the versioned method/topic surface (D-B3): presence retained+LWT
// helpers, initialize-time capability negotiation (accept/refuse), and the
// claim topic layout.
import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('BusTopics', () {
    test('claimUnclaimed is scoped under the wildcard-matchable prefix', () {
      expect(BusTopics.claimUnclaimed('abc'), 'grid/claim/unclaimed/abc');
      expect(
        topicMatches(BusTopics.claimUnclaimedAll, BusTopics.claimUnclaimed('abc')),
        isTrue,
      );
    });
  });

  group('presence: retained online + will offline (D-B1)', () {
    test('presenceOnline encodes an online notification carrying the '
        'Presence profile verbatim', () {
      const presence = Presence(
        station: 'studio',
        kinds: ['compute'],
        offered: 2,
        available: 1,
        profile: {'system-os': 'macos'},
      );
      final decoded = decodeAcp(presenceOnline(presence)) as AcpNotification;
      expect(decoded.method, BusMethods.presence);
      expect(decoded.params['station'], 'studio');
      expect(decoded.params['online'], isTrue);
      expect(decoded.params['profile'], {'system-os': 'macos'});
    });

    test('presenceWill targets the SAME topic, transitioning to offline', () {
      final will = presenceWill('studio');
      expect(will.topic, BusTopics.presence);
      final decoded = decodeAcp(will.payload) as AcpNotification;
      expect(decoded.method, BusMethods.presence);
      expect(decoded.params['station'], 'studio');
      expect(decoded.params['online'], isFalse);
    });

    test(
      'wired through a real broker: subscriber sees online then, on '
      'close, the will (offline) retained',
      () async {
        const presence = Presence(
          station: 'studio',
          kinds: ['compute'],
          offered: 1,
          available: 1,
        );
        final broker = InMemoryBroker(
          station: 'studio',
          will: presenceWill('studio'),
        );
        broker.publish(BusTopics.presence, presenceOnline(presence), retain: true);

        final events = <bool>[];
        final sub = broker.subscribe(BusTopics.presence).listen((m) {
          final note = decodeAcp(m.payload) as AcpNotification;
          events.add(note.params['online'] as bool);
        });
        await broker.close();
        expect(events, [true, false]);
        await sub.cancel();
      },
    );
  });

  group('initialize-time capability negotiation', () {
    test('a matching protocol version is accepted', () {
      final result = negotiate(
        'b',
        const InitializeParams(station: 'a'),
      );
      expect(result.accepted, isTrue);
      expect(result.station, 'b');
      expect(result.protocolVersion, kBusProtocolVersion);
    });

    test('a mismatched protocol version is refused (fail-closed)', () {
      final result = negotiate(
        'b',
        const InitializeParams(station: 'a', protocolVersion: 999),
      );
      expect(result.accepted, isFalse);
    });

    test('InitializeParams/InitializeResult round-trip through JSON', () {
      const params = InitializeParams(
        station: 'a',
        capabilities: {'claim', 'presence'},
      );
      final decodedParams = InitializeParams.fromJson(params.toJson());
      expect(decodedParams.station, 'a');
      expect(decodedParams.protocolVersion, kBusProtocolVersion);
      expect(decodedParams.capabilities, {'claim', 'presence'});

      const result = InitializeResult(station: 'b', accepted: true);
      final decodedResult = InitializeResult.fromJson(result.toJson());
      expect(decodedResult.station, 'b');
      expect(decodedResult.accepted, isTrue);
    });

    test('carried as an AcpRequest/AcpResultResponse pair over the envelope', () {
      const params = InitializeParams(station: 'a');
      final req = AcpRequest(
        id: 'init-1',
        method: BusMethods.initialize,
        params: params.toJson(),
      );
      final decodedReq = decodeAcp(encodeAcp(req)) as AcpRequest;
      expect(decodedReq.method, BusMethods.initialize);
      final reParsed = InitializeParams.fromJson(decodedReq.params);
      expect(reParsed.station, 'a');

      final result = negotiate('b', reParsed);
      final resp = AcpResultResponse(id: req.id, result: result.toJson());
      final decodedResp = decodeAcp(encodeAcp(resp)) as AcpResultResponse;
      expect(decodedResp.id, 'init-1');
      expect(InitializeResult.fromJson(decodedResp.result).accepted, isTrue);
    });
  });
}
