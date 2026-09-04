/// The reusable, UI-drivable metrics SERVICE — all the logic behind the
/// station's `metrics report` verb. The Command is a thin adapter over this; a
/// Flutter app calls it directly.
library;

import 'package:grid_sdk/grid_sdk.dart' as sdk;

import 'distribution.dart';
import 'ledger_source.dart';
import 'metrics_store.dart';
import 'station_metrics_builder.dart';
import 'station_metrics_report.dart';

/// Reads a STORE SET and builds the report.
class StationMetricsService {
  /// Creates the service over [source] and [dirExists].
  const StationMetricsService({
    LedgerMetricsSource source = const BdLedgerMetricsSource(),
    sdk.DirectoryProbe dirExists = sdk.defaultDirectoryProbe,
  }) : _source = source,
       _dirExists = dirExists;

  final LedgerMetricsSource _source;
  final sdk.DirectoryProbe _dirExists;

  /// Reports over [stores] — the set is an INPUT, read SEQUENTIALLY in set
  /// order. An absent store is reported; a failed read is isolated.
  Future<StationMetricsReport> report({
    required List<MetricsStore> stores,
    int sparseSampleThreshold = kDefaultSparseSampleThreshold,
    double headroomFactor = kDefaultHeadroomFactor,
  }) async {
    if (stores.isEmpty) {
      throw ArgumentError.value(
        stores,
        'stores',
        'StationMetricsService.report: the store set is an INPUT and must '
            'name at least one store — an empty set is a caller defect',
      );
    }
    final outcomes = <StoreLedgerOutcome>[];
    final projections = <StoreProjection>[];
    for (final store in stores) {
      if (!_dirExists(store.beadsDir)) {
        outcomes.add(
          StoreLedgerAbsent(
            store,
            reason: 'no grid state store at ${store.beadsDir}',
          ),
        );
        continue;
      }
      try {
        final projection = await _source.project(store);
        projections.add((store: store, projection: projection));
        outcomes.add(
          StoreLedgerRead(
            store,
            sessionCount: projection.sessionsById.length,
            nodeCount: projection.sessionsById.values.fold<int>(
              0,
              (sum, session) => sum + session.nodes.length,
            ),
            decodeIssueCount: projection.issues.length,
          ),
        );
      } on Object catch (error) {
        outcomes.add(StoreLedgerFailed(store, reason: '$error'));
      }
    }
    return buildStationMetricsReport(
      outcomes: outcomes,
      projections: projections,
      sparseSampleThreshold: sparseSampleThreshold,
      headroomFactor: headroomFactor,
    );
  }
}
