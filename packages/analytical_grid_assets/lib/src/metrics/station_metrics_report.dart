/// The station metrics REPORT — pure view models over the ledger projection.
/// Nothing here touches IO, so a later Flutter cockpit history surface renders
/// the same objects without going through the CLI.
library;

import 'package:grid_engine/grid_engine.dart'
    show CacheTokenTotals, FalseFMetrics, LandedDeliveryTotals, LedgerGrade;

import 'distribution.dart';
import 'ledger_metric.dart';
import 'metrics_store.dart';
import 'split_axis.dart';
import 'work_bucket.dart';

/// The per-store outcome — a sealed union so a consumer must face all three
/// cases. A report NEVER silently drops a store from the set.
sealed class StoreLedgerOutcome {
  /// Creates the outcome for [store].
  const StoreLedgerOutcome(this.store);

  /// The store this outcome is for.
  final MetricsStore store;

  /// JSON form (each case adds its own fields over the shared envelope).
  Map<String, dynamic> toJson();

  Map<String, dynamic> _envelope(String outcome) => {
    'store': store.name,
    'gridRoot': store.store.gridRoot,
    'outcome': outcome,
  };
}

/// The store resolved and its ledger projected; [sessionCount] may be zero.
class StoreLedgerRead extends StoreLedgerOutcome {
  /// Creates the read outcome.
  const StoreLedgerRead(
    super.store, {
    required this.sessionCount,
    required this.nodeCount,
    required this.decodeIssueCount,
  });

  /// How many sessions the projection carried.
  final int sessionCount;

  /// How many result nodes those sessions carried.
  final int nodeCount;

  /// How many decode issues the projection reported.
  final int decodeIssueCount;

  @override
  Map<String, dynamic> toJson() => {
    ..._envelope('read'),
    'sessionCount': sessionCount,
    'nodeCount': nodeCount,
    'decodeIssueCount': decodeIssueCount,
  };
}

/// The store's grid root carries no state store (`<gridRoot>/.grid/.beads/`
/// absent). Reported and skipped, never dropped.
class StoreLedgerAbsent extends StoreLedgerOutcome {
  /// Creates the absent outcome with the human-readable [reason].
  const StoreLedgerAbsent(super.store, {required this.reason});

  /// Names the missing store path.
  final String reason;

  @override
  Map<String, dynamic> toJson() => {..._envelope('absent'), 'reason': reason};
}

/// The store exists but the read failed — isolated per store.
class StoreLedgerFailed extends StoreLedgerOutcome {
  /// Creates the failed outcome with the human-readable [reason].
  const StoreLedgerFailed(super.store, {required this.reason});

  /// The failure detail.
  final String reason;

  @override
  Map<String, dynamic> toJson() => {..._envelope('failed'), 'reason': reason};
}

/// One bucket of one split — its key, its four work-kind counts, and a
/// separate [LedgerMetric] distribution map for EACH [WorkBucket].
class SplitBucket {
  /// Creates the bucket.
  const SplitBucket({
    required this.key,
    required this.workCounts,
    required this.distributionsByWork,
  });

  /// The axis value this bucket is keyed by.
  final String key;

  /// How many nodes fell in each work kind — kept apart, never pooled.
  final Map<WorkBucket, int> workCounts;

  /// One complete metric map per work kind. Every work kind is present, even
  /// when all its distributions carry zero samples and insufficient-data.
  final Map<WorkBucket, Map<LedgerMetric, Distribution>> distributionsByWork;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'key': key,
    'work': {
      for (final bucket in WorkBucket.values)
        bucket.wire: {
          'count': workCounts[bucket] ?? 0,
          'metrics': {
            for (final metric in LedgerMetric.values)
              metric.wire: distributionsByWork[bucket]![metric]!.toJson(),
          },
        },
    },
  };
}

/// One split — an axis and its buckets, in key order.
class SplitReport {
  /// Creates the split.
  const SplitReport({required this.axis, required this.buckets});

  /// The axis split on.
  final MetricsSplitAxis axis;

  /// The buckets, sorted by key.
  final List<SplitBucket> buckets;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'axis': axis.wire,
    'buckets': [for (final bucket in buckets) bucket.toJson()],
  };
}

/// One UTC day of the false-F trend. Overall false-F totals do NOT live here:
/// they remain the_grid's [FalseFMetrics], merged by the builder.
class FalseFDay {
  /// Creates the day.
  const FalseFDay({
    required this.day,
    required this.total,
    required this.byTransport,
  });

  /// The UTC calendar day, `YYYY-MM-DD`, or `(undated)`.
  final String day;

  /// How many F grades that day.
  final int total;

  /// How many of them arrived on each transport provenance.
  final Map<String, int> byTransport;

  /// The fail-closed share of that day's Fs, or null when there were none.
  double? get rate =>
      total == 0 ? null : (byTransport['fail-closed-default'] ?? 0) / total;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'day': day,
    'total': total,
    'byTransport': byTransport,
    'rate': rate,
  };
}

