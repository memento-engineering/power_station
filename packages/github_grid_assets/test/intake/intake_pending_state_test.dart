import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The bead `BdGitHubIntakeStore` now files: OPEN, `chore`-typed, correlated on
/// node id, carrying only the four `github.*` keys — and no approval stamp.
const filed = Bead(
  id: 'pow-new',
  title: '[GitHub issue memento/power_station#42] Fix the flux capacitor',
  issueType: IssueType.chore,
  priority: 2,
  externalRef: 'github:I_1',
  metadata: <String, dynamic>{
    'github.node_id': 'I_1',
    'github.kind': 'issue',
    'github.repository': 'memento/power_station',
    'github.actor': 'nico',
  },
);

void main() {
  group('the GitHub intake pending state', () {
    test('an OPEN, unstamped intake bead is refused by the mount gate', () {
      expect(
        mountEligibilityFindings(filed),
        contains('approval: not approved - run the approve verb'),
      );
    });

    test('only the approve verb clears it', () {
      final approved = filed.copyWith(
        metadata: <String, dynamic>{
          ...filed.metadata,
          'validation_plan': 'cd packages/github_grid_assets && dart test',
          kApprovedByKey: 'nico',
          kApprovedAtKey: '2026-09-03T00:00:00Z',
          kApprovedRevKey: 'c635790',
        },
      );

      expect(mountEligibilityFindings(approved), isEmpty);
    });
  });
}
