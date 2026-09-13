import 'dart:convert';

import 'package:grid_engine/grid_engine.dart';

import 'reconciler_event.dart';

/// The effect implied by one pull request's aggregate check state.
enum CiFeedbackAction { ignore, landingReady, rework, gate }

/// A feedback state correlated with the current durable rework generation.
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

/// The `Refs:` trailer key, spelled exactly as the org's commit and pull-body
/// convention authors it.
const String _refsTrailer = 'Refs:';

/// The DISTINCT bead references stated in [body]'s `Refs:` trailers.
///
/// The PRIMARY attribution for an open pull request, and the reason the branch
/// name is no longer one: `grid/<bead>` parses only for a branch the station
/// itself minted, so every pull a seat opened was dropped — while a trailer is
/// a reference anyone can state on any branch. The org already fixes the shape
/// (`Refs: <bead>` in the trailer block, and nowhere else), so this reads
/// exactly that and never searches prose.
///
/// A trailer must start its own LINE and carry a non-blank value; repeated
/// identical trailers collapse to one. Two DISTINCT values are returned as
/// two, because an ambiguous pull must be reported rather than guessed at.
List<String> pullRequestBodyBeadReferences(String body) {
  final references = <String>[];
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith(_refsTrailer)) continue;
    final value = line.substring(_refsTrailer.length).trim();
    if (value.isEmpty) continue;
    if (references.contains(value)) continue;
    references.add(value);
  }
  return List<String>.unmodifiable(references);
}

/// Derives the effect of [checkState] against the immutable rework ledger.
///
/// [beadId] is resolved by the CALLER from an EXPLICIT reference — a `Refs:`
/// body trailer or a `gh-<number>` external ref — so no branch value reaches
/// this decision at all. [sessionId] is the unique current session the
/// projection selected, and [workBeadKeys] is the complete exported ledger,
/// including retired `#r<N>` keys. Green deliberately does not erase that
/// history.
///
/// [feedbackIdentity] is the caller's stable name for WHAT was observed; it is
/// the last segment of [CiFeedbackDecision.idempotencyKey], so a value that
/// moves when nothing meaningful changed would mint a second rework round for
/// one unchanged failure.
CiFeedbackDecision decideCiFeedback({
  required String beadId,
  required String sessionId,
  required Iterable<String> workBeadKeys,
  required String feedbackIdentity,
  required PullRequestCheckState checkState,
}) {
  final round = maxReworkRound(beadId, workBeadKeys);
  final action = switch (checkState) {
    PullRequestCheckState.green => CiFeedbackAction.landingReady,
    PullRequestCheckState.failing =>
      round < kMaxReworkRounds
          ? CiFeedbackAction.rework
          : CiFeedbackAction.gate,
    // Nothing has reported, something is still running, or everything finished
    // without a verdict: three ways of saying "no fact to act on yet".
    PullRequestCheckState.notReported ||
    PullRequestCheckState.pending ||
    PullRequestCheckState.inconclusive => CiFeedbackAction.ignore,
  };
  return CiFeedbackDecision(
    beadId: beadId,
    sessionId: sessionId,
    round: round,
    checkIdentity: feedbackIdentity,
    action: action,
  );
}
