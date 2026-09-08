// Pure-logic proof of the owner-authoritative [LeaseManager] — the four ADR-0011
// hazard bake-ins, tested with an injected clock + id generator, no IO:
//   1. fencing (monotonic token; stale token refused; reap+reissue bumps it)
//   2. max-lifetime + a FIFO wait-queue (starvation bound)
//   3. owner-clock reaping (no cross-machine time math)
//   4. request idempotency (a dup key → a single grant)
//
// Plus the manager's OWN schedule: it arms one timer at its earliest deadline
// and pumps itself, so an idle station still reaps and still denies an overdue
// waiter with no other traffic. The timer factory is injected beside the clock,
// so those deadlines are driven here rather than by wall-time.
import 'dart:async';

import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

/// A controllable owner clock.
class _Clock {
  DateTime now = DateTime.utc(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// A fake one-shot [Timer]: the manager's own scheduling, driven by the test.
/// [deadline] is the owner-clock instant it was armed for.
class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.deadline, this._callback);

  final Duration delay;
  final DateTime deadline;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  /// Fires the callback ONCE — inactive first, so the manager re-arming from
  /// inside the callback is never mistaken for this timer still being live.
  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

/// Hands out [_ManualTimer]s against the same fake clock the manager reads, and
/// records every one so a test can see how the manager re-arms.
class _ManualTimerFactory {
  _ManualTimerFactory(this._clock);

  final _Clock _clock;

  /// Every timer handed out, in creation order (cancelled ones included).
  final List<_ManualTimer> created = [];

  Timer call(Duration delay, void Function() callback) {
    final t = _ManualTimer(delay, _clock.now.add(delay), callback);
    created.add(t);
    return t;
  }

  /// The timers still armed — never more than one, if the manager holds its
  /// one-pending-timer invariant.
  List<_ManualTimer> get live =>
      created.where((t) => t.isActive).toList(growable: false);

