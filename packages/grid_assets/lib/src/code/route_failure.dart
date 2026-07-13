/// The LOUD failure channel of a [RouteCapability] body (M5 D-4a).
///
/// A route emits a `RouteVerdict {Advance, Rewind, Escalate}` — there is NO
/// failure arm. `RouteAllocation` (grid_engine `sdk/route.dart`) catches a
/// throwing body and sinks `AllocationFailed('route threw: $e')`, so THROWING is
/// how a route routes itself to supervision (ADR-0008 Decision 10, the per-work
/// fail-closed posture) — and it is also the cancellation unwind, because the
/// allocation swallows a throw whose token is already cancelled.
///
/// A bare `StateError` would stamp `Bad state:` into the FT-1 `failureReason` an
/// operator reads; this carries the reason VERBATIM instead.
library;

/// A route body's failure — its [reason] rides the node's `failureReason`
/// unmodified (beyond the engine's `route threw: ` prefix).
class RouteFailure implements Exception {
  /// Creates the failure with a human-readable [reason].
  const RouteFailure(this.reason);

  /// Why the route could not decide.
  final String reason;

  @override
  String toString() => reason;
}

/// The cancellation unwind — a route that observes `StepArgs.cancel` set after an
/// async gap throws this. `RouteAllocation` drops it silently (it checks the
/// token before sinking), so it can never record a stale terminal.
const RouteFailure kRouteCancelled = RouteFailure('cancelled');
