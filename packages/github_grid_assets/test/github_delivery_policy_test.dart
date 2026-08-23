import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  const passing = {
    'validation_rc': '0',
    'committee_grades': 'code-validation=A,spec-adherence=B',
  };

  test('default threshold accepts the all-B boundary', () {
    const policy = PrAutoMergePolicy();
    expect(
      autoMergeGateRefusal(passing, minimumGrade: policy.minimumGrade),
      isNull,
    );
  });

  test('default threshold names a C below the B boundary', () {
    expect(
      autoMergeGateRefusal(const {
        'validation_rc': '0',
        'committee_grades': 'code-validation=A,spec-adherence=C',
      }, minimumGrade: const PrAutoMergePolicy().minimumGrade),
      'spec-adherence=C is below B',
    );
  });

  test('threshold is configurable', () {
    const policy = PrAutoMergePolicy(minimumGrade: CommitteeGrade.c);
    expect(
      autoMergeGateRefusal(const {
        'validation_rc': '0',
        'committee_grades': 'code-validation=C',
      }, minimumGrade: policy.minimumGrade),
      isNull,
    );
  });

  test('refuses nonzero validation, empty, and malformed grades', () {
    expect(
      autoMergeGateRefusal(const {
        'validation_rc': '2',
        'committee_grades': 'x=A',
      }, minimumGrade: CommitteeGrade.b),
      'code-validation rc=2',
    );
    expect(
      autoMergeGateRefusal(const {
        'validation_rc': '0',
      }, minimumGrade: CommitteeGrade.b),
      'committee grades are empty',
    );
    expect(
      autoMergeGateRefusal(const {
        'validation_rc': '0',
        'committee_grades': 'broken',
      }, minimumGrade: CommitteeGrade.b),
      'malformed committee grade: broken',
    );
  });
}
