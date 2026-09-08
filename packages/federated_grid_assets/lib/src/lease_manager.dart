/// The lessor's lease bookkeeping — the owner-authoritative serialization point
/// (ADR-0011 D5). It bakes in the four hard-earned federation hazards:
///
/// 1. **Fencing** — every grant carries an owner-issued monotonically increasing
///    [LeaseGrant.fencingToken]; a dispatch/release with a stale token is refused
///    ([LeaseInvalidException]). No zombie double-use after reap+reissue.
/// 2. **Max lifetime + a FIFO wait-queue** — a lease has a hard lifetime (caps
///    total TTL renewal → no incumbent monopoly); when capacity is full, requests
///    enqueue FIFO (bounded) and are granted in arrival order as slots free → a
///    starvation bound, no priority/aging.
/// 3. **Owner-clock reaping** — ALL expiry/lifetime math uses the owner's
///    injectable [clock]; no cross-machine timestamp arithmetic. Fencing uses the
///    owner's monotonic version counter, never wall-time.
/// 4. **Idempotency** — a [LeaseRequest.idempotencyKey] dedups: a retried request
///    returns the SAME live grant, never a second grant.
///
/// On top of those, M6 Track B adds **heartbeat liveness** (ADR-0011 D5/D7): when
/// [heartbeat] is set, each grant carries a heartbeat deadline; a lessee [beat]s
/// to renew it, and the owner reaps a held lease once the heartbeat is missed past
/// [missedHeartbeatThreshold] intervals — **by its OWN clock** (disconnect = a
/// missed-heartbeat threshold, never cross-machine time math). Heartbeat is
/// orthogonal to the idle TTL: TTL reaps an *idle* lease, heartbeat reaps a
/// *disconnected* one. With [heartbeat] unset, behaviour is unchanged (idle TTL +
/// max-lifetime only).
///
/// The manager also OWNS its schedule. Every deadline it holds — a lease's idle
/// TTL, its max lifetime, its heartbeat window, and a queued request's `maxWait`
/// — is backed by ONE pending timer armed at the EARLIEST of them, re-armed on
/// every state change that can move that minimum. Without it, expiry only ever
/// advanced when some OTHER request happened to pump the manager, so an idle
/// station held an overdue waiter open forever and freed a dead lease's slot
/// only on the next unrelated call. The timer's callback is the same pump [tick]
/// runs — the one every request path already drives — so all expiry semantics
/// stay in one place and the [clock] remains the sole source of every
/// COMPARISON. Stop the scheduling with [close].
///
/// Pure, synchronous, injectable clock + id generator + timer factory so it is
/// fully testable without a wall-clock, randomness, or real IO.
library;

import 'dart:async';

import 'package:grid_engine/grid_engine.dart';

/// One held lease: its kind, the idle-TTL expiry (renewed by [LeaseManager.touch]),
/// the immovable max-lifetime deadline, the optional heartbeat deadline (renewed
/// by [LeaseManager.beat]; `null` when heartbeat is not required), the fencing
/// token, and the (optional) idempotency key it was granted under.
class _Held {
  _Held({
    required this.kind,
    required this.expiry,
    required this.hardDeadline,
    required this.heartbeatDeadline,
    required this.fencingToken,
    required this.idempotencyKey,
  });

  final String kind;
  DateTime expiry;
  final DateTime hardDeadline;
  DateTime? heartbeatDeadline;
  final int fencingToken;
  final String idempotencyKey;
}

/// A queued lease request awaiting capacity (FIFO). [deadline] is the
/// owner-clock instant after which the wait is denied.
class _Waiter {
  _Waiter(this.req, this.completer, this.deadline);

  final LeaseRequest req;
  final Completer<LeaseGrant> completer;
  final DateTime deadline;
}