/// The cache-hit rate of one (harness, model) pair — the only cache
/// recomputation finer than a store. Overall cache totals remain
/// [CacheTokenTotals], merged by the builder.
class CacheHitRow {
  /// Creates the row.
  const CacheHitRow({
    required this.harness,
    required this.model,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    required this.uncachedInputTokens,
    required this.sessionCount,
    required this.threshold,
  });

  /// The agent program.
  final String harness;

  /// The model it served on.
  final String model;

  /// Tokens read from cache.
  final int cacheReadTokens;

  /// Tokens written to cache.
  final int cacheCreationTokens;

  /// Tokens billed uncached.
  final int uncachedInputTokens;

  /// How many distinct sessions contributed.
  final int sessionCount;

  /// The sparse floor.
  final int threshold;

  /// True when too few sessions contribute to report a rate honestly.
  bool get insufficientData => sessionCount < threshold;

  /// Cache reads over all input tokens, or null for sparse/no-input rows.
  double? get ratio {
    if (insufficientData) return null;
    final denominator =
        cacheReadTokens + cacheCreationTokens + uncachedInputTokens;
    return denominator == 0 ? null : cacheReadTokens / denominator;
  }

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'harness': harness,
    'model': model,
    'cacheReadTokens': cacheReadTokens,
    'cacheCreationTokens': cacheCreationTokens,
    'uncachedInputTokens': uncachedInputTokens,
    'sessionCount': sessionCount,
    'threshold': threshold,
    'insufficientData': insufficientData,
    'ratio': ratio,
  };
}

/// One lane's rubric calibration — the projected grades plus the session and
/// fail-closed provenance needed to interpret them.
class RubricCalibrationRow {
  /// Creates the row.
  const RubricCalibrationRow({
    required this.lane,
    required this.grades,
    required this.failClosedFs,
    required this.sessionCount,
    required this.threshold,
  });

  /// The lane.
  final String lane;

  /// The projection-owned grade counts for this lane.
  final Map<LedgerGrade, int> grades;

  /// How many of its Fs arrived on the fail-closed default transport.
  final int failClosedFs;

  /// How many distinct sessions contributed.
  final int sessionCount;

  /// The sparse floor.
  final int threshold;

  /// True when too few sessions contribute to report calibration honestly.
  bool get insufficientData => sessionCount < threshold;

  /// The mean grade point (A=4 … E=0.5, F=0), or null when
  /// [insufficientData] or the lane graded nothing.
  double? get meanGradePoint {
    if (insufficientData) return null;
    final count = grades.values.fold<int>(0, (sum, n) => sum + n);
    if (count == 0) return null;
    const points = <LedgerGrade, double>{
      LedgerGrade.a: 4,
      LedgerGrade.b: 3,
      LedgerGrade.c: 2,
      LedgerGrade.d: 1,
      LedgerGrade.e: 0.5,
      LedgerGrade.f: 0,
    };
    final total = grades.entries.fold<double>(
      0,
      (sum, entry) => sum + points[entry.key]! * entry.value,
    );
    return total / count;
  }

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'lane': lane,
    'grades': {
      for (final grade in LedgerGrade.values) grade.name: grades[grade] ?? 0,
    },
    'failClosedFs': failClosedFs,
    'sessionCount': sessionCount,
    'threshold': threshold,
    'insufficientData': insufficientData,
    'meanGradePoint': meanGradePoint,
  };
}

/// One conservative high-water mark. There is NO global counterpart.
class HighWaterMark {
  /// Creates the mark.
  const HighWaterMark({
    required this.key,
    required this.distribution,
    required this.headroomFactor,
  });

  /// The circuit coordinate or task this mark is for.
  final String key;

  /// The total-token distribution over HEALTHY TERMINAL sessions only.
  final Distribution distribution;

  /// The headroom applied to the high-water mark, stated explicitly.
  final double headroomFactor;

  /// The observed maximum, or null when [Distribution.insufficientData].
  num? get highWaterTotalTokens => distribution.max;

  /// The high-water mark with headroom, or null when there is no mark.
  int? get recommendedTotalTokens {
    final mark = highWaterTotalTokens;
    return mark == null ? null : (mark * headroomFactor).ceil();
  }

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'key': key,
    'headroomFactor': headroomFactor,
    'insufficientData': distribution.insufficientData,
    'sessionCount': distribution.sessionCount,
    'sampleCount': distribution.sampleCount,
    if (distribution.insufficientData)
      'reason': distribution.insufficientDataReason,
    'highWaterTotalTokens': highWaterTotalTokens,
    'recommendedTotalTokens': recommendedTotalTokens,
    'worstSessionId': distribution.worstSessionId,
  };
}

/// The recommendation surface: per-circuit-coordinate and per-task marks,
/// nothing global.
class RecommendationReport {
  /// Creates the surface.
  const RecommendationReport({
    required this.headroomFactor,
    required this.perCircuit,
    required this.perTask,
  });

  /// The headroom every mark carries.
  final double headroomFactor;

  /// Per-circuit-coordinate marks, in key order.
  final List<HighWaterMark> perCircuit;

