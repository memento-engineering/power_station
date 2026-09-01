import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

/// Mechanical pre-session findings that decide whether [bead] may mount.
List<String> mountEligibilityFindings(Bead bead) {
  final findings = <String>[];
  if (!bead.issueType.isDriveable) {
    findings.add('type: not driveable');
  }
  final plan = bead.metadata['validation_plan'];
  if (plan is! String || plan.trim().isEmpty) {
    findings.add('validation_plan: missing');
  }
  if (!bead.labels.contains('grid.approved')) {
    findings.add('approval: missing grid.approved label');
  }
  return findings;
}

/// The grid_engine predicate supplied by this assets pack.
///
/// When [freshBead] is supplied, every clause is recomputed from that bead
/// before the deliberate first-refusal projection. A mismatched id is an
/// authoring error: one bead's fresh state may never decide another bead.
MountEligibilityDecision mountEligibilityDecision(
  Bead bead, {
  Bead? freshBead,
}) {
  if (freshBead != null && freshBead.id != bead.id) {
    throw ArgumentError.value(
      freshBead.id,
      'freshBead.id',
      'must match snapshot bead ${bead.id}',
    );
  }
  final findings = mountEligibilityFindings(freshBead ?? bead);
  return findings.isEmpty
      ? const MountEligibilityDecision.eligible()
      : MountEligibilityDecision.refused(clause: findings.first);
}
