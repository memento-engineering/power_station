// The six SPLIT AXES and the measured metrics behind them. The `circuit` axis
// is deliberately NOT called `seat`: `the_grid#agent-seat-and-agent-disc`
// reserves that noun for a standing agent position.
import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _session = LedgerSessionMetrics(sessionId: 's1', workBeadId: 'pow-1');
const _node = LedgerNodeMetrics(
  beadId: 'step-1',
  nodePath: 'pow-1/review/coherence',
  lane: 'coherence',
  harness: 'claude',
  model: 'opus',
  tokensIn: 10,
  cacheCreationInputTokens: 2,
  cacheReadInputTokens: 3,
  tokensOut: 4,
  numTurns: 5,
  harnessDurationMs: 6,
  durationMs: 7,
  costUsd: 0.25,
  rawFields: {
    AnalyticalResultFields.capability: 'critic',
    AnalyticalResultFields.thinkingTokens: '8',
    AnalyticalResultFields.retries: '9',
  },
);

void main() {
  test('the split axes carry no reserved `seat` noun', () {
    expect(
      MetricsSplitAxis.values.map((axis) => axis.wire),
      isNot(contains('seat')),
    );
    expect(MetricsSplitAxis.values.first, MetricsSplitAxis.circuit);
  });

  test('all six split axes derive their stable bucket key', () {
    expect(
      {
        for (final axis in MetricsSplitAxis.values)
          axis: bucketKeyOf(axis, _session, _node),
      },
      {
        MetricsSplitAxis.circuit: 'review/coherence',
        MetricsSplitAxis.task: 'pow-1',
        MetricsSplitAxis.lane: 'coherence',
        MetricsSplitAxis.capability: 'critic',
        MetricsSplitAxis.harness: 'claude',
        MetricsSplitAxis.model: 'opus',
      },
    );
  });

  test('a node path not rooted at its work bead survives whole', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'other/land',
      lane: 'land',
    );
    expect(circuitOf(_session, node), 'other/land');
  });

  test('capability falls back to the circuit leading segment', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/review/coherence',
      lane: 'coherence',
    );
    expect(capabilityOf(_session, node), 'review');
  });

  test('a missing harness or model is reported, never dropped', () {
    const node = LedgerNodeMetrics(
      beadId: 'step-2',
      nodePath: 'pow-1/land',
      lane: 'land',
    );
    expect(harnessOf(_session, node), kUnreportedBucket);
    expect(modelOf(_session, node), kUnreportedBucket);
  });

  test('a session with no work bead reports its task as unreported', () {
    const orphan = LedgerSessionMetrics(sessionId: 's9', workBeadId: '');
    expect(taskOf(orphan, _node), kUnreportedBucket);
  });

  group('readMetric', () {
    const rework = {'pow-1': 3};

    num? read(LedgerMetric metric, [LedgerNodeMetrics node = _node]) =>
        readMetric(metric, _session, node, reworkRoundsByWorkBead: rework);

    test('reads every carried metric and sums all token kinds', () {
      expect(read(LedgerMetric.uncachedInputTokens), 10);
      expect(read(LedgerMetric.cacheCreationTokens), 2);
      expect(read(LedgerMetric.cacheReadTokens), 3);
      expect(read(LedgerMetric.outputTokens), 4);
      expect(read(LedgerMetric.thinkingTokens), 8);
      expect(totalTokensOf(_node), 27);
      expect(read(LedgerMetric.totalTokens), 27);
      expect(read(LedgerMetric.turns), 5);
      expect(read(LedgerMetric.durationMs), 6);
      expect(read(LedgerMetric.retries), 9);
      expect(read(LedgerMetric.reworkRounds), 3);
      expect(read(LedgerMetric.costUsd), 0.25);
    });

    test('durationMs falls back to the step duration', () {
      const node = LedgerNodeMetrics(
        beadId: 'step-2',
        nodePath: 'pow-1/land',
        lane: 'land',
        durationMs: 42,
      );
      expect(read(LedgerMetric.durationMs, node), 42);
    });

    test('an absent metric is null and contributes no false zero', () {
      const node = LedgerNodeMetrics(
        beadId: 'step-2',
        nodePath: 'pow-1/land',
        lane: 'land',
      );
      expect(totalTokensOf(node), isNull);
      for (final metric in [
        LedgerMetric.uncachedInputTokens,
        LedgerMetric.cacheCreationTokens,
        LedgerMetric.cacheReadTokens,
        LedgerMetric.outputTokens,
        LedgerMetric.thinkingTokens,
        LedgerMetric.totalTokens,
        LedgerMetric.turns,
        LedgerMetric.durationMs,
        LedgerMetric.retries,
        LedgerMetric.costUsd,
      ]) {
        expect(
          readMetric(metric, _session, node, reworkRoundsByWorkBead: const {}),
          isNull,
          reason: '${metric.wire} must not invent a zero',
        );
      }
    });
  });
}
