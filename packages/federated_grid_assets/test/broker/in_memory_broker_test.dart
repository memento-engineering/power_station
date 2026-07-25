// Proof of the D-B2 shield's offline discharge: retained-topic map + wildcard
// subscriber fan-out + a will fired on close (presence = broker liveness + LWT,
// D-B1) — everything the claim protocol above this file needs, all in-process
// (no sockets, no bytes on a wire).
import 'dart:convert';
import 'dart:typed_data';

import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _text(Uint8List b) => utf8.decode(b);

void main() {
  group('InMemoryBroker', () {
    test('a live publish is delivered to a matching subscriber', () async {
      final broker = InMemoryBroker(station: 'a');
      final sub = broker.subscribe('grid/presence');
      final first = sub.first;

      broker.publish('grid/presence', _bytes('online'));
      final msg = await first;
      expect(_text(msg.payload), 'online');
      expect(msg.retained, isFalse);
      await broker.close();
    });

    test('a publish to a non-matching topic is not delivered', () async {
      final broker = InMemoryBroker(station: 'a');
      final events = <String>[];
      final sub = broker
          .subscribe('grid/presence')
          .listen((m) => events.add(_text(m.payload)));
      broker.publish('grid/claim/unclaimed/x', _bytes('nope'));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
      await broker.close();
    });

    test(
      'wildcard subscription (+ and #) receives matching publishes',
      () async {
        final broker = InMemoryBroker(station: 'a');
        final events = <String>[];
        final sub = broker
            .subscribe('grid/claim/#')
            .listen((m) => events.add(m.topic));
        broker.publish('grid/claim/unclaimed/x', _bytes('1'));
        broker.publish('grid/claim/respond', _bytes('2'));
        broker.publish('grid/presence', _bytes('ignored'));
        await Future<void>.delayed(Duration.zero);
        expect(events, ['grid/claim/unclaimed/x', 'grid/claim/respond']);
        await sub.cancel();
        await broker.close();
      },
    );

    test(
      'a retained publish is replayed IMMEDIATELY to a NEW subscriber',
      () async {
        final broker = InMemoryBroker(station: 'a');
        broker.publish('grid/presence', _bytes('online'), retain: true);

        // Subscribing AFTER the publish still gets it — the whole point of
        // "advertisement = retained" (D-B1).
        final msg = await broker.subscribe('grid/presence').first;
        expect(_text(msg.payload), 'online');
        expect(msg.retained, isTrue);
        await broker.close();
      },
    );

    test(
      'an EMPTY retained publish clears the retained store for that topic',
      () async {
        final broker = InMemoryBroker(station: 'a');
        broker.publish('grid/claim/unclaimed/x', _bytes('ad'), retain: true);
        broker.publish(
          'grid/claim/unclaimed/x',
          Uint8List(0),
          retain: true,
        ); // retraction

        final events = <String>[];
        final sub = broker
            .subscribe('grid/claim/unclaimed/x')
            .listen((m) => events.add(_text(m.payload)));
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty); // nothing retained to replay
        await sub.cancel();
        await broker.close();
      },
    );

    test('retained replay happens BEFORE any live publish ordering', () async {
      final broker = InMemoryBroker(station: 'a');
      broker.publish('grid/presence', _bytes('online'), retain: true);

      final events = <String>[];
      final sub = broker
          .subscribe('grid/presence')
          .listen((m) => events.add('${m.retained}:${_text(m.payload)}'));
      broker.publish('grid/presence', _bytes('update'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['true:online', 'false:update']);
      await sub.cancel();
      await broker.close();
    });

    test(
      'multiple subscribers each get their own independent fan-out',
      () async {
        final broker = InMemoryBroker(station: 'a');
        final e1 = <String>[];
        final e2 = <String>[];
        final s1 = broker.subscribe('grid/#').listen((m) => e1.add(m.topic));
        final s2 = broker
            .subscribe('grid/presence')
            .listen((m) => e2.add(m.topic));
        broker.publish('grid/presence', _bytes('x'));
        broker.publish('grid/claim/unclaimed/y', _bytes('y'));
        await Future<void>.delayed(Duration.zero);
        expect(e1, ['grid/presence', 'grid/claim/unclaimed/y']);
        expect(e2, ['grid/presence']);
        await s1.cancel();
        await s2.cancel();
        await broker.close();
      },
    );

    test('cancelling a subscription stops further delivery', () async {
      final broker = InMemoryBroker(station: 'a');
      final events = <String>[];
      final sub = broker
          .subscribe('grid/presence')
          .listen((m) => events.add(_text(m.payload)));
      broker.publish('grid/presence', _bytes('1'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      broker.publish('grid/presence', _bytes('2'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['1']);
      await broker.close();
    });

    group('presence = broker liveness + LWT (D-B1)', () {
      test('a GRACEFUL close publishes the registered will (retained) as an '
          'explicit goodbye', () async {
        final broker = InMemoryBroker(
          station: 'a',
          will: LastWill(topic: 'grid/presence', payload: _bytes('offline')),
        );
        final events = <String>[];
        final sub = broker
            .subscribe('grid/presence')
            .listen((m) => events.add(_text(m.payload)));
        await broker.close();
        expect(events, ['offline']);
        await sub.cancel();
      });

      test(
        'a late subscriber sees the will retained AFTER a graceful close',
        () async {
          final broker = InMemoryBroker(
            station: 'a',
            will: LastWill(topic: 'grid/presence', payload: _bytes('offline')),
          );
          await broker.close();
          // Subscribing to an already-closed broker still replays the LAST
          // retained value synchronously (the map itself outlives `_closed`).
          final msg = await broker.subscribe('grid/presence').first;
          expect(_text(msg.payload), 'offline');
        },
      );

      test('simulateCrash does NOT publish the will — only the stream ends '
          '(the honest disconnect signal, no zombie retained ad)', () async {
        final broker = InMemoryBroker(
          station: 'a',
          will: LastWill(topic: 'grid/presence', payload: _bytes('offline')),
        );
        broker.publish('grid/presence', _bytes('online'), retain: true);
        final events = <String>[];
        var done = false;
        broker
            .subscribe('grid/presence')
            .listen(
              (m) => events.add(_text(m.payload)),
              onDone: () => done = true,
            );
        await broker.simulateCrash();
        expect(events, ['online']); // only the retained replay — no will
        expect(done, isTrue); // the stream itself ended
      });
    });

    test('publish after close is a silent no-op', () async {
      final broker = InMemoryBroker(station: 'a');
      final events = <String>[];
      broker.subscribe('grid/presence').listen((m) => events.add(m.topic));
      await broker.close();
      broker.publish('grid/presence', _bytes('x'));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ping throws after close', () async {
      final broker = InMemoryBroker(station: 'a');
      await broker.ping(); // fine while live
      await broker.close();
      await expectLater(broker.ping(), throwsA(isA<StateError>()));
    });

    test('close is idempotent', () async {
      final broker = InMemoryBroker(
        station: 'a',
        will: LastWill(topic: 'grid/presence', payload: _bytes('offline')),
      );
      var deliveries = 0;
      broker.subscribe('grid/presence').listen((_) => deliveries++);
      await broker.close();
      await broker.close(); // a second close does not re-fire the will
      expect(deliveries, 1);
    });
  });
}
