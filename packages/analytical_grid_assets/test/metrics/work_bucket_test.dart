// The four work KINDS. Pooling them is what makes a token number meaningless,
// so classification is pinned first-match-wins.
import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _firstNode = LedgerNodeMetrics(
  beadId: 'step-1',
  nodePath: 'pow-1/review/coherence',
  lane: 'coherence',
);

LedgerSessionMetrics _session(
  String id,
  LedgerNodeMetrics node, {
  DateTime? startedAt,
}) => LedgerSessionMetrics(
  sessionId: id,
  workBeadId: 'pow-1',
  startedAt: startedAt,
  nodes: [node],
);

void main() {
  final first = _session('s1', _firstNode, startedAt: DateTime.utc(2026));
  final replay = _session(
    's2',
    _firstNode,
    startedAt: DateTime.utc(2026, 1, 2),
  );
  final firstSessions = firstSessionByWorkBead([replay, first]);

  test('the first session is chosen by start time, not iteration order', () {
    expect(firstSessions, {'pow-1': 's1'});
  });

  test('typed non-results win classification, including on a replay', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/review/coherence',
      lane: 'coherence',
      grade: LedgerGrade.f,
      transport: ResultTransport.failClosedDefault(),
    );
    expect(
      bucketOf(replay, node, firstSessions: firstSessions),
      WorkBucket.typedNonResult,
    );
  });

  test('a graded node whose transport is absent is a typed non-result', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/review/coherence',
      lane: 'coherence',
      grade: LedgerGrade.a,
    );
    expect(isTypedNonResult(node), isTrue);
  });

  test('an ungraded node with absent transport is NOT a non-result', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/land',
      lane: 'land',
    );
    expect(isTypedNonResult(node), isFalse);
  });

  test('a later session for the work bead is replayed work', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/review/coherence',
      lane: 'coherence',
      grade: LedgerGrade.a,
      transport: ResultTransport.reported('file'),
    );
    expect(
      bucketOf(replay, node, firstSessions: firstSessions),
      WorkBucket.replayedWork,
    );
  });

  test('a real grade in the first session is substantive', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-1',
      nodePath: 'pow-1/review/coherence',
      lane: 'coherence',
      grade: LedgerGrade.a,
      transport: ResultTransport.reported('file'),
    );
    expect(
      bucketOf(first, node, firstSessions: firstSessions),
      WorkBucket.substantiveGrade,
    );
  });

  test('an ungraded first-session delivery is successful work', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-1',
      nodePath: 'pow-1/land',
      lane: 'land',
      delivery: 'pr',
    );
    expect(
      bucketOf(first, node, firstSessions: firstSessions),
      WorkBucket.successfulWork,
    );
  });
}
