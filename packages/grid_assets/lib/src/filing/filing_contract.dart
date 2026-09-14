import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:grid_engine/grid_engine.dart';

import '../search/station_search.dart';
import 'approval_stamp.dart';

/// The four mechanical checks reported for a newly filed bead.
enum FilingRequirement {
  driveableType('driveable_type'),
  validationPlan('validation_plan'),
  acceptanceCriteria('acceptance_criteria'),
  dependencies('dependencies');

  const FilingRequirement(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// One deterministic filing requirement result.
final class FilingRequirementRow {
  /// Creates one result row.
  const FilingRequirementRow({
    required this.requirement,
    required this.passed,
    required this.detail,
  });

  /// Requirement evaluated by this row.
  final FilingRequirement requirement;

  /// Whether the filed bead satisfies the requirement.
  final bool passed;

  /// Human-readable evidence or correction.
  final String detail;

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'requirement': requirement.wire,
    'passed': passed,
    'detail': detail,
  };
}

/// The complete filing report for one bead id.
final class FilingReport {
  /// Creates a report.
  const FilingReport({
    required this.beadId,
    required this.requirements,
    this.approvalRevision = '',
    this.error,
  });

  /// Creates the loud unknown-id report with no passing rows.
  factory FilingReport.missing(String beadId) => FilingReport(
    beadId: beadId,
    requirements: const <FilingRequirementRow>[],
    error: 'bead not found',
  );

  /// Bead id checked.
  final String beadId;

  /// Four rows for a found bead, in [FilingRequirement.values] order.
  final List<FilingRequirementRow> requirements;

  /// The revision this filing WOULD be approved against — the deterministic
  /// digest of everything the four rows are evaluated over. Empty for a report
  /// with no bead to evaluate.
  ///
  /// This is what `ApproveService` stamps as `grid.approved_rev` and what the
  /// mount gate re-derives to tell a live receipt from a stale one.
  final String approvalRevision;

  /// Lookup-level refusal; non-null reports never pass.
  final String? error;

  /// True only for a found bead with exactly four passing rows.
  bool get passed =>
      error == null &&
      requirements.length == FilingRequirement.values.length &&
      requirements.every((row) => row.passed);

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'id': beadId,
    'passed': passed,
    'approval_revision': approvalRevision,
    'requirements': [for (final row in requirements) row.toJson()],
    if (error case final error?) 'error': error,
  };
}

/// Splits a description where a blocker DECLARATION can end: a sentence
/// terminator followed by whitespace or end-of-input, or a line break. A `.`
/// followed by a word character stays inside its segment, so dotted child ids
/// (`pow-n6n.1`) survive the split.
final RegExp _segmentBreak = RegExp(r'(?:[.!?;](?=\s|$)|\n)+');

/// A segment DECLARES blockers only when it OPENS with the phrase, after any
/// list or quote marker: `Blocked by: pow-one` on its own line declares, and
/// `pow-pry0 carries a 'DEPENDS ON: tg-1n4y' receipt` only MENTIONS one.
final RegExp _leadingBlockerPhrase = RegExp(
  r'^[\s>*#-]*(?:\d+[.)]\s*)?(?:blocked\s+(?:by|on)|depends\s+on)\b',
  caseSensitive: false,
);

/// A `<prefix>-<tail>` token — the SHAPE of a bead id. Shape alone does not
/// make one: [_isBeadId] decides.
final RegExp _candidateId = RegExp(r'\b[a-z][a-z0-9_]*(?:-[a-z0-9_.]+)+\b');

final RegExp _digit = RegExp(r'[0-9]');

/// The store prefix of [id] — `pow` for `pow-n6n.1`; empty when [id] carries
/// no prefix at all.
String _prefixOf(String id) {
  final hyphen = id.indexOf('-');
  return hyphen <= 0 ? '' : id.substring(0, hyphen);
}

/// True when [candidate] reads as a bead id rather than a hyphenated English
/// compound (`cross-store`, `read-only`): its prefix is one this check already
/// knows ([knownPrefixes] — the checked bead's own store, plus the store of
/// every blocker already wired), or its tail carries a digit.
///
/// The prefix arm is what keeps digitless ids (`pow-one`, `filing-blocker`)
/// readable; requiring a digit alone would silently stop naming them.
///
/// Since the_grid#447 "already wired" means a LOCAL outgoing `blocks` edge and
/// nothing else, so a FOREIGN store's prefix reaches this check only when the
/// bead already wires a local blocker in that store. A digitless foreign id
/// (`pow-abaw` named from a `space-` bead) is therefore not read as an id at
/// all and never reaches the dependency row — that row is fail-closed only for
/// the tokens this check still recognises, and silent about the rest. Reading
/// a foreign blocker from bd's own `external:` rows instead of from prose is
/// pow-f6pc (power_station#330).
bool _isBeadId(String candidate, Set<String> knownPrefixes) {
  final hyphen = candidate.indexOf('-');
  return knownPrefixes.contains(candidate.substring(0, hyphen)) ||
      _digit.hasMatch(candidate.substring(hyphen + 1));
}

