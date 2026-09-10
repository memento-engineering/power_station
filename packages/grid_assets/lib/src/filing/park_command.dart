import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'approve_command.dart';
import 'filing_contract.dart';
import 'state_root_option.dart';

String _currentDirectory(String _) => Directory.current.path;
BdRunner _processRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);

/// The gate bead's metadata key naming the SESSION it blocks.
///
/// The engine exports no constant for it — the lifecycle writer stamps this
/// literal at gate mint and the resident rework verb's own park predicate
/// reads the same literal — so this MIRRORS one schema key rather than
/// minting a second park mechanic beside the ratified one
/// (`the_grid#park-predicate-keys-on-the-open-gate`).
const String kGateBlocksKey = 'blocks';

/// The state store's per-bead worktree parent, relative to the state store.
const String _worktreesDir = 'worktrees';

/// The DURABLE marker that admitted one park.
///
/// Both arms are ratified park evidence; worktree staleness is NOT one of
/// them and can never appear here (`the_grid#park-predicate-keys-on-the-open-
/// gate`: *"Cursor state is not consulted to prove a park"*).
enum ParkMarker {
  /// An OPEN `type=gate` bead in the state store whose [kGateBlocksKey]
  /// metadata equals the session id.
  openGate('open_gate'),

  /// `grid.session.pause_state = paused` on the session bead — the
  /// non-terminal blocking disposition the resident pause verb wrote.
  pauseState('pause_state');

