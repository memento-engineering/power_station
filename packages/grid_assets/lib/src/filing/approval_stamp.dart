import 'package:beads_dart/beads_dart.dart';

/// Metadata key: the `--actor` that ran the approve verb.
const String kApprovedByKey = 'grid.approved_by';

/// Metadata key: the UTC ISO-8601 instant the approve verb stamped.
const String kApprovedAtKey = 'grid.approved_at';

/// Metadata key: the revision the approval was granted AGAINST.
const String kApprovedRevKey = 'grid.approved_rev';

/// Metadata key: the `bead-readiness` letter the PRE-STAMP ADVISORY graded this
/// filing, written only on a stamp whose advisory RAN and passed.
///
/// PROVENANCE, never validity. The three-key tuple below is still the whole of
/// what makes a receipt readable; this says what was judged and how well, so a
/// governor sweeping receipts can tell a `C` mount from an `A` one without
/// re-running a lens.
const String kReadinessGradeKey = 'grid.readiness_grade';

/// Metadata key: `true` when the advisory was WAIVED on this stamp.
const String kReadinessSkippedKey = 'grid.readiness_skipped';

/// Metadata key: `skipped` when the advisory was waived — the operator-legible
/// half of [kReadinessSkippedKey], so a receipt says WHY no grade is recorded
/// rather than leaving its absence to be read as a lens that found nothing.
const String kApprovedAdvisoryKey = 'grid.approved_advisory';

/// The [kApprovedAdvisoryKey] value a waived advisory records.
const String kApprovedAdvisorySkipped = 'skipped';

/// The scheme + version prefix of an approval revision that binds the FILING
/// BASIS — the digest `FilingContract.evaluate` derives from the bead's work
/// fields, its validation plan and the dependency ROWS bd holds for it.
///
/// A revision carrying this prefix is COMPARABLE: re-evaluating the filing
/// reproduces it exactly when nothing the governor approved has changed, and
/// produces a different one the moment something has.
///
/// The version moved to `v2` when the basis stopped carrying a link-proof
/// member. That member asserted a cross-store link bead had been found, and
/// the hard cut that retired cross-store link beads made it permanently false
/// — a digest member no evaluation can ever reproduce is a receipt nothing can
/// re-derive. There is NO dual-basis compatibility path: a receipt minted
/// under a retired version is [isStaleFilingApprovalStamp], never a second
/// accepted basis, so every standing receipt reads as stale exactly ONCE and
/// the governor re-approves in one sweep.
const String kFilingApprovalRevisionPrefix = 'filing:v2:sha256:';

/// A raw git sha, in the abbreviated-to-full range git itself accepts.
final RegExp _legacyGitSha = RegExp(r'^[0-9a-f]{7,40}$');

/// The lowercase hex body of a [kFilingApprovalRevisionPrefix] revision.
final RegExp _filingDigest = RegExp(r'^[0-9a-f]{64}$');

/// A COMPLETE filing revision of any scheme version — the shape the approve
/// verb mints, whichever version minted it.
final RegExp _anyFilingRevision = RegExp(r'^filing:v\d+:sha256:[0-9a-f]{64}$');

/// Whether [rev] is a revision this receipt scheme recognizes at all.
bool _isApprovalRevision(String rev) =>
    _legacyGitSha.hasMatch(rev) ||
    (rev.startsWith(kFilingApprovalRevisionPrefix) &&
        _filingDigest.hasMatch(
          rev.substring(kFilingApprovalRevisionPrefix.length),
        ));

/// Whether [rev] is a complete filing revision minted under a RETIRED scheme
/// version.
///
/// A malformed revision is not one: it was never a receipt this package wrote,
/// so it is an ordinary unapproved bead rather than a migration.
bool _isRetiredFilingRevision(String rev) =>
    _anyFilingRevision.hasMatch(rev) &&
    !rev.startsWith(kFilingApprovalRevisionPrefix);

/// The COMPLETE receipt [bead] carries when its revision satisfies [accepts],
/// or null when it carries none.
///
/// ONE reading of a receipt's actor, instant and revision, so an accepted
/// receipt and a retired one can never disagree about anything but the scheme
/// version that minted them.
ApprovalStamp? _approvalStampWhere(
  Bead bead,
  bool Function(String rev) accepts,
) {
  final by = bead.metadata[kApprovedByKey];
  if (by is! String || by.trim().isEmpty) return null;
  final at = bead.metadata[kApprovedAtKey];
  if (at is! String) return null;
  final instant = DateTime.tryParse(at.trim());
  if (instant == null || !instant.isUtc) return null;
  final rev = bead.metadata[kApprovedRevKey];
  if (rev is! String || !accepts(rev.trim())) return null;
  return ApprovalStamp(by: by.trim(), at: at.trim(), rev: rev.trim());
}

/// Whether [bead] carries a COMPLETE receipt minted under a RETIRED filing
/// scheme version — well-formed in every part, and unreproducible only because
/// the basis its digest was taken over no longer exists.
///
/// This is the MIGRATION report, not a second accepted basis: a retired
/// receipt is never an [ApprovalStamp] and never mounts. It exists so the
/// refusal can say STALE with the approve verb as its remedy, instead of
/// saying "not approved" about a bead a governor demonstrably approved.
///
/// False for every other shape — a current receipt, a raw git sha, a malformed
/// revision, and an incomplete receipt missing an actor or a UTC instant. An
/// upper-case or truncated digest was never minted by the verb, so it is an
/// ordinary unapproved bead rather than work awaiting one re-approval.
bool isStaleFilingApprovalStamp(Bead bead) =>
    _approvalStampWhere(bead, _isRetiredFilingRevision) != null;

