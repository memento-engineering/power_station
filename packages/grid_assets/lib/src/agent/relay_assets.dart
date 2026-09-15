/// The PROTECTIVE RELAY asset — the read-only observer a station mounts for
/// its own stuck sessions, and the seed that arms it from the tree.
///
/// A relay in the power-grid sense the governor is already named for: the
/// device that SENSES an abnormal condition and DECIDES whether the desired
/// state must change. It is NEVER the breaker. Nothing here closes a session,
/// kills a process, writes a bead, moves a worktree or clears a gate; the one
/// thing this asset produces is a [RelayVerdict], and the engine
/// (`WorkSessionLiveness`) is what acts on it.
///
/// The posture is `memento-engineering#protect-the-governor`, rules 4 and 5,
/// in code:
///
///  - **ABSORB BY DEFAULT.** A mounted relay's default verdict is to absorb the
///    signal with a positive next horizon. Escalation is the exception and owes
///    a concrete reason.
///  - **FAILURE ESCALATES.** A relay that cannot answer must FAIL, never
///    manufacture an absorb. Every failure here — an unreachable reader, a dead
///    inference call, a malformed answer — is thrown, and the engine turns a
///    thrown observation into `kRelayErrorFlare`. An absorb that was never
///    decided is the one outcome this library will not produce.
///
/// **Five named surfaces, four of them read-only.** [kRelayToolAllowList] is
/// the exact tool set a relay may reach: the session's worktree mtimes and last
/// commit, its flare tail, its telemetry usage records, and any open gate —
/// plus the ONE write it owns, its own verdict. [RelayReadTools] binds the four
/// read names to injected implementations and REFUSES loudly when the armed
/// seat names a different set. The `verdict.write` name is implemented by
/// decoding the inference answer into the returned verdict and by nothing else.
///
/// **The D-H doctrine (ADR-0008; ADR-0000 A8).** [RelayAssets] reads every
/// ambient value in `build` with the SUBSCRIBING verb, selects the relay by
/// EXACT type (ADR-0006 D2 — a generic [ModelPreference] never manufactures a
/// relay), takes its readers and its runner as injected impls, and exposes no
/// synchronous accessor over its own mutable state.
library;

import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'environment_registry.dart';
import 'seat_environments.dart';
import 'typed_environment.dart';

/// The read tool naming a session's worktree evidence — its per-path modified
/// times and its last commit. The governor disc's dead-session lesson: worktree
/// mtimes are the signal that separates a long build from a stopped one.
const String kRelayWorktreeReadTool = 'worktree.read';

/// The read tool naming the tail of the session's observability flares.
const String kRelayFlaresReadTool = 'flares.read';

/// The read tool naming the session's captured usage telemetry records.
const String kRelayTelemetryReadTool = 'telemetry.read';

/// The read tool naming the session's open gate, if it is parked at one.
const String kRelayGatesReadTool = 'gates.read';

/// The ONE write a relay owns: its own verdict. It writes no session, no
/// horizon, no flare, no bead — the verdict is the return value, and the engine
/// persists whatever follows from it.
const String kRelayVerdictWriteTool = 'verdict.write';

/// The EXACT tool set a relay may reach — four read-only inspections and the
/// one verdict write. A `RelayAgentEnvironment.tools` that is not equal to this
/// set is refused by [RelayReadTools.inspect] before any reader runs.
const Set<String> kRelayToolAllowList = <String>{
  kRelayWorktreeReadTool,
  kRelayFlaresReadTool,
  kRelayTelemetryReadTool,
  kRelayGatesReadTool,
  kRelayVerdictWriteTool,
};

/// What `worktree.read` returns: the session worktree's per-path modified times
/// plus its last commit and when that commit landed.
class RelayWorktreeSnapshot {
  /// Creates the snapshot; [mtimes] is copied defensively.
  RelayWorktreeSnapshot({
    required Map<String, DateTime> mtimes,
    required this.lastCommit,
    required this.lastCommitAt,
  }) : mtimes = Map<String, DateTime>.unmodifiable(mtimes);

  /// Modified time per worktree-relative path. Unmodifiable.
  final Map<String, DateTime> mtimes;

  /// The worktree's last commit (subject or sha — whatever the reader vends).
  final String lastCommit;

  /// When that last commit landed.
  final DateTime lastCommitAt;

