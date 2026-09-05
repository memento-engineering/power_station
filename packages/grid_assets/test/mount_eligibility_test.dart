import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const String _notApproved = 'approval: not approved - run the approve verb';
const String _unevaluated =
    'approval: revision not evaluated - fresh filing read required';
const String _stale = 'approval: stale - rerun the approve verb';

/// A complete receipt of the shape the verb wrote BEFORE revisions bound the
/// filing basis: an actor, a UTC instant and a raw store-HEAD git sha.
const Map<String, dynamic> _legacyReceipt = {
  'grid.approved_by': 'nico',
  'grid.approved_at': '2026-09-02T14:30:00.000Z',
  'grid.approved_rev': '9f1c2d3e4b5a69788899aabbccddeeff00112233',
};

const String _boundRev =
    '${kFilingApprovalRevisionPrefix}0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef';
const String _otherRev =
    '${kFilingApprovalRevisionPrefix}fedcba9876543210fedcba9876543210'
    'fedcba9876543210fedcba9876543210';

Map<String, dynamic> _boundReceipt([String rev = _boundRev]) => {
  ..._legacyReceipt,
  'grid.approved_rev': rev,
};

Bead _bead({
  IssueType type = IssueType.task,
  Object? plan = 'dart test',
  List<String> labels = const [],
  String description = 'A concrete brief',
  String design = '',
  String acceptance = '',
  DateTime? deferUntil,
  Map<String, dynamic> stamp = _legacyReceipt,
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

  test('receipt requires actor timestamp and revision', () {
    for (final incomplete in <Map<String, dynamic>>[
      // the timestamp alone — exactly what a hand-written approval looks like
      {'grid.approved_at': _legacyReceipt['grid.approved_at']},
      {..._legacyReceipt}..remove('grid.approved_by'),
      {..._legacyReceipt, 'grid.approved_by': '   '},
      {..._legacyReceipt, 'grid.approved_by': 7},
      {..._legacyReceipt}..remove('grid.approved_rev'),
      {..._legacyReceipt, 'grid.approved_rev': '   '},
      {..._legacyReceipt, 'grid.approved_rev': 42},
      // a local instant is not the UTC one the verb writes
      {..._legacyReceipt, 'grid.approved_at': '2026-09-02T14:30:00'},
      {..._legacyReceipt, 'grid.approved_at': 'approved'},
      {..._legacyReceipt, 'grid.approved_at': 20260902},
      // revision shapes the scheme does not recognize
      {..._legacyReceipt, 'grid.approved_rev': 'HEAD'},
      {..._legacyReceipt, 'grid.approved_rev': '9F1C2D3'},
      {..._legacyReceipt, 'grid.approved_rev': '9f1c2d'},
      {..._legacyReceipt, 'grid.approved_rev': 'filing:v1:sha256:abc'},
      {..._legacyReceipt, 'grid.approved_rev': 'filing:v2:sha256:${'a' * 64}'},
      {..._legacyReceipt, 'grid.approved_rev': 'a' * 64},
    ]) {
      final bead = _bead(stamp: incomplete);
      expect(isApprovalStamped(bead), isFalse, reason: '$incomplete');
      expect(ApprovalStamp.tryParse(bead), isNull, reason: '$incomplete');
      expect(mountEligibilityFindings(bead), [
        _notApproved,
      ], reason: '$incomplete');
    }
    expect(isApprovalStamped(_bead(stamp: _legacyReceipt)), isTrue);
    expect(isApprovalStamped(_bead(stamp: _boundReceipt())), isTrue);
  });

  test('bound receipt refuses changed bead and validation plan', () {
    final bound = _bead(stamp: _boundReceipt());
    expect(ApprovalStamp.tryParse(bound)!.bindsFilingBasis, isTrue);

    // No fresh evaluation ⇒ nothing to agree with, so the receipt is refused
    // rather than trusted on its face.
    expect(mountEligibilityFindings(bound), [_unevaluated]);
    expect(_clause(mountEligibilityDecision(bound)), _unevaluated);

    // A fresh evaluation that disagrees means the bead changed under the
    // approval.
    expect(
      mountEligibilityFindings(bound, evaluatedApprovalRevision: _otherRev),
      [_stale],
    );
    expect(
      _clause(
        mountEligibilityDecision(bound, evaluatedApprovalRevision: _otherRev),
      ),
      _stale,
    );

    // Agreement mounts.
    expect(
      mountEligibilityFindings(bound, evaluatedApprovalRevision: _boundRev),
      isEmpty,
    );

    // An INCOMPLETE receipt never reaches the comparison, however fresh the
    // evaluation is.
    expect(
      mountEligibilityFindings(
        _bead(stamp: const {'grid.approved_at': '2026-09-02T14:30:00.000Z'}),
        evaluatedApprovalRevision: _boundRev,
      ),
      [_notApproved],
    );

    // The earlier clauses keep their order and their precedence.
    expect(
      mountEligibilityFindings(
        _bead(type: IssueType.epic, plan: null, stamp: _boundReceipt()),
      ),
      ['type: not driveable', 'validation_plan: missing', _unevaluated],
    );
  });

  test('complete legacy receipt remains eligible', () {
    for (final rev in const [
      'c635790',
      '9f1c2d3e4b5a69788899aabbccddeeff00112233',
    ]) {
      final legacy = _bead(
        stamp: {..._legacyReceipt, 'grid.approved_rev': rev},
      );
      final stamp = ApprovalStamp.tryParse(legacy);
      expect(stamp, isNotNull, reason: rev);
      expect(stamp!.bindsFilingBasis, isFalse, reason: rev);
      // A store HEAD names no basis to re-derive, so no fresh evaluation is
      // required — and a supplied one is not compared against.
      expect(mountEligibilityFindings(legacy), isEmpty, reason: rev);
      expect(
        mountEligibilityFindings(legacy, evaluatedApprovalRevision: _otherRev),
        isEmpty,
        reason: rev,
      );
      expect(_clause(mountEligibilityDecision(legacy)), isNull, reason: rev);
    }
  });

  test('intake remains its distinct two-clause lifecycle contract', () {
    final bead = _bead(plan: null, stamp: const {});
    expect(intakeFindings(bead), isEmpty);
    expect(mountEligibilityFindings(bead), isNotEmpty);
  });
}
