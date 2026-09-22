/// LANE HEALTH — the station's own diagnosis of the agent environment it is
/// spawning into, and the blocking marker it publishes when that environment
/// is what broke.
///
/// THE MEASURED INCIDENT. The global codex CLI moved to 0.155.1 at 23:22Z on
/// 2026-09-21; from 23:3xZ every codex session setup refused with `ACP agent
/// does not offer pinned model gpt-5.6-sol`. The station closed each affected
/// session `held`, flared `step.failed failureClass=work`, and let the wedge
/// counter read `0 running`: it attributed an ENVIRONMENT change to the WORK,
/// one bead at a time, burned an attempt per bead, and emitted no
/// station-level condition. Everything that actually diagnosed it — the binary
/// version, its mtime five minutes before the first failure, the resolver's
/// verdict on the offered catalog — a human read by hand.
///
/// WHAT THIS IS. A correlator over one evidence type ([LaneEnvironmentDiagnosis])
/// and one blocking value ([LaneEnvironmentCondition]). Two failed targeted
/// diagnoses for the same lane inside [kLaneFailureCorrelationWindow] PARK the
/// LANE — the registry name, not the bead — and publish one [kLaneDownFlare]
/// carrying the whole record. A later passing diagnosis un-parks it, and the
/// availability seed re-admits the environment, so work held behind it re-mints
/// with no operator rework.
///
/// THE D-H DOCTRINE (ADR-0008 D3; `power_station#a8-…`). This file holds no
/// tree reader. The coordinator exposes ASYNC COMMANDS and a BROADCAST STREAM
/// of immutable conditions — never a public synchronous accessor over its own
/// mutable state. `availability_assets.dart` subscribes to that stream and
/// RE-PROJECTS the condition into the tree, which is where a `build` observes
/// it. The diagnostic probe is DI; only `environment_probe.dart`'s
/// [ProcessLaneEnvironmentProbe] touches the machine.
///
/// **DEPARTURE, DECLARED (`power_station#a38-bead-pow-n6n-3-the-mechanism-of-adr-0006-d3-s-availabili`
/// clause 5).** A38(5) reads: "THE FAILURE SIGNAL is the probe's own failure
/// (false OR a throw) plus a watched dependency change (registry / site
/// binding); an engine-side spawn-failure bus is out of scope because
/// `ServiceBundle.transport` is documented as the OUTBOUND sink with no inbound
/// handle, and the bounded tick is the recovery path." This seam ADDS A THIRD
/// FAILURE SIGNAL that clause scoped out: a session-edge SPAWN failure
/// ([AgentSession]'s `phase: setup` arm) reaching lane health by a direct
/// injected call. That is a departure, not an extension, and it is NOT taken on
/// this seam's own authority — it is taken under Nico's recorded ruling of
/// 2026-09-21, "The station should be able to debug this itself", which is the
/// override A38(5) does not itself provide. A38's stated reason for the
/// exclusion survives intact: `ServiceBundle.transport` is still OUTBOUND-ONLY
/// here — it carries the flare OUT and is never read as an inbound bus — and
/// the bounded tick is still the recovery path ([confirmScheduledRecovery]).
/// What changed is only WHO may hand lane health a failure, and the measured
/// incident is the evidence that the two signals A38(5) allowed cannot see this
/// class at all: the boolean probe passed throughout (the binary was present
/// and the provider was reachable), and no watched dependency changed.
library;

import 'dart:async';

import 'agent_environment.dart';
import 'model_tier.dart';

/// How long two failures must land within to be ONE lane condition.
///
/// THIRTY MINUTES, bounded on purpose: the measured incident put the CLI
/// upgrade at 23:22Z and the first refusal at 23:3xZ, and every subsequent seat
/// failed inside the same half hour. Wider would correlate a fault with a fix
/// that already landed between them; narrower would miss a lane whose seats
/// only spawn a few times an hour.
const Duration kLaneFailureCorrelationWindow = Duration(minutes: 30);

/// The ONE station-level condition this seam publishes: a named lane is down,
/// and the flare carries the whole diagnosis.
///
/// ONE line, not a log to correlate: `codex lane down since 2026-09-21T23:22Z:
/// binary 0.155.1 at /opt/homebrew/bin/codex (changed 2026-09-21T23:22Z), pin
/// gpt-5.6-sol not resolvable against […]`.
const String kLaneDownFlare = 'lane.down';