/// Tracks offered vs held slots for a single station and arbitrates leases.
class LeaseManager {
  /// Creates a manager offering the insertion-ordered [offerings] for [station].
  ///
  /// [ttl] is the idle-renewal window (each [touch] extends it). [maxLifetime] is
  /// the immovable cap on a lease's total life (renewal cannot push past it).
  /// [maxQueueDepth] bounds the FIFO wait-queue. [heartbeat] (when set) is the
  /// expected liveness cadence; a lease with no [beat] within
  /// [heartbeat] × [missedHeartbeatThreshold] is reaped as disconnected. [clock],
  /// [idGen] and [timerFactory] are injectable for deterministic tests;
  /// [timerFactory] defaults to `dart:async`'s [Timer] and is how the manager
  /// arms its own earliest-deadline timer (a test drives expiry by firing a fake
  /// one against the same injected [clock]).
  ///
  /// Fencing deliberately uses one manager-wide counter. A fencing token only
  /// needs to be an owner-issued monotonic version; sharing the sequence across
  /// kinds makes every grant from this station manager strictly ordered without
  /// combining any kind's capacity, queue, idempotency, or lifecycle state.
  LeaseManager({
    required this.station,
    required Map<String, int> offerings,
    this.ttl = const Duration(seconds: 300),
    this.maxLifetime = const Duration(seconds: 3600),
    this.maxQueueDepth = 64,
    this.heartbeat,
    this.missedHeartbeatThreshold = 3,
    this.onLeaseEnded,
    DateTime Function()? clock,
    String Function(int seq)? idGen,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  }) : offerings = Map.unmodifiable(_validateOfferings(offerings)),
       _queues = {for (final kind in offerings.keys) kind: <_Waiter>[]},
       _grantsByKindAndKey = {
         for (final kind in offerings.keys) kind: <String, LeaseGrant>{},
       },
       assert(missedHeartbeatThreshold > 0, 'threshold must be positive'),
       _clock = clock ?? DateTime.now,
       _idGen = idGen ?? ((seq) => '$station-lease-$seq'),
       _timerFactory = timerFactory ?? Timer.new;

  /// The station id this manager speaks for.
  final String station;

  /// Resource-asset kinds and their capacities, in advertisement order.
  final Map<String, int> offerings;

  /// Total slots offered across all kinds.
  int get offered => offerings.values.fold(0, (sum, value) => sum + value);

  /// How long a lease lives without activity before it is reaped.
  final Duration ttl;

  /// The immovable cap on a lease's total life (TTL renewal cannot exceed it).
  final Duration maxLifetime;

  /// The maximum number of requests that may wait in the FIFO queue.
  final int maxQueueDepth;

  /// The expected heartbeat cadence, or `null` when heartbeat liveness is off
  /// (idle TTL + max-lifetime only). Surfaced to the lessee via
  /// [LeaseGrant.heartbeatSeconds].
  final Duration? heartbeat;

  /// How many heartbeat intervals may be missed before the owner reaps the lease
  /// (the disconnect threshold). Only meaningful when [heartbeat] is set.
  final int missedHeartbeatThreshold;

  /// The grace window a held lease survives without a heartbeat
  /// ([heartbeat] × [missedHeartbeatThreshold]), or `null` when heartbeat is off.
  Duration? get heartbeatTimeout =>
      heartbeat == null ? null : heartbeat! * missedHeartbeatThreshold;

  final DateTime Function() _clock;
  final String Function(int seq) _idGen;
  final Timer Function(Duration delay, void Function() callback) _timerFactory;

  /// The ONE pending deadline timer (see [_rearm]), or `null` when the manager
  /// holds no deadline at all — or has been [close]d.
  Timer? _deadlineTimer;
  bool _closed = false;
  final Map<String, _Held> _held = {};
  final Map<String, List<_Waiter>> _queues;
  final Map<String, Map<String, LeaseGrant>> _grantsByKindAndKey;
  int _seq = 0;
  int _fence = 0;

  /// Free slots right now (after reaping expired leases and draining the queue).
  ///
  /// Reading liveness also drives the queue: a slot freed by TTL/lifetime expiry
  /// is handed to the FIFO head here, so a waiter is released without a separate
  /// ticker (the spike already reaped on this read; this extends it to pump).
  int get available {
    _pump();
    return offerings.keys.fold(0, (sum, kind) => sum + _availableFor(kind));
  }

  /// Free slots for [kind] after driving owner-clock expiry and its FIFO queue.
  int availableFor(String kind) {
    _requireKind(kind);
    _reap();
    _pumpKind(kind);
    return _availableFor(kind);
  }

  /// The number of requests currently waiting in the FIFO queue.
  int get queued {
    _pump();
    return _queues.values.fold(0, (sum, queue) => sum + queue.length);
  }

  /// The number of requests waiting for [kind].
  int queuedFor(String kind) {
    _requireKind(kind);
    _reap();
    _pumpKind(kind);
    return _queues[kind]!.length;
  }

  /// A presence snapshot.
  Presence get presence => Presence(
    station: station,
    kinds: offerings.keys.toList(growable: false),
    offered: offered,
    available: available,
  );

  /// Grants a lease for [req] IMMEDIATELY, or throws [LeaseDeniedException] if the
  /// kind is not offered or there is no free capacity (the synchronous
  /// declare-and-check; no queueing). Use [acquire] to opt into the FIFO wait.
  LeaseGrant grant(LeaseRequest req) {
    final g = _tryGrantNow(req);
    if (g == null) throw const LeaseDeniedException('no capacity');
    return g;
  }