  const ParkMarker(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// WHICH of the two stores one park mutation targets (A37).
enum ParkStore {
  /// The substation work store the work bead lives in.
  work('work'),

  /// The grid home's own state store the session bead lives in.
  state('state');

  const ParkStore(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// The five hand steps the park verb absorbs, in the ONE order it performs
/// them. The order is load-bearing: the work bead stops being mountable and
/// stops being ready BEFORE its session is closed, and the closed session is
/// re-keyed LAST so a crash between the two leaves a dead join key rather than
/// a live one pointing at a closed session.
enum ParkStep {
  /// Append the operator receipt to the work bead's notes.
  note('note', ParkStore.work),

  /// Unset the three `grid.approved_*` keys, so the mount predicate refuses.
  unstamp('unstamp', ParkStore.work),

  /// Defer the work bead — a scheduled hold on READY work, never a session
  /// lifecycle operation (`the_grid#pause-is-a-non-terminal-blocking-
  /// disposition`).
  defer('defer', ParkStore.work),

  /// Close the session bead with the receipt as its reason.
  closeSession('close_session', ParkStore.state),

  /// Write the ENGINE-AUTHORED retire payload onto the closed session.
  voidRetire('void_retire', ParkStore.state);

  const ParkStep(this.wire, this.store);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;

  /// The store this step writes — the A37 split, declared per step.
  final ParkStore store;
}

/// One recorded fence probe: the pgid, its leader, and who was still alive.
///
/// The probe returns MEMBERS, not a bool
/// (`the_grid#pgid-liveness-is-supervision-evidence`), so a leader that
/// backgrounded a descendant and exited still reads [live].
final class FenceLiveness {
  /// Creates one probe record.
  const FenceLiveness({
    required this.pgid,
    required this.pid,
    required this.leaderAlive,
    required this.members,
  });

  /// The fence's process-group id, or null when the session never recorded
  /// one (nothing to probe — the fence cannot be live).
  final int? pgid;

  /// The fence's leader pid, or null when the session never recorded one.
  final int? pid;

  /// Whether `processAlive(pid)` answered true.
  final bool leaderAlive;

  /// The pids `groupMembers(pgid)` reported still in the group.
  final List<int> members;

  /// LIVE when the leader is alive OR the group still has members.
  bool get live => leaderAlive || members.isNotEmpty;

  /// The one-line refusal/override evidence, naming the pgid and the member
  /// count exactly as the runtime's orphan report does.
  String describe() =>
      'pgid ${pgid ?? '-'} (leader pid ${pid ?? '-'} '
      '${leaderAlive ? 'ALIVE' : 'gone'}, ${members.length} group member'
      '${members.length == 1 ? '' : 's'})';

  /// Structured command/UI representation.
  Map<String, Object?> toJson() => {
    'pgid': pgid,
    'pid': pid,
    'leader_alive': leaderAlive,
    'members': members.length,
  };
}

/// CORROBORATION only: when the work bead's worktree was last written.
///
/// Reported in every receipt and every refusal, and NEVER an admission arm —
/// a park is proved by a durable marker, not by a quiet directory.
final class WorktreeActivity {
  /// Creates observed corroboration for the worktree at [path].
  const WorktreeActivity({
    required this.path,
    required this.lastWrite,
    required this.age,
  }) : detail = null;

  /// Creates the explicit UNAVAILABLE corroboration — an absent, ambiguous or
  /// unreadable worktree says nothing, and saying nothing is reported rather
  /// than silently read as "quiet".
  const WorktreeActivity.unavailable(String this.detail)
    : path = null,
      lastWrite = null,
      age = null;

  /// The single matching worktree directory, or null when unavailable.
  final String? path;

  /// The newest descendant write instant in UTC, or null when unavailable.
  final DateTime? lastWrite;

  /// How long ago [lastWrite] was, or null when unavailable.
  final Duration? age;

  /// WHY no last-write time could be read, or null when one was.
  final String? detail;

  /// Whether a last-write time was actually observed.
  bool get available => lastWrite != null;

  /// The one-line corroboration string carried into receipts and refusals.
  String describe() => switch (lastWrite) {
    final lastWrite? =>
      'last worktree write ${lastWrite.toIso8601String()} '
          '(${age!.inHours}h ago) at $path',
    _ => 'worktree activity unavailable: $detail',
  };

  /// Structured command/UI representation.
  Map<String, Object?> toJson() => {
    'available': available,
    if (path case final path?) 'path': path,
    if (lastWrite case final lastWrite?)
      'last_write': lastWrite.toIso8601String(),
    if (age case final age?) 'age_hours': age.inHours,
    if (detail case final detail?) 'detail': detail,
  };
}

/// Reads the corroborating worktree activity for one work bead.
abstract interface class WorktreeActivityProbe {
  /// The activity for [workBeadId] under the resolved [stateStoreRoot].
  Future<WorktreeActivity> probe({
    required String stateStoreRoot,
    required String workBeadId,
  });
}

/// The real probe: `<state-store>/worktrees/<substation>/<work-bead-id>`.
final class FileSystemWorktreeActivityProbe implements WorktreeActivityProbe {
  /// Creates the probe over an injectable clock.
  const FileSystemWorktreeActivityProbe({
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final DateTime Function() _now;

  @override
  Future<WorktreeActivity> probe({
    required String stateStoreRoot,
    required String workBeadId,
  }) async {
    final parent = Directory(p.join(stateStoreRoot, _worktreesDir));
    if (!parent.existsSync()) {
      return WorktreeActivity.unavailable(
        'no $_worktreesDir directory under $stateStoreRoot',
      );
    }
    final matches = <String>[];
    for (final entry in parent.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final candidate = p.join(entry.path, workBeadId);
      if (Directory(candidate).existsSync()) matches.add(candidate);
    }
    if (matches.isEmpty) {
      return WorktreeActivity.unavailable(
        'no worktree for $workBeadId under ${parent.path}',
      );
    }
    if (matches.length > 1) {
      return WorktreeActivity.unavailable(
        '${matches.length} worktrees claim $workBeadId: ${matches.join(', ')}',
      );
    }
    final worktree = matches.single;
    final newest = _newestWrite(Directory(worktree));
    if (newest == null) {
      return WorktreeActivity.unavailable('$worktree holds no readable files');
    }
    return WorktreeActivity(
      path: worktree,
      lastWrite: newest,
      age: _now().toUtc().difference(newest),
    );
  }

  /// The newest descendant FILE mtime under [root], links NOT followed and
  /// `.git` skipped whole — git's own bookkeeping moves without the agent
  /// writing a line of work, and a directory's mtime moves for its children
  /// rather than for its content.
  static DateTime? _newestWrite(Directory root) {
    DateTime? newest;
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entry in entries) {
        if (p.basename(entry.path) == '.git') continue;
        if (entry is Directory) {
          pending.add(entry);
          continue;
        }
        if (entry is! File) continue;
        final modified = entry.statSync().modified.toUtc();
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
    }
    return newest;
  }
}

/// The outcome of one park run — a sealed union so every consumer faces all
/// three arms.
sealed class ParkOutcome {
  /// Creates an outcome for [workBeadId].
  const ParkOutcome({required this.workBeadId, this.sessionId});

  /// The work bead the verb was run against.
  final String workBeadId;

  /// The session bead the verb resolved, or null when it never got that far.
  final String? sessionId;

  /// Structured command/UI representation.
  Map<String, Object?> toJson();
}

/// The verb performed ALL FIVE steps and the slot is reclaimed.
final class Parked extends ParkOutcome {
  /// Creates the parked outcome.
  const Parked({
    required super.workBeadId,
    required String super.sessionId,
    required this.marker,
    required this.receipt,
    required this.voidMetadata,
    required this.activity,
    required this.overriddenFences,
    required this.unparkHint,
  });

  /// WHICH durable marker admitted this park.
  final ParkMarker marker;

  /// The receipt written to BOTH the work bead's notes and the session's
  /// close reason.
  final String receipt;

  /// The ENGINE-AUTHORED retire payload, exactly as written.
  final Map<String, String> voidMetadata;

  /// The corroborating worktree activity.
  final WorktreeActivity activity;

  /// Every live fence `--override-live` waived; empty on an ordinary park.
  final List<FenceLiveness> overriddenFences;

  /// The executable command that undoes this park.
  final String unparkHint;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'parked': true,
    'session': sessionId,
    'marker': marker.wire,
    'receipt': receipt,
    'void_metadata': voidMetadata,
    'worktree': activity.toJson(),
    'overrode_live': [for (final f in overriddenFences) f.toJson()],
    'unpark': unparkHint,
  };
}

/// The verb WROTE NOTHING and says why — a missing marker, an unresolvable
/// session, or a fence that is still LIVE.
final class ParkRefused extends ParkOutcome {
  /// Creates the refusal.
  const ParkRefused({
    required super.workBeadId,
    required this.reason,
    super.sessionId,
    this.activity,
    this.liveFences = const <FenceLiveness>[],
  });

  /// The LOUD reason, printed on both the plain and the JSON path.
  final String reason;

  /// The corroborating worktree activity, when it was collected before the
  /// refusal.
  final WorktreeActivity? activity;

  /// The fences that refused this park; empty for a marker refusal.
  final List<FenceLiveness> liveFences;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'parked': false,
    if (sessionId case final sessionId?) 'session': sessionId,
    'reason': reason,
    if (activity case final activity?) 'worktree': activity.toJson(),
    if (liveFences.isNotEmpty)
      'live_fences': [for (final f in liveFences) f.toJson()],
  };
}

/// The ritual STARTED and a `bd` call refused mid-way. It is never reported as
/// a park: the completed steps are named so the operator finishes by hand from
/// exactly where it stopped.
final class ParkFailed extends ParkOutcome {
  /// Creates the partial-failure outcome.
  const ParkFailed({
    required super.workBeadId,
    required super.sessionId,
    required this.step,
    required this.detail,
    required this.completed,
  });

  /// The step whose `bd` call exited non-zero.
  final ParkStep step;

  /// The failing call's stderr (or stdout when stderr was empty).
  final String detail;

  /// The steps that DID land, in order.
  final List<ParkStep> completed;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'parked': false,
    'session': sessionId,
    'failed_step': step.wire,
    'failed_store': step.store.wire,
    'completed': [for (final done in completed) done.wire],
    'reason':
        'bd ${step.wire} refused in the ${step.store.wire} store: '
        '$detail',
  };
}

/// UI-drivable park: the five-step reclaim ritual, behind two guards.
///
/// **ADMIT ON A DURABLE MARKER.** Either an open `type=gate` bead blocking the
/// session, or `grid.session.pause_state = paused` on it. Worktree staleness is
/// collected and REPORTED, never an accept arm
/// (`the_grid#park-predicate-keys-on-the-open-gate`).
///
/// **REFUSE ON A LIVE FENCE.** Every fence `staleFences` reports is probed
/// through the [ProcessGroupController] seam — `processAlive` on the leader,
/// then `groupMembers` on the group. Liveness only ever REFUSES; it never
/// authorizes (`the_grid#pgid-liveness-is-supervision-evidence`).
///
/// **TWO STORES.** Work-bead writes go to the substation store, session writes
/// to the grid home's own state store, and neither crosses
/// (`the_grid#a37-session-bead-write-target-b-a-separate-the-grid-owned-st`).
///
/// The session's retire payload is whatever
/// [voidRetireMetadata] returns — the verb never composes the retired join key
/// itself (`the_grid#a48-a-closed-session-is-dispositioned-done-held-voided-
/// not-b`).
final class ParkService {
  /// Creates the service over four injectable seams.
  ParkService({
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    ProcessGroupController processes = const SystemProcessGroupController(),
    WorktreeActivityProbe? worktrees,
    ExactSubstationBeadSource? source,
  }) : _runnerFor = runnerFor,
       _processes = processes,
       _worktrees = worktrees ?? const FileSystemWorktreeActivityProbe(),
       _source = source ?? ExactSubstationBeadSource(runnerFor: runnerFor);

  final BdRunner Function(String storeRoot) _runnerFor;
  final ProcessGroupController _processes;
  final WorktreeActivityProbe _worktrees;
  final ExactSubstationBeadSource _source;

  /// Parks [workBeadId], reclaiming its agent slot.
  ///
  /// [workStoreRoot] is the substation store the work bead lives in;
  /// [stateRoot] is the RESOLVED grid state store the session bead lives in.
  /// [deferUntil] is handed to `bd defer --until` verbatim. [overrideLive]
  /// waives ONLY the live-fence refusal — never the marker requirement.
  Future<ParkOutcome> park({
    required String workStoreRoot,
    required String stateRoot,
    required String workBeadId,
    required String actor,
    required String reason,
    required String deferUntil,
    bool overrideLive = false,
  }) async {
    final read = await _source.readExact(
      storeRoot: workStoreRoot,
      beadId: workBeadId,
    );
    if (read.bead == null) {
      return ParkRefused(
        workBeadId: workBeadId,
        reason: 'work bead $workBeadId not found in $workStoreRoot',
      );
    }
    final stateCli = BdCliService(_runnerFor(stateRoot));
    final sessions = (await stateCli.listScope(
      type: GridIssueTypes.session,
      metadataFields: {SessionBeadKeys.workBead: workBeadId},
    )).beads.where((bead) => !bead.isClosed).toList(growable: false);
    if (sessions.isEmpty) {
      return ParkRefused(
        workBeadId: workBeadId,
        reason:
            'no open session in $stateRoot carries '
            '${SessionBeadKeys.workBead}=$workBeadId — there is no slot to '
            'reclaim',
      );
    }
    if (sessions.length > 1) {
      return ParkRefused(
        workBeadId: workBeadId,
        reason:
            '${sessions.length} open sessions carry '
            '${SessionBeadKeys.workBead}=$workBeadId '
            '(${sessions.map((bead) => bead.id).join(', ')}) — refusing an '
            'ambiguous park',
      );
    }
    final session = sessions.single;
    final projection = projectSession(session);
    // Corroboration is collected BEFORE the marker decision so a refusal
    // carries it too — and so nothing about the ORDER suggests it decides.
    final activity = await _worktrees.probe(
      stateStoreRoot: stateRoot,
      workBeadId: workBeadId,
    );
    final gates = (await stateCli.listScope(
      type: GridIssueTypes.gate,
      metadataFields: {kGateBlocksKey: session.id},
    )).beads.where((bead) => !bead.isClosed).toList(growable: false);
    final ParkMarker marker;
    if (gates.isNotEmpty) {
      marker = ParkMarker.openGate;
    } else if (projection.pauseState == SessionPauseState.paused) {
      marker = ParkMarker.pauseState;
    } else {
      return ParkRefused(
        workBeadId: workBeadId,
        sessionId: session.id,
        activity: activity,
        reason:
            'session ${session.id} carries no durable park marker — park '
            'admits on an OPEN ${GridIssueTypes.gate.wire} bead whose '
            '$kGateBlocksKey metadata is ${session.id}, or on '
            '${SessionBeadKeys.pauseState}=paused on the session bead. '
            '${activity.describe()} corroborates but never admits',
      );
    }

    final probed = <FenceLiveness>[];
    for (final fence in staleFences(projection)) {
      final pid = fence.pid;
      final pgid = fence.pgid;
      probed.add(
        FenceLiveness(
          pgid: pgid,
          pid: pid,
          leaderAlive: pid != null && _processes.processAlive(pid),
          members: pgid == null
              ? const <int>[]
              : await _processes.groupMembers(pgid),
        ),
      );
    }
    final live = probed.where((fence) => fence.live).toList(growable: false);
    if (live.isNotEmpty && !overrideLive) {
      return ParkRefused(
        workBeadId: workBeadId,
        sessionId: session.id,
        activity: activity,
        liveFences: live,
        reason:
            'session ${session.id} is still LIVE — '
            '${live.map((fence) => fence.describe()).join('; ')}. Parking it '
            'would discard a working round; pass --override-live to park '
            'anyway',
      );
    }

    final unparkHint =
        'unpark --actor $actor --state-root $stateRoot $workBeadId';
    final receipt = _receipt(
      workBeadId: workBeadId,
      sessionId: session.id,
      actor: actor,
      reason: reason,
      deferUntil: deferUntil,
      marker: marker,
      gateIds: [for (final gate in gates) gate.id],
      activity: activity,
      overridden: overrideLive ? live : const <FenceLiveness>[],
      unparkHint: unparkHint,
    );
    final voidMetadata = voidRetireMetadata(
      workBeadId: workBeadId,
      deadSessionId: session.id,
      reason: receipt,
    );
    final calls = <ParkStep, ({String root, List<String> argv})>{
      ParkStep.note: (
        root: workStoreRoot,
        argv: [
          'update',
          workBeadId,
          '--json',
          '--actor',
          actor,
          '--append-notes',
          receipt,
        ],
      ),
      ParkStep.unstamp: (
        root: workStoreRoot,
        argv: [
          'update',
          workBeadId,
          '--json',
          '--actor',
          actor,
          for (final key in const [
            kApprovedAtKey,
            kApprovedByKey,
            kApprovedRevKey,
          ]) ...['--unset-metadata', key],
        ],
      ),
      ParkStep.defer: (
        root: workStoreRoot,
        argv: [
          'defer',
          workBeadId,
          '--until',
          deferUntil,
          '--json',
          '--actor',
          actor,
        ],
      ),
      ParkStep.closeSession: (
        root: stateRoot,
        argv: [
          'close',
          session.id,
          '--reason',
          receipt,
          '--json',
          '--actor',
          actor,
        ],
      ),
      ParkStep.voidRetire: (
        root: stateRoot,
        argv: [
          'update',
          session.id,
          '--json',
          '--actor',
          actor,
          for (final entry in voidMetadata.entries) ...[
            '--set-metadata',
            '${entry.key}=${entry.value}',
          ],
        ],
      ),
    };
    final completed = <ParkStep>[];
    for (final step in ParkStep.values) {
      final call = calls[step]!;
      final result = await _runnerFor(call.root).run(call.argv);
      if (!result.ok) {
        final detail = result.stderr.trim().isEmpty
            ? result.stdout.trim()
            : result.stderr.trim();
        return ParkFailed(
          workBeadId: workBeadId,
          sessionId: session.id,
          step: step,
          detail: detail,
          completed: completed,
        );
      }
      completed.add(step);
    }
    return Parked(
      workBeadId: workBeadId,
      sessionId: session.id,
      marker: marker,
      receipt: receipt,
      voidMetadata: voidMetadata,
      activity: activity,
      overriddenFences: overrideLive ? live : const <FenceLiveness>[],
      unparkHint: unparkHint,
    );
  }

  String _receipt({
    required String workBeadId,
    required String sessionId,
    required String actor,
    required String reason,
    required String deferUntil,
    required ParkMarker marker,
    required List<String> gateIds,
    required WorktreeActivity activity,
    required List<FenceLiveness> overridden,
    required String unparkHint,
  }) => [
    'PARKED $workBeadId by $actor: $reason',
    'session $sessionId closed and void-retired; work bead deferred until '
        '$deferUntil and unstamped',
    'admitted on ${marker.wire}'
        '${gateIds.isEmpty ? '' : ' (${gateIds.join(', ')})'}',
    activity.describe(),
    for (final fence in overridden) 'OVERRODE LIVE ${fence.describe()}',
    'unpark with: $unparkHint',
  ].join('\n');
}

/// The `park` VERB — reclaim a stalled session's agent slot in ONE command:
/// unstamp and defer the work bead, then close and void-retire the session
/// that holds the slot. [invocation] carries the exact shape.
class ParkCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// [workStoreRoot] is the station-injected, PREFIX-AWARE resolver: it is
  /// handed the parsed work-bead id and answers the substation store that
  /// owns it. [stateRoot] is the station-injected grid home.
  ParkCommand({
    ParkService? service,
    String Function(String workBeadId) workStoreRoot = _currentDirectory,
    String? Function() stateRoot = noStateRoot,
    StringSink? out,
    StringSink? err,
  }) : _service = service ?? ParkService(),
       _workStoreRoot = workStoreRoot,
       _stateRoot = stateRoot,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit {id, parked, session, marker, receipt, void_metadata, '
            'worktree, reason?} as one JSON object.',
      )
      ..addFlag(
        'override-live',
        negatable: false,
        help:
            'Park past a LIVE process fence. Waives ONLY the liveness '
            'refusal — never the durable park marker — and prints what it '
            'overrode.',
      )
      ..addOption(
        'actor',
        help:
            'The operator parking the session, recorded on both beads. '
            'Required.',
      )
      ..addOption(
        'reason',
        help:
            'WHY this session is being parked, carried into the work-bead '
            'note and the session close reason. Required.',
      )
      ..addOption(
        'until',
        help: 'The defer date handed to `bd defer --until`. Required.',
      );
    addStateRootOption(argParser);
  }

