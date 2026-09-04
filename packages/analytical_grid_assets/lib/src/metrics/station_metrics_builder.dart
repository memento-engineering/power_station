/// The pure builder: ledger projections in, [StationMetricsReport] out. No IO,
/// no clock, no filesystem.
///
/// Aggregate false-F/cache/landing/rework/grade data is merged from the
/// projection's OWNED fields. Only finer reports read `sessionsById`.
library;

import 'package:grid_engine/grid_engine.dart'
    show
        CacheTokenTotals,
        FalseFMetrics,
        LandedDeliveryTotals,
        LedgerGrade,
        LedgerNodeMetrics,
        LedgerSessionMetrics,
        ResultTransport,
        ResultTransportAbsent,
        ResultTransportFailClosedDefault,
        ResultTransportOperatorRuling,
        ResultTransportReported,
        SessionLedgerMetricsProjection;

import 'distribution.dart';
import 'ledger_metric.dart';
import 'metrics_store.dart';
import 'split_axis.dart';
import 'station_metrics_report.dart';
import 'work_bucket.dart';

/// One store's projection, paired with the store it came from.
typedef StoreProjection = ({
  MetricsStore store,
  SessionLedgerMetricsProjection projection,
});

typedef _Observation = ({LedgerSessionMetrics session, LedgerNodeMetrics node});

class _CacheTally {
  int read = 0;
  int create = 0;
  int uncached = 0;
  final Set<String> sessions = <String>{};
}

/// A session is HEALTHY TERMINAL when it closed, recorded a delivery, and
/// carries no substantive F. A typed non-result is a transport failure, not a
/// verdict, so it does not disqualify the session.
bool isHealthyTerminalSession(LedgerSessionMetrics session) =>
    session.closedAt != null &&
    session.nodes.any((node) => (node.delivery ?? '').isNotEmpty) &&
    !session.nodes.any(
      (node) => node.grade == LedgerGrade.f && !isTypedNonResult(node),
    );

