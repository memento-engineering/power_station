/// The measured quantities a split reports a distribution of. A reading the
/// ledger does not carry returns null and contributes NO sample.
library;

import 'package:grid_engine/grid_engine.dart'
    show LedgerNodeMetrics, LedgerSessionMetrics;

import 'split_axis.dart';

/// One measured quantity.
enum LedgerMetric {
  /// `tokensIn` — input tokens billed uncached.
  uncachedInputTokens('uncachedInputTokens'),

  /// `cache_creation_input_tokens`.
  cacheCreationTokens('cacheCreationTokens'),

  /// `cache_read_input_tokens`.
  cacheReadTokens('cacheReadTokens'),

  /// `tokensOut`.
  outputTokens('outputTokens'),

  /// Thinking / reasoning tokens, from the raw result fields.
  thinkingTokens('thinkingTokens'),

  /// Every token reading a node carried, summed.
  totalTokens('totalTokens'),

  /// `numTurns`.
  turns('turns'),

  /// The harness-observed duration, falling back to the step's own.
  durationMs('durationMs'),

  /// In-step retries, from the raw result fields.
  retries('retries'),

  /// The owning work bead's circuit / rework rounds.
  reworkRounds('reworkRounds'),

  /// `costUsd`.
  costUsd('costUsd');

  const LedgerMetric(this.wire);

  /// The stable JSON name.
  final String wire;
}

int? _rawInt(LedgerNodeMetrics node, String field) {
  final wire = node.rawFields[field];
  return wire == null ? null : int.tryParse(wire);
}

/// Every token reading [node] carried, summed — null when the node carried
/// none, so a token-free node contributes no sample instead of a zero.
int? totalTokensOf(LedgerNodeMetrics node) {
  final parts = <int?>[
    node.tokensIn,
    node.cacheCreationInputTokens,
    node.cacheReadInputTokens,
    node.tokensOut,
    _rawInt(node, AnalyticalResultFields.thinkingTokens),
  ];
  if (parts.every((part) => part == null)) return null;
  return parts.fold<int>(0, (sum, part) => sum + (part ?? 0));
}

/// Reads [metric] off [node] — null when the ledger did not carry it.
/// [reworkRoundsByWorkBead] is the projection's own per-work-bead round count.
num? readMetric(
  LedgerMetric metric,
  LedgerSessionMetrics session,
  LedgerNodeMetrics node, {
  required Map<String, int> reworkRoundsByWorkBead,
}) => switch (metric) {
  LedgerMetric.uncachedInputTokens => node.tokensIn,
  LedgerMetric.cacheCreationTokens => node.cacheCreationInputTokens,
  LedgerMetric.cacheReadTokens => node.cacheReadInputTokens,
  LedgerMetric.outputTokens => node.tokensOut,
  LedgerMetric.thinkingTokens => _rawInt(
    node,
    AnalyticalResultFields.thinkingTokens,
  ),
  LedgerMetric.totalTokens => totalTokensOf(node),
  LedgerMetric.turns => node.numTurns,
  LedgerMetric.durationMs => node.harnessDurationMs ?? node.durationMs,
  LedgerMetric.retries => _rawInt(node, AnalyticalResultFields.retries),
  LedgerMetric.reworkRounds => reworkRoundsByWorkBead[session.workBeadId],
  LedgerMetric.costUsd => node.costUsd,
};
