library;

/// A composition value selecting one GitHub delivery posture.
sealed class GitHubDeliveryPolicy {
  const GitHubDeliveryPolicy();
}

/// Opens or reuses a pull request and leaves merging to a human.
final class PrNoMergePolicy extends GitHubDeliveryPolicy {
  const PrNoMergePolicy();
}

/// Opens a pull request and enables native auto-merge when receipts qualify.
final class PrAutoMergePolicy extends GitHubDeliveryPolicy {
  const PrAutoMergePolicy({this.minimumGrade = CommitteeGrade.b});

  /// The lowest committee grade allowed to enable auto-merge.
  final CommitteeGrade minimumGrade;
}

/// Pushes a reviewed branch directly to an unprotected base branch.
final class DirectMergePolicy extends GitHubDeliveryPolicy {
  const DirectMergePolicy();
}

/// Ordered committee grades, best to worst.
enum CommitteeGrade { a, b, c, d, f }

/// Returns null only when the bounded landing receipts permit auto-merge.
String? autoMergeGateRefusal(
  Map<String, String> payload, {
  required CommitteeGrade minimumGrade,
}) {
  if (payload['validation_rc'] != '0') {
    return 'code-validation rc=${payload['validation_rc'] ?? 'missing'}';
  }
  final raw = payload['committee_grades'] ?? '';
  if (raw.isEmpty) return 'committee grades are empty';
  for (final entry in raw.split(',')) {
    final parts = entry.split('=');
    if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
      return 'malformed committee grade: $entry';
    }
    CommitteeGrade? grade;
    for (final candidate in CommitteeGrade.values) {
      if (candidate.name == parts.last.toLowerCase()) grade = candidate;
    }
    if (grade == null) {
      return '${parts.first} has malformed grade ${parts.last}';
    }
    if (grade.index > minimumGrade.index) {
      return '${parts.first}=${parts.last} is below '
          '${minimumGrade.name.toUpperCase()}';
    }
  }
  return null;
}
