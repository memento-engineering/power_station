import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

CheckConcluded check(String conclusion, {String branch = 'grid/tg-1'}) =>
    NormalizedGitHubEvent.checkConcluded(
          nodeId: 'node',
          actor: 'actions',
          repository: 'memento/power',
          substation: 'power',
          observationId: 'observation',
          headBranch: branch,
          checkName: 'build',
          conclusion: conclusion,
        )
        as CheckConcluded;

void main() {
  test('correlates exact bead and builds a stable ledger key', () {
    final decision = decideCiFeedback(check('failure'), 'session', [
      'tg-12#r3',
      'tg-1#r1',
    ])!;
    expect(decision.beadId, 'tg-1');
    expect(decision.round, 1);
    expect(decision.action, CiFeedbackAction.rework);
    expect(decision.idempotencyKey, 'github-ci:tg-1:r1:build:observation');
  });

  test('maps every documented conclusion', () {
    expect(
      decideCiFeedback(check('success'), 's', const [])!.action,
      CiFeedbackAction.landingReady,
    );
    for (final conclusion in [
      'failure',
      'timed_out',
      'cancelled',
      'action_required',
    ]) {
      expect(
        decideCiFeedback(check(conclusion), 's', const [])!.action,
        CiFeedbackAction.rework,
      );
    }
    for (final conclusion in [
      'neutral',
      'skipped',
      'stale',
      'startup_failure',
      'unknown',
    ]) {
      expect(
        decideCiFeedback(check(conclusion), 's', const [])!.action,
        CiFeedbackAction.ignore,
      );
    }
  });

  test('gates at the shared cap and ignores foreign branches', () {
    final keys = [for (var i = 1; i <= kMaxReworkRounds; i++) 'tg-1#r$i'];
    expect(
      decideCiFeedback(check('failure'), 's', keys)!.action,
      CiFeedbackAction.gate,
    );
    expect(
      decideCiFeedback(check('failure', branch: 'feature/tg-1'), 's', keys),
      isNull,
    );
  });
}