  /// This snapshot as the brief's canonical evidence object. Paths are sorted
  /// lexically so the same worktree renders the same JSON every time.
  Map<String, Object?> toJson() => <String, Object?>{
    'mtimes': <String, Object?>{
      for (final path in mtimes.keys.toList()..sort())
        path: _instant(mtimes[path]!),
    },
    'lastCommit': lastCommit,
    'lastCommitAt': _instant(lastCommitAt),
  };
}

/// What `flares.read` returns, one row: an observability flare the session
/// emitted.
class RelayFlareRecord {
  /// Creates the record; [data] is copied defensively.
  RelayFlareRecord({
    required this.occurredAt,
    required this.name,
    required Map<String, String> data,
  }) : data = Map<String, String>.unmodifiable(data);

  /// When the flare was emitted.
  final DateTime occurredAt;

  /// The flare name (`relay.error`, a circuit's own name, …).
  final String name;

  /// The flare's payload. Unmodifiable.
  final Map<String, String> data;

  /// This flare as the brief's canonical evidence object; payload keys sorted.
  Map<String, Object?> toJson() => <String, Object?>{
    'occurredAt': _instant(occurredAt),
    'name': name,
    'data': <String, Object?>{
      for (final key in data.keys.toList()..sort()) key: data[key],
    },
  };
}

/// What `telemetry.read` returns, one row: the usage captured at one circuit
/// node of the session.
class RelayTelemetryRecord {
  /// Creates the record; [usage] is copied defensively.
  RelayTelemetryRecord({
    required this.nodePath,
    required Map<String, String> usage,
  }) : usage = Map<String, String>.unmodifiable(usage);

  /// The circuit node this usage was captured at (`<bead>/<step>`).
  final String nodePath;

  /// The captured usage fields (tokens, cost, model, an error marker, …).
  /// Unmodifiable.
  final Map<String, String> usage;

  /// This record as the brief's canonical evidence object; usage keys sorted.
  Map<String, Object?> toJson() => <String, Object?>{
    'nodePath': nodePath,
    'usage': <String, Object?>{
      for (final key in usage.keys.toList()..sort()) key: usage[key],
    },
  };
}

/// What `gates.read` returns: the gate a session is parked at, if any.
class RelayGateRecord {
  /// Creates the gate record.
  const RelayGateRecord({
    required this.id,
    required this.reason,
    required this.awaitingHuman,
  });

  /// The gate's own id.
  final String id;

  /// Why the session is parked here.
  final String reason;

  /// Whether a HUMAN owns this gate. A session parked on a human is not stuck
  /// in the sense a relay escalates for — it is already where it belongs.
  final bool awaitingHuman;

  /// This gate as the brief's canonical evidence object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'reason': reason,
    'awaitingHuman': awaitingHuman,
  };
}

/// ONE session, as the relay sees it: the engine's [RelayObservation] plus
/// everything the four read tools returned for it.
///
/// A pure VALUE — every collection is copied at construction and handed back
/// unmodifiable, so the brief a relay reasons over cannot be edited underneath
/// it.
class RelaySessionSnapshot {
  /// Creates the snapshot; [flares] and [telemetry] are copied defensively.
  RelaySessionSnapshot({
    required this.observation,
    required this.worktree,
    required List<RelayFlareRecord> flares,
    required List<RelayTelemetryRecord> telemetry,
    this.openGate,
  }) : flares = List<RelayFlareRecord>.unmodifiable(flares),
       telemetry = List<RelayTelemetryRecord>.unmodifiable(telemetry);

  /// The engine's observation this snapshot answers.
  final RelayObservation observation;

  /// What `worktree.read` returned.
  final RelayWorktreeSnapshot worktree;

  /// What `flares.read` returned, in the order the reader vended it.
  /// Unmodifiable.
  final List<RelayFlareRecord> flares;

  /// What `telemetry.read` returned, in the order the reader vended it.
  /// Unmodifiable.
  final List<RelayTelemetryRecord> telemetry;

  /// What `gates.read` returned; null when the session is parked at no gate.
  final RelayGateRecord? openGate;