  final ParkService _service;
  final String Function(String workBeadId) _workStoreRoot;
  final String? Function() _stateRoot;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'park';

  @override
  final String description =
      'Park a stalled session: unstamp and defer the work bead, then close '
      'and void-retire the session that holds its slot.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape =
        'park --actor <name> --reason <text> --until <date> [--override-live] '
        '[--json] [--state-root <grid-home>] <work-bead-id>';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('park: exactly one work bead id is required — $invocation');
      return 64;
    }
    final workBeadId = rest.single.trim();
    final actor = argResults!.option('actor')?.trim() ?? '';
    if (actor.isEmpty) {
      _err.writeln(
        'park: --actor <name> is required — the receipt records WHO parked.',
      );
      return 64;
    }
    final reason = argResults!.option('reason')?.trim() ?? '';
    if (reason.isEmpty) {
      _err.writeln(
        'park: --reason <text> is required — a slot reclaimed without a '
        'recorded why is a slot nobody can unpark.',
      );
      return 64;
    }
    final until = argResults!.option('until')?.trim() ?? '';
    if (until.isEmpty) {
      _err.writeln(
        'park: --until <date> is required — the defer is a SCHEDULED hold.',
      );
      return 64;
    }
    final String? stateRoot;
    try {
      stateRoot = resolveStateRoot(argResults!, _stateRoot);
    } on Object catch (error) {
      _err.writeln('park: $error');
      return 64;
    }
    if (stateRoot == null) {
      _err.writeln(
        'park: --state-root <grid-home> is required — the session bead lives '
        "in the grid home's own state store, never in the work store.",
      );
      return 64;
    }
    final ParkOutcome outcome;
    try {
      outcome = await _service.park(
        workStoreRoot: p.normalize(_workStoreRoot(workBeadId)),
        stateRoot: stateRoot,
        workBeadId: workBeadId,
        actor: actor,
        reason: reason,
        deferUntil: until,
        overrideLive: argResults!.flag('override-live'),
      );
    } on Object catch (error) {
      _err.writeln('park: failed to park $workBeadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(outcome.toJson()));
    } else {
      switch (outcome) {
        case Parked(:final receipt, :final overriddenFences):
          _out.writeln(receipt);
          for (final fence in overriddenFences) {
            _out.writeln('OVERRODE LIVE ${fence.describe()}');
          }
        case ParkRefused(:final reason):
          _out.writeln('REFUSED $workBeadId: $reason');
        case ParkFailed(:final step, :final detail, :final completed):
          _out.writeln(
            'PARTIAL $workBeadId: ${step.wire} refused in the '
            '${step.store.wire} store: $detail',
          );
          _out.writeln(
            'completed: '
            '${completed.isEmpty ? 'nothing' : completed.map((s) => s.wire).join(', ')}',
          );
      }
    }
    return switch (outcome) {
      Parked() => 0,
      ParkRefused() || ParkFailed() => 1,
    };
  }
}

