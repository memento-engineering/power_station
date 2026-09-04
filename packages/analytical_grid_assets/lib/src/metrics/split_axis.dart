/// The axes a token distribution is SPLIT by, and their derivations from the
/// ledger projection. Nothing here averages: each axis is reported whole.
///
/// **On the word `circuit`.** The operator's report shape asked for a split
/// "by seat"; this pack calls that axis [MetricsSplitAxis.circuit] instead.
/// `the_grid#agent-seat-and-agent-disc` (accepted 2026-09-01, surfaces include
/// `**/*_grid_assets/**`) reserves **Agent Seat** for a standing agent
/// position — a role definition plus a wake condition — and names space-5rp as
/// the work "freeing the word `seat` by renaming the existing code symbols".
/// This axis is not that: it is a COORDINATE IN A CIRCUIT, a node's path
/// within the work bead's circuit with the bead prefix stripped
/// (`<work-bead>/review/coherence` → `review/coherence`). Minting a third
/// `seat` while the org clears the second would collide, so the axis carries
/// the circuit noun it actually names.
library;

import 'package:grid_engine/grid_engine.dart'
    show LedgerNodeMetrics, LedgerSessionMetrics;

/// The bucket key a split uses when the ledger reported no value on that axis.
/// An unreported harness or model is REPORTED under this key, never dropped.
const String kUnreportedBucket = '(unreported)';

/// The `grid.result.<nodePath>.<field>` raw-field keys this pack reads off
/// `LedgerNodeMetrics.rawFields` for metrics the typed projection does not
/// carry. A field no harness writes yields NO sample, so the split reports
/// insufficient-data rather than a false zero.
abstract final class AnalyticalResultFields {
  /// The `CapabilityRegistry` id, when a harness recorded it beside the
  /// result.
  static const capability = 'capability';

  /// Thinking / reasoning tokens.
  static const thinkingTokens = 'thinkingTokens';

  /// In-step retries the harness performed.
  static const retries = 'retries';
}

/// The six split axes.
enum MetricsSplitAxis {
  /// The CIRCUIT COORDINATE a node occupied — comparable across beads. NOT an
  /// Agent Seat; see this library's doc comment.
  circuit('circuit'),

  /// The unit of work — the work bead the session drives.
  task('task'),

  /// The projection's own lane (the node path's last segment).
  lane('lane'),

  /// The capability that ran the node.
  capability('capability'),

  /// The agent program that ran it.
  harness('harness'),

  /// The model that served it.
  model('model');

  const MetricsSplitAxis(this.wire);

  /// The stable JSON name.
  final String wire;
}

/// The CIRCUIT COORDINATE [node] occupied — its `nodePath` with the owning
/// session's work bead stripped (`<work-bead>/review/coherence` →
/// `review/coherence`), because a node path is rooted at the work bead id.
String circuitOf(LedgerSessionMetrics session, LedgerNodeMetrics node) {
  final prefix = '${session.workBeadId}/';
  return session.workBeadId.isNotEmpty && node.nodePath.startsWith(prefix)
      ? node.nodePath.substring(prefix.length)
      : node.nodePath;
}

/// The TASK — the work bead the session drives.
String taskOf(LedgerSessionMetrics session, LedgerNodeMetrics node) =>
    session.workBeadId.isEmpty ? kUnreportedBucket : session.workBeadId;

/// The LANE — the projection's own field.
String laneOf(LedgerSessionMetrics session, LedgerNodeMetrics node) =>
    node.lane.isEmpty ? kUnreportedBucket : node.lane;

/// The CAPABILITY that ran the node: the recorded
/// [AnalyticalResultFields.capability] when a harness wrote one, else the
/// circuit coordinate's leading segment.
String capabilityOf(LedgerSessionMetrics session, LedgerNodeMetrics node) {
  final recorded = node.rawFields[AnalyticalResultFields.capability];
  if (recorded != null && recorded.isNotEmpty) return recorded;
  final circuit = circuitOf(session, node);
  final slash = circuit.indexOf('/');
  final head = slash < 0 ? circuit : circuit.substring(0, slash);
  return head.isEmpty ? kUnreportedBucket : head;
}

/// The HARNESS that ran the node.
String harnessOf(LedgerSessionMetrics session, LedgerNodeMetrics node) {
  final harness = node.harness;
  return (harness == null || harness.isEmpty) ? kUnreportedBucket : harness;
}

/// The MODEL that served the node.
String modelOf(LedgerSessionMetrics session, LedgerNodeMetrics node) {
  final model = node.model;
  return (model == null || model.isEmpty) ? kUnreportedBucket : model;
}

/// The bucket key of [node] on [axis] — one exhaustive switch, so a new axis
/// cannot be added without a derivation.
String bucketKeyOf(
  MetricsSplitAxis axis,
  LedgerSessionMetrics session,
  LedgerNodeMetrics node,
) => switch (axis) {
  MetricsSplitAxis.circuit => circuitOf(session, node),
  MetricsSplitAxis.task => taskOf(session, node),
  MetricsSplitAxis.lane => laneOf(session, node),
  MetricsSplitAxis.capability => capabilityOf(session, node),
  MetricsSplitAxis.harness => harnessOf(session, node),
  MetricsSplitAxis.model => modelOf(session, node),
};