/// The out-of-band flare sink, as a plain function.
///
/// Passed IN at each call rather than held, so this coordinator owns no
/// transport: `ServiceBundle.transport` stays the caller's to read, and stays
/// OUTBOUND-ONLY.
typedef LaneFlare = void Function(String name, Map<String, String> data);

/// WHICH lane a diagnosis is about, and everything needed to re-ask the
/// question: the registry [lane] name, the FLATTENED [environment] armed under
/// it, the model [pin] the spawn resolved, and the seat [tier] that pinned it.
///
/// A pure VALUE (config = VALUES in the tree). The tier is carried rather than
/// re-derived because an ACP agent names the reasoning effort INSIDE the model
/// id, so the same pin resolves differently per rung — and the resolver's
/// verdict is meaningless without it.
class LaneEnvironmentTarget {
  /// Creates the target over its [lane] name, [environment], [pin] and [tier].
  const LaneEnvironmentTarget({
    required this.lane,
    required this.environment,
    required this.tier,
    this.pin,
  });

  /// The armed registry name — the LANE. Parking keys on this, never on a bead.
  final String lane;

  /// The flattened environment armed under [lane].
  final AgentEnvironment environment;

  /// The seat rung this spawn declared.
  final AgentTier tier;

  /// The model pin this spawn resolved, or null when the lane pins none.
  final String? pin;

  @override
  bool operator ==(Object other) =>
      other is LaneEnvironmentTarget &&
      other.lane == lane &&
      other.environment == environment &&
      other.tier == tier &&
      other.pin == pin;

  @override
  int get hashCode => Object.hash(lane, environment, tier, pin);

  @override
  String toString() => 'LaneEnvironmentTarget($lane, $pin, ${tier.name})';
}

/// The agent binary as the station FOUND it: where it resolved, what it says
/// its version is, and when it was last written.
///
/// The mtime is the load-bearing field. In the measured incident it is what
/// turned "every codex seat is failing" into "the CLI changed five minutes
/// before the first failure" — a fact no bead, log line or retry could carry.
class LaneBinaryFingerprint {
  /// Creates the fingerprint; every field is nullable because an inspection
  /// that could not answer must say so rather than invent a value.
  const LaneBinaryFingerprint({this.path, this.version, this.mtime});

  /// Nothing could be inspected at all.
  static const LaneBinaryFingerprint unknown = LaneBinaryFingerprint();

  /// The absolute path the lane's binary resolved to.
  final String? path;

  /// The version the binary reports.
  final String? version;

  /// When the binary was last written, in UTC.
  final DateTime? mtime;

  @override
  bool operator ==(Object other) =>
      other is LaneBinaryFingerprint &&
      other.path == path &&
      other.version == version &&
      other.mtime == mtime;

  @override
  int get hashCode => Object.hash(path, version, mtime);

  @override
  String toString() => 'LaneBinaryFingerprint($path, $version, $mtime)';
}

/// ONE targeted or scheduled question about a lane's environment.
class LaneEnvironmentProbeRequest {
  /// Creates the request over its [target] and the [offered] model catalog.
  ///
  /// [scheduled] separates the two legs: a TARGETED probe answers a setup
  /// refusal that just happened, so only the resolver accepting the catalog the
  /// agent actually offered can clear it; a SCHEDULED probe is the bounded
  /// recovery tick, so a REPLACED binary ([priorBinary] differs) re-admits the
  /// lane for exactly one handshake.
  const LaneEnvironmentProbeRequest({
    required this.target,
    required this.offered,
    required this.scheduled,
    this.pin,
    this.priorBinary,
  });

  /// The lane being asked about.
  final LaneEnvironmentTarget target;

  /// The model ids the agent offered — observed at the refusal, or retained
  /// from the down record on a scheduled recheck.
  final List<String> offered;

  /// Whether this is the bounded recovery tick rather than a setup refusal.
  final bool scheduled;

  /// The pin the refusal named, when the bridge declared one; null falls back
  /// to [LaneEnvironmentTarget.pin].
  final String? pin;

  /// The binary fingerprint recorded when this lane went down, so a scheduled
  /// recheck can tell a REPLACEMENT from the same broken binary.
  final LaneBinaryFingerprint? priorBinary;