/// The outcome of one unpark run — a sealed union so every consumer faces all
/// three arms.
sealed class UnparkOutcome {
  /// Creates an outcome for [workBeadId].
  const UnparkOutcome({required this.workBeadId});

  /// The work bead the verb was run against.
  final String workBeadId;

  /// Structured command/UI representation.
  Map<String, Object?> toJson();
}

/// The defer DATE cleared and the approval preflight re-stamped it.
final class Unparked extends UnparkOutcome {
  /// Creates the unparked outcome.
  const Unparked({
    required super.workBeadId,
    required this.stamp,
    required this.approval,
  });

  /// The fresh receipt the approve verb wrote.
  final ApprovalStamp stamp;

  /// The approval outcome the composed verb returned, carried whole.
  final ApprovalStamped approval;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'unparked': true,
    'undeferred': true,
    ...approval.toJson(),
  };
}

/// The bead IS undeferred, but the approval preflight refused to re-stamp it.
/// Never reported as unparked: an unstamped bead does not mount.
final class UnparkRefused extends UnparkOutcome {
  /// Creates the refusal.
  const UnparkRefused({
    required super.workBeadId,
    required this.reason,
    required this.undeferred,
    this.approval,
  });

  /// The LOUD reason, printed on both the plain and the JSON path.
  final String reason;