  /// The CANONICAL evidence object the brief carries — one nested JSON value
  /// over all five reads. Map keys inside each read are sorted; the flare and
  /// telemetry ROWS keep the order their reader vended, because that order is
  /// itself evidence.
  Map<String, Object?> toJson() => <String, Object?>{
    'observation': <String, Object?>{
      'sessionId': observation.sessionId,
      'workBeadId': observation.workBeadId,
      'startedAt': observation.startedAt == null
          ? null
          : _instant(observation.startedAt!),
      'deadline': _instant(observation.deadline),
      'observedAt': _instant(observation.observedAt),
    },
    'worktree': worktree.toJson(),
    'flares': <Object?>[for (final flare in flares) flare.toJson()],
    'telemetry': <Object?>[for (final record in telemetry) record.toJson()],
    'openGate': openGate?.toJson(),
  };
}

/// Reads the session's worktree evidence (`worktree.read`). Injected.
typedef RelayWorktreeReader =
    Future<RelayWorktreeSnapshot> Function(RelayObservation observation);

/// Reads the tail of the session's flares (`flares.read`). Injected.
typedef RelayFlareTailReader =
    Future<List<RelayFlareRecord>> Function(RelayObservation observation);

/// Reads the session's captured usage telemetry (`telemetry.read`). Injected.
typedef RelayTelemetryReader =
    Future<List<RelayTelemetryRecord>> Function(RelayObservation observation);

/// Reads the session's open gate, if any (`gates.read`). Injected.
typedef RelayGateReader =
    Future<RelayGateRecord?> Function(RelayObservation observation);

/// The relay's READ-ONLY tool surface: the four injected readers behind the
/// four read names, and nothing else.
///
/// It owns no writer, no bead service, no process service, no filesystem
/// handle and no mutable store — the only way a caller reaches a session
/// through this object is by reading it.
class RelayReadTools {
  /// Binds the four read tools to their implementations (impls are DI).
  const RelayReadTools({
    required this.readWorktree,
    required this.readFlareTail,
    required this.readTelemetry,
    required this.readGate,
  });

  /// The `worktree.read` implementation.
  final RelayWorktreeReader readWorktree;

  /// The `flares.read` implementation.
  final RelayFlareTailReader readFlareTail;

  /// The `telemetry.read` implementation.
  final RelayTelemetryReader readTelemetry;

  /// The `gates.read` implementation.
  final RelayGateReader readGate;

  /// Runs all four reads for [observation] and returns the whole snapshot.
  ///
  /// [toolNames] is the ARMED seat's own tool set, and the guard is LOUD: it
  /// must equal [kRelayToolAllowList] exactly. A missing name means the station
  /// armed a relay that cannot see what a verdict requires; an unknown name
  /// means it armed a surface this asset does not implement. Either way the
  /// answer would be decided on an evidence set nobody authorized, so this
  /// throws a [StateError] BEFORE any reader runs.
  ///
  /// All four calls are created before any result is awaited, so one failing
  /// reader cannot hide another's work: every authorized reader is invoked
  /// exactly once, and the first failure — synchronous or asynchronous —
  /// propagates to the caller. Nothing is caught: a relay that cannot read
  /// cannot answer, and it must escalate rather than absorb blind.
  Future<RelaySessionSnapshot> inspect({
    required RelayObservation observation,
    required Set<String> toolNames,
  }) async {
    if (toolNames.length != kRelayToolAllowList.length ||
        !toolNames.containsAll(kRelayToolAllowList)) {
      throw StateError(
        'a relay may reach exactly $kRelayToolAllowList; the armed seat '
        'names $toolNames',
      );
    }
    final pending = <Future<Object?>>[
      Future<RelayWorktreeSnapshot>.sync(() => readWorktree(observation)),
      Future<List<RelayFlareRecord>>.sync(() => readFlareTail(observation)),
      Future<List<RelayTelemetryRecord>>.sync(() => readTelemetry(observation)),
      Future<RelayGateRecord?>.sync(() => readGate(observation)),
    ];
    final read = await Future.wait(pending);
    return RelaySessionSnapshot(
      observation: observation,
      worktree: read[0]! as RelayWorktreeSnapshot,
      flares: read[1]! as List<RelayFlareRecord>,
      telemetry: read[2]! as List<RelayTelemetryRecord>,
      openGate: read[3] as RelayGateRecord?,
    );
  }
}

