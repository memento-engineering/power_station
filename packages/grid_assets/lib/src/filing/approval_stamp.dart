import 'package:beads_dart/beads_dart.dart';

/// The label a bead carries once it has been approved for mounting.
///
/// The label alone is NOT approval: any writer can add it at any time, which is
/// how four `pow-n6n` children mounted ahead of their blockers on 2026-09-02.
/// Approval is the label PLUS the [ApprovalStamp] the approve verb writes in the
/// same `bd update` — see [isApprovalStamped].
const String kApprovedLabel = 'grid.approved';

/// Metadata key: the `--actor` that ran the approve verb.
const String kApprovedByKey = 'grid.approved_by';

/// Metadata key: the UTC ISO-8601 instant the approve verb stamped.
const String kApprovedAtKey = 'grid.approved_at';

/// Metadata key: the store root's git HEAD sha at approval time.
const String kApprovedRevKey = 'grid.approved_rev';

/// The RECEIPT the approve verb writes beside [kApprovedLabel]: WHO approved,
/// WHEN, and against WHICH revision of the bead's store root.
final class ApprovalStamp {
  /// Creates a stamp.
  const ApprovalStamp({required this.by, required this.at, required this.rev});

  /// The approver — the `--actor` the verb ran under.
  final String by;

  /// The UTC ISO-8601 instant of the stamp.
  final String at;

  /// The store root's `git rev-parse HEAD` sha.
  final String rev;

  /// The three metadata pairs, written in ONE `bd update`.
  Map<String, String> get metadata => {
    kApprovedByKey: by,
    kApprovedAtKey: at,
    kApprovedRevKey: rev,
  };

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {'by': by, 'at': at, 'rev': rev};
}

/// Whether [bead] carries the verb-written stamp.
///
/// [kApprovedAtKey] is the witness: the verb writes all three keys in one
/// update, so the instant cannot exist without the actor and the revision, and
/// a hand-added label has none of them.
bool isApprovalStamped(Bead bead) {
  final at = bead.metadata[kApprovedAtKey];
  return at is String && at.trim().isNotEmpty;
}