/// Builds the whole report from [outcomes] and [projections].
///
/// OWNED MERGE MATH: sum [FalseFMetrics] components; sum [CacheTokenTotals]
/// components and derive one weighted ratio; sum [LandedDeliveryTotals]
/// components and derive one weighted cost; take the maximum rework round per
/// work bead; sum projected grade counts. Per-store ratios are never averaged.
StationMetricsReport buildStationMetricsReport({
  required List<StoreLedgerOutcome> outcomes,
  required List<StoreProjection> projections,
  int sparseSampleThreshold = kDefaultSparseSampleThreshold,
  double headroomFactor = kDefaultHeadroomFactor,
}) {
  if (sparseSampleThreshold < 1) {
    throw ArgumentError.value(
      sparseSampleThreshold,
      'sparseSampleThreshold',
      'buildStationMetricsReport: threshold must be a positive integer',
    );
  }
  if (!headroomFactor.isFinite || headroomFactor < 1) {
    throw ArgumentError.value(
      headroomFactor,
      'headroomFactor',
      'buildStationMetricsReport: headroom must be finite and at least 1.0',
    );
  }

  var falseFTotal = 0;
  var falseFFailClosed = 0;
  var falseFRealVerdict = 0;
  var cacheRead = 0;
  var cacheCreate = 0;
  var uncachedInput = 0;
  var landedCost = 0.0;
  var landedCount = 0;
  final sessions = <LedgerSessionMetrics>[];
  final seenSessions = <String>{};
  final rework = <String, int>{};
  final gradeByLane = <String, Map<LedgerGrade, int>>{};

  for (final entry in projections) {
    final projection = entry.projection;
    falseFTotal += projection.falseFs.total;
    falseFFailClosed += projection.falseFs.failClosedDefault;
    falseFRealVerdict += projection.falseFs.realVerdict;
    cacheRead += projection.cacheTokens.cacheRead;
    cacheCreate += projection.cacheTokens.cacheCreate;
    uncachedInput += projection.cacheTokens.uncachedInput;
    landedCost += projection.landedDeliveries.landedCost;
    landedCount += projection.landedDeliveries.landedCount;

    for (final session in projection.sessionsById.values) {
      if (seenSessions.add(session.sessionId)) sessions.add(session);
    }
    projection.reworkRoundsByWorkBead.forEach((bead, rounds) {
      final prior = rework[bead] ?? 0;
      rework[bead] = rounds > prior ? rounds : prior;
    });
    projection.gradeDistributionByLane.forEach((lane, counts) {
      final target = gradeByLane[lane] ??= <LedgerGrade, int>{};
      counts.forEach(
        (grade, count) => target[grade] = (target[grade] ?? 0) + count,
      );
    });
  }
  sessions.sort((a, b) => a.sessionId.compareTo(b.sessionId));

  final falseFs = FalseFMetrics(
    total: falseFTotal,
    failClosedDefault: falseFFailClosed,
    realVerdict: falseFRealVerdict,
    rate: falseFTotal == 0 ? null : falseFFailClosed / falseFTotal,
  );
  final cacheTokens = CacheTokenTotals(
    cacheRead: cacheRead,
    cacheCreate: cacheCreate,
    uncachedInput: uncachedInput,
  );
  final cacheDenominator = cacheRead + cacheCreate + uncachedInput;
  final cacheHitRatio = cacheDenominator == 0
      ? null
      : cacheRead / cacheDenominator;
  final landedDeliveries = LandedDeliveryTotals(
    landedCost: landedCost,
    landedCount: landedCount,
  );
  final costPerLandedDelivery = landedCount == 0
      ? null
      : landedCost / landedCount;

  final observations = <_Observation>[
    for (final session in sessions)
      for (final node in session.nodes) (session: session, node: node),
  ];
  final firstSessions = firstSessionByWorkBead(sessions);
  final healthyIds = <String>{
    for (final session in sessions)
      if (isHealthyTerminalSession(session)) session.sessionId,
  };

  // The owned landed components do not carry a token numerator. Read only that
  // missing numerator from projected sessions — over the same node set the
  // engine sums `landedCost` across — so cost and count above remain
  // exclusively projection-owned.
  final landedTokens = sessions
      .where(
        (session) =>
            session.nodes.any((node) => (node.delivery ?? '').isNotEmpty),
      )
      .expand((session) => session.nodes)
      .fold<int>(0, (sum, node) => sum + (totalTokensOf(node) ?? 0));
  final tokensPerLandedDelivery = landedCount == 0
      ? null
      : landedTokens / landedCount;

  return StationMetricsReport(
    stores: outcomes,
    sparseSampleThreshold: sparseSampleThreshold,
    gradeDistributionByLane: gradeByLane,
    falseFs: falseFs,
    falseFsByDay: _falseFTrend(observations),
    landedDeliveries: landedDeliveries,
    landedTokens: landedTokens,
    costPerLandedDelivery: costPerLandedDelivery,
    tokensPerLandedDelivery: tokensPerLandedDelivery,
    cacheTokens: cacheTokens,
    cacheHitRatio: cacheHitRatio,
    cacheHitsByHarnessAndModel: _cacheHitSplits(
      observations,
      sparseSampleThreshold,
    ),
    reworkRoundsByWorkBead: rework,
    rubricCalibration: _calibration(
      observations,
      gradeByLane,
      sparseSampleThreshold,
    ),
    splits: [
      for (final axis in MetricsSplitAxis.values)
        SplitReport(
          axis: axis,
          buckets: _bucketsFor(
            axis,
            observations,
            firstSessions: firstSessions,
            rework: rework,
            threshold: sparseSampleThreshold,
          ),
        ),
    ],
    recommendations: RecommendationReport(
      headroomFactor: headroomFactor,
      perCircuit: _marks(
        MetricsSplitAxis.circuit,
        observations,
        healthyIds: healthyIds,
        threshold: sparseSampleThreshold,
        headroomFactor: headroomFactor,
      ),
      perTask: _marks(
        MetricsSplitAxis.task,
        observations,
        healthyIds: healthyIds,
        threshold: sparseSampleThreshold,
        headroomFactor: headroomFactor,
      ),
    ),
  );
}

/// The transport's wire name — the provenance a false-F day is keyed by.
String transportWireOf(ResultTransport transport) => switch (transport) {
  ResultTransportAbsent() => 'absent',
  ResultTransportFailClosedDefault() => 'fail-closed-default',
  ResultTransportOperatorRuling() => 'operator-ruling',
  ResultTransportReported(:final value) => value,
};

