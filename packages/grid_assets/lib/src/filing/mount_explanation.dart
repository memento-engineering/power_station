/// The MOUNT EXPLAINER — why this bead will not mount, as ROWS, offline.
///
/// The refiner seat has an oracle for one question and none for the next. The
/// `filing` verb answers "is this bead APPROVABLE" deterministically. Nothing
/// answered "why will this bead not MOUNT", so the answer lived in human memory
/// as a set of memorised dances: a hand-closed session leaves a bare
/// `work_bead` key and the bead never re-mounts; a stamp not stripped before a
/// session closes makes the bead re-mint; a mount-ATTEMPT cap has no reset verb
/// at all. Each of those is a state the machine HOLDS, decides mounting on, and
/// discloses to nobody. This library converts the dances into rows.
///
/// **OFFLINE.** It reads stores and needs no resident. Every live-only fact is
/// reported [MountOutcome.unchecked] with a pointer to the live surface, never
/// as a pass — [MountPrecondition.liveAdmission] is always unchecked, because
/// capacity, reservations, admission latches, process liveness and the
/// engine-only session-mint and step-successor retry counters are engine
/// MEMORY, not store state.
///
/// **NAME THE REMEDY.** A row that only says BLOCKED leaves the dance in the
/// operator's head, so every non-passing row carries what to do about it —
/// enforced by [MountPreconditionRow]'s own constructor. The verb NEVER
/// performs a remedy: several are destructive and belong to the governor.
///
/// **COMPOSE, DO NOT REINVENT.** The field clauses are
/// [mountEligibilityFindings] — the one predicate the engine's mount boundary
/// already calls — and the first four rows RENDER the [FilingReport] the
/// `filing` verb emits, which rides out whole under `filing`. The
/// `dependencies` row is the very [DependencyProjection] that report was
/// rendered from ([FilingService.inspect] hands both back together), refined
/// with each local target's open/closed state. No second completeness
/// predicate is minted here
/// (`power_station#approval-is-the-stamp-the-grid-approved-label-retires`), and
/// bead PROSE is never read for blockers
/// (`power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`).
///
/// **FAIL CLOSED.** An unchecked condition is never reported as a pass. A
/// missing or unreadable state store makes the three state-backed rows
/// unchecked rather than green, and an unreadable local dependency target makes
/// the `dependencies` row unchecked rather than clear.
///
/// **READ-ONLY BY CONSTRUCTION (A37).** Every store touch is a scoped read
/// through [ExactSubstationBeadSource.readExact], [BdCliService.query] over an
/// id-scoped expression, or [BdCliService.listScope] — never `bd show` (which
/// writes `.beads/last-touched` and self-triggers the store's watcher), never a
/// mutating subcommand, and never the retired `type=link` read.
///
/// **BOUNDED OUTPUT**
/// (`power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`):
/// both renderings fit [kBoundedOutputCapBytes] through the pack's ONE
/// selector, [boundedOutput]. A precondition row is never removed — the answer
/// is the row set — so the only material this verb gives up is the TAIL of a
/// row's evidence list, and every cut names what it withheld and the exact
/// scoped read that retrieves it.
///
/// **THE CAP BOUNDARY.** Both named caps are STORE state and therefore ordinary
/// offline rows: the verdict cap derives from durable session/step beads and
/// their `supersedes` edges, and the mount-attempt cap is carried by a
/// `type=mount-attempt` bead's `grid.attempt.*` metadata. Neither is
/// engine-only. The engine-only mint and successor-retry counters are OUTSIDE
/// the named caps and stay covered by [MountPrecondition.liveAdmission].
///
/// The relay seat is NOT a dependency of this verb: this mechanical explanation
/// runs FIRST, and a relay is the cheap inference pass over whatever survives
/// it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart'
    show
        Bead,
        BdCliService,
        BdRunner,
        BeadDependency,
        BeadStatus,
        ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart' show StationTrajectoryRecorder;
import 'package:path/path.dart' as p;

import '../code/mount_eligibility.dart';
import '../io/bounded_output.dart';
import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'filing_command.dart' show noArmedSubstations;
import 'filing_contract.dart';
import 'state_root_option.dart';

String _currentDirectory() => Directory.current.path;
BdRunner _processRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);
DateTime _utcNow() => DateTime.now().toUtc();

/// What one mount precondition says.
///
/// Three values, not two: [unchecked] is the whole point of an OFFLINE
/// explainer. A condition this verb could not consult is reported as unasked,
/// never folded into [pass], because a refiner told an absent condition is
/// clear stops looking exactly where the answer is.
enum MountOutcome {
  /// The condition holds; nothing here stops a mount.
  pass('PASS'),

  /// The condition does NOT hold, and the row names the remedy.
  blocked('BLOCKED'),

  /// The condition was NOT consulted, and the row names where to ask.
  unchecked('UNCHECKED');

