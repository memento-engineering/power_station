import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

import '../search/station_search.dart';

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
    'requirements': [for (final row in requirements) row.toJson()],
    if (error case final error?) 'error': error,
  };
}

final RegExp _blockerLine = RegExp(
  r'^\s*(?:Blocked by|Depends on)\s*:?\s*(.*)$',
  multiLine: true,
);
final RegExp _beadId = RegExp(r'\b[a-z][a-z0-9_]*(?:-[a-z0-9_.]+)+\b');

Set<String> _namedBlockers(String description) => {
  for (final line in _blockerLine.allMatches(description))
    for (final id in _beadId.allMatches(line.group(1)!).map((m) => m.group(0)!))
      id,
};

/// Pure evaluator for the four-row filing report.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against its [dependencies].
  FilingReport evaluate(Bead bead, Iterable<BeadDependency> dependencies) {
    final validationPlan = bead.metadata['validation_plan'];
    final named = _namedBlockers(bead.description);
    final wired = {
      for (final edge in dependencies)
        if (edge.issueId == bead.id && edge.type == DependencyType.blocks)
          edge.dependsOnId,
    };
    final missing = named.difference(wired).toList()..sort();
    final dependencyPass = missing.isEmpty;
    return FilingReport(
      beadId: bead.id,
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
          detail: dependencyPass
              ? (named.isEmpty
                    ? 'no local blockers named'
                    : 'all named local blockers are wired')
              : 'missing outgoing blocks edges: ${missing.join(', ')}',
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

  /// Checks [beadId] in the store rooted at [storeRoot].
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    return bead == null
        ? FilingReport.missing(beadId)
        : contract.evaluate(bead, read.dependencies);
  }
}