  @override
  String toString() =>
      'LaneEnvironmentProbeRequest(${target.lane}, scheduled: $scheduled)';
}

/// The ANSWER: the lane's environment as the station just measured it.
class LaneEnvironmentDiagnosis {
  /// Creates the diagnosis.
  const LaneEnvironmentDiagnosis({
    required this.lane,
    required this.observedAt,
    required this.binary,
    required this.offered,
    required this.resolverVerdict,
    required this.passed,
    this.pin,
  });

  /// The armed registry name this diagnosis is about.
  final String lane;

  /// When it was taken, in UTC.
  final DateTime observedAt;

  /// The agent binary as found.
  final LaneBinaryFingerprint binary;

  /// The model pin under test, or null when the lane pins none.
  final String? pin;

  /// The ids the agent offered.
  final List<String> offered;

  /// What the RESOLVER said about [pin] against [offered] at [observedAt] —
  /// the refusal prose an operator reads the cure from, or the id it resolved.
  final String resolverVerdict;

  /// Whether the lane is healthy as of [observedAt].
  final bool passed;

  @override
  String toString() =>
      'LaneEnvironmentDiagnosis($lane, passed: $passed, $resolverVerdict)';
}

/// A lane diagnosis, on demand. Injected — impls are DI; the real one is
/// `ProcessLaneEnvironmentProbe` (`environment_probe.dart`).
typedef LaneEnvironmentDiagnosticProbe =
    Future<LaneEnvironmentDiagnosis> Function(
      LaneEnvironmentProbeRequest request,
    );

/// One session-edge SETUP refusal, as the bridge declared it.
///
/// This is the evidence A38(5) did not have a channel for — see the library
/// docstring's declared departure.
class LaneEnvironmentSetupFailure {
  /// Creates the report over its [target] and the bridge-authored evidence.
  const LaneEnvironmentSetupFailure({
    required this.target,
    this.offered = const <String>[],
    this.pin,
    this.resolverVerdict,
  });

  /// The lane the refused spawn was aimed at.
  final LaneEnvironmentTarget target;

  /// The ids the agent offered at the refusal (empty when the setup failed
  /// before a catalog existed at all — a dead binary, a failed handshake).
  final List<String> offered;

  /// The pin the bridge named, when it named one.
  final String? pin;

  /// The bridge's own refusal prose, when it authored one.
  final String? resolverVerdict;
}

/// WHICH lanes are currently PARKED, and the diagnosis that parked each.
///
/// An immutable VALUE: `availability_assets.dart` re-projects it into the tree
/// and a `build` reads it there. Absence of a lane from [down] is the whole of
/// "this lane is fine" — there is no second health field to disagree with it.
class LaneEnvironmentCondition {
  /// Creates the condition over [down] (lane name -> the parking diagnosis).
  LaneEnvironmentCondition(Map<String, LaneEnvironmentDiagnosis> down)
    : down = Map<String, LaneEnvironmentDiagnosis>.unmodifiable(down);

  const LaneEnvironmentCondition._empty()
    : down = const <String, LaneEnvironmentDiagnosis>{};

  /// Nothing is parked (mirrors `SiteBinding.none`).
  static const LaneEnvironmentCondition none =
      LaneEnvironmentCondition._empty();

  /// The parked lanes, by registry name.
  final Map<String, LaneEnvironmentDiagnosis> down;

  /// Whether [lane] is parked — no spawn may be minted on it.
  bool isDown(String lane) => down.containsKey(lane);

  @override
  bool operator ==(Object other) =>
      other is LaneEnvironmentCondition &&
      other.down.length == down.length &&
      other.down.keys.every((lane) => identical(other.down[lane], down[lane]));

  @override
  int get hashCode => Object.hashAllUnordered(down.keys);

  @override
  String toString() => 'LaneEnvironmentCondition(${down.keys.toList()})';
}

/// The station's lane-health coordinator seam.
///
/// ASYNC COMMANDS and a STREAM, and nothing else: no synchronous accessor over
/// the correlation state escapes (the D-H doctrine's second bullet).
abstract interface class LaneEnvironmentHealth {
  /// Every published condition, most recent last. A BROADCAST stream, so the
  /// availability seed and a test can both observe the same transitions.
  Stream<LaneEnvironmentCondition> get conditions;

