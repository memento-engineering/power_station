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

    test('complete legacy approval receipt clears pending state', () {
      // The receipt shape the fleet's already-approved work carries: an actor,
      // a UTC instant, and a raw store-HEAD sha. It names no filing basis to
      // re-derive, so it clears the gate synchronously and downstream packs
      // keep mounting through the compatibility arm.
      final approved = filed.copyWith(
        metadata: <String, dynamic>{
          ...filed.metadata,
          'validation_plan': 'cd packages/github_grid_assets && dart test',
          kApprovedByKey: 'nico',
          kApprovedAtKey: '2026-09-03T00:00:00Z',
          kApprovedRevKey: 'c635790',
        },
      );

      expect(isApprovalStamped(approved), isTrue);
      expect(mountEligibilityFindings(approved), isEmpty);
    });
  });
}