  /// Requests a lease, optionally WAITING up to [maxWait] in the FIFO queue when
  /// capacity is full.
  ///
  /// - Free capacity (and no one ahead in the queue) → granted now.
  /// - Full + [maxWait] null/zero → denied immediately ([LeaseDeniedException]).
  /// - Full + the queue is already at [maxQueueDepth] → denied ('wait-queue
  ///   full').
  /// - Otherwise enqueued FIFO; granted in arrival order as slots free, or denied
  ///   ('wait expired') once [maxWait] passes by the owner clock.
  ///
  /// Idempotent: a retried [req] (same non-empty [LeaseRequest.idempotencyKey])
  /// returns the live grant, or attaches to the existing waiter — never a second
  /// grant.
  Future<LeaseGrant> acquire(LeaseRequest req, {Duration? maxWait}) {
    final LeaseGrant? now;
    try {
      now = _tryGrantNow(req);
    } on LeaseDeniedException catch (e) {
      return Future.error(e); // permanent deny (e.g. kind not offered)
    }
    if (now != null) return Future.value(now);

    if (maxWait == null || maxWait == Duration.zero) {
      return Future.error(const LeaseDeniedException('no capacity'));
    }
    // Idempotent retry that lands on an already-queued waiter.
    if (req.idempotencyKey.isNotEmpty) {
      for (final w in _queues[req.kind]!) {
        if (w.req.idempotencyKey == req.idempotencyKey) {
          return w.completer.future;
        }
      }
    }
    final queue = _queues[req.kind]!;
    if (queue.length >= maxQueueDepth) {
      return Future.error(const LeaseDeniedException('wait-queue full'));
    }
    final w = _Waiter(req, Completer<LeaseGrant>(), _clock().add(maxWait));
    queue.add(w);
    _rearm(); // the wait deadline is ours to enforce, traffic or not
    return w.completer.future;
  }

  /// Whether [leaseId] is currently a live (non-expired) lease.
  bool isValid(String leaseId) {
    _reap();
    return _held.containsKey(leaseId);
  }

  /// Extends [leaseId]'s idle TTL on activity (a dispatch). Renewal cannot keep a
  /// lease alive past its max lifetime: the idle expiry is pushed forward freely,
  /// but the immovable [_Held.hardDeadline] is enforced ORTHOGONALLY by the
  /// owner-clock reaper ([_reap]) — renewal never clamps the stored deadline, so
  /// the hard-deadline reap (not this push) is the sole max-lifetime bound. Throws
  /// [LeaseInvalidException] if the lease is unknown/expired or [token] is stale
  /// (fencing).
  void touch(String leaseId, int token) {
    _validate(leaseId, token);
    final h = _held[leaseId]!;
    h.expiry = _clock().add(ttl);
    _pump();
  }

  /// Records a liveness HEARTBEAT for [leaseId], renewing its heartbeat deadline
  /// to `now + heartbeatTimeout`. A no-op on the deadline when [heartbeat] is off,
  /// but it still validates the handle + fencing [token] (so a stale beat is
  /// refused). A beat cannot keep a lease alive past its max lifetime: the
  /// [_Held.hardDeadline] reaper ([_reap]) bounds the lease ORTHOGONALLY,
  /// regardless of how far the renewed heartbeat deadline is pushed. Throws
  /// [LeaseInvalidException] if the lease is unknown/expired or [token] is stale.
  void beat(String leaseId, int token) {
    _validate(leaseId, token);
    final h = _held[leaseId]!;
    final timeout = heartbeatTimeout;
    if (timeout != null) {
      h.heartbeatDeadline = _clock().add(timeout);
    }
    _pump();
  }

  /// Releases [leaseId], freeing its slot and draining the FIFO queue.
  ///
  /// Idempotent for the rightful holder: releasing an unknown/already-reaped lease
  /// is a no-op. But a [token] that does not match a STILL-LIVE lease is rejected
  /// ([LeaseInvalidException]) so a zombie cannot free the new holder's slot
  /// (fencing). Pass `null` only for internal/trusted cleanup.
  void release(String leaseId, {int? token}) {
    _reap();
    final h = _held[leaseId];
    if (h == null) {
      _pump();
      return; // idempotent
    }
    if (token != null && h.fencingToken != token) {
      throw LeaseInvalidException(
        'stale fencing token $token for lease "$leaseId" '
        '(current ${h.fencingToken})',
      );
    }
    _remove(leaseId, h);
    _pump();
  }