  /// Per-task marks, in key order.
  final List<HighWaterMark> perTask;

  /// JSON form. There is deliberately NO aggregate field here.
  Map<String, dynamic> toJson() => {
    'headroomFactor': headroomFactor,
    'basis':
        'conservative per-circuit and per-task high-water marks over healthy '
        'terminal sessions; reporting only, no cap is enforced',
    'perCircuit': [for (final mark in perCircuit) mark.toJson()],
    'perTask': [for (final mark in perTask) mark.toJson()],
  };
}

/// The whole report. Aggregate false-F/cache/landing values are the projection
/// components after cross-store summation; day and harness/model are finer
/// views computed from projected sessions.
class StationMetricsReport {
  /// Creates the report.
  const StationMetricsReport({
    required this.stores,
    required this.sparseSampleThreshold,
    required this.gradeDistributionByLane,
    required this.falseFs,
    required this.falseFsByDay,
    required this.landedDeliveries,
    required this.landedTokens,
    required this.costPerLandedDelivery,
    required this.tokensPerLandedDelivery,
    required this.cacheTokens,
    required this.cacheHitRatio,
    required this.cacheHitsByHarnessAndModel,
    required this.reworkRoundsByWorkBead,
    required this.rubricCalibration,
    required this.splits,
    required this.recommendations,
  });

  /// One outcome per store in the set, in set order.
  final List<StoreLedgerOutcome> stores;

  /// The sparse floor this report was built against — stated in its output.
  final int sparseSampleThreshold;

  /// Projection-owned grade counts, summed per lane.
  final Map<String, Map<LedgerGrade, int>> gradeDistributionByLane;

  /// Projection-owned false-F components, summed across stores.
  final FalseFMetrics falseFs;

  /// The only new false-F computation: UTC day and transport splits.
  final List<FalseFDay> falseFsByDay;

  /// Projection-owned landed cost/count components, summed across stores.
  final LandedDeliveryTotals landedDeliveries;

  /// Tokens in landed sessions, read from projected sessions because the owned
  /// landed component does not carry a token numerator.
  final int landedTokens;

  /// Weighted cost per delivery from [landedDeliveries].
  final double? costPerLandedDelivery;

  /// [landedTokens] divided by the owned landed count.
  final double? tokensPerLandedDelivery;

  /// Projection-owned cache token components, summed across stores.
  final CacheTokenTotals cacheTokens;

  /// Weighted aggregate ratio from [cacheTokens].
  final double? cacheHitRatio;

  /// The only fine cache computation: rows by projected harness and model.
  final List<CacheHitRow> cacheHitsByHarnessAndModel;

  /// Projection-owned rework rounds per work bead, merged by maximum.
  final Map<String, int> reworkRoundsByWorkBead;

  /// Rubric calibration rows, in lane order.
  final List<RubricCalibrationRow> rubricCalibration;

  /// One split per axis, in [MetricsSplitAxis] order.
  final List<SplitReport> splits;

  /// The recommendation surface.
  final RecommendationReport recommendations;

  /// True when at least one store was read.
  bool get readAnyStore => stores.any((store) => store is StoreLedgerRead);

  /// JSON form — ONE object, deterministic key order, no wall clock.
  Map<String, dynamic> toJson() => {
    'spec': 1,
    'sparseSampleThreshold': sparseSampleThreshold,
    'stores': [for (final store in stores) store.toJson()],
    'gradeDistributionByLane': {
      for (final lane in gradeDistributionByLane.keys.toList()..sort())
        lane: {
          for (final grade in LedgerGrade.values)
            grade.name: gradeDistributionByLane[lane]![grade] ?? 0,
        },
    },
    'falseFs': {
      'total': falseFs.total,
      'failClosedDefault': falseFs.failClosedDefault,
      'realVerdict': falseFs.realVerdict,
      'rate': falseFs.rate,
      'byDay': [for (final day in falseFsByDay) day.toJson()],
    },
    'landedDelivery': {
      'landedCount': landedDeliveries.landedCount,
      'landedCost': landedDeliveries.landedCost,
      'landedTokens': landedTokens,
      'costPerLandedDelivery': costPerLandedDelivery,
      'tokensPerLandedDelivery': tokensPerLandedDelivery,
    },
    'cacheHit': {
      'cacheRead': cacheTokens.cacheRead,
      'cacheCreate': cacheTokens.cacheCreate,
      'uncachedInput': cacheTokens.uncachedInput,
      'ratio': cacheHitRatio,
    },
    'cacheHitByHarnessAndModel': [
      for (final row in cacheHitsByHarnessAndModel) row.toJson(),
    ],
    'reworkRoundsByWorkBead': {
      for (final bead in reworkRoundsByWorkBead.keys.toList()..sort())
        bead: reworkRoundsByWorkBead[bead],
    },
    'rubricCalibrationByLane': [
      for (final row in rubricCalibration) row.toJson(),
    ],
    'splits': [for (final split in splits) split.toJson()],
    'recommendations': recommendations.toJson(),
  };
}
