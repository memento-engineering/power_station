library;

import 'package:grid_engine/grid_engine.dart';

import 'github_delivery_policy.dart';
import 'github_merge_runner.dart';
import 'github_pr_delivery.dart';

/// Opens a pull request through [GitHubPrDelivery], then conditionally enables
/// GitHub native auto-merge from the bounded validation and grade receipts.
final class GitHubAutoMergeDelivery implements DeliveryMethod {
  const GitHubAutoMergeDelivery({
    required GitHubPrDelivery prDelivery,
    required GitHubMergeRunner runner,
    required PrAutoMergePolicy policy,
    ExplorationTransport? transport,
  }) : _pr = prDelivery,
       _runner = runner,
       _policy = policy,
       _transport = transport;

  final GitHubPrDelivery _pr;
  final GitHubMergeRunner _runner;
  final PrAutoMergePolicy _policy;
  final ExplorationTransport? _transport;

  @override
  String get id => 'github-pr-auto-merge';

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async {
    final opened = await _pr.deliver(request);
    if (opened is Failed) return opened;
    final receipt = (opened as Ok).payload ?? const <String, String>{};
    final refusal = autoMergeGateRefusal(
      request.payload,
      minimumGrade: _policy.minimumGrade,
    );
    if (refusal != null) return _fallback(request, receipt, refusal);
    final result = await _runner.enableAutoMerge(
      request.workspace.workspaceDir,
      receipt['pr_url'] ?? '',
    );
    return switch (result) {
      GitHubMergeEnabled() => Ok({...receipt, 'auto_merge': 'enabled'}),
      GitHubMergeRefused(:final reason) => _fallback(request, receipt, reason),
    };
  }

  Ok _fallback(
    DeliveryRequest request,
    Map<String, String> receipt,
    String reason,
  ) {
    try {
      _transport?.flare('delivery.autoMergeFallback', {
        'bead': request.bead.id,
        'branch': request.workspace.branch,
        'minimum_grade': _policy.minimumGrade.name.toUpperCase(),
        'reason': reason,
      });
    } catch (_) {
      // Observability never changes the delivery result.
    }
    return Ok({
      ...receipt,
      'auto_merge': 'fallback-pr-no-merge',
      'auto_merge_reason': reason,
    });
  }
}