/// The blocker ids DECLARED by [description] — read ONLY from segments that
/// open with a blocker phrase, and only from tokens [_isBeadId] accepts.
Set<String> _namedBlockers(String description, Set<String> knownPrefixes) => {
  for (final segment in description.split(_segmentBreak))
    if (_leadingBlockerPhrase.matchAsPrefix(segment) case final phrase?)
      for (final match in _candidateId.allMatches(
        segment.substring(phrase.end),
      ))
        if (_isBeadId(match.group(0)!, knownPrefixes)) match.group(0)!,
};

/// The version-1 approval revision of one evaluated filing.
///
/// It digests exactly what an approval is a judgement ABOUT: the bead's work
/// fields, its validation plan, and — per named blocker, sorted — whether a
/// local outgoing `blocks` edge and an open linked-blocker proof were found.
/// Lifecycle timestamps, status, assignee/owner, result metadata and the
/// receipt itself are all EXCLUDED, so stamping the receipt can never
/// invalidate the receipt it stamps, and a bead moving through its lifecycle
/// does not revoke a governor's approval of its content.
///
/// The `linked` member is FROZEN at false, and that is a BASIS CHANGE for one
/// shape of bead rather than a no-op. The basis SHAPE stays v1
/// ([kFilingApprovalRevisionPrefix]): every stamp already written is a digest
/// over these same keys, and DROPPING the member would re-digest every
/// approved bead in every store. Its VALUE, though, can no longer be true,
/// because the state-store link surface that set it is deleted (grid_engine
/// 0.4.0-dev.3, the_grid#447). A bead approved while that store was CONSULTED
/// and a link MATCHED digested `linked: true`, and the matched blocker also
/// put its store prefix into the `knownPrefixes` that let a digitless foreign
/// id be NAMED at all. Both inputs are gone, so such a bead re-digests here,
/// its standing `grid.approved_rev` reads stale, and `approve`/`unpark` refuse
/// it until a governor re-approves.
///
/// MEASURED 2026-09-13 against space_station `space-7tj`, approved that day at
/// `filing:v1:sha256:2ff365a6…`: this code digests it
/// `filing:v1:sha256:caf7bb15…` and fails its dependency row closed on
/// `pow-f6pc`. Mount is not blocked by that today only because
/// `mountEligibilityFindings` carries the revision without enforcing it; the
/// approve verb's staleness report and the audit trail are affected now. The
/// re-approval sweep is the governor's, named in pow-abaw's PR, not done here.
///
/// Re-proving a cross-store blocker from bd's own `external:` rows is a v2
/// basis behind a NEW prefix (pow-f6pc, power_station#330), and a v2 basis
/// re-digests every store; that is its own bead.
String _approvalRevisionOf(
  Bead bead, {
  required Set<String> named,
  required Set<String> localBlocks,
}) {
  final plan = bead.metadata['validation_plan'];
  final basis = <String, Object?>{
    'id': bead.id,
    'title': bead.title,
    'description': bead.description,
    'design': bead.design,
    'acceptanceCriteria': bead.acceptanceCriteria,
    'notes': bead.notes,
    'specId': bead.specId,
    'issueType': bead.issueType.wire,
    'priority': bead.priority,
    'validationPlan': plan is String ? plan : null,
    'dependencies': [
      for (final id in named.toList()..sort())
        {'id': id, 'blocks': localBlocks.contains(id), 'linked': false},
    ],
  };
  final digest = sha256.convert(utf8.encode(jsonEncode(basis)));
  return '$kFilingApprovalRevisionPrefix$digest';
}

