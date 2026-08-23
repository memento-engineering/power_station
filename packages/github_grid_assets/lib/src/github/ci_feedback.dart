import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'reconciler_event.dart';

/// The effect implied by a completed CI check.
enum CiFeedbackAction { ignore, landingReady, rework, gate }

/// A check result correlated with the current durable rework generation.
final class CiFeedbackDecision {
  const CiFeedbackDecision({
    required this.beadId,
    required this.sessionId,
    required this.round,
    required this.checkIdentity,
    required this.action,
  });

  final String beadId;
  final String sessionId;
  final int round;
  final String checkIdentity;
  final CiFeedbackAction action;

  String get idempotencyKey => 'github-ci:$beadId:r$round:$checkIdentity';
}

/// Derives feedback exclusively from the branch and immutable rework ledger.
///
/// [sessionId] is the unique current session selected by the projection.
/// [workBeadKeys] is the complete exported ledger, including retired `#r<N>`
/// keys. Green deliberately does not erase that history.
CiFeedbackDecision? decideCiFeedback(
  CheckConcluded event,
  String sessionId,
  Iterable<String> workBeadKeys,
) {
  const prefix = 'grid/';
  if (!event.headBranch.startsWith(prefix)) return null;
  final name = event.headBranch.substring(prefix.length);
  final beadId = WorktreeLayout.beadIdFromName(name);
  if (beadId == null) return null;
  final round = maxReworkRound(beadId, workBeadKeys);
  final action = switch (event.conclusion) {
    'success' => CiFeedbackAction.landingReady,
    'failure' || 'timed_out' || 'cancelled' || 'action_required' =>
      round < kMaxReworkRounds
          ? CiFeedbackAction.rework
          : CiFeedbackAction.gate,
    'neutral' ||
    'skipped' ||
    'stale' ||
    'startup_failure' => CiFeedbackAction.ignore,
    _ => CiFeedbackAction.ignore,
  };
  return CiFeedbackDecision(
    beadId: beadId,
    sessionId: sessionId,
    round: round,
    checkIdentity: '${event.checkName}:${event.observationId}',
    action: action,
  );
}