  /// Records one session-edge setup refusal and correlates it.
  ///
  /// The diagnosis this takes decides BOTH directions: a failing one accrues
  /// toward a park, and a passing one against a lane already parked un-parks
  /// it there and then, without waiting for the bounded tick.
  ///
  /// Returns the diagnosis it took, so a caller that wants the evidence has it
  /// without reading state back. [flare] is the ambient transport's own emit
  /// function; NULL simply drops the flare — an absent carrier is never a
  /// session failure.
  Future<LaneEnvironmentDiagnosis> recordSetupFailure(
    LaneEnvironmentSetupFailure failure, {
    LaneFlare? flare,
  });

  /// Asks whether a PARKED [lane] may be re-admitted, given that the ordinary
  /// boolean presence probe just said [present].
  ///
  /// True un-parks it. An unparked or unknown lane answers true — this verb
  /// narrows the presence set, it never widens it.
  Future<bool> confirmScheduledRecovery({
    required String lane,
    required bool present,
  });
}

/// The correlating implementation: two failed targeted diagnoses for one lane
/// inside [kLaneFailureCorrelationWindow] park it.
///
/// TWO, not one: a single refusal can be one bad pin on one bead, and parking a
/// whole lane on it would be the same over-attribution in the other direction.
/// Two failures naming the same lane inside one window are an ENVIRONMENT.
class CorrelatingLaneEnvironmentHealth implements LaneEnvironmentHealth {
  /// Creates the coordinator over its injected diagnostic [probe] and clock.
  CorrelatingLaneEnvironmentHealth({
    required this.probe,
    DateTime Function() now = _systemNow,
  }) : _now = now;

  /// The injected diagnostic probe (impls are DI).
  final LaneEnvironmentDiagnosticProbe probe;

  final DateTime Function() _now;
  final Map<String, List<LaneEnvironmentDiagnosis>> _failures =
      <String, List<LaneEnvironmentDiagnosis>>{};
  final Map<String, LaneEnvironmentDiagnosis> _down =
      <String, LaneEnvironmentDiagnosis>{};
  final Map<String, LaneEnvironmentTarget> _targets =
      <String, LaneEnvironmentTarget>{};

  /// SYNCHRONOUS on purpose. The park must be published BEFORE the command
  /// that earned it completes, because supervision asks for the next spawn off
  /// the very failure report [recordSetupFailure] is holding open — and an
  /// asynchronous delivery lands one event-loop turn behind that request. That
  /// is the third spawn the live incident served while the second failure was
  /// still being classified. The subscriber's own work stays cheap and
  /// re-entrancy-free: it mints a pass marker and returns.
  final StreamController<LaneEnvironmentCondition> _conditions =
      StreamController<LaneEnvironmentCondition>.broadcast(sync: true);

  static DateTime _systemNow() => DateTime.now().toUtc();

  @override
  Stream<LaneEnvironmentCondition> get conditions => _conditions.stream;

  @override
  Future<LaneEnvironmentDiagnosis> recordSetupFailure(
    LaneEnvironmentSetupFailure failure, {
    LaneFlare? flare,
  }) async {
    final lane = failure.target.lane;
    _targets[lane] = failure.target;
    final diagnosis = await probe(
      LaneEnvironmentProbeRequest(
        target: failure.target,
        offered: failure.offered,
        scheduled: false,
        pin: failure.pin,
      ),
    );
    if (diagnosis.passed) {
      // The environment answers correctly RIGHT NOW, so whatever refused this
      // spawn was not the lane. Clear the correlation rather than accruing
      // toward a park the evidence does not support.
      final wasDown = _down.containsKey(lane);
      _clear(lane);
      // RECOVERY BY THE TARGETED LEG. A spawn already in flight when the lane
      // went down answers the recovery question just as well as the bounded
      // tick does — and sooner. Publishing here is what un-parks it; the tick
      // ([confirmScheduledRecovery]) remains the path for a lane with no
      // in-flight work left to ask on.
      //
      // Only on a real TRANSITION: a passing probe against a lane that was
      // never down has nothing to say, and republishing an unchanged empty
      // condition would churn every subscriber for it.
      if (wasDown) _publish();
      return diagnosis;
    }
    final window = _correlated(lane)..add(diagnosis);
    _failures[lane] = window;
    if (window.length < 2 || _down.containsKey(lane)) return diagnosis;
    _down[lane] = diagnosis;
    // ONE flare per down condition, carrying the WHOLE record: the operator
    // reads the cause in one line instead of correlating N held beads.
    flare?.call(kLaneDownFlare, laneDownFlareFields(diagnosis, window.first));
    _publish();
    return diagnosis;
  }