String _utcDay(DateTime at) {
  final utc = at.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// ONLY the UTC-day/transport split is derived here. Overall false-F values
/// come from the merged [FalseFMetrics].
List<FalseFDay> _falseFTrend(List<_Observation> observations) {
  final byDay = <String, Map<String, int>>{};
  for (final observation in observations) {
    if (observation.node.grade != LedgerGrade.f) continue;
    final transport = transportWireOf(observation.node.transport);
    final at = observation.session.startedAt ?? observation.node.startedAt;
    final day = at == null ? '(undated)' : _utcDay(at);
    final counts = byDay[day] ??= <String, int>{};
    counts[transport] = (counts[transport] ?? 0) + 1;
  }
  return [
    for (final day in byDay.keys.toList()..sort())
      FalseFDay(
        day: day,
        total: byDay[day]!.values.fold<int>(0, (sum, n) => sum + n),
        byTransport: Map<String, int>.unmodifiable(byDay[day]!),
      ),
  ];
}

/// ONLY the harness/model split is derived here. Overall cache values come
/// from the merged [CacheTokenTotals].
List<CacheHitRow> _cacheHitSplits(
  List<_Observation> observations,
  int threshold,
) {
  final tallies = <(String, String), _CacheTally>{};
  for (final observation in observations) {
    final key = (
      harnessOf(observation.session, observation.node),
      modelOf(observation.session, observation.node),
    );
    final tally = tallies[key] ??= _CacheTally();
    tally.read += observation.node.cacheReadInputTokens ?? 0;
    tally.create += observation.node.cacheCreationInputTokens ?? 0;
    tally.uncached += observation.node.tokensIn ?? 0;
    tally.sessions.add(observation.session.sessionId);
  }
  final keys = tallies.keys.toList()
    ..sort((a, b) {
      final byHarness = a.$1.compareTo(b.$1);
      return byHarness != 0 ? byHarness : a.$2.compareTo(b.$2);
    });
  return [
    for (final key in keys)
      CacheHitRow(
        harness: key.$1,
        model: key.$2,
        cacheReadTokens: tallies[key]!.read,
        cacheCreationTokens: tallies[key]!.create,
        uncachedInputTokens: tallies[key]!.uncached,
        sessionCount: tallies[key]!.sessions.length,
        threshold: threshold,
      ),
  ];
}

List<RubricCalibrationRow> _calibration(
  List<_Observation> observations,
  Map<String, Map<LedgerGrade, int>> gradeByLane,
  int threshold,
) {
  final failClosed = <String, int>{};
  final sessions = <String, Set<String>>{};
  for (final observation in observations) {
    if (observation.node.grade == null) continue;
    final lane = laneOf(observation.session, observation.node);
    (sessions[lane] ??= <String>{}).add(observation.session.sessionId);
    final failClosedTransport = switch (observation.node.transport) {
      ResultTransportFailClosedDefault() => true,
      ResultTransportAbsent() ||
      ResultTransportOperatorRuling() ||
      ResultTransportReported() => false,
    };
    if (observation.node.grade == LedgerGrade.f && failClosedTransport) {
      failClosed[lane] = (failClosed[lane] ?? 0) + 1;
    }
  }
  return [
    for (final lane in gradeByLane.keys.toList()..sort())
      RubricCalibrationRow(
        lane: lane,
        grades: Map<LedgerGrade, int>.unmodifiable(gradeByLane[lane]!),
        failClosedFs: failClosed[lane] ?? 0,
        sessionCount: sessions[lane]?.length ?? 0,
        threshold: threshold,
      ),
  ];
}

List<SplitBucket> _bucketsFor(
  MetricsSplitAxis axis,
  List<_Observation> observations, {
  required Map<String, String> firstSessions,
  required Map<String, int> rework,
  required int threshold,
}) {
  final grouped = <String, List<_Observation>>{};
  for (final observation in observations) {
    final key = bucketKeyOf(axis, observation.session, observation.node);
    (grouped[key] ??= <_Observation>[]).add(observation);
  }
  final buckets = <SplitBucket>[];
  for (final key in grouped.keys.toList()..sort()) {
    final members = grouped[key]!;
    final classified = <WorkBucket, List<_Observation>>{
      for (final bucket in WorkBucket.values) bucket: <_Observation>[],
    };
    for (final observation in members) {
      classified[bucketOf(
            observation.session,
            observation.node,
            firstSessions: firstSessions,
          )]!
          .add(observation);
    }
    final work = <WorkBucket, int>{
      for (final bucket in WorkBucket.values)
        bucket: classified[bucket]!.length,
    };
    final distributions = <WorkBucket, Map<LedgerMetric, Distribution>>{
      for (final bucket in WorkBucket.values)
        bucket: <LedgerMetric, Distribution>{
          for (final metric in LedgerMetric.values)
            metric: Distribution.from([
              for (final observation in classified[bucket]!)
                if (readMetric(
                      metric,
                      observation.session,
                      observation.node,
                      reworkRoundsByWorkBead: rework,
                    )
                    case final value?)
                  (value: value, sessionId: observation.session.sessionId),
            ], threshold: threshold),
        },
    };
    buckets.add(
      SplitBucket(
        key: key,
        workCounts: Map<WorkBucket, int>.unmodifiable(work),
        distributionsByWork:
            Map<WorkBucket, Map<LedgerMetric, Distribution>>.unmodifiable({
              for (final entry in distributions.entries)
                entry.key: Map<LedgerMetric, Distribution>.unmodifiable(
                  entry.value,
                ),
            }),
      ),
    );
  }
  return buckets;
}

List<HighWaterMark> _marks(
  MetricsSplitAxis axis,
  List<_Observation> observations, {
  required Set<String> healthyIds,
  required int threshold,
  required double headroomFactor,
}) {
  final grouped = <String, Map<String, int>>{};
  for (final observation in observations) {
    if (!healthyIds.contains(observation.session.sessionId)) continue;
    final key = bucketKeyOf(axis, observation.session, observation.node);
    final bySession = grouped[key] ??= <String, int>{};
    final total = totalTokensOf(observation.node);
    if (total == null) continue;
    final sessionId = observation.session.sessionId;
    bySession[sessionId] = (bySession[sessionId] ?? 0) + total;
  }
  return [
    for (final key in grouped.keys.toList()..sort())
      HighWaterMark(
        key: key,
        distribution: Distribution.from([
          for (final entry in grouped[key]!.entries)
            (value: entry.value, sessionId: entry.key),
        ], threshold: threshold),
        headroomFactor: headroomFactor,
      ),
  ];
}