  /// Whether the defer date was cleared before the refusal.
  final bool undeferred;

  /// The approval refusal, carried whole so its failing rows print.
  final ApprovalRefused? approval;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'unparked': false,
    'undeferred': undeferred,
    'reason': reason,
    if (approval case final approval?) 'filing': approval.report?.toJson(),
  };
}

/// `bd undefer` itself refused — the approval step never ran.
final class UnparkFailed extends UnparkOutcome {
  /// Creates the undefer failure.
  const UnparkFailed({required super.workBeadId, required this.detail});

  /// The failing call's stderr (or stdout when stderr was empty).
  final String detail;

  @override
  Map<String, Object?> toJson() => {
    'id': workBeadId,
    'unparked': false,
    'undeferred': false,
    'reason': 'bd undefer refused: $detail',
  };
}

/// UI-drivable unpark: clear the defer DATE, then re-run the EXISTING approval
/// verb.
///
/// Both halves matter. Reopening the status alone leaves `defer_until` set and
/// the bead silently never mints, so the clear rides `bd undefer` — which
/// resets status AND date together. And the re-stamp is [ApproveService] ITSELF,
/// never a second expression of the filing preflight: one contract, answered
/// one way (`power_station#filing-and-approve-share-one-state-root-seam`).
final class UnparkService {
  /// Creates the service over the approval verb and the store seam.
  UnparkService({
    ApproveService? approve,
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    ExactSubstationBeadSource? source,
  }) : approve = approve ?? ApproveService(runnerFor: runnerFor),
       _runnerFor = runnerFor,
       _source = source ?? ExactSubstationBeadSource(runnerFor: runnerFor);