  @override
  Future<bool> confirmScheduledRecovery({
    required String lane,
    required bool present,
  }) async {
    final recorded = _down[lane];
    final target = _targets[lane];
    // Not parked: this verb NARROWS the presence set and never widens it.
    if (recorded == null || target == null) return true;
    // The ordinary boolean probe is the floor — a lane whose binary is gone is
    // absent for the older, simpler reason and needs no second opinion.
    if (!present) return false;
    final diagnosis = await probe(
      LaneEnvironmentProbeRequest(
        target: target,
        offered: recorded.offered,
        scheduled: true,
        pin: recorded.pin,
        priorBinary: recorded.binary,
      ),
    );
    if (!diagnosis.passed) return false;
    _clear(lane);
    _publish();
    return true;
  }

  /// Drops correlated failures that fell out of the window, newest kept.
  List<LaneEnvironmentDiagnosis> _correlated(String lane) {
    final floor = _now().subtract(kLaneFailureCorrelationWindow);
    return <LaneEnvironmentDiagnosis>[
      for (final seen in _failures[lane] ?? const <LaneEnvironmentDiagnosis>[])
        if (!seen.observedAt.isBefore(floor)) seen,
    ];
  }

  void _clear(String lane) {
    _failures.remove(lane);
    _down.remove(lane);
  }

  void _publish() {
    if (_conditions.isClosed) return;
    _conditions.add(LaneEnvironmentCondition(_down));
  }

  /// Releases the condition stream. Idempotent.
  Future<void> dispose() async {
    if (_conditions.isClosed) return;
    await _conditions.close();
  }
}

/// The [kLaneDownFlare] payload for [diagnosis], whose lane first failed at
/// [first].
///
/// EXACTLY nine keys, always all of them: a reader that has to test for a key's
/// presence is back to correlating logs. An unknown fact renders
/// [kLaneFactUnknown] rather than being omitted.
///
/// `since` prefers the BINARY MTIME — in the measured incident that is 23:22Z,
/// the moment the environment actually changed, five minutes ahead of the first
/// failure the station could see.
Map<String, String> laneDownFlareFields(
  LaneEnvironmentDiagnosis diagnosis,
  LaneEnvironmentDiagnosis first,
) {
  final since = diagnosis.binary.mtime ?? first.observedAt;
  return <String, String>{
    'lane': diagnosis.lane,
    'since': _stamp(since),
    'binaryPath': diagnosis.binary.path ?? kLaneFactUnknown,
    'binaryVersion': diagnosis.binary.version ?? kLaneFactUnknown,
    'binaryMtime': diagnosis.binary.mtime == null
        ? kLaneFactUnknown
        : _stamp(diagnosis.binary.mtime!),
    'pin': diagnosis.pin ?? kLaneFactUnknown,
    'offered': diagnosis.offered.join(', '),
    'resolverVerdict': diagnosis.resolverVerdict,
    'summary': laneDownSummary(diagnosis, since),
  };
}

/// What an unmeasurable fact renders as — NAMED, so a reader can tell "the
/// station could not read this" from "the station read an empty value".
const String kLaneFactUnknown = 'unknown';

/// The ONE LINE an operator reads the whole incident from.
String laneDownSummary(LaneEnvironmentDiagnosis diagnosis, DateTime since) {
  final version = diagnosis.binary.version ?? kLaneFactUnknown;
  final path = diagnosis.binary.path ?? kLaneFactUnknown;
  final changed = diagnosis.binary.mtime == null
      ? kLaneFactUnknown
      : _stamp(diagnosis.binary.mtime!);
  final pin = diagnosis.pin ?? kLaneFactUnknown;
  return '${diagnosis.lane} lane down since ${_stamp(since)}: '
      'binary $version at $path (changed $changed), '
      'pin $pin not resolvable against [${diagnosis.offered.join(', ')}]';
}

String _stamp(DateTime at) => at.toUtc().toIso8601String();
