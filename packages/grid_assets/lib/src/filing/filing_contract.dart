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
  /// This is what `ApproveService` stamps as `grid.approved_rev`. The mount
  /// gate does not compare it against the stamped one (see
  /// `mountEligibilityFindings`); what that gate reads off the receipt is its
  /// SCHEME VERSION, which tells a receipt minted under the current basis from
  /// one minted under a retired, unreproducible one.
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

/// What the station ROSTER said about one `external:` row's project.
enum ExternalResolution {
  /// The roster arms a substation of that name — the row is an ordinary
  /// prerequisite and the dependencies requirement passes on it.
  armed,

  /// The roster was consulted and arms NO substation of that name. An edge
  /// naming a store this station does not arm is never a silent pass.
  notArmed,

  /// The roster was NOT consulted, so nothing can be said about the project.
  /// Fail-closed, exactly as [notArmed] is: an unasked roster cannot clear a
  /// cross-project blocker.
  unconsulted,
}

/// One `external:<project>:<capability>` dependency row, with what the roster
/// said about its project.
final class ExternalBlocker {
  /// Binds [ref] to its [resolution].
  const ExternalBlocker({required this.ref, required this.resolution});

  /// The parsed row — bd's OWN type
  /// ([ExternalDepRef], `beads_dart`), never a second spelling of it.
  final ExternalDepRef ref;

  /// The roster's answer about [ExternalDepRef.project].
  final ExternalResolution resolution;

  /// Whether this row clears the dependencies requirement.
  bool get passed => switch (resolution) {
    ExternalResolution.armed => true,
    ExternalResolution.notArmed || ExternalResolution.unconsulted => false,
  };
}

/// The dependencies requirement's whole content: the PROJECTION of the
/// dependency rows bd holds for one bead.
///
/// `power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`
/// — ruled by Nico on 2026-09-13 under
/// `the_grid#the-grid-is-a-beads-controller`: a blocker is a declaration bd
/// holds, and bd's rows are the single typed view of it. Bead PROSE is never
/// read for blockers; a `Blocked by` sentence is prose, and the hyphenated
/// spelling is the same prose. There is nothing to compare the rows AGAINST,
/// so the row reports what bd holds and refuses only what the roster cannot
/// resolve.
final class DependencyProjection {
  /// Creates a projection over already-classified rows.
  const DependencyProjection({
    required this.local,
    required this.external,
    required this.armedSubstations,
  });

  /// Projects [beadId]'s own outgoing BLOCKING rows out of [dependencies].
  ///
  /// [armedSubstations] is the station's roster by NAME, or null when no
  /// roster was supplied — the [ExternalResolution.unconsulted] arm.
  factory DependencyProjection.of({
    required String beadId,
    required Iterable<BeadDependency> dependencies,
    required Set<String>? armedSubstations,
  }) {
    final local = <String>{};
    final external = <String, ExternalBlocker>{};
    for (final edge in dependencies) {
      if (edge.issueId != beadId || edge.type != DependencyType.blocks) {
        continue;
      }
      // bd's own parser decides what an `external:` target is. A malformed
      // spelling parses to null and is read as a LOCAL id — exactly what bd
      // does with it, so the projection never invents a third reading.
      final ref = ExternalDepRef.parse(edge.dependsOnId);
      if (ref == null) {
        local.add(edge.dependsOnId);
        continue;
      }
      external[ref.wire] = ExternalBlocker(
        ref: ref,
        resolution: armedSubstations == null
            ? ExternalResolution.unconsulted
            : armedSubstations.contains(ref.project)
            ? ExternalResolution.armed
            : ExternalResolution.notArmed,
      );
    }
    return DependencyProjection(
      local: local.toList()..sort(),
      external: (external.keys.toList()..sort())
          .map((wire) => external[wire]!)
          .toList(growable: false),
      armedSubstations: armedSubstations,
    );
  }