  /// Advances time-driven state: reap expired leases/lifetimes by the owner clock,
  /// expire overdue waiters, then grant freed slots to the FIFO head. Idempotent.
  ///
  /// The manager already calls this from its own deadline timer, so a caller
  /// never has to poll; a coarse external ticker remains a harmless safety net.
  void tick() => _pump();

  /// Stops the manager's OWN scheduling: cancels the pending deadline timer so
  /// nothing more fires from it. Idempotent — a second call is a no-op.
  ///
  /// Deliberately NOT a drain. Held leases stay held, queued waiters stay
  /// pending (their futures are neither granted nor denied) and [onLeaseEnded]
  /// never fires here: tearing the lessee-facing surface down belongs to whoever
  /// owns it (the station server closes this beside its socket). After [close]
  /// the manager still answers every call correctly — it is simply back to
  /// advancing only when something pumps it.
  void close() {
    if (_closed) return;
    _closed = true;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }

  /// Validates a lease handle + fencing [token] for the given [leaseId].
  void _validate(String leaseId, int token) {
    _reap();
    final h = _held[leaseId];
    if (h == null) {
      throw LeaseInvalidException('lease "$leaseId" is unknown or expired');
    }
    if (h.fencingToken != token) {
      throw LeaseInvalidException(
        'stale fencing token $token for lease "$leaseId" '
        '(current ${h.fencingToken})',
      );
    }
  }

  /// The synchronous declare-and-check core: idempotency dedup, kind check, and a
  /// capacity check that yields to any FIFO waiter. Returns the grant, or `null`
  /// when there is no free capacity. Throws [LeaseDeniedException] for a permanent
  /// refusal (the kind is not offered).
  LeaseGrant? _tryGrantNow(LeaseRequest req) {
    _pump(); // reap + hand freed slots to the queue FIRST (fairness)
    if (!offerings.containsKey(req.kind)) {
      throw LeaseDeniedException(
        'kind "${req.kind}" not offered (offers ${offerings.keys.join(', ')})',
      );
    }
    if (req.idempotencyKey.isNotEmpty) {
      final existing = _grantsByKindAndKey[req.kind]![req.idempotencyKey];
      if (existing != null && _held.containsKey(existing.leaseId)) {
        return existing; // dedup: the live grant, never a second
      }
    }
    // Full — any FIFO waiters are ahead of a fresh direct grant.
    if (_availableFor(req.kind) == 0) return null;
    return _issue(req);
  }

  /// Mints a fresh lease + fencing token and records it.
  LeaseGrant _issue(LeaseRequest req) {
    final id = _idGen(_seq++);
    final token = ++_fence; // monotonic owner version (1, 2, 3, …)
    final now = _clock();
    final hardDeadline = now.add(maxLifetime);
    final timeout = heartbeatTimeout;
    _held[id] = _Held(
      kind: req.kind,
      // The idle/heartbeat deadlines are NOT clamped to the hard deadline; the
      // hard deadline is enforced independently by [_reap], so it stays the lone,
      // testable max-lifetime bound (no masking by a clamped idle expiry).
      expiry: now.add(ttl),
      hardDeadline: hardDeadline,
      // A grace window before the first heartbeat is due.
      heartbeatDeadline: timeout == null ? null : now.add(timeout),
      fencingToken: token,
      idempotencyKey: req.idempotencyKey,
    );
    final grant = LeaseGrant(
      leaseId: id,
      station: station,
      ttlSeconds: ttl.inSeconds,
      fencingToken: token,
      heartbeatSeconds: heartbeat?.inSeconds ?? 0,
      kind: req.kind,
    );
    if (req.idempotencyKey.isNotEmpty) {
      _grantsByKindAndKey[req.kind]![req.idempotencyKey] = grant;
    }
    _rearm(); // a fresh lease brings three deadlines with it
    return grant;
  }

  /// Fired whenever a held lease ends — explicit [release] OR any reap
  /// (idle TTL / hard deadline / missed heartbeat). The lessor's teardown
  /// hook: a domain that launched work under the lease reaps it here
  /// (ADR-0011 Hazards, "orphaned work on the lessor" — the burn's
  /// follower app must die when its lease does). Exception-isolated: a
  /// throwing callback never corrupts lease accounting.
  final void Function(String leaseId)? onLeaseEnded;

  void _remove(String leaseId, _Held h) {
    _held.remove(leaseId);
    if (h.idempotencyKey.isNotEmpty) {
      _grantsByKindAndKey[h.kind]!.remove(h.idempotencyKey);
    }
    try {
      onLeaseEnded?.call(leaseId);
    } on Object {
      // The hook is best-effort; lease accounting already advanced.
    }
  }

