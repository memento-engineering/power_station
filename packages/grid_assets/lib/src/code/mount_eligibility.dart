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
/// evaluation of this bead just produced. It is accepted and carried but NOT
/// ENFORCED at this gate: the basis hashes design, acceptance criteria and
/// notes, and the station's own specify step and rework verb write exactly
/// those fields, so enforcing agreement here un-approved every bead at its
/// own first spec write and the content gate disposed the running round
/// (pow-lr8n; lunar epoch 43, 2026-09-05, four of four fresh rounds). Until
/// pow-lr8n decides what the basis binds, a COMPLETE stamp of either form
/// mounts; the revision stays on the stamp for the audit trail and for the
/// approve verb's own staleness report.
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
