import 'package:beads_dart/beads_dart.dart';

/// Metadata key: the `--actor` that ran the approve verb.
const String kApprovedByKey = 'grid.approved_by';

/// Metadata key: the UTC ISO-8601 instant the approve verb stamped.
const String kApprovedAtKey = 'grid.approved_at';

/// Metadata key: the revision the approval was granted AGAINST.
const String kApprovedRevKey = 'grid.approved_rev';

/// The scheme + version prefix of an approval revision that binds the FILING
/// BASIS — the digest `FilingContract.evaluate` derives from the bead's work
/// fields, its validation plan and its dependency proofs.
///
/// A revision carrying this prefix is COMPARABLE: re-evaluating the filing
/// reproduces it exactly when nothing the governor approved has changed, and
/// produces a different one the moment something has.
const String kFilingApprovalRevisionPrefix = 'filing:v1:sha256:';

/// A raw git sha, in the abbreviated-to-full range git itself accepts.
final RegExp _legacyGitSha = RegExp(r'^[0-9a-f]{7,40}$');

/// The lowercase hex body of a `filing:v1:sha256:` revision.
final RegExp _filingDigest = RegExp(r'^[0-9a-f]{64}$');

/// Whether [rev] is a revision this receipt scheme recognizes at all.
bool _isApprovalRevision(String rev) =>
    _legacyGitSha.hasMatch(rev) ||
    (rev.startsWith(kFilingApprovalRevisionPrefix) &&
        _filingDigest.hasMatch(
          rev.substring(kFilingApprovalRevisionPrefix.length),
        ));

/// The RECEIPT the approve verb writes — and the ONLY approval marker the
/// mount gate reads: WHO approved, WHEN, and against WHICH revision of the
/// bead's filing basis. The `grid.approved` label it used to sit beside is
/// retired; a label any writer can add was the same act written twice.
final class ApprovalStamp {
  /// Creates a stamp.
  const ApprovalStamp({required this.by, required this.at, required this.rev});

  /// The COMPLETE receipt [bead] carries, or null when it carries none.
  ///
  /// All three keys are read and all three must be well-formed — the verb
  /// writes them in ONE `bd update`, so a receipt missing an actor or a
  /// revision was not written by the verb. A hand-added timestamp parses to
  /// null exactly like a hand-added label.
  ///
  /// [kApprovedRevKey] is accepted in two shapes. The authoritative one is a
  /// [kFilingApprovalRevisionPrefix] digest, which the mount gate compares
  /// against a fresh evaluation. The other is a raw git sha — a READ-ONLY
  /// COMPATIBILITY ARM for receipts the verb already wrote against a store
  /// HEAD, kept so approved in-flight work is not stranded by this tightening.
  /// The verb writes only [kFilingApprovalRevisionPrefix] revisions now, so
  /// the raw-sha arm can only shrink; nothing mints a new one.
  ///
  /// Retirement: the_grid tg-lt0s makes StationAdmissionAuthority grants authoritative.
  ///
  /// That Stage-3 grant already records the bead revision, the approval
  /// evidence, the validation-plan digest and the dependency revisions, so
  /// when it becomes the mount authority the raw-sha arm goes first and this
  /// whole interim receipt comparison follows it — a second grant scheme is
  /// never the answer.
  static ApprovalStamp? tryParse(Bead bead) {
    final by = bead.metadata[kApprovedByKey];
    if (by is! String || by.trim().isEmpty) return null;
    final at = bead.metadata[kApprovedAtKey];
    if (at is! String) return null;
    final instant = DateTime.tryParse(at.trim());
    if (instant == null || !instant.isUtc) return null;
    final rev = bead.metadata[kApprovedRevKey];
    if (rev is! String || !_isApprovalRevision(rev.trim())) return null;
    return ApprovalStamp(by: by.trim(), at: at.trim(), rev: rev.trim());
  }

  /// The approver — the `--actor` the verb ran under.
  final String by;

  /// The UTC ISO-8601 instant of the stamp.
  final String at;

  /// The revision this approval was granted against — a
  /// [kFilingApprovalRevisionPrefix] digest, or a legacy raw git sha.
  final String rev;

  /// Whether [rev] binds the FILING BASIS, and is therefore comparable with a
  /// fresh `FilingContract` evaluation. False for the legacy raw-sha arm,
  /// which names a store HEAD and says nothing about the bead's content.
  bool get bindsFilingBasis => rev.startsWith(kFilingApprovalRevisionPrefix);

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
/// Delegates to [ApprovalStamp.tryParse] — there is no timestamp-only
/// shortcut, because a lone `grid.approved_at` is exactly what a hand-written
/// approval looks like.
///
/// This is the mount gate's approval clause — see `mountEligibilityFindings`
/// in `lib/src/code/mount_eligibility.dart`.
bool isApprovalStamped(Bead bead) => ApprovalStamp.tryParse(bead) != null;