  /// Reap by the OWNER clock: a lease dies when ANY of three ORTHOGONAL bounds
  /// passes — its idle TTL ([_Held.expiry], renewed by [touch]), its immovable max
  /// lifetime ([_Held.hardDeadline], NEVER renewed), or (when heartbeat is on) its
  /// heartbeat deadline ([_Held.heartbeatDeadline], renewed by [beat]) — whichever
  /// is first. These are independent: a greedy lease that renews its idle TTL (and
  /// heartbeat) forever is STILL reaped at its hard deadline. Because renewal never
  /// clamps the stored deadlines, the hard-deadline clause is the SOLE
  /// max-lifetime enforcer — load-bearing and independently testable (no idle-TTL
  /// reap masking it). The heartbeat deadline is the disconnect reaper: a
  /// missed-heartbeat threshold elapsing frees the slot exactly like an
  /// idle/expired lease.
  void _reap() {
    final now = _clock();
    final dead = <String>[];
    _held.forEach((id, h) {
      final hb = h.heartbeatDeadline;
      if (!h.expiry.isAfter(now) ||
          !h.hardDeadline.isAfter(now) ||
          (hb != null && !hb.isAfter(now))) {
        dead.add(id);
      }
    });
    for (final id in dead) {
      _remove(id, _held[id]!);
    }
    _rearm();
  }

  /// Reap, expire overdue waiters, then grant freed slots to the FIFO head.
  void _pump() {
    _reap();
    for (final kind in offerings.keys) {
      _pumpKind(kind);
    }
    _rearm();
  }

  void _pumpKind(String kind) {
    final now = _clock();
    final queue = _queues[kind]!;
    queue.removeWhere((w) {
      if (w.deadline.isAfter(now)) return false;
      if (!w.completer.isCompleted) {
        w.completer.completeError(const LeaseDeniedException('wait expired'));
      }
      return true;
    });
    while (queue.isNotEmpty && _availableFor(kind) > 0) {
      final w = queue.removeAt(0);
      w.completer.complete(_issue(w.req));
    }
    _rearm();
  }

  /// Re-points the manager's ONE pending timer at the earliest deadline it now
  /// holds, cancelling whatever was armed before. Called after every state
  /// change that can move that minimum (a grant, an enqueue, a reap, a waiter
  /// expiry or completion, a release), so nested pump work never leaves a second
  /// timer live — the last call wins, and the fire arrives no later than the
  /// soonest thing that could change.
  ///
  /// The callback is [_pump] and NOTHING else: reaping, waiter expiry and FIFO
  /// granting are not restated here, they stay where they already live. A
  /// deadline already in the past arms at [Duration.zero] rather than a negative
  /// delay, and arming nothing is the right answer when the manager holds no
  /// deadline (or is closed).
  void _rearm() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    if (_closed) return;
    final earliest = _earliestDeadline();
    if (earliest == null) return;
    final delay = earliest.difference(_clock());
    _deadlineTimer = _timerFactory(
      delay.isNegative ? Duration.zero : delay,
      _pump,
    );
  }

  /// The soonest instant any held lease or queued waiter could need attention:
  /// the minimum over every lease's idle expiry, hard deadline and (when set)
  /// heartbeat deadline — the three ORTHOGONAL bounds [_reap] compares — and
  /// every waiter's wait deadline. `null` when the manager holds neither.
  DateTime? _earliestDeadline() {
    DateTime? earliest;
    for (final h in _held.values) {
      earliest = _earlier(earliest, h.expiry);
      earliest = _earlier(earliest, h.hardDeadline);
      earliest = _earlier(earliest, h.heartbeatDeadline);
    }
    for (final queue in _queues.values) {
      for (final w in queue) {
        earliest = _earlier(earliest, w.deadline);
      }
    }
    return earliest;
  }

  static DateTime? _earlier(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.isBefore(a) ? b : a;
  }

  int _availableFor(String kind) =>
      offerings[kind]! - _held.values.where((held) => held.kind == kind).length;

  void _requireKind(String kind) {
    if (!offerings.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is not offered');
    }
  }

  static Map<String, int> _validateOfferings(Map<String, int> offerings) {
    if (offerings.isEmpty) {
      throw ArgumentError.value(offerings, 'offerings', 'must not be empty');
    }
    for (final entry in offerings.entries) {
      if (entry.key.isEmpty) {
        throw ArgumentError.value(
          entry.key,
          'offerings',
          'kind must not be empty',
        );
      }
      if (entry.value <= 0) {
        throw ArgumentError.value(
          entry.value,
          'offerings[${entry.key}]',
          'capacity must be positive',
        );
      }
    }
    return Map<String, int>.of(offerings);
  }
}