  const MountOutcome(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// The ten preconditions one bead must satisfy before a station mounts it, in
/// the ONE order both renderings emit them.
///
/// The order is mechanical-first: the bead's own FIELDS, then the rows bd
/// holds, then the stamp, then the durable state the grid home carries about
/// this bead, and last the live surface this verb cannot see.
enum MountPrecondition {
  /// The bead's issue type is one the mount boundary drives.
  driveableType('driveable_type'),

  /// The bead carries a non-blank `validation_plan`.
  validationPlan('validation_plan'),

  /// The bead carries acceptance criteria a command can falsify.
  acceptanceCriteria('acceptance_criteria'),

  /// The dependency ROWS bd holds, local and `external:` alike, each resolved.
  dependencies('dependencies'),

  /// The `grid.approved_*` receipt the approve verb writes.
  approvalStamp('approval_stamp'),

  /// Which session rows currently link this bead's `work_bead` key.
  sessionOccupancy('session_occupancy'),

  /// Whether the bead is deferred out of the ready frontier.
  deferState('defer_state'),

  /// The rework-round / per-step verdict budget.
  verdictCap('verdict_cap'),

  /// The durable remount-attempt budget.
  mountAttemptCap('mount_attempt_cap'),

  /// Everything that lives only in a running station's memory.
  liveAdmission('live_admission');

  const MountPrecondition(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// One precondition's answer: the outcome, the evidence that produced it, and
/// — when it does not pass — what to do about it.
///
/// The constructor is the GUARD that keeps the ruling "NAME THE REMEDY" true by
/// construction rather than by review: a blank detail, a non-passing row with no
/// remedy, or a passing row carrying one are each an [ArgumentError], and a row
/// whose evidence could be trimmed away without naming the read that retrieves
/// it is one too.
final class MountPreconditionRow {
  /// Creates one answered precondition.
  ///
  /// [evidence] is the trimmable material — ids, keys, per-path counts — that
  /// backs [detail]. [retrievedBy] is the exact scoped read that returns it in
  /// full, and is required whenever there is evidence to lose.
  MountPreconditionRow({
    required this.precondition,
    required this.outcome,
    required this.detail,
    this.remedy = '',
    this.evidence = const <String>[],
    this.retrievedBy = '',
  }) {
    if (detail.trim().isEmpty) {
      throw ArgumentError.value(
        detail,
        'detail',
        'every ${precondition.wire} row states its evidence; a blank detail is '
            'a row that says nothing',
      );
    }
    if (outcome != MountOutcome.pass && remedy.trim().isEmpty) {
      throw ArgumentError.value(
        remedy,
        'remedy',
        'a ${outcome.wire} ${precondition.wire} row without a remedy leaves '
            "the dance in the operator's head",
      );
    }
    if (outcome == MountOutcome.pass && remedy.trim().isNotEmpty) {
      throw ArgumentError.value(
        remedy,
        'remedy',
        'a PASS ${precondition.wire} row has nothing to remedy',
      );
    }
    if (evidence.isNotEmpty && retrievedBy.trim().isEmpty) {
      throw ArgumentError.value(
        retrievedBy,
        'retrievedBy',
        'evidence that can be withheld names the read that retrieves it',
      );
    }
  }

  /// Which precondition this row answers.
  final MountPrecondition precondition;

  /// What the precondition says.
  final MountOutcome outcome;

  /// The human-readable evidence for [outcome]; never blank.
  final String detail;

  /// What to DO about a non-passing row; empty exactly when [outcome] passes.
  final String remedy;

  /// The trimmable backing material, in a deterministic order.
  final List<String> evidence;

  /// The exact scoped read that returns [evidence] in full.
  final String retrievedBy;

  /// This row with only the leading [keep] evidence entries — the ONE trim the
  /// bound performs. The row itself, its detail and its remedy are never cut.
  MountPreconditionRow truncatedTo(int keep) => MountPreconditionRow(
    precondition: precondition,
    outcome: outcome,
    detail: detail,
    remedy: remedy,
    evidence: evidence.take(keep).toList(growable: false),
    retrievedBy: retrievedBy,
  );

  /// Structured command/UI representation.
  Map<String, Object?> toJson() => {
    'precondition': precondition.wire,
    'outcome': outcome.wire,
    'detail': detail,
    if (remedy.isNotEmpty) 'remedy': remedy,
    if (evidence.isNotEmpty) 'evidence': evidence,
  };
}

/// The complete mount explanation for one bead id.
final class MountExplanationReport {
  /// Creates a report over already-answered rows.
  const MountExplanationReport({
    required this.beadId,
    required this.preconditions,
    required this.filing,
    this.withheld = const <MountPrecondition, int>{},
    this.withheldRetrievedBy = '',
    this.error,
  });

  /// Creates the loud unknown-id report: no rows at all, so nothing reads
  /// green for a bead that does not exist.
  factory MountExplanationReport.missing(String beadId) =>
      MountExplanationReport(
        beadId: beadId,
        preconditions: const <MountPreconditionRow>[],
        filing: FilingReport.missing(beadId),
        error: 'bead not found',
      );

  /// The bead explained.
  final String beadId;

  /// Ten rows for a found bead, in [MountPrecondition.values] order.
  final List<MountPreconditionRow> preconditions;

  /// The EXACT [FilingReport] [FilingService.inspect] returned — composed, not
  /// restated, so the embedded rows are byte-identical to `filing --json`.
  final FilingReport filing;

  /// Evidence entries withheld by the bound, per precondition.
  final Map<MountPrecondition, int> withheld;

  /// The scoped reads that retrieve everything [withheld] names, joined with
  /// `&&` in precondition order.
  final String withheldRetrievedBy;

  /// Lookup-level refusal; a non-null report never passes.
  final String? error;

  /// The aggregate: BLOCKED outranks UNCHECKED outranks PASS. A refusal is
  /// blocked — an id nobody can read is not a bead that mounts.
  MountOutcome get verdict {
    if (error != null) return MountOutcome.blocked;
    if (preconditions.any((row) => row.outcome == MountOutcome.blocked)) {
      return MountOutcome.blocked;
    }
    if (preconditions.any((row) => row.outcome == MountOutcome.unchecked)) {
      return MountOutcome.unchecked;
    }
    return MountOutcome.pass;
  }

  /// Structured command/UI representation.
  Map<String, Object?> toJson() => {
    'id': beadId,
    'verdict': verdict.wire,
    'preconditions': [for (final row in preconditions) row.toJson()],
    'filing': filing.toJson(),
    if (withheld.isNotEmpty) ...{
      'withheld': {
        for (final entry in withheld.entries) entry.key.wire: entry.value,
      },
      'withheld_retrieved_by': withheldRetrievedBy,
    },
    if (error case final error?) 'error': error,
  };
}

/// Everything the explainer READ before it evaluated anything — the pre-read
/// store state the pure contract is a function of.
///
/// Two independent availability axes, because they are two different stores.
/// [unavailableDetail] covers the grid home's STATE store and makes
/// `session_occupancy`, `verdict_cap` and `mount_attempt_cap` unchecked;
/// [unreadableLocalDependencyIds] covers the WORK store's local dependency
/// targets and makes `dependencies` unchecked. Neither is ever reported as an
/// empty collection that reads like an answer.
final class MountStateEvidence {
  /// Creates the evidence bundle.
  const MountStateEvidence({
    this.workStoreRoot = '',
    this.stateRoot,
    this.localDependencies = const <Bead>[],
    this.unreadableLocalDependencyIds = const <String>[],
    this.localDependencyRetrieval = '',
    this.sessions = const <Bead>[],
    this.stepsBySession = const <String, List<Bead>>{},
    this.stepDependenciesBySession = const <String, List<BeadDependency>>{},
    this.mountAttempts = const <Bead>[],
    this.sessionRetrieval = '',
    this.stepRetrieval = '',
    this.mountAttemptRetrieval = '',
    this.unavailableDetail,
  });

  /// The substation work store the bead itself lives in.
  final String workStoreRoot;

  /// The RESOLVED grid state store, or null when none was named.
  final String? stateRoot;

  /// The local dependency targets that were read back, whatever their status.
  final List<Bead> localDependencies;

  /// Local dependency ids the single scoped query did not answer for, sorted.
  final List<String> unreadableLocalDependencyIds;

  /// The exact scoped read that returns the local dependency targets.
  final String localDependencyRetrieval;

  /// Every `type=session` bead in the state store, closed included.
  final List<Bead> sessions;

  /// The `type=step` beads of each historically associated session.
  final Map<String, List<Bead>> stepsBySession;

  /// The dependency rows that came back with those step beads — the
  /// `supersedes` edges the verdict count walks.
  final Map<String, List<BeadDependency>> stepDependenciesBySession;

  /// The `type=mount-attempt` records joined to this bead.
  final List<Bead> mountAttempts;

  /// The exact scoped read that returns the session beads.
  final String sessionRetrieval;

  /// The exact scoped read that returns one session's step beads.
  final String stepRetrieval;

  /// The exact scoped read that returns the attempt records.
  final String mountAttemptRetrieval;

  /// WHY the state store says nothing, or null when it was read.
  final String? unavailableDetail;

  /// Whether the grid home's state store actually answered.
  bool get stateStoreConsulted => unavailableDetail == null;

  /// The grid HOME the resident verbs take, derived from [stateRoot].
  String get gridHome => switch (stateRoot) {
    final root? when p.basename(root) == '.grid' => p.dirname(root),
    final root? => root,
    _ => '<grid-home>',
  };
}

/// The work store's own dependency targets, joined to the projection.
final class _LocalTargets {
  const _LocalTargets({
    required this.open,
    required this.closed,
    required this.unreadable,
  });

  final List<String> open;
  final List<String> closed;
  final List<String> unreadable;
}

/// One bead's session rows, split the way the mount boundary splits them.
final class _LinkedSessions {
  const _LinkedSessions({
    required this.contenders,
    required this.history,
    required this.verdict,
    required this.beadsBySessionId,
  });

  /// The rows whose [linkedWorkBeadKeyOf] IS this bead — what the join
  /// publishes over.
  final List<SessionProjection> contenders;

  /// Terminal retired (`#r<N>`) and void-rekeyed (`#void-`) rows. Literal
  /// history: they never re-enter the join.
  final List<SessionProjection> history;

  /// The engine's own verdict over [contenders].
  final LinkedSessionVerdict verdict;

  /// The raw session beads, by id — what `reworkVerdictEvidence` reads.
  final Map<String, Bead> beadsBySessionId;
}

/// Pure evaluator for the ten-row mount explanation.
///
/// It COMPOSES rather than re-derives: the retained [FilingReport] supplies the
/// rendered detail of the first four rows, the retained [DependencyProjection]
/// IS the `dependencies` row's content, and [mountEligibilityFindings] — called
/// exactly once — supplies the mount-side classification of type, validation
/// plan and approval. Nothing here evaluates filing again, and nothing here
/// authors a second eligibility predicate.
final class MountExplanationContract {
  /// Creates the stateless evaluator.
  const MountExplanationContract();

  /// Explains [bead] against its retained [filing] report, its retained
  /// [dependencies] projection, the pre-read [evidence], and the injected UTC
  /// instant [now].
  MountExplanationReport evaluate({
    required Bead bead,
    required FilingReport filing,
    required DependencyProjection dependencies,
    required MountStateEvidence evidence,
    required DateTime now,
  }) {
    // ONE call to the ONE predicate. Its findings classify the MOUNT side of
    // three rows; the filing report stays the rendered source of the first
    // three details, so `mount` and `filing` cannot describe the same field
    // two ways.
    final findings = mountEligibilityFindings(bead);
    final targets = _localTargets(dependencies, evidence);
    final linked = _linkedSessions(bead, evidence);
    final rows = <MountPreconditionRow>[
      _typeRow(bead, filing, findings, evidence),
      _validationPlanRow(bead, filing, findings, evidence),
      _acceptanceRow(bead, filing, evidence),
      _dependenciesRow(bead, dependencies, evidence, targets),
      _approvalRow(bead, findings),
      _sessionRow(bead, evidence, linked),
      _deferRow(bead, now),
      _verdictCapRow(bead, evidence, linked),
      _mountAttemptCapRow(bead, evidence),
      _liveAdmissionRow(),
    ];
    // Guards LOUD or GONE: the ANSWER is the complete row set in one order, so
    // a row set that drifted from the enum is a defect, not a shorter report.
    if (rows.length != MountPrecondition.values.length) {
      throw StateError(
        'the mount explanation emitted ${rows.length} rows for '
        '${MountPrecondition.values.length} preconditions',
      );
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].precondition != MountPrecondition.values[i]) {
        throw StateError(
          'the mount explanation emitted ${rows[i].precondition.wire} where '
          '${MountPrecondition.values[i].wire} belongs',
        );
      }
    }
    return MountExplanationReport(
      beadId: bead.id,
      preconditions: rows,
      filing: filing,
    );
  }
}

// ── the field rows: the filing report renders, the predicate classifies ──────

/// The retained row for [requirement]; LOUD when the report carries none,
/// because a mount row rendered off a missing filing row would be invented.
FilingRequirementRow _filingRow(
  FilingReport filing,
  FilingRequirement requirement,
) => filing.requirements.firstWhere(
  (row) => row.requirement == requirement,
  orElse: () => throw StateError(
    'the retained filing report carries no ${requirement.wire} row',
  ),
);

/// Whether [findings] — the sole eligibility predicate's output — carries a
/// clause opening with [prefix].
bool _refusedOn(List<String> findings, String prefix) =>
    findings.any((finding) => finding.startsWith(prefix));

MountPreconditionRow _typeRow(
  Bead bead,
  FilingReport filing,
  List<String> findings,
  MountStateEvidence evidence,
) {
  final refused = _refusedOn(findings, 'type:');
  return MountPreconditionRow(
    precondition: MountPrecondition.driveableType,
    outcome: refused ? MountOutcome.blocked : MountOutcome.pass,
    detail: _filingRow(filing, FilingRequirement.driveableType).detail,
    remedy: refused
        ? 'bd -C ${evidence.workStoreRoot} update ${bead.id} '
              '--type <task|bug|feature|chore> --actor <actor> — or re-home '
              'the work under a driveable child. An epic, decision, spike, '
              'story or milestone is organizational and correctly never mounts.'
        : '',
  );
}

MountPreconditionRow _validationPlanRow(
  Bead bead,
  FilingReport filing,
  List<String> findings,
  MountStateEvidence evidence,
) {
  final refused = _refusedOn(findings, 'validation_plan:');
  return MountPreconditionRow(
    precondition: MountPrecondition.validationPlan,
    outcome: refused ? MountOutcome.blocked : MountOutcome.pass,
    detail: _filingRow(filing, FilingRequirement.validationPlan).detail,
    remedy: refused
        ? 'bd -C ${evidence.workStoreRoot} update ${bead.id} --set-metadata '
              "'validation_plan=<command>' --actor <actor> — scope it to every "
              'package the change reaches, not just the one the diff edits.'
        : '',
  );
}

/// Acceptance criteria are not read by the mount predicate — they are read by
/// APPROVAL, which is. A blank one cannot be (re-)stamped, so the bead cannot
/// re-enter the frontier after any edit; the row says exactly that rather than
/// pretending the mount boundary checks it.
MountPreconditionRow _acceptanceRow(
  Bead bead,
  FilingReport filing,
  MountStateEvidence evidence,
) {
  final row = _filingRow(filing, FilingRequirement.acceptanceCriteria);
  return MountPreconditionRow(
    precondition: MountPrecondition.acceptanceCriteria,
    outcome: row.passed ? MountOutcome.pass : MountOutcome.blocked,
    detail: row.passed
        ? row.detail
        : '${row.detail} — the mount predicate does not read it, but the '
              'approve verb does, so an unstamped or re-edited bead can never '
              'be stamped back into the frontier',
    remedy: row.passed
        ? ''
        : 'bd -C ${evidence.workStoreRoot} update ${bead.id} --acceptance '
              "'- [ ] <outcome a named command can falsify>' --actor <actor>",
  );
}

MountPreconditionRow _approvalRow(Bead bead, List<String> findings) {
  final refused = _refusedOn(findings, 'approval:');
  // The STALE arm is read back off the ONE predicate's own finding. This verb
  // renders that classification; it never re-asks the question, because a
  // second approval predicate here is exactly what the row set exists to
  // avoid.
  final stale = _refusedOn(findings, 'approval: stale');
  final stamp = ApprovalStamp.tryParse(bead);
  return MountPreconditionRow(
    precondition: MountPrecondition.approvalStamp,
    outcome: refused ? MountOutcome.blocked : MountOutcome.pass,
    detail: switch ((stale: stale, refused: refused)) {
      (stale: true, refused: _) =>
        'approval: stale — the receipt names revision '
            '${bead.metadata[kApprovedRevKey]}, minted under a RETIRED filing '
            'basis scheme. Nothing re-derives it, so it is not read as an '
            'approval; the bead needs ONE re-approval, not an edit.',
      (stale: false, refused: true) =>
        'approval: not approved — the mount predicate reads the '
            '$kApprovedByKey / $kApprovedAtKey / $kApprovedRevKey receipt '
            'the approve verb writes, and the retired `grid.approved` label '
            'is not read',
      (stale: false, refused: false) =>
        'approved by ${stamp?.by} at ${stamp?.at} against rev ${stamp?.rev}',
    },
    remedy: refused
        ? 'approve --actor <actor> --json ${bead.id} — the verb re-runs the '
              'four-row filing preflight and stamps only if it passes. '
              'APPROVAL STAYS HUMAN: it runs on an explicit per-bead ruling.'
        : '',
  );
}

// ── the dependencies row: the SAME projection, plus target state ─────────────

_LocalTargets _localTargets(
  DependencyProjection dependencies,
  MountStateEvidence evidence,
) {
  final unreadable = [...evidence.unreadableLocalDependencyIds]..sort();
  final byId = {for (final bead in evidence.localDependencies) bead.id: bead};
  final open = <String>[];
  final closed = <String>[];
  for (final id in dependencies.local) {
    final target = byId[id];
    if (target == null) continue;
    (target.isClosed ? closed : open).add(id);
  }
  return _LocalTargets(
    open: open..sort(),
    closed: closed..sort(),
    unreadable: unreadable,
  );
}

MountPreconditionRow _dependenciesRow(
  Bead bead,
  DependencyProjection dependencies,
  MountStateEvidence evidence,
  _LocalTargets targets,
) {
  // The retained projection's own evidence line, VERBATIM and first — the same
  // sentence `filing --json` prints for the same rows.
  final parts = <String>[dependencies.detail];
  if (targets.open.isNotEmpty) {
    parts.add('still OPEN locally: ${targets.open.join(', ')}');
  }
  if (targets.unreadable.isNotEmpty) {
    parts.add(
      'NOT READ BACK (so their state is unknown): '
      '${targets.unreadable.join(', ')}',
    );
  }
  if (targets.open.isEmpty &&
      targets.unreadable.isEmpty &&
      targets.closed.isNotEmpty) {
    parts.add('every local target is closed: ${targets.closed.join(', ')}');
  }

  final rosterRefused = !dependencies.passed;
  final remedies = <String>[];
  if (targets.open.isNotEmpty) {
    remedies.add(
      'finish the named target, or detach the row with '
      '`bd -C ${evidence.workStoreRoot} dep remove ${bead.id} <target>`',
    );
  }
  if (targets.unreadable.isNotEmpty) {
    remedies.add(
      're-point or remove the rows naming ids this store does not hold, then '
      're-run this verb',
    );
  }
  for (final blocker in dependencies.external) {
    switch (blocker.resolution) {
      case ExternalResolution.notArmed:
        remedies.add(
          'arm the substation "${blocker.ref.project}", or re-point '
          '${blocker.ref.wire} at one the roster carries',
        );
      case ExternalResolution.unconsulted:
        remedies.add(
          'pass the station\'s coded roster through `armedSubstations` so '
          '${blocker.ref.wire} can resolve — an unconsulted roster is a '
          'COMPOSITION gap, not a bead defect, and the row stays wired',
        );
      case ExternalResolution.armed:
        break;
    }
  }

  // BLOCKED before UNCHECKED before PASS: a refused row outranks an unasked
  // one, and an unasked one is never a pass.
  final MountOutcome outcome;
  if (rosterRefused || targets.open.isNotEmpty) {
    outcome = MountOutcome.blocked;
  } else if (targets.unreadable.isNotEmpty) {
    outcome = MountOutcome.unchecked;
  } else {
    outcome = MountOutcome.pass;
  }
  return MountPreconditionRow(
    precondition: MountPrecondition.dependencies,
    outcome: outcome,
    detail: parts.join(' — '),
    remedy: outcome == MountOutcome.pass ? '' : remedies.join('; '),
    evidence: [...targets.open, ...targets.unreadable],
    retrievedBy: evidence.localDependencyRetrieval,
  );
}

// ── the state rows ──────────────────────────────────────────────────────────

String _dispositionWire(SessionDisposition disposition) =>
    switch (disposition) {
      NoSession() => 'none',
      LiveSession() => 'live',
      DoneSession() => 'done',
      HeldSession() => 'held',
      VoidedSession() => 'voided',
      PausedSession() => 'paused',
    };

String _sessionLine(SessionProjection row) =>
    '${row.sessionId ?? '<unkeyed>'} work_bead=${row.workBeadId} '
    '${row.isTerminal ? 'closed' : 'open'} '
    '${_dispositionWire(sessionDispositionOf(row))}';

_LinkedSessions _linkedSessions(Bead bead, MountStateEvidence evidence) {
  final beadsBySessionId = {
    for (final session in evidence.sessions) session.id: session,
  };
  final mine = <SessionProjection>[
    for (final session in evidence.sessions)
      if (StationTrajectoryRecorder.parseLegacyWorkKey(
            '${session.metadata[SessionBeadKeys.workBead] ?? ''}',
          ).workBeadId ==
          bead.id)
        projectSession(session),
  ];
  // The join's OWN membership key decides a contender. A terminal `#r<N>` or
  // `#void-` row keys to itself and is therefore history; a NON-terminal one
  // normalizes back to the bare bead and is an anomalous open tombstone, which
  // is exactly the state that blocks re-mount indefinitely.
  final contenders = [
    for (final row in mine)
      if (linkedWorkBeadKeyOf(row) == bead.id) row,
  ];
  final history = [
    for (final row in mine)
      if (linkedWorkBeadKeyOf(row) != bead.id) row,
  ];
  return _LinkedSessions(
    contenders: contenders,
    history: history,
    verdict: linkedSessionVerdictOf(contenders),
    beadsBySessionId: beadsBySessionId,
  );
}

/// The unchecked row every state-backed precondition falls back to.
MountPreconditionRow _stateUnchecked(
  MountPrecondition precondition,
  MountStateEvidence evidence,
) => MountPreconditionRow(
  precondition: precondition,
  outcome: MountOutcome.unchecked,
  detail:
      '${evidence.unavailableDetail} — this condition was NOT asked, so it is '
      'not a pass',
  remedy:
      're-run with --state-root <grid-home> pointing at the home whose '
      '.grid/.beads holds the session-lifecycle beads',
);

MountPreconditionRow _sessionRow(
  Bead bead,
  MountStateEvidence evidence,
  _LinkedSessions linked,
) {
  if (!evidence.stateStoreConsulted) {
    return _stateUnchecked(MountPrecondition.sessionOccupancy, evidence);
  }
  final evidenceLines = [
    for (final row in [...linked.contenders, ...linked.history])
      _sessionLine(row),
  ]..sort();
  final historyNote = linked.history.isEmpty
      ? 'no retired or void-rekeyed history'
      : '${linked.history.length} terminal dead-key row(s) remain history';

  MountPreconditionRow row(
    MountOutcome outcome,
    String detail, {
    String remedy = '',
  }) => MountPreconditionRow(
    precondition: MountPrecondition.sessionOccupancy,
    outcome: outcome,
    detail: detail,
    remedy: remedy,
    evidence: evidenceLines,
    retrievedBy: evidence.sessionRetrieval,
  );

  switch (linked.verdict) {
    case NoLinkedSession():
      return row(
        MountOutcome.pass,
        'no session row links ${bead.id}; the next mount mints its first '
        'round ($historyNote)',
      );
    case AdoptLinkedSession(:final session, :final rivals):
      if (rivals.isNotEmpty) {
        return row(
          MountOutcome.blocked,
          'TWIN MINT: ${rivals.length + 1} open rows link ${bead.id} — '
          '${[session, ...rivals].map((r) => r.sessionId ?? '<unkeyed>').join(', ')}. '
          'The engine never auto-resolves this: demoting one would hide a '
          'running agent',
          remedy:
              'the GOVERNOR resolves it — park the session that is not driving '
              '(`park --actor <actor> --reason \'<why>\' --until <date> '
              '--state-root ${evidence.gridHome} ${bead.id}`), which closes and '
              'void-retires it. This verb never performs it.',
        );
      }
      if (session.workBeadId != bead.id) {
        return row(
          MountOutcome.blocked,
          'an OPEN session carries the TOMBSTONE key '
          '"${session.workBeadId}" (session '
          '${session.sessionId ?? '<unkeyed>'}) — retirement closes a row, so '
          'a non-terminal tombstone is anomalous and keeps the bare bead '
          'joined to a row nothing will drive',
          remedy:
              'the GOVERNOR resolves it — park the session '
              '(`park --actor <actor> --reason \'<why>\' --until <date> '
              '--state-root ${evidence.gridHome} ${bead.id}`) so it is closed '
              'and void-retired onto a terminal key. This verb never performs '
              'it.',
        );
      }
      return row(
        MountOutcome.pass,
        'one open session (${session.sessionId ?? '<unkeyed>'}) holds the bare '
        '${SessionBeadKeys.workBead} key with no rival — the next reconcile '
        'ADOPTS it ($historyNote)',
      );
    case BlockedLinkedSession(:final session):
      final disposition = sessionDispositionOf(session);
      final id = session.sessionId ?? '<unkeyed>';
      return switch (disposition) {
        DoneSession() => row(
          MountOutcome.blocked,
          'session $id closed at a DELIVERED positive terminal '
          '(${SessionBeadKeys.outcome}) — the work source is read-only, so the '
          'closed session is the only latch that stops the station re-driving '
          'landed work',
          remedy:
              'the round DELIVERED: close the work bead with its receipts '
              '(`bd -C ${evidence.workStoreRoot} close ${bead.id} --reason '
              "'<paths, commit ids>' --actor <actor>`). If it did NOT deliver, "
              'that is a governor ruling, not a re-mount.',
        ),
        HeldSession(:final reason) => row(
          MountOutcome.blocked,
          'session $id is HELD for a human: $reason',
          remedy:
              "rework --note '<why this round gets another budget>' "
              '${bead.id} — the verb retires the held round and mints the '
              'next one. It is the governor\'s.',
        ),
        PausedSession(:final reason) => row(
          MountOutcome.blocked,
          'session $id is OPEN but operator-PAUSED: $reason',
          remedy:
              'resume ${bead.id} — the pause is non-terminal and the cursor is '
              'preserved, so the session re-competes for a slot.',
        ),
        NoSession() || LiveSession() || VoidedSession() => row(
          MountOutcome.blocked,
          'ANOMALY: session $id is published as BLOCKING while its disposition '
          'reads ${_dispositionWire(disposition)}, which does not block — the '
          "engine's own union disagrees with itself about this row",
          remedy:
              'escalate to the governor with this session id; do not re-mint '
              'around it.',
        ),
      };
    case RemintLinkedSession(:final session, :final surplus):
      return row(
        MountOutcome.pass,
        'every linked row is a terminal, non-blocking DEAD KEY (published: '
        '${session.sessionId ?? '<unkeyed>'}; ${surplus.length} older surplus '
        'row(s)) — the next mount retires them and mints fresh ($historyNote)',
      );
  }
}

MountPreconditionRow _deferRow(Bead bead, DateTime now) {
  final deferUntil = bead.deferUntil?.toUtc();
  final deferred = bead.status == BeadStatus.deferred;
  final scheduled = deferUntil != null && deferUntil.isAfter(now);
  final until = deferUntil?.toIso8601String() ?? '<none>';
  if (!deferred && !scheduled) {
    return MountPreconditionRow(
      precondition: MountPrecondition.deferState,
      outcome: MountOutcome.pass,
      detail:
          'status=${bead.status.wire}, defer_until=$until — the bead is not '
          'held out of the ready frontier at ${now.toIso8601String()}',
    );
  }
  return MountPreconditionRow(
    precondition: MountPrecondition.deferState,
    outcome: MountOutcome.blocked,
    detail:
        'status=${bead.status.wire}, defer_until=$until — a deferred bead is '
        'not READY, so the frontier never offers it at '
        '${now.toIso8601String()}',
    remedy:
        'unpark --actor <actor> ${bead.id} — it clears the defer DATE and the '
        'status together (a reopen alone leaves defer_until set and the bead '
        'silently never mints) and re-runs the approval preflight.',
  );
}

MountPreconditionRow _verdictCapRow(
  Bead bead,
  MountStateEvidence evidence,
  _LinkedSessions linked,
) {
  if (!evidence.stateStoreConsulted) {
    return _stateUnchecked(MountPrecondition.verdictCap, evidence);
  }
  final winner = linked.verdict.winner;
  final winnerId = winner?.sessionId;
  final spentByPath = winnerId == null
      ? const <String, int>{}
      : supersedesVerdictCountByPath(
          evidence.stepsBySession[winnerId] ?? const <Bead>[],
          evidence.stepDependenciesBySession[winnerId] ??
              const <BeadDependency>[],
        );
  final exhaustedPaths = [
    for (final entry
        in (spentByPath.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
      if (entry.value >= kMaxReworkRounds)
        '${entry.key}=${entry.value}/$kMaxReworkRounds',
  ];
  // Historical exhaustion is evidence for the RETIRED round it belongs to; it
  // never permanently blocks a later current round, so only the published
  // round's own step paths are compared against the cap.
  final retired = <RetiredReworkRound>[
    for (final row in linked.history)
      if (reworkRoundOf(bead.id, row.workBeadId) != null)
        (
          workBeadKey: row.workBeadId,
          reachedVerdict:
              linked.beadsBySessionId[row.sessionId] != null &&
              reworkVerdictEvidence(
                session: linked.beadsBySessionId[row.sessionId]!,
                steps: evidence.stepsBySession[row.sessionId] ?? const <Bead>[],
              ).reachedVerdict,
        ),
  ];
  final spentRounds = spentReworkRounds(bead.id, retired);
  final roundsSpent = spentRounds >= kMaxReworkRounds;
  final blocked = exhaustedPaths.isNotEmpty || roundsSpent;
  final lines = <String>[
    for (final key in exhaustedPaths) 'step $key',
    for (final round in retired)
      'retired ${round.workBeadKey} '
          '${round.reachedVerdict ? 'spent a verdict' : 'spent nothing'}',
  ];
  return MountPreconditionRow(
    precondition: MountPrecondition.verdictCap,
    outcome: blocked ? MountOutcome.blocked : MountOutcome.pass,
    detail: blocked
        ? 'the verdict budget is SPENT: $spentRounds/$kMaxReworkRounds retired '
              'rounds reached a verdict'
              '${exhaustedPaths.isEmpty ? '' : ', and the published round has '
                        'exhausted step path(s) ${exhaustedPaths.join(', ')}'}'
        : 'verdict budget available: $spentRounds/$kMaxReworkRounds retired '
              'rounds reached a verdict, and no step path of the published '
              'round is at the cap '
              '(${winnerId ?? 'no published session'})',
    remedy: blocked
        ? "rework --note '<why this bead gets another budget>' ${bead.id}"
              '${roundsSpent ? ' --beyond-cap --actor <actor> (the retired-round '
                        'budget is spent too, so the cap must be crossed '
                        'deliberately)' : ''}'
        : '',
    evidence: lines,
    retrievedBy: evidence.stepRetrieval,
  );
}

MountPreconditionRow _mountAttemptCapRow(
  Bead bead,
  MountStateEvidence evidence,
) {
  if (!evidence.stateStoreConsulted) {
    return _stateUnchecked(MountPrecondition.mountAttemptCap, evidence);
  }
  final records = <MountAttemptRecord>[
    for (final attempt in evidence.mountAttempts)
      if (projectMountAttempt(attempt) case final record?)
        if (record.workBeadId == bead.id) record,
  ]..sort((a, b) => a.recordId.compareTo(b.recordId));
  final exhausted = records.where((record) => record.isExhausted).toList();
  return MountPreconditionRow(
    precondition: MountPrecondition.mountAttemptCap,
    outcome: exhausted.isEmpty ? MountOutcome.pass : MountOutcome.blocked,
    detail: exhausted.isEmpty
        ? 'the durable remount budget is available: '
              '${records.isEmpty ? 'no' : records.map((r) => r.count).reduce((a, b) => a > b ? a : b).toString()}'
              ' of $kMaxMountAttempts attempt(s) recorded'
        : 'the durable remount budget is SPENT: '
              '${exhausted.map((r) => '${r.count}').join(', ')} of '
              '$kMaxMountAttempts attempts — the frontier stops remounting a '
              'bead at the cap so a crash loop becomes visibly '
              'human-attention-requiring',
    remedy: exhausted.isEmpty
        ? ''
        : 'bead rearm --grid-root ${evidence.gridHome} --actor <actor> '
              "--reason '<why this bead is worth another mount>' ${bead.id} — "
              'the reset is a RESIDENT verb, so a station must be up to run it.',
    evidence: [
      for (final record in records)
        '${record.recordId} count=${record.count}/$kMaxMountAttempts',
    ],
    retrievedBy: evidence.mountAttemptRetrieval,
  );
}

/// The one row this verb can NEVER answer, reported as unasked rather than
/// omitted.
MountPreconditionRow _liveAdmissionRow() => MountPreconditionRow(
  precondition: MountPrecondition.liveAdmission,
  outcome: MountOutcome.unchecked,
  detail:
      'capacity, slot reservations, admission latches, process liveness and '
      'the engine-only session-mint and step-successor retry counters live in '
      "a running station's MEMORY, not in any store — this verb is offline, so "
      'they were NOT asked',
  remedy:
      "read the resident `status` verb's StationAdmissionStatus surface "
      'against the live station; send whatever survives these ten rows to '
      'relay inference, which is the cheap pass OVER the mechanical answer, '
      'never a replacement for it.',
);

// ── the bound ───────────────────────────────────────────────────────────────

/// [report] rendered down to [kBoundedOutputCapBytes] in BOTH renderings.
///
/// The cap, the both-renderings-must-fit predicate and the search for the
/// largest candidate that fits are the PACK's — [boundedOutput] owns them. What
/// is THIS verb's is the policy: a precondition ROW is never removed, because
/// the row set IS the answer; only the TAIL of a row's evidence list is given
/// up, in precondition order, and every cut names the count withheld and the
/// exact scoped read that retrieves it.
MountExplanationReport boundedMountExplanation(MountExplanationReport report) {
  final policy = _MountTrimPolicy(report);
  return boundedOutput<MountExplanationReport>(
    complete: report,
    maximumTrimBudget: policy.maximumBudget,
    renderPlain: renderMountExplanationPlain,
    renderJson: (value) => jsonEncode(value.toJson()),
    trim: policy.at,
  );
}

/// This verb's trim POLICY, in units of whole evidence ENTRIES.
final class _MountTrimPolicy {
  const _MountTrimPolicy(this._report);

  final MountExplanationReport _report;

  /// Every evidence entry the report could possibly give up.
  int get maximumBudget =>
      _report.preconditions.fold(0, (sum, row) => sum + row.evidence.length);

  /// The report keeping the leading [budget] evidence entries, poured in
  /// precondition order — MONOTONE in [budget], because each row's keep count
  /// only grows with the budget the pour reaches it with.
  MountExplanationReport at(int budget) {
    var remaining = budget;
    final rows = <MountPreconditionRow>[];
    final withheld = <MountPrecondition, int>{};
    final retrievals = <String>[];
    for (final row in _report.preconditions) {
      final keep = row.evidence.length <= remaining
          ? row.evidence.length
          : remaining;
      remaining -= keep;
      if (keep == row.evidence.length) {
        rows.add(row);
        continue;
      }
      withheld[row.precondition] = row.evidence.length - keep;
      retrievals.add(row.retrievedBy);
      rows.add(row.truncatedTo(keep));
    }
    return MountExplanationReport(
      beadId: _report.beadId,
      preconditions: rows,
      filing: _report.filing,
      withheld: withheld,
      withheldRetrievedBy: retrievals.join(' && '),
      error: _report.error,
    );
  }
}

// ── the plain rendering ─────────────────────────────────────────────────────

/// The plain rendering of one bounded [report] — the single renderer both the
/// bound calculation and [MountCommand] consume, so what the cap is measured
/// against is exactly what is printed.
String renderMountExplanationPlain(MountExplanationReport report) {
  if (report.error case final error?) {
    return 'REFUSED ${report.beadId}: $error';
  }
  final buffer = StringBuffer('MOUNT ${report.beadId}: ${report.verdict.wire}');
  for (final row in report.preconditions) {
    buffer.write(
      '\n${row.outcome.wire} ${row.precondition.wire}: ${row.detail}',
    );
    if (row.evidence.isNotEmpty) {
      buffer.write('\n  evidence: ${row.evidence.join('; ')}');
    }
  }
  for (final row in report.preconditions) {
    if (row.remedy.isEmpty) continue;
    buffer.write('\nREMEDY ${row.precondition.wire}: ${row.remedy}');
  }
  if (report.withheld.isNotEmpty) {
    final counts = [
      for (final precondition in MountPrecondition.values)
        if (report.withheld[precondition] case final count?)
          '${precondition.wire}=$count',
    ];
    buffer.write(
      '\nWITHHELD ${counts.join(', ')} evidence entries — retrieve with: '
      '${report.withheldRetrievedBy}',
    );
  }
  return buffer.toString();
}

// ── the service ─────────────────────────────────────────────────────────────

/// Renders [argv] as the copy-pasteable `bd` read it is, rooted at [root].
String _readCommand(String root, List<String> argv) => [
  'bd',
  '-C',
  root,
  for (final arg in argv) arg.contains(' ') ? "'$arg'" : arg,
].join(' ');

/// UI-drivable mount explanation: ONE filing inspect, ONE id-scoped work-store
/// read, and the grid home's scoped session/step/attempt lists — then the pure
/// contract and the pack's bound.
final class MountExplanationService {
  /// Creates the service over four injectable seams.
  ///
  /// [runnerFor] is the SAME per-store bd runner seam `ParkService` and
  /// `ShowService` take, so one Fake fences every spawn this verb makes.
  /// [filing] defaults to a service built on that same seam, which is what
  /// makes `mount` and `filing` answer one contract one way.
  MountExplanationService({
    FilingService? filing,
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    MountExplanationContract contract = const MountExplanationContract(),
    DateTime Function() now = _utcNow,
  }) : filing =
           filing ??
           FilingService(
             source: ExactSubstationBeadSource(runnerFor: runnerFor),
           ),
       _runnerFor = runnerFor,
       _contract = contract,
       _now = now;

  /// The ONE read/evaluate path the `filing` verb rides too.
  final FilingService filing;

  final BdRunner Function(String storeRoot) _runnerFor;
  final MountExplanationContract _contract;
  final DateTime Function() _now;

  /// Explains [beadId], read out of [workStoreRoot] and — when [stateRoot] is
  /// non-null — the grid home's state store.
  ///
  /// A null [stateRoot] is NOT an error: the run continues and the three
  /// state-backed rows come back unchecked, naming the option that would answer
  /// them. [armedSubstations] is the station's roster by NAME, handed straight
  /// to the filing evaluation's dependency projection.
  Future<MountExplanationReport> explain({
    required String workStoreRoot,
    required String beadId,
    String? stateRoot,
    Set<String>? armedSubstations,
  }) async {
    final inspected = await filing.inspect(
      storeRoot: workStoreRoot,
      beadId: beadId,
      armedSubstations: armedSubstations,
    );
    final bead = inspected.bead;
    final projection = inspected.dependencyProjection;
    if (bead == null || projection == null) {
      return MountExplanationReport.missing(beadId);
    }
    final evidence = await _read(
      bead: bead,
      projection: projection,
      workStoreRoot: workStoreRoot,
      stateRoot: stateRoot,
    );
    return boundedMountExplanation(
      _contract.evaluate(
        bead: bead,
        filing: inspected.report,
        dependencies: projection,
        evidence: evidence,
        now: _now().toUtc(),
      ),
    );
  }

  Future<MountStateEvidence> _read({
    required Bead bead,
    required DependencyProjection projection,
    required String workStoreRoot,
    required String? stateRoot,
  }) async {
    final work = BdCliService(_runnerFor(workStoreRoot));
    var localDependencies = const <Bead>[];
    var unreadable = const <String>[];
    var localRetrieval = '';
    if (projection.local.isNotEmpty) {
      final expression = projection.local.map((id) => 'id=$id').join(' OR ');
      localRetrieval = _readCommand(
        workStoreRoot,
        work.queryArgs(expression, includeClosed: true),
      );
      try {
        localDependencies = await work.query(expression, includeClosed: true);
        final found = {for (final target in localDependencies) target.id};
        unreadable = [
          for (final id in projection.local)
            if (!found.contains(id)) id,
        ];
      } on Object {
        // Fail closed: a read that refused says nothing about the targets, so
        // every one of them is unknown rather than clear.
        unreadable = [...projection.local];
      }
    }

    if (stateRoot == null) {
      return MountStateEvidence(
        workStoreRoot: workStoreRoot,
        localDependencies: localDependencies,
        unreadableLocalDependencyIds: unreadable,
        localDependencyRetrieval: localRetrieval,
        unavailableDetail:
            'no --state-root was supplied, so the grid home\'s '
            'session-lifecycle store was never opened',
      );
    }

    final state = BdCliService(_runnerFor(stateRoot));
    final sessionRetrieval = _readCommand(
      stateRoot,
      state.listScopeArgs(type: GridIssueTypes.session, includeClosed: true),
    );
    final stepRetrieval = _readCommand(
      stateRoot,
      state.listScopeArgs(
        type: GridIssueTypes.step,
        metadataFields: const {MoleculeStepKeys.session: '<session-id>'},
        includeClosed: true,
      ),
    );
    final attemptRetrieval = _readCommand(
      stateRoot,
      state.listScopeArgs(
        type: GridIssueTypes.mountAttempt,
        metadataFields: {MountAttemptKeys.workBead: bead.id},
        includeClosed: true,
      ),
    );
    try {
      final sessions = (await state.listScope(
        type: GridIssueTypes.session,
        includeClosed: true,
      )).beads;
      final stepsBySession = <String, List<Bead>>{};
      final stepDependenciesBySession = <String, List<BeadDependency>>{};
      for (final session in sessions) {
        final key = '${session.metadata[SessionBeadKeys.workBead] ?? ''}';
        if (StationTrajectoryRecorder.parseLegacyWorkKey(key).workBeadId !=
            bead.id) {
          continue;
        }
        final scope = await state.listScope(
          type: GridIssueTypes.step,
          metadataFields: {MoleculeStepKeys.session: session.id},
          includeClosed: true,
        );
        stepsBySession[session.id] = scope.beads;
        stepDependenciesBySession[session.id] = scope.dependencies;
      }
      final attempts = (await state.listScope(
        type: GridIssueTypes.mountAttempt,
        metadataFields: {MountAttemptKeys.workBead: bead.id},
        includeClosed: true,
      )).beads;
      return MountStateEvidence(
        workStoreRoot: workStoreRoot,
        stateRoot: stateRoot,
        localDependencies: localDependencies,
        unreadableLocalDependencyIds: unreadable,
        localDependencyRetrieval: localRetrieval,
        sessions: sessions,
        stepsBySession: stepsBySession,
        stepDependenciesBySession: stepDependenciesBySession,
        mountAttempts: attempts,
        sessionRetrieval: sessionRetrieval,
        stepRetrieval: stepRetrieval,
        mountAttemptRetrieval: attemptRetrieval,
      );
    } on Object catch (error) {
      // Fail closed: a partial state read is reported as NO state read, so a
      // row can never go green on a collection that is empty because the store
      // refused rather than because the state is absent.
      return MountStateEvidence(
        workStoreRoot: workStoreRoot,
        stateRoot: stateRoot,
        localDependencies: localDependencies,
        unreadableLocalDependencyIds: unreadable,
        localDependencyRetrieval: localRetrieval,
        sessionRetrieval: sessionRetrieval,
        stepRetrieval: stepRetrieval,
        mountAttemptRetrieval: attemptRetrieval,
        unavailableDetail:
            'reading the state store at $stateRoot failed '
            '(${error.runtimeType}): $error',
      );
    }
  }
}

/// `mount [--json] [--state-root <grid-home>] <bead-id>` — the offline
/// EXPLAINER for why one bead will not mount.
///
/// Its own command, never an alias of `filing`: an alias shares ONE argParser,
/// and registering `--state-root` on it would put back on `filing` the option
/// `power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`
/// deleted. It is the THIRD consumer of [addStateRootOption]/[resolveStateRoot]
/// beside `park` and `show`, with the same name, help, default, grid-home
/// resolution and loud invalid-root refusal.
class MountCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// [storeRoot] is the WORK store the bead is read from (the CWD by default);
  /// [stateRoot] is the station-injected grid home; [armedSubstations] is the
  /// station-injected roster by NAME — the SAME seam `filing` and `approve`
  /// take, fail-closed by default ([noArmedSubstations]).
  MountCommand({
    MountExplanationService? service,
    String Function() storeRoot = _currentDirectory,
    String? Function() stateRoot = noStateRoot,
    Set<String>? Function() armedSubstations = noArmedSubstations,
    StringSink? out,
    StringSink? err,
  }) : _service = service ?? MountExplanationService(),
       _storeRoot = storeRoot,
       _stateRoot = stateRoot,
       _armedSubstations = armedSubstations,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser.addFlag(
      'json',
      negatable: false,
      help:
          'Emit {id, verdict, preconditions, filing, withheld?, '
          'withheld_retrieved_by?, error?} as one JSON object.',
    );
    addStateRootOption(argParser);
  }

  final MountExplanationService _service;
  final String Function() _storeRoot;
  final String? Function() _stateRoot;
  final Set<String>? Function() _armedSubstations;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'mount';

  @override
  final String description =
      'Explain, offline, every precondition one bead must satisfy before a '
      'station will mount it — with the remedy for each one that fails.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'mount [--json] [--state-root <grid-home>] <bead-id>';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('mount: exactly one bead id is required — $invocation');
      return 64;
    }
    final beadId = rest.single.trim();
    final String? stateRoot;
    try {
      stateRoot = resolveStateRoot(argResults!, _stateRoot);
    } on Object catch (error) {
      _err.writeln('mount: $error');
      return 1;
    }
    final MountExplanationReport report;
    try {
      report = await _service.explain(
        workStoreRoot: p.normalize(_storeRoot()),
        beadId: beadId,
        stateRoot: stateRoot,
        armedSubstations: _armedSubstations(),
      );
    } on Object catch (error) {
      _err.writeln('mount: failed to explain $beadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(report.toJson()));
    } else {
      _out.writeln(renderMountExplanationPlain(report));
    }
    return switch (report.verdict) {
      MountOutcome.pass => 0,
      MountOutcome.blocked => 1,
      MountOutcome.unchecked => 2,
    };
  }
}
