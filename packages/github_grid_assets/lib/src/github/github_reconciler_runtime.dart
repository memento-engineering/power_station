import 'package:grid_sdk/grid_sdk.dart' show ObligationAppend, ObligationQuery;

import 'github_reconciler.dart';

/// Injectable polling delay.
typedef PollDelay = Future<void> Function(Duration duration);

/// Injectable polling clock.
typedef PollClock = DateTime Function();

/// Serializes and start-spaces poll requests sharing an installation quota.
class GitHubPollCoordinator {
  /// Creates an installation-aware coordinator.
  GitHubPollCoordinator({
    this.minimumSpacing = const Duration(seconds: 5),
    PollDelay? delay,
    PollClock? now,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  /// The DEFAULT minimum time between starts under one key — what a caller
  /// that requests no spacing of its own gets.
  final Duration minimumSpacing;
  final PollDelay _delay;
  final PollClock _now;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};
  final Map<String, DateTime> _lastStarts = <String, DateTime>{};
  final Map<String, Duration> _lastSpacings = <String, Duration>{};

  /// Schedules [request] behind work already queued under [key], and RETURNS
  /// its result.
  ///
  /// [key] is an opaque quota identity, not necessarily an installation: the
  /// token-less foreign read lane schedules under its own key so its 60-per-hour
  /// allowance can never be spent by an installation poll, nor the reverse.
  ///
  /// The result is returned so a scheduled REQUEST — not just a whole cycle —
  /// can ride the budget: a foreign GET has a response its caller needs.
  ///
  /// [minimumSpacing] is THIS cycle's request, defaulting to the coordinator's
  /// own. One key is now shared by every repository on an installation, and two
  /// repositories may each configure their own rate, so the spacing cannot be a
  /// property of the coordinator alone. The interval between two starts is the
  /// MAXIMUM of what the previous start asked for and what the next one asks —
  /// in either ordering — so the stricter of two adjacent cycles is honoured
  /// and a loose repository can never spend a strict one's reserve. Once the
  /// strict repository leaves the pair, only the one boundary from its last
  /// start stays strict; later lower/lower pairs use the lower interval.
  ///
  /// This spacing is a TRANSPORT RATE, not a schedule: it decides how closely
  /// two requests may follow one another, never when reconciliation happens.
  /// That decision belongs to the station tick (see
  /// [GitHubReconciliationQuery]).
  Future<T> schedule<T>(
    String key,
    Future<T> Function() request, {
    Duration? minimumSpacing,
  }) {
    final requested = minimumSpacing ?? this.minimumSpacing;
    final prior = _tails[key] ?? Future<void>.value();
    late final Future<T> run;
    run = prior
        .catchError((Object _) {})
        .then<T>((_) async {
          final last = _lastStarts[key];
          if (last != null) {
            final previous = _lastSpacings[key] ?? this.minimumSpacing;
            final required = requested > previous ? requested : previous;
            final wait = required - _now().difference(last);
            if (wait > Duration.zero) await _delay(wait);
          }
          _lastStarts[key] = _now();
          _lastSpacings[key] = requested;
          return request();
        })
        .whenComplete(() {
          if (identical(_tails[key], run)) _tails.remove(key);
        });
    _tails[key] = run;
    return run;
  }
}

/// One resident seat's reconciliation WORK — and nothing about its schedule.
///
/// It owns no loop, no interval and no lifecycle: [runOnce] is invoked by the
/// station's fenced service tick through [GitHubReconciliationQuery]. A poll
/// that owned its own loop could not raise its own funeral — when it died,
/// the only thing that would have reported the death was the thing that died
/// — so the decision of WHEN reconciliation runs, and the accounting of when
/// it stops, belong to the station.
class GitHubReconcilerRuntime {
  /// Creates a runtime.
  GitHubReconcilerRuntime({
    required this.installationId,
    required this.reconciler,
    required this.coordinator,
    Duration? minimumSpacing,
    this.onError,
  }) : minimumSpacing = minimumSpacing ?? coordinator.minimumSpacing;

  /// Quota-sharing installation identity.
  final String installationId;