/// Pure evaluator for the four-row filing report.
///
/// This is the FILING COMPLETENESS contract of
/// `power_station#approval-is-the-stamp-the-grid-approved-label-retires` —
/// *"FILING COMPLETENESS in `lib/src/filing/`, MOUNT ELIGIBILITY in
/// `lib/src/code/`, neither subsuming the other, no third completeness
/// predicate minted"*. The unchecked cross-store arm is a refinement of this
/// contract's own dependency row, not a fifth requirement and not a second
/// predicate.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against its [dependencies].
  ///
  /// Wiring is the bead's OWN outgoing `blocks` edges and nothing else. The
  /// cross-store arm is gone with the state-store link surface it read
  /// (grid_engine 0.4.0-dev.3, the_grid#447): a named foreign blocker with no
  /// local edge is reported missing, fail-closed, exactly like a local one —
  /// PROVIDED the token is still read as an id. A digitless foreign id loses
  /// the wired-blocker prefix that made it readable ([_isBeadId]) and is not
  /// named at all, so its row passes vacuously. Both of those outcomes differ
  /// from the pre-cut consulted evaluation, and both move the approval
  /// revision ([_approvalRevisionOf]).
  ///
  /// A blocker is DECLARED by a description segment that OPENS with
  /// `Blocked by` / `Blocked on` / `Depends on`; a mid-sentence mention of the
  /// phrase declares nothing. Within such a segment a `<prefix>-<tail>` token
  /// is a bead id when its prefix is the bead's own store or that of an
  /// already-wired blocker, or when its tail carries a digit.
  FilingReport evaluate(Bead bead, Iterable<BeadDependency> dependencies) {
    final validationPlan = bead.metadata['validation_plan'];
    final localBlocks = {
      for (final edge in dependencies)
        if (edge.issueId == bead.id && edge.type == DependencyType.blocks)
          edge.dependsOnId,
    };
    final ownPrefix = _prefixOf(bead.id);
    final knownPrefixes = <String>{
      ownPrefix,
      for (final id in localBlocks) _prefixOf(id),
    }..remove('');
    final named = _namedBlockers(bead.description, knownPrefixes);
    final missing = named.difference(localBlocks).toList()..sort();
    final dependencyPass = missing.isEmpty;
    final dependencyDetail = dependencyPass
        ? (named.isEmpty
              ? 'no local blockers named'
              : 'all named local blockers are wired')
        : 'missing outgoing blocks edges: ${missing.join(', ')}';
    return FilingReport(
      beadId: bead.id,
      approvalRevision: _approvalRevisionOf(
        bead,
        named: named,
        localBlocks: localBlocks,
      ),
      requirements: [
        FilingRequirementRow(
          requirement: FilingRequirement.driveableType,
          passed: bead.issueType.isDriveable,
          detail: bead.issueType.isDriveable
              ? '${bead.issueType.wire} is driveable'
              : '${bead.issueType.wire} is not driveable',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.validationPlan,
          passed: validationPlan is String && validationPlan.trim().isNotEmpty,
          detail: validationPlan is String && validationPlan.trim().isNotEmpty
              ? 'validation_plan is present'
              : 'validation_plan is blank',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.acceptanceCriteria,
          passed: bead.acceptanceCriteria.trim().isNotEmpty,
          detail: bead.acceptanceCriteria.trim().isNotEmpty
              ? 'acceptance_criteria is present'
              : 'acceptance_criteria is blank',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.dependencies,
          passed: dependencyPass,
          detail: dependencyDetail,
        ),
      ],
    );
  }
}

/// UI-drivable filing lookup plus contract evaluation.
final class FilingService {
  /// Creates the service over the existing source extension and pure contract.
  const FilingService({
    this.source = const ExactSubstationBeadSource(),
    this.contract = const FilingContract(),
  });

  /// Exact read source.
  final ExactSubstationBeadSource source;

  /// Pure contract evaluator.
  final FilingContract contract;

  /// Reads [beadId] in the store rooted at [storeRoot] and evaluates it,
  /// returning BOTH the exact bead read and its report.
  ///
  /// This is the ONE read/evaluate path: the filing verb, the approve verb and
  /// the mount gate all reach the store through it, so the report's
  /// [FilingReport.approvalRevision] is always the digest of the very bead
  /// alongside it.
  ///
  /// There is no cross-store leg any more: grid_engine 0.4.0-dev.3 deleted the
  /// state-store link surface this service used to project (the_grid#447), and
  /// bd's replacement `external:<project>:<capability>` row does not reach
  /// [ExactSubstationBeadSource.readExact] — `bd dep list` cannot resolve an
  /// external target, so those rows arrive only on bd's RECORD surface
  /// (`BdCliService.queryGraph`). A named foreign blocker is therefore reported
  /// missing, fail-closed, like any other unwired one — and a digitless one is
  /// not named at all ([FilingContract.evaluate]). Either way its approval
  /// revision moves, so a bead approved against a CONSULTED state store needs
  /// re-approving.
  Future<({Bead? bead, FilingReport report})> inspect({
    required String storeRoot,
    required String beadId,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    if (bead == null) {
      return (bead: null, report: FilingReport.missing(beadId));
    }
    return (bead: bead, report: contract.evaluate(bead, read.dependencies));
  }

  /// Checks [beadId] in the store rooted at [storeRoot] — [inspect] without
  /// the bead.
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
  }) async => (await inspect(storeRoot: storeRoot, beadId: beadId)).report;
}