  /// The approval verb this one COMPOSES — the second unpark step IS approve.
  final ApproveService approve;

  final BdRunner Function(String storeRoot) _runnerFor;
  final ExactSubstationBeadSource _source;

  /// Unparks [workBeadId] in [workStoreRoot] on behalf of [actor].
  ///
  /// [stateRoot] is the resolved state store, passed straight through to the
  /// approval preflight's cross-store link read.
  Future<UnparkOutcome> unpark({
    required String workStoreRoot,
    required String workBeadId,
    required String actor,
    String? stateRoot,
  }) async {
    final read = await _source.readExact(
      storeRoot: workStoreRoot,
      beadId: workBeadId,
    );
    if (read.bead == null) {
      return UnparkRefused(
        workBeadId: workBeadId,
        reason: 'work bead $workBeadId not found in $workStoreRoot',
        undeferred: false,
      );
    }
    final undeferred = await _runnerFor(
      workStoreRoot,
    ).run(['undefer', workBeadId, '--json', '--actor', actor]);
    if (!undeferred.ok) {
      final detail = undeferred.stderr.trim().isEmpty
          ? undeferred.stdout.trim()
          : undeferred.stderr.trim();
      return UnparkFailed(workBeadId: workBeadId, detail: detail);
    }
    final approval = await approve.approve(
      storeRoot: workStoreRoot,
      beadId: workBeadId,
      actor: actor,
      stateRoot: stateRoot,
    );
    return switch (approval) {
      ApprovalStamped(:final stamp) => Unparked(
        workBeadId: workBeadId,
        stamp: stamp,
        approval: approval,
      ),
      ApprovalRefused(:final reason) => UnparkRefused(
        workBeadId: workBeadId,
        reason:
            '$workBeadId is undeferred but remains UNSTAMPED — the approval '
            'preflight refused: $reason',
        undeferred: true,
        approval: approval,
      ),
    };
  }
}