/// The relay's ONE inference seam: run [brief] on [environment] and return the
/// raw answer.
///
/// DELIBERATELY NOT the process-level `InferenceRunner` in `code/pr_describe.dart`.
/// That seam takes a rendered `RuntimeConfig` — a workspace, an argv, a
/// supervised child — and converts every failure into a not-ok
/// `InferenceResult`, because its callers fall back. A relay has no workspace,
/// no argv, no allocation and no session lifecycle, and it must NOT fall back:
/// a failure here has to stay THROWN so the engine escalates it rather than
/// letting a manufactured answer stand in for a verdict.
abstract interface class RelayInferenceRunner {
  /// Runs [brief] on [environment] and returns the raw answer. Throws on any
  /// failure — a relay that cannot answer escalates.
  Future<String> run({
    required AgentEnvironment environment,
    required AgentBrief brief,
  });
}

/// The relay's BRIEF: the protective-relay mission, the exact tool surface, the
/// whole evidence snapshot, and the answer contract.
///
/// Self-contained by construction (no working agreement, no extra context
/// blocks — the same shape a critic prompt uses): a relay reasons over the
/// evidence it was handed and nothing it could go fetch.
AgentBrief buildRelayBrief(
  RelayAgentEnvironment seat,
  RelaySessionSnapshot snapshot,
) {
  final tools = seat.tools.toList()..sort();
  final task = StringBuffer()
    ..writeln('# Protective relay')
    ..writeln()
    ..writeln('## Mission')
    ..writeln(seat.mission.trim())
    ..writeln()
    ..writeln('## What a relay is')
    ..writeln(
      'You are a PROTECTIVE RELAY over one work session. You SENSE an '
      'abnormal condition and DECIDE whether the desired state must change. '
      'You are NEVER the breaker: you close nothing, kill nothing, write '
      'nothing and clear nothing. A relay decides; something else acts.',
    )
    ..writeln()
    ..writeln('## Your tools')
    ..writeln(
      'You may reach exactly these surfaces, and no others: '
      '${tools.join(', ')}. The first four are READ-ONLY inspections of the '
      'session, already performed for you — their complete results are the '
      'evidence below. `$kRelayVerdictWriteTool` is the only thing you write, '
      'and it is the JSON object you return.',
    )
    ..writeln()
    ..writeln('## Evidence')
    ..writeln(
      'The complete result of every read, as one JSON object. This is all the '
      'evidence there is; there is nothing further to fetch.',
    )
    ..writeln()
    ..writeln(jsonEncode(snapshot.toJson()))
    ..writeln()
    ..writeln('## The rules, non-negotiable')
    ..writeln(
      '1. ABSORB IS THE DEFAULT. Unless escalation is positively justified by '
      'the evidence, absorb the signal and name a POSITIVE next horizon — how '
      'long to leave this session alone before looking again.',
    )
    ..writeln(
      '2. ESCALATION IS EXCEPTIONAL and owes a CONCRETE reason naming what in '
      'the evidence is abnormal. "It might be stuck" is not a reason.',
    )
    ..writeln(
      '3. A HEALTHY LONG BUILD ABSORBS. Long is not stuck: recent worktree '
      'mtimes and continuing telemetry are a session doing its job, however '
      'long it has been running.',
    )
    ..writeln(
      '4. A PAUSED SESSION WHOSE NEWEST WORKTREE ACTIVITY AND LAST COMMIT ARE '
      'TWO DAYS STALE ESCALATES. Nothing has moved; the desired state must '
      'change and only the governor can change it.',
    )
    ..writeln(
      '5. AN ALREADY PARKED HUMAN GATE ABSORBS. A session waiting on a human '
      'is exactly where it belongs; escalating it would wake the governor for '
      'a decision that is already somebody\'s.',
    )
    ..writeln(
      '6. A LANE ERROR ESCALATES. An erroring lane will not fix itself, and '
      'absorbing it buries the failure.',
    )
    ..writeln(
      '7. IF YOU CANNOT ANSWER, FAIL. Do not manufacture an absorb. Returning '
      'an absorb you did not decide is the one unrecoverable outcome: it '
      'silences a signal nobody looked at. Refusing to answer escalates, '
      'which is safe.',
    )
    ..writeln()
    ..writeln('## Your answer')
    ..writeln(
      'Return EXACTLY ONE JSON object and nothing else — no prose before or '
      'after it, no code fence. Exactly one of these two shapes, with no '
      'extra keys and no keys from the other shape:',
    )
    ..writeln()
    ..writeln('{"verdict":"absorb","nextHorizonSeconds":<positive integer>}')
    ..writeln('{"verdict":"escalate","reason":"<nonblank string>"}');
  return AgentBrief(task: task.toString());
}

