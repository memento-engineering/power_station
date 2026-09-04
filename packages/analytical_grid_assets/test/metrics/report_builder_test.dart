// The pure builder. Two things are pinned here: the OWNED MERGE MATH (the
// projection's own components are summed across stores, never averaged and
// never re-derived from result nodes) and the finer reports layered on top.
import 'dart:convert';

import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 9, 1, 12);

LedgerNodeMetrics _node(
  String beadId,
  String nodePath, {
  LedgerGrade? grade,
  ResultTransport transport = const ResultTransport.absent(),
  String? delivery,
  int? tokensIn,
  int? tokensOut,
  double? costUsd,
}) => LedgerNodeMetrics(
  beadId: beadId,
  nodePath: nodePath,
  lane: nodePath.split('/').last,
  grade: grade,
  transport: transport,
  delivery: delivery,
  harness: 'claude',
  model: 'opus',
  tokensIn: tokensIn,
  tokensOut: tokensOut,
  costUsd: costUsd,
  startedAt: _day,
);

/// Five landed sessions on five work beads, one of them fail-closed, plus a
/// sixth session replaying `pow-1` a day later.
List<StoreProjection> _fixture() {
  final sessions = <String, LedgerSessionMetrics>{};
  for (var n = 1; n <= 5; n++) {
    final bead = 'pow-$n';
    sessions['s$n'] = LedgerSessionMetrics(
      sessionId: 's$n',
      workBeadId: bead,
      startedAt: _day,
      closedAt: _day,
      nodes: [
        _node(
          bead,
          '$bead/review/coherence',
          grade: n == 5 ? LedgerGrade.f : LedgerGrade.a,
          transport: n == 5
              ? const ResultTransport.failClosedDefault()
              : const ResultTransport.reported('file'),
          tokensIn: 100 * n,
          tokensOut: 10 * n,
          costUsd: 0.1 * n,
        ),
        _node(
          bead,
          '$bead/land',
          delivery: 'pr',
          tokensIn: 50,
          tokensOut: 5,
          costUsd: 0.05,
        ),
      ],
    );
  }
  sessions['s6'] = LedgerSessionMetrics(
    sessionId: 's6',
    workBeadId: 'pow-1',
    startedAt: _day.add(const Duration(days: 1)),
    closedAt: _day.add(const Duration(days: 1)),
    nodes: [
      _node(
        'pow-1',
        'pow-1/review/coherence',
        grade: LedgerGrade.b,
        transport: const ResultTransport.reported('file'),
        tokensIn: 600,
        tokensOut: 0,
        costUsd: 0.6,
      ),
    ],
  );
  return [
    (
      store: MetricsStore(name: '(grid)', gridRoot: '/g'),
      projection: SessionLedgerMetricsProjection(
        sessionsById: sessions,
        falseFs: const FalseFMetrics(
          total: 1,
          failClosedDefault: 1,
          realVerdict: 0,
          rate: 1,
        ),
        cacheTokens: const CacheTokenTotals(uncachedInput: 2350),
        cacheHitRatio: 0,
        reworkRoundsByWorkBead: const {'pow-1': 1},
        landedDeliveries: const LandedDeliveryTotals(
          landedCost: 1.75,
          landedCount: 5,
        ),
        costPerLandedDelivery: 0.35,
        gradeDistributionByLane: const {
          'coherence': {LedgerGrade.a: 4, LedgerGrade.b: 1, LedgerGrade.f: 1},
        },
      ),
    ),
  ];
}

StationMetricsReport _report({
  int sparseSampleThreshold = kDefaultSparseSampleThreshold,
}) => buildStationMetricsReport(
  outcomes: [
    StoreLedgerRead(
      MetricsStore(name: '(grid)', gridRoot: '/g'),
      sessionCount: 6,
      nodeCount: 11,
      decodeIssueCount: 0,
    ),
  ],
  projections: _fixture(),
  sparseSampleThreshold: sparseSampleThreshold,
);

