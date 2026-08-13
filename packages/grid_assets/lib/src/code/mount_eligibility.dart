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
MountEligibilityDecision mountEligibilityDecision(Bead bead) {
  final findings = mountEligibilityFindings(bead);
  return findings.isEmpty
      ? const MountEligibilityDecision.eligible()
      : MountEligibilityDecision.refused(clause: findings.first);
}