  /// The same-store blocking targets, sorted. bd's own `bd ready` business —
  /// the projection reports them and judges nothing about them.
  final List<String> local;

  /// The `external:` blocking rows, sorted by wire form, each carrying its
  /// roster resolution.
  final List<ExternalBlocker> external;

  /// The roster the external rows were resolved against, or null when none
  /// was supplied.
  final Set<String>? armedSubstations;

  /// True unless an external row named a project the roster cannot resolve.
  bool get passed => external.every((blocker) => blocker.passed);

  /// The armed roster as an operator reads it.
  String get _armedRoster {
    final armed = armedSubstations;
    if (armed == null) return '<not consulted>';
    if (armed.isEmpty) return '<none>';
    return (armed.toList()..sort()).join(', ');
  }

  /// The evidence line: what bd holds, and — when it refuses — which row the
  /// roster could not resolve and what to do about it.
  String get detail {
    final refusals = [
      for (final blocker in external)
        if (!blocker.passed)
          switch (blocker.resolution) {
            ExternalResolution.notArmed =>
              '${blocker.ref.wire} names "${blocker.ref.project}", which this '
                  'station does not arm (armed: $_armedRoster) — arm that '
                  'substation, or re-point the row at one the roster carries',
            ExternalResolution.unconsulted =>
              '${blocker.ref.wire} is unresolved: no station roster was '
                  'supplied, so "${blocker.ref.project}" cannot be resolved to '
                  'an armed substation — the composition that builds this verb '
                  'passes its armed roster in as armedSubstations, and until '
                  'one does every external: row refuses here',
            ExternalResolution.armed => '',
          },
    ];
    if (refusals.isNotEmpty) {
      return 'unresolvable external dependency rows: ${refusals.join('; ')}';
    }
    final rows = [
      ...local,
      for (final blocker in external) '${blocker.ref.wire} (armed)',
    ];
    return rows.isEmpty
        ? 'bd holds no blocking dependency rows'
        : 'bd dependency rows: ${rows.join(', ')}';
  }

  /// The approval-revision basis: the ROWS bd holds, never the roster's answer
  /// about them.
  ///
  /// The roster is the STATION's posture, not the bead's content — the same
  /// reason the basis has always recorded the proofs FOUND rather than the
  /// posture of the lookup. Arming a substation must not revoke a governor's
  /// approval of a bead nobody edited.
  List<Map<String, Object?>> get basis => [
    for (final id in local) {'id': id, 'kind': 'local'},
    for (final blocker in external)
      {'id': blocker.ref.wire, 'kind': 'external'},
  ];
}

