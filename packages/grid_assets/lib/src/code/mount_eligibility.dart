import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

import '../filing/approval_stamp.dart';

/// Mechanical pre-session findings that decide whether [bead] may mount.
///
/// Approval IS the `grid.approved_*` stamp the approve verb writes: the
/// retired `grid.approved` LABEL is never consulted. A bead carried four
/// encodings of "not yet"; the stamp is the one that survives, because it
/// records WHO approved, WHEN and against WHICH revision, and only the verb can
/// write it.
///
/// The revision is what makes the receipt more than a timestamp. When the
/// stamp binds a FILING BASIS (`ApprovalStamp.bindsFilingBasis`),
/// [evaluatedApprovalRevision] is the revision a FRESH `FilingContract`
/// evaluation of this bead just produced, and the two must AGREE: an approved
/// bead whose brief, acceptance criteria, validation plan or dependency basis
/// has since been edited no longer carries approval for what it now says.
/// Absent that fresh evaluation there is nothing to agree with, so the receipt
/// is refused as unevaluated rather than trusted on its face.
List<String> mountEligibilityFindings(
  Bead bead, {
  String? evaluatedApprovalRevision,
}) {
  final findings = <String>[];
  if (!bead.issueType.isDriveable) {
    findings.add('type: not driveable');
  }
  final plan = bead.metadata['validation_plan'];
  if (plan is! String || plan.trim().isEmpty) {
    findings.add('validation_plan: missing');
  }
  final stamp = ApprovalStamp.tryParse(bead);
  if (stamp == null) {
    findings.add('approval: not approved - run the approve verb');
  } else if (stamp.bindsFilingBasis) {
    if (evaluatedApprovalRevision == null) {
      findings.add(
        'approval: revision not evaluated - fresh filing read '
        'required',
      );
    } else if (evaluatedApprovalRevision != stamp.rev) {
      findings.add('approval: stale - rerun the approve verb');
    }
  }
  return findings;
}

/// The grid_engine predicate supplied by this assets pack.
///
/// When [freshBead] is supplied, every clause is recomputed from that bead
/// before the deliberate first-refusal projection. A mismatched id is an
/// authoring error: one bead's fresh state may never decide another bead.
///
/// [evaluatedApprovalRevision] is the revision the same fresh read evaluated,
/// so a bound receipt is compared against the bead it is being read beside —
/// never against a revision derived from some other read.
MountEligibilityDecision mountEligibilityDecision(
  Bead bead, {
  Bead? freshBead,
  String? evaluatedApprovalRevision,
}) {
  if (freshBead != null && freshBead.id != bead.id) {
    throw ArgumentError.value(
      freshBead.id,
      'freshBead.id',
      'must match snapshot bead ${bead.id}',
    );
  }
  final findings = mountEligibilityFindings(
    freshBead ?? bead,
    evaluatedApprovalRevision: evaluatedApprovalRevision,
  );
  return findings.isEmpty
      ? const MountEligibilityDecision.eligible()
      : MountEligibilityDecision.refused(clause: findings.first);
}