  /// Bound per-seat reconciler.
  final GitHubReconciler reconciler;

  /// Shared installation coordinator.
  ///
  /// SHARED in production: one instance is owned at station scope and injected
  /// into every repository's runtime, so [installationId] is what partitions
  /// the budget rather than the instance.
  final GitHubPollCoordinator coordinator;

  /// THIS seat's requested minimum time between starts on [installationId].
  ///
  /// Defaults to [coordinator]'s own, which is what a direct construction over
  /// a dedicated coordinator has always meant. The production factory passes
  /// the repository's configured value instead, because the shared coordinator
  /// carries no single seat's rate.
  final Duration minimumSpacing;

  /// Optional failure observer — the seat's own local report.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Reconciles EXACTLY once, behind this installation's request budget.
  ///
  /// A failure is reported to [onError] and then RETHROWN: the local flare is
  /// what an operator reads on the seat, and the rethrow is what the station
  /// tick accounts for as a refusal. Reporting without rethrowing would put
  /// the seat back in the posture this design exists to retire — a failure
  /// visible only where nobody is counting.
  Future<void> runOnce() async {
    try {
      await coordinator.schedule<void>(
        installationId,
        reconciler.reconcileOnce,
        minimumSpacing: minimumSpacing,
      );
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      rethrow;
    }
  }
}

/// The STATION-REGISTERED standing query that runs seat reconciliation on the
/// fenced service tick.
///
/// A station authors ONE of these, registers it in
/// `TrajectoryConfig.obligationQueryExtensions`, and every live
/// `GitHubReconcilerAssets` under that config attaches its runtime here. The
/// tick then owns the cadence, and a seat that stops reconciling shows up in
/// the pass telemetry as a refusal against [name] instead of as silence.
///
/// It adds no scheduler, daemon or side loop of its own: [repair] runs when —
/// and only when — the ratified tick calls it.
final class GitHubReconciliationQuery extends ObligationQuery {
  /// Creates an unattached query.
  GitHubReconciliationQuery();

  /// The insertion-ordered set of seats this query reconciles. A `Set` because
  /// [attach] is idempotent: a rebuild that re-attaches the same runtime must
  /// not double its requests.
  final Set<GitHubReconcilerRuntime> _attached = <GitHubReconcilerRuntime>{};

  @override
  String get name => 'github-reconciliation';

  /// The tick's standing SELECT.
  ///
  /// Deliberately a constant row rather than a projection read: the external
  /// state this obligation repairs is GITHUB, which no local projection can
  /// see. The obligation is therefore always open — the repair is what decides
  /// there was nothing to do — and it appends nothing, so a pass carrying it
  /// stays quiet.
  @override
  String get sql => 'SELECT 1 AS github_reconciliation_due';

  /// Attaches [runtime] so the next tick reconciles it. Idempotent.
  void attach(GitHubReconcilerRuntime runtime) => _attached.add(runtime);

  /// Detaches [runtime] — the seat stops riding the tick at once. Idempotent,
  /// and safe for a runtime that was never attached.
  void detach(GitHubReconcilerRuntime runtime) => _attached.remove(runtime);

  /// Whether [runtime] currently rides this query.
  bool isAttached(GitHubReconcilerRuntime runtime) =>
      _attached.contains(runtime);

  /// The seats attached right now, in attachment order.
  Iterable<GitHubReconcilerRuntime> get attached =>
      List<GitHubReconcilerRuntime>.unmodifiable(_attached);

  /// Reconciles every attached seat once, then appends nothing.
  ///
  /// The set is SNAPSHOT first: a seat that mounts or unmounts mid-repair
  /// joins or leaves at the next pass rather than mutating the set under the
  /// iteration. A throwing seat fails the whole repair — that is the point,
  /// since a refusal against [name] is the tick's record that this seat's
  /// reconciliation is not running.
  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final seats = List<GitHubReconcilerRuntime>.of(_attached);
    await Future.wait<void>(seats.map((seat) => seat.runOnce()));
    return const <ObligationAppend>[];
  }
}
