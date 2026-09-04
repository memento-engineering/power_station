/// The four work KINDS a report keeps apart. Pooling them into one
/// distribution is what makes a token number meaningless — a fail-closed
/// non-result and a landed build are not the same event.
library;

import 'package:grid_engine/grid_engine.dart'
    show
        LedgerNodeMetrics,
        LedgerSessionMetrics,
        ResultTransportAbsent,
        ResultTransportFailClosedDefault,
        ResultTransportOperatorRuling,
        ResultTransportReported;

/// The four buckets.
enum WorkBucket {
  /// Ran to a result and produced no grade — a build, land or deliver lane.
  successfulWork('successfulWork'),

  /// Produced a real letter grade through a real transport.
  substantiveGrade('substantiveGrade'),

  /// The verdict never really arrived (absent, or the fail-closed default).
  typedNonResult('typedNonResult'),

  /// A re-run of work an earlier session already attempted.
  replayedWork('replayedWork');

  const WorkBucket(this.wire);

  /// The stable JSON name.
  final String wire;
}

/// True when [node]'s verdict never really arrived: the fail-closed default,
/// or a grade whose transport provenance is absent. A node that never graded
/// at all — a build, land or deliver lane — is NOT a non-result.
bool isTypedNonResult(LedgerNodeMetrics node) => switch (node.transport) {
  ResultTransportFailClosedDefault() => true,
  ResultTransportAbsent() => node.grade != null,
  ResultTransportOperatorRuling() || ResultTransportReported() => false,
};

/// The earliest session id per work bead — the sessions that are NOT replays.
/// Ordered by `startedAt` then `sessionId`.
Map<String, String> firstSessionByWorkBead(
  Iterable<LedgerSessionMetrics> sessions,
) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final ordered = [...sessions]
    ..sort((a, b) {
      final byTime = (a.startedAt ?? epoch).compareTo(b.startedAt ?? epoch);
      return byTime != 0 ? byTime : a.sessionId.compareTo(b.sessionId);
    });
  final first = <String, String>{};
  for (final session in ordered) {
    first.putIfAbsent(session.workBeadId, () => session.sessionId);
  }
  return first;
}

/// Classifies one node. FIRST MATCH WINS: typed non-result, replay,
/// substantive grade, successful work.
WorkBucket bucketOf(
  LedgerSessionMetrics session,
  LedgerNodeMetrics node, {
  required Map<String, String> firstSessions,
}) {
  if (isTypedNonResult(node)) return WorkBucket.typedNonResult;
  if (firstSessions[session.workBeadId] != session.sessionId) {
    return WorkBucket.replayedWork;
  }
  return node.grade != null
      ? WorkBucket.substantiveGrade
      : WorkBucket.successfulWork;
}