/// The approval revision of one evaluated filing, under the CURRENT scheme
/// version ([kFilingApprovalRevisionPrefix]).
///
/// It digests exactly what an approval is a judgement ABOUT: the bead's work
/// fields, its validation plan, and the DEPENDENCY ROWS bd holds for it
/// ([DependencyProjection.basis]). Lifecycle timestamps, status,
/// assignee/owner, result metadata and the receipt itself are all EXCLUDED, so
/// stamping the receipt can never invalidate the receipt it stamps, and a bead
/// moving through its lifecycle does not revoke a governor's approval of its
/// content. The station's ROSTER is excluded for the same reason: arming a
/// substation is the station's posture, not the bead's content.
///
/// The basis has NO link-proof member. The retired one recorded that a
/// cross-store link bead had been FOUND for each declared id; the hard cut
/// that retired cross-store link beads made it permanently false, so no
/// evaluation could ever reproduce a receipt carrying it. It is replaced —
/// not pinned, and not dropped in place — by the rows bd itself holds, typed
/// `local` or `external`, which is the one surface a cross-project blocker
/// still lives on.
///
/// That replacement is a new receipt SCHEME, so the version in
/// [kFilingApprovalRevisionPrefix] moved with it and every receipt minted
/// under the retired one reads as stale EXACTLY ONCE
/// ([isStaleFilingApprovalStamp]). There is no dual-basis compatibility path:
/// this function is the only thing that mints a revision, and it mints one
/// version.
String _approvalRevisionOf(Bead bead, DependencyProjection dependencies) {
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
    'dependencies': dependencies.basis,
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
/// predicate minted"*. The roster resolution of an `external:` row is a
/// refinement of this contract's own dependency row, not a fifth requirement
/// and not a second predicate.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against the dependency rows bd holds for it.
  ///
  /// The dependencies row is a PURE PROJECTION of those rows — local targets
  /// and `external:<project>:<capability>` targets alike — with each external
  /// row resolved through [armedSubstations], the station's roster by NAME.
  /// Bead PROSE is never read: `Blocked-by: pow-x` and `Blocked by pow-x` are
  /// both sentences, and both project identically because neither is a row.
  ///
  /// [armedSubstations] is NULL when no roster was supplied. An unasked roster
  /// cannot clear a cross-project blocker, so an external row then refuses
  /// fail-closed exactly as an unarmed project does — the difference is in the
  /// detail, which says which condition it is and what to do about it.
  FilingReport evaluate(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    Set<String>? armedSubstations,
  }) => _evaluateWithProjection(
    bead,
    dependencies,
    armedSubstations: armedSubstations,
  ).report;

  /// [evaluate], RETAINING the projection the dependencies row was rendered
  /// from.
  ///
  /// The mount explainer's own `dependencies` precondition is a REFINEMENT of
  /// this very projection — the rows bd holds, plus whether each local target
  /// is still open — so it consumes the one this evaluation already built.
  /// Rebuilding a second projection from a second read is how the two verbs
  /// would come to disagree about the same rows.
  ({DependencyProjection dependencyProjection, FilingReport report})
  _evaluateWithProjection(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    Set<String>? armedSubstations,
  }) {
    final validationPlan = bead.metadata['validation_plan'];
    final projection = DependencyProjection.of(
      beadId: bead.id,
      dependencies: dependencies,
      armedSubstations: armedSubstations,
    );
    final report = FilingReport(
      beadId: bead.id,
      approvalRevision: _approvalRevisionOf(bead, projection),
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
          passed: projection.passed,
          detail: projection.detail,
        ),
      ],
    );
    return (dependencyProjection: projection, report: report);
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
  /// ONE store answers it. The dependencies row is a projection of the rows
  /// this store holds, cross-project rows included: bd carries those as
  /// `external:<project>:<capability>` targets on its own RECORD surface
  /// ([ExactSubstationBeadSource.readExact]), so there is no second store to
  /// consult and no link bead to read.
  ///
  /// [DependencyProjection] rides back out beside the report, and is null only
  /// when there was no bead to evaluate. A consumer that needs the ROWS — the
  /// mount explainer refines them with each local target's open/closed state —
  /// reads the projection this evaluation already built instead of rebuilding
  /// one, so the two verbs cannot disagree about the same rows.
  Future<
    ({
      Bead? bead,
      DependencyProjection? dependencyProjection,
      FilingReport report,
    })
  >
  inspect({
    required String storeRoot,
    required String beadId,
    Set<String>? armedSubstations,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    if (bead == null) {
      return (
        bead: null,
        dependencyProjection: null,
        report: FilingReport.missing(beadId),
      );
    }
    final evaluated = contract._evaluateWithProjection(
      bead,
      read.dependencies,
      armedSubstations: armedSubstations,
    );
    return (
      bead: bead,
      dependencyProjection: evaluated.dependencyProjection,
      report: evaluated.report,
    );
  }

  /// Checks [beadId] in the store rooted at [storeRoot] — [inspect] without
  /// the bead.
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
    Set<String>? armedSubstations,
  }) async => (await inspect(
    storeRoot: storeRoot,
    beadId: beadId,
    armedSubstations: armedSubstations,
  )).report;
}
