/// The OFFLINE discharge of the [Broker] seam (D-B2) — a single-process
/// pub/sub simulating exactly what a real single-writer broker does: a
/// retained-topic map + subscriber fan-out + a will fired on [close]. Every
/// unit test in this package (and the claim protocol above it) proves its
/// behavior against this impl — "no live network in tests." A real wire
/// transport (a TCP MQTT-shaped listener) is a follow-up behind the SAME
/// [Broker] seam; nothing above it changes.
library;

import 'dart:async';
import 'dart:typed_data';

import 'broker.dart';

class _Retained {
  const _Retained(this.payload, this.qos);
  final Uint8List payload;
  final int qos;
}

class _Sub {
  _Sub(this.filter, this.controller);
  final String filter;
  final StreamController<BrokerMessage> controller;
}

/// An in-process [Broker]: no sockets, no bytes on a wire — just topic
/// matching, a retained-message store, and stream fan-out, so the whole claim
/// protocol is provable without a live network.
class InMemoryBroker implements Broker {
  /// Creates this station's own broker. [will], if set, is published
  /// (retained) on [close] — see the library doc on [Broker] for why that is
  /// the presence mechanism.
  InMemoryBroker({required this.station, this.will});

  @override
  final String station;

  /// The registered last-will — published on a graceful [close], never on
  /// [simulateCrash] (see its doc).
  final LastWill? will;

  final Map<String, _Retained> _retained = {};
  final List<_Sub> _subs = [];
  bool _closed = false;

  /// Whether this broker has been torn down ([close] or [simulateCrash]).
  bool get isClosed => _closed;

  @override
  void publish(
    String topic,
    Uint8List payload, {
    bool retain = false,
    int qos = 0,
  }) {
    if (_closed) return; // a torn-down broker accepts no further writes
    if (retain) {
      if (payload.isEmpty) {
        _retained.remove(topic); // empty + retain clears (MQTT convention)
      } else {
        _retained[topic] = _Retained(payload, qos);
      }
    }
    final msg = BrokerMessage(topic: topic, payload: payload, qos: qos);
    // Snapshot: a subscriber's own handler may (un)subscribe reentrantly.
    for (final s in List<_Sub>.of(_subs)) {
      if (topicMatches(s.filter, topic)) s.controller.add(msg);
    }
  }

  @override
  Stream<BrokerMessage> subscribe(String topicFilter) {
    late final _Sub sub;
    final controller = StreamController<BrokerMessage>(
      onCancel: () => _subs.remove(sub),
    );
    sub = _Sub(topicFilter, controller);
    // Replay retained matches BEFORE registering for live traffic — both are
    // synchronous `add()`s queued on the (not-yet-listened) controller, so
    // they are delivered to whoever listens in this exact order: retained
    // catch-up first, then anything published after this call.
    for (final e in _retained.entries) {
      if (topicMatches(topicFilter, e.key)) {
        controller.add(
          BrokerMessage(
            topic: e.key,
            payload: e.value.payload,
            qos: e.value.qos,
            retained: true,
          ),
        );
      }
    }
    _subs.add(sub);
    return controller.stream;
  }

  @override
  Future<void> ping() async {
    if (_closed) throw StateError('ping against a closed broker ($station)');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    final w = will;
    if (w != null) {
      // The explicit goodbye — published (retained) BEFORE teardown so every
      // current subscriber (and any later one, via the retained store) sees
      // the honest "offline" transition.
      publish(w.topic, w.payload, retain: true, qos: w.qos);
    }
    _closed = true;
    for (final s in List<_Sub>.of(_subs)) {
      await s.controller.close();
    }
    _subs.clear();
  }

  /// TEST-ONLY: models an ABRUPT crash — this broker dies WITHOUT publishing
  /// its will (unlike [close]), so a subscriber observes only its stream
  /// ending, never an explicit "offline" message. That is the honest signal a
  /// real in-process, non-graceful death gives (D-B1): nothing else could fire
  /// the will on this station's behalf, so this impl does not pretend
  /// otherwise.
  Future<void> simulateCrash() async {
    if (_closed) return;
    _closed = true;
    for (final s in List<_Sub>.of(_subs)) {
      await s.controller.close();
    }
    _subs.clear();
  }
}
