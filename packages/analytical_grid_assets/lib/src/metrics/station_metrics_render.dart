/// The human face of the report — deterministic lines, no colour, no clock.
library;

import 'package:grid_engine/grid_engine.dart' show LedgerGrade;

import 'ledger_metric.dart';
import 'station_metrics_report.dart';
import 'work_bucket.dart';

/// Renders [report] to [out].
void renderStationMetricsReport(StationMetricsReport report, StringSink out) {
  for (final store in report.stores) {
    switch (store) {
      case StoreLedgerRead(:final sessionCount, :final nodeCount):
        out.writeln(
          '${store.store.name}: read — $sessionCount session(s), '
          '$nodeCount node(s)',
        );
      case StoreLedgerAbsent(:final reason):
        out.writeln('${store.store.name}: no state store — $reason');
      case StoreLedgerFailed(:final reason):
        out.writeln('${store.store.name}: read FAILED — $reason');
    }
  }
  out.writeln(
    'sparse threshold: ${report.sparseSampleThreshold} sampled session(s) — '
    'a split below it prints insufficient-data',
  );

  out.writeln('grade distribution by lane');
  for (final lane in report.gradeDistributionByLane.keys.toList()..sort()) {
    final counts = report.gradeDistributionByLane[lane]!;
    final rendered = [
      for (final grade in LedgerGrade.values)
        if ((counts[grade] ?? 0) > 0)
          '${grade.name.toUpperCase()}=${counts[grade]}',
    ].join(' ');
    out.writeln('  $lane: $rendered');
  }

  final falseFs = report.falseFs;
  out.writeln(
    'false F: ${falseFs.failClosedDefault}/${falseFs.total} fail-closed '
    '(${falseFs.realVerdict} real verdict, rate ${falseFs.rate})',
  );
  for (final day in report.falseFsByDay) {
    final byTransport = [
      for (final key in day.byTransport.keys.toList()..sort())
        '$key=${day.byTransport[key]}',
    ].join(' ');
    out.writeln('  ${day.day}: ${day.total} F — $byTransport');
  }

  final landed = report.landedDeliveries;
  out.writeln(
    'landed: ${landed.landedCount} delivery/deliveries — '
    'cost ${landed.landedCost}, cost/delivery '
    '${report.costPerLandedDelivery}, tokens ${report.landedTokens}, '
    'tokens/delivery ${report.tokensPerLandedDelivery}',
  );

  final cache = report.cacheTokens;
  out.writeln(
    'cache hit: ${report.cacheHitRatio} '
    '(read=${cache.cacheRead} create=${cache.cacheCreate} '
    'uncached=${cache.uncachedInput})',
  );
  out.writeln('cache hit by harness and model');
  for (final row in report.cacheHitsByHarnessAndModel) {
    out.writeln(
      row.insufficientData
          ? '  ${row.harness}/${row.model}: insufficient-data '
                '(${row.sessionCount} session(s), threshold ${row.threshold})'
          : '  ${row.harness}/${row.model}: ${row.ratio}',
    );
  }

  out.writeln('rework rounds by work bead');
  for (final bead in report.reworkRoundsByWorkBead.keys.toList()..sort()) {
    out.writeln('  $bead: ${report.reworkRoundsByWorkBead[bead]}');
  }

  out.writeln('rubric calibration by lane');
  for (final row in report.rubricCalibration) {
    out.writeln(
      row.insufficientData
          ? '  ${row.lane}: insufficient-data (${row.sessionCount} session(s))'
          : '  ${row.lane}: mean ${row.meanGradePoint}, '
                '${row.failClosedFs} fail-closed F',
    );
  }

  for (final split in report.splits) {
    out.writeln('split: ${split.axis.wire}');
    for (final bucket in split.buckets) {
      out.writeln('  ${bucket.key}');
      for (final workBucket in WorkBucket.values) {
        out.writeln(
          '    ${workBucket.wire}: '
          '${bucket.workCounts[workBucket] ?? 0} node(s)',
        );
        for (final metric in LedgerMetric.values) {
          final distribution = bucket.distributionsByWork[workBucket]![metric]!;
          out.writeln(
            distribution.insufficientData
                ? '      ${metric.wire}: '
                      '${distribution.insufficientDataReason}'
                : '      ${metric.wire}: samples=${distribution.sampleCount} '
                      'sessions=${distribution.sessionCount} '
                      'p50=${distribution.p50} p90=${distribution.p90} '
                      'p99=${distribution.p99} max=${distribution.max} '
                      '(worst ${distribution.worstSessionId})',
          );
        }
      }
    }
  }

  final recommendations = report.recommendations;
  out.writeln(
    'recommendations — conservative high-water marks with '
    'x${recommendations.headroomFactor} headroom; reporting only, nothing is '
    'enforced',
  );
  for (final (label, marks) in [
    ('per circuit', recommendations.perCircuit),
    ('per task', recommendations.perTask),
  ]) {
    out.writeln('  $label');
    for (final mark in marks) {
      out.writeln(
        mark.distribution.insufficientData
            ? '    ${mark.key}: ${mark.distribution.insufficientDataReason}'
            : '    ${mark.key}: high-water ${mark.highWaterTotalTokens} '
                  'tokens -> ${mark.recommendedTotalTokens} '
                  '(worst ${mark.distribution.worstSessionId})',
      );
    }
  }
}