SplitBucket _bucket(
  StationMetricsReport report,
  MetricsSplitAxis axis,
  String key,
) => report.splits
    .firstWhere((split) => split.axis == axis)
    .buckets
    .firstWhere((bucket) => bucket.key == key);

void main() {
  group('builder guards', () {
    test('invalid sparse floors and headroom are refused loudly', () {
      expect(
        () => buildStationMetricsReport(
          outcomes: const [],
          projections: const [],
          sparseSampleThreshold: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildStationMetricsReport(
          outcomes: const [],
          projections: const [],
          headroomFactor: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildStationMetricsReport(
          outcomes: const [],
          projections: const [],
          headroomFactor: 0.9,
        ),
        throwsArgumentError,
      );
    });
  });

  group('owned projection merge', () {
    test('components are summed and ratios weighted, never averaged', () {
      final report = buildStationMetricsReport(
        outcomes: const [],
        projections: [
          (
            store: MetricsStore(name: 'one', gridRoot: '/one'),
            projection: const SessionLedgerMetricsProjection(
              falseFs: FalseFMetrics(
                total: 10,
                failClosedDefault: 1,
                realVerdict: 9,
                rate: 0.1,
              ),
              cacheTokens: CacheTokenTotals(
                cacheRead: 9,
                cacheCreate: 0,
                uncachedInput: 1,
              ),
              cacheHitRatio: 0.9,
              landedDeliveries: LandedDeliveryTotals(
                landedCost: 9,
                landedCount: 3,
              ),
              costPerLandedDelivery: 3,
              reworkRoundsByWorkBead: {'pow-1': 1},
              gradeDistributionByLane: {
                'coherence': {LedgerGrade.a: 2},
              },
            ),
          ),
          (
            store: MetricsStore(name: 'two', gridRoot: '/two'),
            projection: const SessionLedgerMetricsProjection(
              falseFs: FalseFMetrics(
                total: 20,
                failClosedDefault: 18,
                realVerdict: 2,
                rate: 0.9,
              ),
              cacheTokens: CacheTokenTotals(
                cacheRead: 20,
                cacheCreate: 30,
                uncachedInput: 50,
              ),
              cacheHitRatio: 0.2,
              landedDeliveries: LandedDeliveryTotals(
                landedCost: 10,
                landedCount: 1,
              ),
              costPerLandedDelivery: 10,
              reworkRoundsByWorkBead: {'pow-1': 4, 'pow-2': 2},
              gradeDistributionByLane: {
                'coherence': {LedgerGrade.a: 3, LedgerGrade.f: 1},
              },
            ),
          ),
        ],
      );

      expect(report.falseFs.total, 30);
      expect(report.falseFs.failClosedDefault, 19);
      expect(report.falseFs.realVerdict, 11);
      // 19/30, NOT the mean of the per-store 0.1 and 0.9.
      expect(report.falseFs.rate, closeTo(19 / 30, 1e-12));
      expect(
        report.cacheTokens,
        const CacheTokenTotals(
          cacheRead: 29,
          cacheCreate: 30,
          uncachedInput: 51,
        ),
      );
      // 29/110, NOT the mean of the per-store 0.9 and 0.2.
      expect(report.cacheHitRatio, closeTo(29 / 110, 1e-12));
      expect(
        report.landedDeliveries,
        const LandedDeliveryTotals(landedCost: 19, landedCount: 4),
      );
      // 19/4, NOT the mean of the per-store 3 and 10.
      expect(report.costPerLandedDelivery, 4.75);
      expect(report.reworkRoundsByWorkBead, {'pow-1': 4, 'pow-2': 2});
      expect(report.gradeDistributionByLane['coherence'], {
        LedgerGrade.a: 5,
        LedgerGrade.f: 1,
      });
      // Component-only stores carry no sessions, so the finer views are empty
      // while the aggregates above are whole — the merge never re-derives.
      expect(report.falseFsByDay, isEmpty);
      expect(report.cacheHitsByHarnessAndModel, isEmpty);
    });

    test('an empty projection set yields null rates, never zero or NaN', () {
      final report = buildStationMetricsReport(
        outcomes: const [],
        projections: const [],
      );
      expect(report.falseFs.rate, isNull);
      expect(report.cacheHitRatio, isNull);
      expect(report.costPerLandedDelivery, isNull);
      expect(report.tokensPerLandedDelivery, isNull);
      expect(report.readAnyStore, isFalse);
    });

    test('a session projected by two stores is counted once', () {
      const shared = SessionLedgerMetricsProjection(
        sessionsById: {
          's1': LedgerSessionMetrics(
            sessionId: 's1',
            workBeadId: 'pow-1',
            nodes: [
              LedgerNodeMetrics(
                beadId: 'step-1',
                nodePath: 'pow-1/land',
                lane: 'land',
                tokensIn: 10,
              ),
            ],
          ),
        },
      );
      final report = buildStationMetricsReport(
        outcomes: const [],
        projections: [
          (
            store: MetricsStore(name: 'one', gridRoot: '/one'),
            projection: shared,
          ),
          (
            store: MetricsStore(name: 'two', gridRoot: '/two'),
            projection: shared,
          ),
        ],
        sparseSampleThreshold: 1,
      );
      expect(
        _bucket(report, MetricsSplitAxis.lane, 'land')
            .distributionsByWork[WorkBucket.successfulWork]![LedgerMetric
                .uncachedInputTokens]!
            .sampleCount,
        1,
      );
    });
  });

  group('named reports', () {
    test('grade distribution by lane rides through from the projection', () {
      expect(_report().gradeDistributionByLane['coherence'], {
        LedgerGrade.a: 4,
        LedgerGrade.b: 1,
        LedgerGrade.f: 1,
      });
    });

    test('false-F aggregate is owned; only day/provenance is layered on', () {
      final report = _report();
      expect(report.falseFs.total, 1);
      expect(report.falseFs.failClosedDefault, 1);
      expect(report.falseFs.realVerdict, 0);
      expect(report.falseFs.rate, 1.0);
      expect(report.falseFsByDay.single.day, '2026-09-01');
      expect(report.falseFsByDay.single.byTransport, {
        'fail-closed-default': 1,
      });
      expect(report.falseFsByDay.single.rate, 1.0);
    });

    test('cost and tokens per landed delivery use the owned count', () {
      final report = _report();
      expect(report.landedDeliveries.landedCount, 5);
      expect(report.landedDeliveries.landedCost, closeTo(1.75, 1e-9));
      expect(report.landedTokens, 1925);
      expect(report.tokensPerLandedDelivery, closeTo(385, 1e-9));
      expect(report.costPerLandedDelivery, closeTo(0.35, 1e-9));
    });

    test('cache-hit rate is aggregate and split per harness/model', () {
      final report = _report();
      expect(report.cacheTokens.uncachedInput, 2350);
      expect(report.cacheHitRatio, 0);
      final row = report.cacheHitsByHarnessAndModel.single;
      expect((row.harness, row.model), ('claude', 'opus'));
      expect(row.sessionCount, 6);
      expect(row.insufficientData, isFalse);
      expect(row.uncachedInputTokens, 2350);
      expect(row.ratio, 0.0);
    });

    test('a sparse harness/model row reports no rate at all', () {
      final row = _report(
        sparseSampleThreshold: 20,
      ).cacheHitsByHarnessAndModel.single;
      expect(row.insufficientData, isTrue);
      expect(row.ratio, isNull);
      expect(row.toJson()['ratio'], isNull);
    });

    test('rework rounds ride through per work bead', () {
      expect(_report().reworkRoundsByWorkBead, {'pow-1': 1});
    });

    test('per-lane rubric calibration uses the owned grade counts', () {
      final row = _report().rubricCalibration.single;
      expect(row.lane, 'coherence');
      expect(row.sessionCount, 6);
      expect(row.failClosedFs, 1);
      // (4*A + 1*B + 1*F) / 6 = (16 + 3 + 0) / 6.
      expect(row.meanGradePoint, closeTo(19 / 6, 1e-9));
    });

    test('a sparse lane withholds its mean rather than misleading', () {
      final row = _report(sparseSampleThreshold: 20).rubricCalibration.single;
      expect(row.insufficientData, isTrue);
      expect(row.meanGradePoint, isNull);
    });
  });

  group('splits', () {
    test('every axis is reported', () {
      expect(
        _report().splits.map((split) => split.axis),
        MetricsSplitAxis.values,
      );
    });

    test('the circuit split carries p50/p90/p99/max and the worst session', () {
      final bucket = _bucket(
        _report(sparseSampleThreshold: 1),
        MetricsSplitAxis.circuit,
        'review/coherence',
      );
      final tokens =
          bucket.distributionsByWork[WorkBucket.substantiveGrade]![LedgerMetric
              .uncachedInputTokens]!;
      expect(tokens.sampleCount, 4);
      expect(tokens.sessionCount, 4);
      expect(tokens.insufficientData, isFalse);
      expect(tokens.p50, 200);
      expect(tokens.p90, 400);
      expect(tokens.p99, 400);
      expect(tokens.max, 400);
      expect(tokens.worstSessionId, 's4');
    });

    test('the four work kinds are counted apart, never pooled', () {
      final report = _report();
      final review = _bucket(
        report,
        MetricsSplitAxis.circuit,
        'review/coherence',
      );
      expect(review.workCounts[WorkBucket.substantiveGrade], 4);
      expect(review.workCounts[WorkBucket.typedNonResult], 1);
      expect(review.workCounts[WorkBucket.replayedWork], 1);
      expect(review.workCounts[WorkBucket.successfulWork], 0);
      expect(review.distributionsByWork.keys, WorkBucket.values);
      expect(
        review
            .distributionsByWork[WorkBucket.substantiveGrade]![LedgerMetric
                .uncachedInputTokens]!
            .sampleCount,
        4,
      );
      expect(
        review
            .distributionsByWork[WorkBucket.typedNonResult]![LedgerMetric
                .uncachedInputTokens]!
            .sampleCount,
        1,
      );
      expect(
        review
            .distributionsByWork[WorkBucket.replayedWork]![LedgerMetric
                .uncachedInputTokens]!
            .sampleCount,
        1,
      );
      expect(
        _bucket(
          report,
          MetricsSplitAxis.circuit,
          'land',
        ).workCounts[WorkBucket.successfulWork],
        5,
      );
    });

    test('an unreported metric says insufficient-data, never zero', () {
      final retries = _bucket(
        _report(),
        MetricsSplitAxis.circuit,
        'land',
      ).distributionsByWork[WorkBucket.successfulWork]![LedgerMetric.retries]!;
      expect(retries.sampleCount, 0);
      expect(retries.insufficientData, isTrue);
      expect(retries.p50, isNull);
      expect(retries.toJson().containsKey('p50'), isFalse);
      expect(retries.toJson()['sampleCount'], 0);
      expect(retries.insufficientDataReason, contains('insufficient-data'));
    });

    test('a null harness buckets under (unreported) rather than vanishing', () {
      final report = buildStationMetricsReport(
        outcomes: const [],
        projections: [
          (
            store: MetricsStore(name: '(grid)', gridRoot: '/g'),
            projection: const SessionLedgerMetricsProjection(
              sessionsById: {
                's1': LedgerSessionMetrics(
                  sessionId: 's1',
                  workBeadId: 'pow-1',
                  nodes: [
                    LedgerNodeMetrics(
                      beadId: 'pow-1',
                      nodePath: 'pow-1/land',
                      lane: 'land',
                      tokensIn: 10,
                    ),
                  ],
                ),
              },
            ),
          ),
        ],
      );
      expect(
        _bucket(report, MetricsSplitAxis.harness, kUnreportedBucket).key,
        kUnreportedBucket,
      );
      expect(
        _bucket(report, MetricsSplitAxis.model, kUnreportedBucket).key,
        kUnreportedBucket,
      );
    });
  });

  group('recommendation', () {
    test('per-circuit marks carry the headroom and the worst session', () {
      final mark = _report().recommendations.perCircuit.firstWhere(
        (mark) => mark.key == 'review/coherence',
      );
      expect(mark.distribution.sessionCount, 5);
      expect(mark.distribution.insufficientData, isFalse);
      expect(mark.highWaterTotalTokens, 550);
      expect(mark.headroomFactor, kDefaultHeadroomFactor);
      expect(mark.recommendedTotalTokens, 825);
      expect(mark.distribution.worstSessionId, 's5');
    });

    test('per-task marks sum all nodes in each healthy terminal session', () {
      final mark = _report(
        sparseSampleThreshold: 1,
      ).recommendations.perTask.firstWhere((mark) => mark.key == 'pow-1');
      expect(mark.distribution.sampleCount, 1);
      expect(mark.distribution.sessionCount, 1);
      expect(mark.highWaterTotalTokens, 165);
      expect(mark.recommendedTotalTokens, 248);
      expect(mark.distribution.worstSessionId, 's1');
    });

    test('a sparse per-task bucket says insufficient-data, not a number', () {
      final mark = _report().recommendations.perTask.firstWhere(
        (mark) => mark.key == 'pow-1',
      );
      expect(mark.distribution.insufficientData, isTrue);
      expect(mark.recommendedTotalTokens, isNull);
      expect(mark.toJson()['reason'], contains('1 session(s)'));
    });

    test('only healthy terminal sessions feed a mark', () {
      // s6 replays pow-1 but delivers nothing, so it is not terminal-healthy.
      expect(
        isHealthyTerminalSession(
          _fixture().single.projection.sessionsById['s6']!,
        ),
        isFalse,
      );
      expect(
        isHealthyTerminalSession(
          _fixture().single.projection.sessionsById['s1']!,
        ),
        isTrue,
      );
      // s5's only F is fail-closed — a transport failure, not a verdict.
      expect(
        isHealthyTerminalSession(
          _fixture().single.projection.sessionsById['s5']!,
        ),
        isTrue,
      );
    });

    test('a substantive F disqualifies an otherwise terminal session', () {
      const session = LedgerSessionMetrics(
        sessionId: 'sx',
        workBeadId: 'pow-9',
        nodes: [
          LedgerNodeMetrics(
            beadId: 'step-1',
            nodePath: 'pow-9/land',
            lane: 'land',
            delivery: 'pr',
          ),
          LedgerNodeMetrics(
            beadId: 'step-2',
            nodePath: 'pow-9/review/coherence',
            lane: 'coherence',
            grade: LedgerGrade.f,
            transport: ResultTransport.reported('file'),
          ),
        ],
      );
      expect(
        isHealthyTerminalSession(
          session.copyWith(closedAt: DateTime.utc(2026)),
        ),
        isFalse,
      );
    });

    test('no global cap ships anywhere in the JSON', () {
      final json = jsonEncode(_report().toJson());
      for (final forbidden in [
        'globalCap',
        'recommendedCap',
        'tokenCap',
        'budget',
        '"global"',
      ]) {
        expect(json, isNot(contains(forbidden)));
      }
      expect(jsonDecode(json), isA<Map<String, dynamic>>());
    });

    test('the report states its own sparse threshold', () {
      expect(
        _report().toJson()['sparseSampleThreshold'],
        kDefaultSparseSampleThreshold,
      );
    });
  });
}
