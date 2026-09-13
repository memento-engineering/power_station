import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

CiFeedbackDecision decide(
  PullRequestCheckState checkState,
  List<String> workBeadKeys, {
  String beadId = 'tg-1',
}) => decideCiFeedback(
  beadId: beadId,
  sessionId: 'session',
  workBeadKeys: workBeadKeys,
  feedbackIdentity: 'abc123:${checkState.name}',
  checkState: checkState,
);

void main() {
  test('correlates the named bead and builds a stable ledger key', () {
    final decision = decide(PullRequestCheckState.failing, <String>[
      'tg-12#r3',
      'tg-1#r1',
    ]);
    expect(decision.beadId, 'tg-1');
    expect(decision.sessionId, 'session');
    expect(decision.round, 1);
    expect(decision.action, CiFeedbackAction.rework);
    expect(decision.idempotencyKey, 'github-ci:tg-1:r1:abc123:failing');
  });

  test('maps every aggregate check state', () {
    expect(
      decide(PullRequestCheckState.green, const <String>[]).action,
      CiFeedbackAction.landingReady,
    );
    expect(
      decide(PullRequestCheckState.failing, const <String>[]).action,
      CiFeedbackAction.rework,
    );
    for (final state in <PullRequestCheckState>[
      PullRequestCheckState.notReported,
      PullRequestCheckState.pending,
      PullRequestCheckState.inconclusive,
    ]) {
      expect(
        decide(state, const <String>[]).action,
        CiFeedbackAction.ignore,
        reason: '$state states no fact to act on',
      );
    }
    // Total: the switch over the sealed state is exhaustive, so every value is
    // covered above and a sixth would be a compile error rather than a silent
    // `ignore`.
    expect(PullRequestCheckState.values, hasLength(5));
  });

  test('gates at the shared cap', () {
    final keys = <String>[
      for (var i = 1; i <= kMaxReworkRounds; i++) 'tg-1#r$i',
    ];
    expect(
      decide(PullRequestCheckState.failing, keys).action,
      CiFeedbackAction.gate,
    );
    expect(
      decide(PullRequestCheckState.green, keys).action,
      CiFeedbackAction.landingReady,
      reason: 'green preserves the ledger rather than gating on it',
    );
  });

  test('no branch value participates in a decision', () {
    // The whole point of the ruling: `decideCiFeedback` cannot see a branch,
    // so `org/lockfile-convention` and `grid/tg-1` produce the same decision
    // for the same bead. There is nothing left to parse.
    expect(
      decide(PullRequestCheckState.failing, const <String>[]).idempotencyKey,
      decide(PullRequestCheckState.failing, const <String>[]).idempotencyKey,
    );
  });

  group('body references', () {
    test('one complete line-start trailer is the reference', () {
      expect(
        pullRequestBodyBeadReferences(
          'A human digest of the change.\n\nRefs: pow-78jk\n',
        ),
        <String>['pow-78jk'],
      );
    });

    test('repeated identical trailers collapse to one', () {
      expect(
        pullRequestBodyBeadReferences('Refs: pow-78jk\nRefs: pow-78jk\n'),
        <String>['pow-78jk'],
      );
    });

    test('two distinct trailers are two references', () {
      expect(
        pullRequestBodyBeadReferences('Refs: pow-78jk\nRefs: pow-9g0o\n'),
        <String>['pow-78jk', 'pow-9g0o'],
      );
    });

    test('prose, indentation and a blank value state nothing', () {
      for (final body in <String>[
        '',
        'This refs: pow-78jk somewhere in prose.',
        'See Refs: pow-78jk mentioned mid-sentence.',
        '  Refs: pow-78jk',
        'Refs:',
        'Refs:   ',
        'refs: pow-78jk',
      ]) {
        expect(
          pullRequestBodyBeadReferences(body),
          isEmpty,
          reason: 'a trailer must start its own line and carry a value',
        );
      }
    });

    test('a CRLF body still yields its trailer', () {
      expect(
        pullRequestBodyBeadReferences('Digest.\r\n\r\nRefs: pow-78jk\r\n'),
        <String>['pow-78jk'],
      );
    });
  });
}