/// `unpark --actor <name> [--json] [--state-root <grid-home>] <work-bead-id>`
/// — clear a parked bead's defer date and re-stamp its approval.
class UnparkCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// [workStoreRoot] is the same station-injected, PREFIX-AWARE resolver
  /// [ParkCommand] takes.
  UnparkCommand({
    UnparkService? service,
    String Function(String workBeadId) workStoreRoot = _currentDirectory,
    String? Function() stateRoot = noStateRoot,
    StringSink? out,
    StringSink? err,
  }) : _service = service ?? UnparkService(),
       _workStoreRoot = workStoreRoot,
       _stateRoot = stateRoot,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit {id, unparked, undeferred, by, at, rev, filing, reason?} as '
            'one JSON object.',
      )
      ..addOption(
        'actor',
        help: 'The operator unparking, recorded as grid.approved_by. Required.',
      );
    addStateRootOption(argParser);
  }

  final UnparkService _service;
  final String Function(String workBeadId) _workStoreRoot;
  final String? Function() _stateRoot;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'unpark';

  @override
  final String description =
      'Clear a parked bead\'s defer date and re-stamp its approval.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape =
        'unpark --actor <name> [--json] [--state-root <grid-home>] '
        '<work-bead-id>';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln(
        'unpark: exactly one work bead id is required — $invocation',
      );
      return 64;
    }
    final workBeadId = rest.single.trim();
    final actor = argResults!.option('actor')?.trim() ?? '';
    if (actor.isEmpty) {
      _err.writeln(
        'unpark: --actor <name> is required — the re-stamp records WHO '
        'approved.',
      );
      return 64;
    }
    final UnparkOutcome outcome;
    try {
      outcome = await _service.unpark(
        workStoreRoot: p.normalize(_workStoreRoot(workBeadId)),
        workBeadId: workBeadId,
        actor: actor,
        stateRoot: resolveStateRoot(argResults!, _stateRoot),
      );
    } on Object catch (error) {
      _err.writeln('unpark: failed to unpark $workBeadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(outcome.toJson()));
    } else {
      switch (outcome) {
        case Unparked(:final stamp):
          _out.writeln(
            'UNPARKED $workBeadId: defer cleared, approved by ${stamp.by} at '
            '${stamp.at} rev ${stamp.rev}',
          );
        case UnparkRefused(:final reason, :final approval):
          _out.writeln('REFUSED $workBeadId: $reason');
          for (final row
              in approval?.report?.requirements ??
                  const <FilingRequirementRow>[]) {
            if (!row.passed) {
              _out.writeln('FAIL ${row.requirement.wire}: ${row.detail}');
            }
          }
        case UnparkFailed(:final detail):
          _out.writeln('REFUSED $workBeadId: bd undefer refused: $detail');
      }
    }
    return switch (outcome) {
      Unparked() => 0,
      UnparkRefused() || UnparkFailed() => 1,
    };
  }
}