/// Decodes a relay's raw answer into the engine's [RelayVerdict].
///
/// STRICT, and deliberately so: the brief states one shape, and anything else
/// is an answer this relay did not actually give. A non-object, an unknown
/// verdict, a missing key, an extra key, a key from the other arm, a
/// non-integer or non-positive horizon, and a non-string or blank reason are
/// each a [FormatException]. Malformed JSON throws [jsonDecode]'s own
/// [FormatException] — it is NOT caught, because "cannot answer" must reach the
/// engine as a failure rather than as a manufactured absorb.
RelayVerdict decodeRelayVerdict(String result) {
  final decoded = jsonDecode(result);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('a relay verdict must be a JSON object', result);
  }
  final verdict = decoded['verdict'];
  switch (verdict) {
    case 'absorb':
      _requireKeys(decoded, const {'verdict', 'nextHorizonSeconds'}, result);
      final seconds = decoded['nextHorizonSeconds'];
      if (seconds is! int || seconds <= 0) {
        throw FormatException(
          'an absorb horizon must be a positive integer number of seconds, '
          'not $seconds',
          result,
        );
      }
      return RelayVerdict.absorb(nextHorizon: Duration(seconds: seconds));
    case 'escalate':
      _requireKeys(decoded, const {'verdict', 'reason'}, result);
      final reason = decoded['reason'];
      if (reason is! String || reason.trim().isEmpty) {
        throw FormatException(
          'an escalation must carry a nonblank reason, not $reason',
          result,
        );
      }
      return RelayVerdict.escalate(reason: reason.trim());
    default:
      throw FormatException(
        'a relay verdict is "absorb" or "escalate", not $verdict',
        result,
      );
  }
}

/// Refuses [decoded] unless its keys are EXACTLY [expected] — a missing key is
/// an incomplete answer, an extra one is an answer to a question nobody asked.
void _requireKeys(
  Map<String, Object?> decoded,
  Set<String> expected,
  String source,
) {
  if (decoded.length == expected.length &&
      expected.every(decoded.containsKey)) {
    return;
  }
  throw FormatException(
    'this verdict must carry exactly $expected, not ${decoded.keys.toSet()}',
    source,
  );
}

/// The relay OBSERVER the engine mounts: inspect, brief, infer, decode.
///
/// It CATCHES NOTHING. A reader failure, an inference failure and a malformed
/// answer all complete [observe] with an error, and `WorkSessionLiveness` turns
/// that into `kRelayErrorFlare` with no horizon written — which is exactly the
/// escalation a relay that cannot answer owes (rule 5 of
/// `memento-engineering#protect-the-governor`).
class RelayAgentObserver implements RelayObserver {
  /// Creates the observer over the ARMED [seat], the environment that seat
  /// selected, its read [tools] and its inference [runner].
  const RelayAgentObserver({
    required this.seat,
    required this.environment,
    required this.tools,
    required this.runner,
  });

  /// The armed relay seat — its mission, its tool set and its ceiling.
  final RelayAgentEnvironment seat;

  /// The environment selected from the seat's OWN preference.
  final AgentEnvironment environment;

  /// The four read tools (impls are DI).
  final RelayReadTools tools;

  /// The inference seam (impls are DI).
  final RelayInferenceRunner runner;

  @override
  Future<RelayVerdict> observe(RelayObservation observation) async {
    final snapshot = await tools.inspect(
      observation: observation,
      toolNames: seat.tools,
    );
    final answer = await runner.run(
      environment: environment,
      brief: buildRelayBrief(seat, snapshot),
    );
    return decodeRelayVerdict(answer);
  }
}