/// The RECEIPT the approve verb writes — and the ONLY approval marker the
/// mount gate reads: WHO approved, WHEN, and against WHICH revision of the
/// bead's filing basis. The `grid.approved` label it used to sit beside is
/// retired; a label any writer can add was the same act written twice.
final class ApprovalStamp {
  /// Creates a stamp, optionally carrying the PRE-STAMP ADVISORY's provenance.
  ///
  /// [readinessGrade] and [advisorySkipped] are mutually exclusive by
  /// construction at the one writer (`ApproveService`): an advisory that RAN
  /// records its letter, an advisory that was WAIVED records the waiver, and a
  /// stamp written with the advisory off records neither. None of the three is
  /// read by [tryParse] — see the class doc.
  const ApprovalStamp({
    required this.by,
    required this.at,
    required this.rev,
    this.readinessGrade = '',
    this.advisorySkipped = false,
  });

  /// The COMPLETE receipt [bead] carries, or null when it carries none.
  ///
  /// All three keys are read and all three must be well-formed — the verb
  /// writes them in ONE `bd update`, so a receipt missing an actor or a
  /// revision was not written by the verb. A hand-added timestamp parses to
  /// null exactly like a hand-added label.
  ///
  /// The PRE-STAMP ADVISORY's provenance keys ([kReadinessGradeKey],
  /// [kReadinessSkippedKey], [kApprovedAdvisoryKey]) are deliberately NOT read
  /// here, and a receipt carrying none of them is exactly as valid as one
  /// carrying all of them. They record what was judged; the three-key tuple
  /// records the approval, and it stays the only mount marker. Widening the
  /// tuple would strand every receipt minted before the advisory existed and
  /// would make a waiver un-writable.
  ///
  /// [kApprovedRevKey] is accepted in two shapes. The authoritative one is a
  /// [kFilingApprovalRevisionPrefix] digest, which names the very content the
  /// governor approved. The other is a raw git sha — a READ-ONLY
  /// COMPATIBILITY ARM for receipts the verb already wrote against a store
  /// HEAD, kept so approved in-flight work is not stranded by this tightening.
  /// The verb writes only [kFilingApprovalRevisionPrefix] revisions now, so
  /// the raw-sha arm can only shrink; nothing mints a new one.
  ///
  /// A receipt minted under a RETIRED filing scheme version is a third shape
  /// and is NOT accepted here — see [isStaleFilingApprovalStamp], which
  /// classifies it so the refusal can name the one remedy. A retired basis is
  /// unreproducible by construction, so accepting it would be a second basis
  /// nothing can re-derive.
  ///
  /// Retirement: the_grid tg-lt0s makes StationAdmissionAuthority grants authoritative.
  ///
  /// That Stage-3 grant already records the bead revision, the approval
  /// evidence, the validation-plan digest and the dependency revisions, so
  /// when it becomes the mount authority the raw-sha arm goes first and this
  /// whole interim receipt comparison follows it — a second grant scheme is
  /// never the answer.
  static ApprovalStamp? tryParse(Bead bead) =>
      _approvalStampWhere(bead, _isApprovalRevision);

  /// The approver — the `--actor` the verb ran under.
  final String by;

  /// The UTC ISO-8601 instant of the stamp.
  final String at;

  /// The revision this approval was granted against — a
  /// [kFilingApprovalRevisionPrefix] digest, or a legacy raw git sha.
  final String rev;

  /// The `bead-readiness` letter the advisory graded, or `''` when it did not
  /// run. PROVENANCE only.
  final String readinessGrade;

  /// Whether the advisory was WAIVED on this stamp. PROVENANCE only.
  final bool advisorySkipped;

  /// Whether [rev] binds the FILING BASIS, and is therefore comparable with a
  /// fresh `FilingContract` evaluation. False for the legacy raw-sha arm,
  /// which names a store HEAD and says nothing about the bead's content.
  bool get bindsFilingBasis => rev.startsWith(kFilingApprovalRevisionPrefix);

  /// The metadata pairs, written in ONE `bd update`.
  ///
  /// The three RECEIPT keys are always present and always first; the advisory
  /// provenance rides the SAME update when there is any, because a receipt and
  /// the account of what was judged to earn it must land together or not at
  /// all.
  Map<String, String> get metadata => {
    kApprovedByKey: by,
    kApprovedAtKey: at,
    kApprovedRevKey: rev,
    if (readinessGrade.isNotEmpty) kReadinessGradeKey: readinessGrade,
    if (advisorySkipped) ...{
      kReadinessSkippedKey: 'true',
      kApprovedAdvisoryKey: kApprovedAdvisorySkipped,
    },
  };

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'by': by,
    'at': at,
    'rev': rev,
    if (readinessGrade.isNotEmpty) 'readiness_grade': readinessGrade,
    if (advisorySkipped) 'readiness_skipped': true,
  };
}

/// Whether [bead] carries the verb-written stamp.
///
/// Delegates to [ApprovalStamp.tryParse] — there is no timestamp-only
/// shortcut, because a lone `grid.approved_at` is exactly what a hand-written
/// approval looks like, and no retired-scheme shortcut, because a receipt
/// whose basis cannot be re-derived is not an approval of anything.
///
/// This is the mount gate's approval clause — see `mountEligibilityFindings`
/// in `lib/src/code/mount_eligibility.dart`.
bool isApprovalStamped(Bead bead) => ApprovalStamp.tryParse(bead) != null;
