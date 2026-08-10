import 'dart:async';

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

  /// Minimum time between starts under one installation.
  final Duration minimumSpacing;
  final PollDelay _delay;
  final PollClock _now;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};
  final Map<String, DateTime> _lastStarts = <String, DateTime>{};

  /// Schedules [request] behind work for [installationId].
  Future<void> schedule(
    String installationId,
    Future<void> Function() request,
  ) {
    final prior = _tails[installationId] ?? Future<void>.value();
    late final Future<void> run;
    run = prior
        .catchError((Object _) {})
        .then((_) async {
          final last = _lastStarts[installationId];
          if (last != null) {
            final wait = minimumSpacing - _now().difference(last);
            if (wait > Duration.zero) await _delay(wait);
          }
          _lastStarts[installationId] = _now();
          await request();
        })
        .whenComplete(() {
          if (identical(_tails[installationId], run)) {
            _tails.remove(installationId);
          }
        });
    _tails[installationId] = run;
    return run;
  }
}

/// Owns one resident seat's staggered polling lifecycle.
class GitHubReconcilerRuntime {
  /// Creates a runtime.
  GitHubReconcilerRuntime({
    required this.installationId,
    required this.reconciler,
    required this.coordinator,
    this.interval = const Duration(minutes: 1),
    PollDelay? delay,
    this.onError,
  }) : _delay = delay ?? Future<void>.delayed;

  /// Quota-sharing installation identity.
  final String installationId;

  /// Bound per-seat reconciler.
  final GitHubReconciler reconciler;

  /// Shared installation coordinator.
  final GitHubPollCoordinator coordinator;

  /// Delay between polling attempts.
  final Duration interval;

  /// Optional failure observer.
  final void Function(Object error, StackTrace stackTrace)? onError;
  final PollDelay _delay;
  bool _running = false;
  Future<void>? _loop;
  Completer<void>? _stopSignal;

  /// Starts the loop once and returns immediately.
  void start() {
    if (_running) return;
    _running = true;
    _stopSignal = Completer<void>();
    _loop = _run(_stopSignal!);
  }

  Future<void> _run(Completer<void> stopSignal) async {
    while (_running) {
      try {
        await coordinator.schedule(installationId, reconciler.reconcileOnce);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
      if (!_running) break;
      await Future.any<void>(<Future<void>>[
        _delay(interval),
        stopSignal.future,
      ]);
    }
  }

  /// Stops promptly, awaiting any active reconciliation.
  Future<void> stop() async {
    if (!_running) {
      await _loop;
      return;
    }
    _running = false;
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    await _loop;
  }
}