/// **RelayAssets** — the seed that ARMS the station's protective relay.
///
/// Mounted BELOW `StationWork` (which provides the [RelayRegistrar]) and below
/// the `RelayAgentEnvironment.provider()` the station armed, it mounts exactly
/// one [RelayAgentObserver] under the SEAT's own ceiling, and unmounts it again
/// the moment any of those inputs goes away.
///
/// **Presence is the whole existence rule.** The seat is read by EXACT type and
/// the walk runs over that seat's OWN entries ([firstAvailableFrom]); a generic
/// [ModelPreference] never activates a relay, because a station model default
/// says which model a scope prefers, never that a relay was armed. With no
/// seat, no present environment, or no registrar, this seed mounts NOTHING and
/// returns its child unchanged — leaving the engine's `relay.absent` path armed
/// so the signal reaches the governor instead of being silently absorbed.
///
/// **Placement.** A station mounts this below `StationWork`; the seat's
/// `provider()` (landed with the seat type itself) remains the separate
/// PRESENCE declaration, and the two are composed independently. The
/// [RelayRegistrar] arrives through a provider, so a `ProviderScope` must
/// enclose this seed — `runGrid`'s root scope is that ancestor in production.
///
/// **D-H (ADR-0008).** Every ambient value is read in `build` with the
/// subscribing verb, the readers and the runner are injected, and the state
/// holds only the live registration plus the identities it was mounted for — no
/// public synchronous accessor, no retained [TreeContext], no cached reactive
/// value.
class RelayAssets extends SingleChildStatefulSeed {
  /// Arms a relay over the injected read [tools] and inference [runner].
  const RelayAssets({
    required this.tools,
    required this.runner,
    super.child,
    super.key,
  });

  /// The four read tools the mounted observer inspects through (impls are DI).
  final RelayReadTools tools;

  /// The inference seam the mounted observer answers through (impls are DI).
  final RelayInferenceRunner runner;

  @override
  SingleChildState<RelayAssets> createState() => _RelayAssetsState();
}

class _RelayAssetsState extends SingleChildState<RelayAssets> {
  RelayRegistration? _registration;
  RelayAgentEnvironment? _seat;
  AgentEnvironment? _environment;
  RelayRegistrar? _registrar;
  RelayReadTools? _tools;
  RelayInferenceRunner? _runner;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // WATCH every dep (the D-H build verb): a re-armed seat, a changed presence
    // set, a re-provided registrar each re-derive the mount below.
    final seat = context
        .dependOnInheritedSeedOfExactType<RelayAgentEnvironment>();
    final available = context
        .dependOnInheritedSeedOfExactType<AvailableEnvironments>();
    final registry = context
        .dependOnInheritedSeedOfExactType<EnvironmentRegistry>();
    final registrar = context.watch<RelayRegistrar>();
    // The same default every availability read falls back to (ADR-0000 A35):
    // the boot-validated registry members, builtins when nothing is armed.
    final effectiveAvailable =
        available ??
        AvailableEnvironments.fromRegistry(
          registry ?? buildBuiltinEnvironmentRegistry(),
        );
    _reconcile(
      seat: seat,
      // The seat's OWN entries, never the generic preference.
      environment: seat == null
          ? null
          : firstAvailableFrom(seat, effectiveAvailable),
      registrar: registrar,
    );
    return child;
  }

  /// Brings the live registration in line with the current inputs: unmount when
  /// any is absent, leave an identical mount alone, and otherwise replace it —
  /// old registration disposed FIRST, because the engine admits one relay at a
  /// time and refuses a second mount.
  void _reconcile({
    required RelayAgentEnvironment? seat,
    required AgentEnvironment? environment,
    required RelayRegistrar? registrar,
  }) {
    final tools = seed.tools;
    final runner = seed.runner;
    if (seat == null || environment == null || registrar == null) {
      _unmount();
      return;
    }
    if (_registration != null &&
        seat == _seat &&
        environment == _environment &&
        registrar == _registrar &&
        tools == _tools &&
        runner == _runner) {
      return;
    }
    _unmount();
    // A throw here leaves NO stale registration: the old one is already gone
    // and the identities are already cleared, so the error reaches the station
    // with the relay honestly unarmed.
    final registration = registrar.mountRelay(
      observer: RelayAgentObserver(
        seat: seat,
        environment: environment,
        tools: tools,
        runner: runner,
      ),
      ceiling: seat.ceiling,
    );
    _registration = registration;
    _seat = seat;
    _environment = environment;
    _registrar = registrar;
    _tools = tools;
    _runner = runner;
  }

  /// Disposes the live registration, if any, and clears every identity.
  /// Idempotent.
  void _unmount() {
    _registration?.dispose();
    _registration = null;
    _seat = null;
    _environment = null;
    _registrar = null;
    _tools = null;
    _runner = null;
  }

  @override
  void dispose() {
    _unmount();
    super.dispose();
  }
}

/// One instant in the canonical evidence form: UTC, ISO-8601.
String _instant(DateTime at) => at.toUtc().toIso8601String();
