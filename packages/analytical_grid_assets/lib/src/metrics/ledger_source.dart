/// The per-store READ seam over the_grid's typed session-ledger metrics
/// projection (tg-5drf.2). This pack PRESENTS that projection; it never
/// re-derives it.
library;

import 'package:beads_dart/beads_dart.dart'
    show
        Bead,
        BdCliService,
        BdRunner,
        BeadDependency,
        GraphSnapshot,
        IssueType,
        ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart'
    show SessionLedgerMetricsProjection, projectSessionLedgerMetrics;
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;

import 'metrics_store.dart';

/// The read seam — READ-ONLY BY CONSTRUCTION: one read method, no mutation
/// surface, so a report cannot write a foreign store *by type*. There is no
/// runtime read-only guard because there is no write path to refuse (guards
/// LOUD or GONE).
abstract interface class LedgerMetricsSource {
  /// Projects [store]'s session ledger — the ONLY data this pack consumes.
  Future<SessionLedgerMetricsProjection> project(MetricsStore store);
}

/// The default source: TWO `bd list` reads per store (session beads, then step
/// beads), merged into one [GraphSnapshot] and handed to the_grid's own
/// [projectSessionLedgerMetrics].
///
/// Never `bd show` (it writes `.beads/last-touched` and self-triggers the
/// store's watcher), never a mutation verb, never SQL.
class BdLedgerMetricsSource implements LedgerMetricsSource {
  /// Creates the source. [runnerFor] is the injectable spawn seam (tests
  /// record argv through it; the default spawns a real `bd` in the store's
  /// runtime dir).
  const BdLedgerMetricsSource({
    BdRunner Function(String runtimeDir) runnerFor = _processRunnerFor,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String runtimeDir) _runnerFor;

  static BdRunner _processRunnerFor(String runtimeDir) =>
      ProcessBdRunner(workspaceRoot: runtimeDir);

  /// The two ledger bead types, in read order — the session beads that own the
  /// ledger and the step beads that carry the per-node results.
  static const List<IssueType> _ledgerTypes = [
    GridIssueTypes.session,
    GridIssueTypes.step,
  ];

  /// The capture instant of a synthesized snapshot. The ledger projection
  /// never reads it, and a wall-clock value would make the report
  /// irreproducible.
  static final DateTime _capturedAt = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  @override
  Future<SessionLedgerMetricsProjection> project(MetricsStore store) async {
    final bd = BdCliService(_runnerFor(store.runtimeDir));
    final beads = <Bead>[];
    final dependencies = <String, BeadDependency>{};
    for (final type in _ledgerTypes) {
      final scope = await bd.listScope(type: type, includeClosed: true);
      beads.addAll(scope.beads);
      for (final dep in scope.dependencies) {
        dependencies[dep.edgeKey] = dep;
      }
    }
    return projectSessionLedgerMetrics(
      GraphSnapshot.fromParts(
        beads: beads,
        dependencies: dependencies.values,
        readyIds: const <String>[],
        capturedAt: _capturedAt,
      ),
    );
  }
}