  /// Advances the clock to the earliest armed deadline and fires that timer:
  /// the manager waking ITSELF up, with no other call made on it.
  void fireNext() {
    final armed = live;
    if (armed.isEmpty) throw StateError('no timer is armed');
    final next = armed.reduce(
      (a, b) => b.deadline.isBefore(a.deadline) ? b : a,
    );
    if (next.deadline.isAfter(_clock.now)) _clock.now = next.deadline;
    next.fire();
  }
}

/// A denial carrying exactly [message].
Matcher _deniedWith(String message) => throwsA(
  isA<LeaseDeniedException>().having((e) => e.message, 'message', message),
);

/// A kind-agnostic dispatch handler — the bus only ever sees opaque maps.
Future<Map<String, dynamic>> _echoHandler(Map<String, dynamic> payload) async =>
    {'echo': payload};

LeaseManager _manager(
  _Clock clock, {
  int offered = 1,
  Duration ttl = const Duration(seconds: 300),
  Duration maxLifetime = const Duration(seconds: 3600),
  int maxQueueDepth = 64,
  Duration? heartbeat,
  int missedHeartbeatThreshold = 3,
  Timer Function(Duration delay, void Function() callback)? timerFactory,
}) => LeaseManager(
  station: 'b',
  offerings: {'kind-a': offered, 'kind-b': 1},
  ttl: ttl,
  maxLifetime: maxLifetime,
  maxQueueDepth: maxQueueDepth,
  heartbeat: heartbeat,
  missedHeartbeatThreshold: missedHeartbeatThreshold,
  clock: clock.call,
  timerFactory: timerFactory,
);

void main() {
  group('fencing token (hazard #1)', () {
    test('every grant carries a monotonically increasing token', () {
      final m = _manager(_Clock(), offered: 3);
      final a = m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      final b = m.grant(const LeaseRequest(lessee: 'y', kind: 'kind-a'));
      final c = m.grant(const LeaseRequest(lessee: 'z', kind: 'kind-a'));
      expect([a.fencingToken, b.fencingToken, c.fencingToken], [1, 2, 3]);
    });

    test('touch/release with a STALE token is refused', () {
      final m = _manager(_Clock());
      final g = m.grant(
        const LeaseRequest(lessee: 'x', kind: 'kind-a'),
      ); // token 1
      expect(
        () => m.touch(g.leaseId, 999),
        throwsA(isA<LeaseInvalidException>()),
      );
      expect(
        () => m.release(g.leaseId, token: 999),
        throwsA(isA<LeaseInvalidException>()),
      );
      // The correct token still works.
      m.touch(g.leaseId, g.fencingToken);
      m.release(g.leaseId, token: g.fencingToken);
      expect(m.isValid(g.leaseId), isFalse);
    });

    test('reap+reissue bumps the token; the zombie old handle is refused', () {
      final clock = _Clock();
      final m = _manager(clock, ttl: const Duration(seconds: 10));
      final old = m.grant(
        const LeaseRequest(lessee: 'x', kind: 'kind-a'),
      ); // token 1
      clock.advance(const Duration(seconds: 11)); // TTL reaps the slot
      final fresh = m.grant(
        const LeaseRequest(lessee: 'y', kind: 'kind-a'),
      ); // token 2 on the reissue
      expect(fresh.fencingToken, greaterThan(old.fencingToken));
      // The zombie prior holder cannot act on its dead handle.
      expect(
        () => m.touch(old.leaseId, old.fencingToken),
        throwsA(isA<LeaseInvalidException>()),
      );
      // …and cannot free the NEW holder's slot with its stale token (fencing).
      expect(
        () => m.release(fresh.leaseId, token: old.fencingToken),
        throwsA(isA<LeaseInvalidException>()),
      );
      expect(m.isValid(fresh.leaseId), isTrue);
    });
  });

  group('FIFO wait-queue + max lifetime (hazard #2)', () {
    test(
      'full capacity → requests queue and are granted in ARRIVAL order',
      () async {
        final m = _manager(_Clock(), offered: 1);
        final held = m.grant(
          const LeaseRequest(lessee: 'first', kind: 'kind-a'),
        ); // takes the slot
        // Two more enqueue (do not await — they wait for capacity).
        final bFut = m.acquire(
          const LeaseRequest(lessee: 'b', kind: 'kind-a'),
          maxWait: const Duration(seconds: 60),
        );
        final cFut = m.acquire(
          const LeaseRequest(lessee: 'c', kind: 'kind-a'),
          maxWait: const Duration(seconds: 60),
        );
        expect(m.queued, 2);

        m.release(held.leaseId, token: held.fencingToken);
        final b = await bFut; // FIFO head granted first
        expect(m.queued, 1);
        m.release(b.leaseId, token: b.fencingToken);
        final c = await cFut;
        // Arrival order preserved by the monotonic id seq.
        expect(b.leaseId, 'b-lease-1');
        expect(c.leaseId, 'b-lease-2');
      },
    );

    test('a bounded queue DENIES when full', () {
      final m = _manager(_Clock(), offered: 1, maxQueueDepth: 1);
      m.grant(const LeaseRequest(lessee: 'held', kind: 'kind-a'));
      m.acquire(
        const LeaseRequest(lessee: 'q1', kind: 'kind-a'),
        maxWait: const Duration(seconds: 60),
      ); // fills the queue
      expect(
        m.acquire(
          const LeaseRequest(lessee: 'q2', kind: 'kind-a'),
          maxWait: const Duration(seconds: 60),
        ),
        throwsA(isA<LeaseDeniedException>()),
      );
    });

    test(
      'a waiter is DENIED once its wait expires by the owner clock',
      () async {
        final clock = _Clock();
        final m = _manager(clock, offered: 1);
        m.grant(const LeaseRequest(lessee: 'held', kind: 'kind-a'));
        final waiter = m.acquire(
          const LeaseRequest(lessee: 'late', kind: 'kind-a'),
          maxWait: const Duration(seconds: 10),
        );
        clock.advance(const Duration(seconds: 11));
        m.tick(); // owner-clock pump expires the overdue waiter
        await expectLater(waiter, throwsA(isA<LeaseDeniedException>()));
      },
    );

    test(
      'max lifetime CAPS renewal — touches cannot keep a lease alive forever',
      () {
        final clock = _Clock();
        // ttl is huge; lifetime is the real bound.
        final m = _manager(
          clock,
          ttl: const Duration(seconds: 1000),
          maxLifetime: const Duration(seconds: 100),
        );
        final g = m.grant(const LeaseRequest(lessee: 'greedy', kind: 'kind-a'));
        clock.advance(const Duration(seconds: 50));
        m.touch(g.leaseId, g.fencingToken); // renew — still inside the lifetime
        final bystander = m.grant(
          const LeaseRequest(lessee: 'bystander', kind: 'kind-b'),
        );
        expect(m.isValid(g.leaseId), isTrue);
        clock.advance(
          const Duration(seconds: 51),
        ); // now past the 100s lifetime
        expect(m.isValid(g.leaseId), isFalse); // reaped despite a fresh touch
        expect(m.isValid(bystander.leaseId), isTrue);
        expect(m.availableFor('kind-b'), 0);
      },
    );
  });

  group('owner-clock reaping (hazard #3)', () {
    test('an idle lease is reaped strictly by the owner clock + TTL', () {
      final clock = _Clock();
      final m = _manager(clock, ttl: const Duration(seconds: 30));
      final g = m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      final bystander = m.grant(
        const LeaseRequest(lessee: 'bystander', kind: 'kind-b'),
      );
      clock.advance(const Duration(seconds: 29));
      expect(m.isValid(g.leaseId), isTrue);
      m.touch(bystander.leaseId, bystander.fencingToken);
      clock.advance(const Duration(seconds: 2)); // 31s total → past TTL
      expect(m.isValid(g.leaseId), isFalse);
      expect(m.availableFor('kind-a'), 1); // the affected slot frees
      expect(m.isValid(bystander.leaseId), isTrue);
      expect(m.availableFor('kind-b'), 0); // the other kind is untouched
    });
  });

  group('onLeaseEnded (the lessor teardown hook)', () {
    test('fires on explicit release AND on every reap path; a throwing '
        'callback never corrupts accounting', () {
      final clock = _Clock();
      final ended = <String>[];
      final m = LeaseManager(
        station: 'b',
        offerings: const {'kind-a': 2, 'kind-b': 1},
        ttl: const Duration(seconds: 30),
        clock: clock.call,
        onLeaseEnded: (id) {
          ended.add(id);
          throw StateError('hook explodes'); // exception-isolated
        },
      );

      // Explicit release fires the hook.
      final g1 = m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      m.release(g1.leaseId, token: g1.fencingToken);
      expect(ended, [g1.leaseId]);
      expect(
        m.availableFor('kind-a'),
        2,
        reason: 'a throwing hook never blocks the slot',
      );

      // An idle-TTL reap fires the hook too (the follower app must die when
      // its lease does, however the lease ends).
      final g2 = m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      clock.advance(const Duration(seconds: 31));
      m.tick();
      expect(ended, [g1.leaseId, g2.leaseId]);
      expect(m.availableFor('kind-a'), 2);
    });
  });

  group('idempotency (hazard #4)', () {
    test(
      'a retried request (same key) returns the SAME grant, never a second',
      () {
        final m = _manager(_Clock(), offered: 2);
        final a = m.grant(
          const LeaseRequest(lessee: 'x', kind: 'kind-a', idempotencyKey: 'k1'),
        );
        final b = m.grant(
          const LeaseRequest(lessee: 'x', kind: 'kind-a', idempotencyKey: 'k1'),
        );
        expect(b.leaseId, a.leaseId);
        expect(b.fencingToken, a.fencingToken);
        expect(m.availableFor('kind-a'), 1); // only ONE slot consumed
      },
    );

    test('after release the key is freed — a re-request is a NEW grant', () {
      final m = _manager(_Clock());
      final a = m.grant(
        const LeaseRequest(lessee: 'x', kind: 'kind-a', idempotencyKey: 'k1'),
      );
      m.release(a.leaseId, token: a.fencingToken);
      final b = m.grant(
        const LeaseRequest(lessee: 'x', kind: 'kind-a', idempotencyKey: 'k1'),
      );
      expect(b.leaseId, isNot(a.leaseId));
      expect(b.fencingToken, greaterThan(a.fencingToken));
    });

    test(
      'a concurrent acquire retry attaches to the SAME queued waiter',
      () async {
        final m = _manager(_Clock(), offered: 1);
        final held = m.grant(
          const LeaseRequest(lessee: 'held', kind: 'kind-a'),
        );
        final f1 = m.acquire(
          const LeaseRequest(
            lessee: 'x',
            kind: 'kind-a',
            idempotencyKey: 'dup',
          ),
          maxWait: const Duration(seconds: 60),
        );
        final f2 = m.acquire(
          const LeaseRequest(
            lessee: 'x',
            kind: 'kind-a',
            idempotencyKey: 'dup',
          ),
          maxWait: const Duration(seconds: 60),
        );
        expect(m.queued, 1); // one waiter, not two
        m.release(held.leaseId, token: held.fencingToken);
        final g1 = await f1;
        final g2 = await f2;
        expect(g2.leaseId, g1.leaseId); // one grant satisfies both
      },
    );
  });

  group('declare-and-check', () {
    test('grant DENIES immediately when no capacity (no queue)', () {
      final m = _manager(_Clock(), offered: 1);
      m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      expect(
        () => m.grant(const LeaseRequest(lessee: 'y', kind: 'kind-a')),
        throwsA(isA<LeaseDeniedException>()),
      );
    });

    test(
      'a kind that is not offered is a permanent deny (even with a wait)',
      () {
        final m = _manager(_Clock());
        expect(
          m.acquire(
            const LeaseRequest(lessee: 'x', kind: 'gpu'),
            maxWait: const Duration(seconds: 60),
          ),
          throwsA(isA<LeaseDeniedException>()),
        );
      },
    );
  });

  group('multi-kind arbitration', () {
    test('offerings must be non-empty with named positive capacities', () {
      for (final offerings in <Map<String, int>>[
        {},
        {'': 1},
        {'kind-a': 0},
        {'kind-a': -1},
      ]) {
        expect(
          () => LeaseManager(station: 'host', offerings: offerings),
          throwsArgumentError,
        );
      }
    });

    test(
      'capacity is independent in both directions, including capacity one',
      () {
        final m = _manager(_Clock());
        final a = m.grant(const LeaseRequest(lessee: 'a', kind: 'kind-a'));
        expect(
          () => m.grant(const LeaseRequest(lessee: 'a2', kind: 'kind-a')),
          throwsA(isA<LeaseDeniedException>()),
        );
        final b = m.grant(const LeaseRequest(lessee: 'b', kind: 'kind-b'));
        expect(m.availableFor('kind-a'), 0);
        expect(m.availableFor('kind-b'), 0);
        m.release(a.leaseId, token: a.fencingToken);
        expect(m.availableFor('kind-a'), 1);
        expect(m.availableFor('kind-b'), 0);
        m.release(b.leaseId, token: b.fencingToken);
      },
    );

    test('a release pumps only that kind FIFO in arrival order', () async {
      final m = _manager(_Clock());
      final heldA = m.grant(
        const LeaseRequest(lessee: 'held-a', kind: 'kind-a'),
      );
      final heldB = m.grant(
        const LeaseRequest(lessee: 'held-b', kind: 'kind-b'),
      );
      final a1 = m.acquire(
        const LeaseRequest(lessee: 'a1', kind: 'kind-a'),
        maxWait: const Duration(minutes: 1),
      );
      final a2 = m.acquire(
        const LeaseRequest(lessee: 'a2', kind: 'kind-a'),
        maxWait: const Duration(minutes: 1),
      );
      var completed = false;
      unawaited(a1.then((_) => completed = true));
      m.release(heldB.leaseId, token: heldB.fencingToken);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      m.release(heldA.leaseId, token: heldA.fencingToken);
      final first = await a1;
      m.release(first.leaseId, token: first.fencingToken);
      expect((await a2).leaseId, isNot(first.leaseId));
    });

    test('presence aggregates offerings and preserves kind order', () {
      final m = LeaseManager(
        station: 'host',
        offerings: const {'kind-a': 2, 'kind-b': 1},
      );
      m.grant(const LeaseRequest(lessee: 'a', kind: 'kind-a'));
      expect(m.presence.kinds, ['kind-a', 'kind-b']);
      expect(m.presence.offered, 3);
      expect(m.presence.available, 2);
    });

    test('idempotency is scoped by kind', () {
      final m = _manager(_Clock());
      const aReq = LeaseRequest(
        lessee: 'same',
        kind: 'kind-a',
        idempotencyKey: 'key',
      );
      const bReq = LeaseRequest(
        lessee: 'same',
        kind: 'kind-b',
        idempotencyKey: 'key',
      );
      final a = m.grant(aReq);
      final b = m.grant(bReq);
      expect(a.leaseId, isNot(b.leaseId));
      expect(m.grant(aReq).leaseId, a.leaseId);
      expect(m.grant(bReq).leaseId, b.leaseId);
    });

    test('manager-wide fencing is monotonic across kinds', () {
      final m = _manager(_Clock());
      final a = m.grant(const LeaseRequest(lessee: 'a', kind: 'kind-a'));
      final b = m.grant(const LeaseRequest(lessee: 'b', kind: 'kind-b'));
      expect(b.fencingToken, greaterThan(a.fencingToken));
      expect(
        () => m.beat(b.leaseId, a.fencingToken),
        throwsA(isA<LeaseInvalidException>()),
      );
    });
  });

  group('the manager owns its schedule', () {
    test(
      'idle full-capacity manager denies a waiter from its owned timer',
      () async {
        final clock = _Clock();
        final timers = _ManualTimerFactory(clock);
        final m = _manager(clock, timerFactory: timers.call);
        m.grant(const LeaseRequest(lessee: 'held', kind: 'kind-a'));
        final waiter = m.acquire(
          const LeaseRequest(lessee: 'late', kind: 'kind-a'),
          maxWait: const Duration(seconds: 10),
        );
        final denied = expectLater(waiter, _deniedWith('wait expired'));
        // The ONLY thing that touches the manager from here — no request pumps it.
        timers.fireNext();
        await denied;
      },
    );

    test('two kinds expire at their own timer deadlines in order', () async {
      final clock = _Clock();
      final start = clock.now;
      final timers = _ManualTimerFactory(clock);
      final m = _manager(clock, timerFactory: timers.call);
      m.grant(const LeaseRequest(lessee: 'held-a', kind: 'kind-a'));
      m.grant(const LeaseRequest(lessee: 'held-b', kind: 'kind-b'));
      final a = m.acquire(
        const LeaseRequest(lessee: 'a', kind: 'kind-a'),
        maxWait: const Duration(seconds: 10),
      );
      final b = m.acquire(
        const LeaseRequest(lessee: 'b', kind: 'kind-b'),
        maxWait: const Duration(seconds: 20),
      );
      // Recorders first, so each denial is logged before its expectation
      // resolves — listeners run in registration order.
      final order = <String>[];
      unawaited(a.then((_) {}, onError: (Object _) => order.add('kind-a')));
      unawaited(b.then((_) {}, onError: (Object _) => order.add('kind-b')));
      final deniedA = expectLater(a, _deniedWith('wait expired'));
      final deniedB = expectLater(b, _deniedWith('wait expired'));

      timers.fireNext(); // kind-a's 10s wait
      await deniedA;
      expect(timers.live, hasLength(1), reason: 'one timer, never two');
      expect(
        timers.live.single.deadline,
        start.add(const Duration(seconds: 20)),
        reason: "the first denial does not mask kind-b's later deadline",
      );

      timers.fireNext(); // kind-b's 20s wait
      await deniedB;
      expect(order, ['kind-a', 'kind-b']);
      expect(
        timers.live.single.deadline,
        start.add(const Duration(seconds: 300)),
        reason: 'with the queues drained the held TTLs are the next deadline',
      );
    });

    test('scheduler re-arms at the earliest deadline with at most one live '
        'timer', () async {
      final clock = _Clock();
      final start = clock.now;
      final timers = _ManualTimerFactory(clock);
      final m = _manager(
        clock,
        ttl: const Duration(seconds: 30),
        maxLifetime: const Duration(seconds: 20),
        heartbeat: const Duration(seconds: 10),
        missedHeartbeatThreshold: 1,
        timerFactory: timers.call,
      );

      final held = m.grant(const LeaseRequest(lessee: 'held', kind: 'kind-a'));
      expect(timers.live, hasLength(1));
      expect(
        timers.live.single.deadline,
        start.add(const Duration(seconds: 10)),
        reason: 'the heartbeat window is the earliest of the three held bounds',
      );

      final waiter = m.acquire(
        const LeaseRequest(lessee: 'next', kind: 'kind-a'),
        maxWait: const Duration(seconds: 2),
      );
      expect(timers.live, hasLength(1));
      expect(
        timers.live.single.deadline,
        start.add(const Duration(seconds: 2)),
        reason: 'a nearer waiter deadline takes the timer',
      );

      m.release(held.leaseId, token: held.fencingToken);
      final granted =
          await waiter; // the release hands the slot to the FIFO head
      expect(timers.live, hasLength(1));
      expect(
        timers.live.single.deadline,
        start.add(const Duration(seconds: 10)),
        reason: "the grant re-arms on the new lease's own bounds",
      );

      m.release(granted.leaseId, token: granted.fencingToken);
      expect(timers.live, isEmpty, reason: 'no deadline left → nothing armed');
    });

    test('scheduler clamps negative delays to zero', () {
      // A clock that has always moved on by the time the manager re-arms, so
      // every deadline it computes is already in the past.
      var now = DateTime.utc(2026);
      DateTime advancingClock() {
        final reading = now;
        now = now.add(const Duration(seconds: 1));
        return reading;
      }

      final delays = <Duration>[];
      final m = LeaseManager(
        station: 'b',
        offerings: const {'kind-a': 1},
        ttl: const Duration(microseconds: 1),
        clock: advancingClock,
        timerFactory: (delay, callback) {
          delays.add(delay);
          return _ManualTimer(delay, now, callback);
        },
      );

      m.grant(const LeaseRequest(lessee: 'x', kind: 'kind-a'));
      expect(delays, isNotEmpty);
      expect(delays.any((d) => d.isNegative), isFalse);
      expect(delays.last, Duration.zero);
    });

    test('owned timer reaps a held lease and grants its waiter', () async {
      final clock = _Clock();
      final timers = _ManualTimerFactory(clock);
      final m = _manager(
        clock,
        ttl: const Duration(seconds: 10),
        timerFactory: timers.call,
      );
      final held = m.grant(const LeaseRequest(lessee: 'held', kind: 'kind-a'));
      final waiter = m.acquire(
        const LeaseRequest(lessee: 'next', kind: 'kind-a'),
        maxWait: const Duration(seconds: 60),
      );

      timers.fireNext(); // the held lease's 10s TTL, ahead of the 60s wait
      final granted = await waiter;
      expect(granted.leaseId, isNot(held.leaseId));
      expect(m.isValid(held.leaseId), isFalse);
      expect(m.isValid(granted.leaseId), isTrue);
    });

    test(
      'close cancels scheduling once without draining leases or waiters',
      () async {
        final clock = _Clock();
        final timers = _ManualTimerFactory(clock);
        final ended = <String>[];
        final m = LeaseManager(
          station: 'b',
          offerings: const {'kind-a': 1},
          ttl: const Duration(seconds: 30),
          clock: clock.call,
          timerFactory: timers.call,
          onLeaseEnded: ended.add,
        );
        final held = m.grant(
          const LeaseRequest(lessee: 'held', kind: 'kind-a'),
        );
        final waiter = m.acquire(
          const LeaseRequest(lessee: 'next', kind: 'kind-a'),
          maxWait: const Duration(seconds: 10),
        );
        var settled = false;
        unawaited(
          waiter.then(
            (_) => settled = true,
            onError: (Object _) => settled = true,
          ),
        );
        expect(timers.live, hasLength(1));

        m.close();
        m.close(); // idempotent
        await Future<void>.delayed(Duration.zero);

        expect(timers.live, isEmpty);
        expect(settled, isFalse, reason: 'close does not drain the wait-queue');
        expect(m.isValid(held.leaseId), isTrue, reason: 'close does not reap');
        expect(ended, isEmpty, reason: 'close is not a lease ending');
        expect(timers.live, isEmpty, reason: 'a closed manager never re-arms');
      },
    );
  });

  group('the station server owns the manager lifecycle', () {
    test('station server without a reap interval denies an idle waiting lease '
        'at leaseWait', () async {
      final server = await StationServer.start(
        station: 'idle',
        offerings: const {'kind-a': 1},
        host: '127.0.0.1',
        leaseWait: const Duration(milliseconds: 250),
        handler: _echoHandler,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      await client.requestLease(
        const LeaseRequest(lessee: 'holder', kind: 'kind-a'),
      );
      // No reapInterval and no further traffic: only the manager's own deadline
      // timer can move this waiting request on.
      await expectLater(
        client.requestLease(
          const LeaseRequest(lessee: 'waiter', kind: 'kind-a'),
        ),
        _deniedWith('wait expired'),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
