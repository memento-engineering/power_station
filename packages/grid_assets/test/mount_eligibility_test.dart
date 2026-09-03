import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const String _notApproved = 'approval: not approved - run the approve verb';

Bead _bead({
  IssueType type = IssueType.task,
  Object? plan = 'dart test',
  List<String> labels = const [],
  String description = 'A concrete brief',
  String design = '',
  String acceptance = '',
  DateTime? deferUntil,
  Map<String, dynamic> stamp = const {
    'grid.approved_by': 'nico',
    'grid.approved_at': '2026-09-02T14:30:00.000Z',
    'grid.approved_rev': '9f1c2d3e4b5a69788899aabbccddeeff00112233',
  },
}) => Bead(
  id: 'pow-test',
  issueType: type,
  description: description,
  design: design,
  acceptanceCriteria: acceptance,
  deferUntil: deferUntil,
  metadata: {if (plan != null) 'validation_plan': plan, ...stamp},
  labels: labels,
);

String? _clause(MountEligibilityDecision decision) => switch (decision) {
  MountEligible() => null,
  MountRefused(:final clause) => clause,
};

void main() {
  test('findings are exact and ordered', () {
    expect(
      mountEligibilityFindings(
        _bead(type: IssueType.epic, plan: null, stamp: const {}),
      ),
      ['type: not driveable', 'validation_plan: missing', _notApproved],
    );
  });

  for (final plan in <Object?>[null, 1, '', '   ']) {
    test('refuses invalid validation plan $plan', () {
      expect(mountEligibilityFindings(_bead(plan: plan)), [
        'validation_plan: missing',
      ]);
    });
  }

  test('the grid.approved label is never consulted', () {
    expect(
      mountEligibilityFindings(
        _bead(labels: const ['grid.approved'], stamp: const {}),
      ),
      [_notApproved],
    );
    expect(
      _clause(
        mountEligibilityDecision(
          _bead(labels: const ['grid.approved'], stamp: const {}),
        ),
      ),
      _notApproved,
    );
    expect(mountEligibilityFindings(_bead()), isEmpty);
  });

  test('legacy audit metadata never substitutes for the stamp', () {
    final bead = _bead(stamp: const {}).copyWith(
      metadata: const {
        'validation_plan': 'dart test',
        'grid.approval.actor': 'nico',
        'grid.approval.at': '2026-08-12T00:00:00Z',
        'grid.approval.reason': 'reviewed',
      },
    );
    expect(mountEligibilityFindings(bead), [_notApproved]);
  });

  test('the stamp does not substitute for a validation plan', () {
    expect(mountEligibilityFindings(_bead(plan: null)), [
      'validation_plan: missing',
    ]);
  });

  test('a blank grid.approved_at is not a stamp', () {
    final blank = _bead(stamp: const {'grid.approved_at': '   '});
    expect(mountEligibilityFindings(blank), [_notApproved]);
    expect(isApprovalStamped(blank), isFalse);
  });

  test('a stamped bead with NO label mounts', () {
    expect(_bead().labels, isEmpty);
    expect(mountEligibilityFindings(_bead()), isEmpty);
    expect(isApprovalStamped(_bead()), isTrue);
    expect(_clause(mountEligibilityDecision(_bead())), isNull);
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
    expect(_clause(mountEligibilityDecision(bead)), isNull);
    expect(bead.design, isEmpty);
    expect(bead.acceptanceCriteria, isEmpty);
  });

  test('refusal carries the first failed clause', () {
    expect(
      _clause(mountEligibilityDecision(_bead(plan: null, stamp: const {}))),
      'validation_plan: missing',
    );
  });

  test('fresh state reports approval when stale validation finding clears', () {
    expect(
      _clause(
        mountEligibilityDecision(
          _bead(plan: null, stamp: const {}),
          freshBead: _bead(stamp: const {}),
        ),
      ),
      _notApproved,
    );
  });

  test('fresh state preserves validation first when both fail', () {
    expect(
      _clause(
        mountEligibilityDecision(
          _bead(plan: null, stamp: const {}),
          freshBead: _bead(plan: null, stamp: const {}),
        ),
      ),
      'validation_plan: missing',
    );
  });

  test('fresh state clears tentative refusal', () {
    expect(
      _clause(
        mountEligibilityDecision(
          _bead(plan: null, stamp: const {}),
          freshBead: _bead(),
        ),
      ),
      isNull,
    );
  });

  test('intake remains its distinct two-clause lifecycle contract', () {
    final bead = _bead(plan: null, stamp: const {});
    expect(intakeFindings(bead), isEmpty);
    expect(mountEligibilityFindings(bead), isNotEmpty);
  });
}
