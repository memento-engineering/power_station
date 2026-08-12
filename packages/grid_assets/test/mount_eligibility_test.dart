import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

Bead _bead({
  IssueType type = IssueType.task,
  Object? plan = 'dart test',
  List<String> labels = const ['grid.approved'],
  String description = 'A concrete brief',
  String design = '',
  String acceptance = '',
  DateTime? deferUntil,
}) => Bead(
  id: 'pow-test',
  issueType: type,
  description: description,
  design: design,
  acceptanceCriteria: acceptance,
  deferUntil: deferUntil,
  metadata: plan == null ? const {} : {'validation_plan': plan},
  labels: labels,
);

void main() {
  test('findings are exact and ordered', () {
    expect(
      mountEligibilityFindings(
        _bead(type: IssueType.epic, plan: null, labels: const []),
      ),
      [
        'type: not driveable',
        'validation_plan: missing',
        'approval: missing grid.approved label',
      ],
    );
  });

  for (final plan in <Object?>[null, 1, '', '   ']) {
    test('refuses invalid validation plan $plan', () {
      expect(mountEligibilityFindings(_bead(plan: plan)), [
        'validation_plan: missing',
      ]);
    });
  }

  test('audit metadata never substitutes for approval label', () {
    final bead = _bead(labels: const []).copyWith(
      metadata: const {
        'validation_plan': 'dart test',
        'grid.approval.actor': 'nico',
        'grid.approval.at': '2026-08-12T00:00:00Z',
        'grid.approval.reason': 'reviewed',
      },
    );
    expect(mountEligibilityFindings(bead), [
      'approval: missing grid.approved label',
    ]);
  });

  test('approval label does not substitute for audit-independent plan', () {
    expect(mountEligibilityFindings(_bead(plan: null)), [
      'validation_plan: missing',
    ]);
  });

  test('every non-driveable issue type is refused', () {
    for (final type in IssueType.coreTypes.where((type) => !type.isDriveable)) {
      expect(mountEligibilityFindings(_bead(type: type)), [
        'type: not driveable',
      ], reason: '$type');
    }
  });

  test('future defer and blank session outputs do not affect eligibility', () {
    final bead = _bead(deferUntil: DateTime.utc(2099));
    final decision = mountEligibilityDecision(bead);
    final result = switch (decision) {
      MountEligible() => 'eligible',
      MountRefused(:final clause) => clause,
    };
    expect(result, 'eligible');
    expect(bead.design, isEmpty);
    expect(bead.acceptanceCriteria, isEmpty);
  });

  test('refusal carries the first failed clause', () {
    final decision = mountEligibilityDecision(_bead(plan: null));
    final result = switch (decision) {
      MountEligible() => null,
      MountRefused(:final clause) => clause,
    };
    expect(result, 'validation_plan: missing');
  });

  test('intake remains its distinct two-clause lifecycle contract', () {
    final bead = _bead(plan: null, labels: const []);
    expect(intakeFindings(bead), isEmpty);
    expect(mountEligibilityFindings(bead), isNotEmpty);
  });
}
