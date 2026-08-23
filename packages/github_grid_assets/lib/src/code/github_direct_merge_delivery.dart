library;

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'github_delivery_policy.dart';
import 'github_merge_runner.dart';

/// Pushes a reviewed branch directly to an unprotected base branch, refusing
/// loudly before any base mutation when protection cannot be ruled out.
final class GitHubDirectMergeDelivery implements DeliveryMethod {
  const GitHubDirectMergeDelivery({
    required GitOps gitOps,
    required GitRunner gitRunner,
    required GitHubMergeRunner mergeRunner,
    required DirectMergePolicy policy,
    ExplorationTransport? transport,
    this.composition = const PrComposition(),
  }) : _ops = gitOps,
       _git = gitRunner,
       _merge = mergeRunner,
       _policy = policy,
       _transport = transport;

  final GitOps _ops;
  final GitRunner _git;
  final GitHubMergeRunner _merge;
  final DirectMergePolicy _policy;
  final ExplorationTransport? _transport;

  /// Supplies the residue commit's trailer token.
  final PrComposition composition;

  @override
  String get id => 'github-direct-merge';

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async {
    final dir = request.workspace.workspaceDir;
    await _ops.commitAll(
      workDir: dir,
      message: composeCommitMessage(
        subject: const ConventionalSubject(
          type: 'chore',
          description: 'commit residual review changes',
        ),
        trailers: {composition.trailerToken: request.bead.id},
      ),
    );
    final clean = await _ops.hasUncommittedWork(dir);
    if (clean != GateOutcome.clear) {
      return const Failed('direct merge refused: tree is not verifiably clean');
    }
    final pushed = await _git.run(
      workingDirectory: dir,
      args: [
        'push',
        '--force-with-lease',
        '-u',
        'origin',
        request.workspace.branch,
      ],
    );
    if (!pushed.ok) {
      return Failed(
        'direct branch push refused — ${landReasonTail(pushed.output)}',
      );
    }
    final protection = await _merge.protection(
      dir,
      request.workspace.baseBranch,
    );
    return switch (protection) {
      GitHubProtected() => _refuse(request, 'base branch is protected'),
      GitHubProtectionProbeFailed(:final reason) => _refuse(request, reason),
      GitHubUnprotected() => await _pushToBase(request),
    };
  }

  Future<StepOutcome> _pushToBase(DeliveryRequest request) async {
    final result = await _git.run(
      workingDirectory: request.workspace.workspaceDir,
      args: [
        'push',
        'origin',
        '${request.workspace.branch}:${request.workspace.baseBranch}',
      ],
    );
    if (!result.ok) {
      return Failed(
        'direct base push refused — ${landReasonTail(result.output)}',
      );
    }
    return Ok({
      'direct_merge': 'landed',
      'branch': request.workspace.branch,
      'base': request.workspace.baseBranch,
    });
  }

  Failed _refuse(DeliveryRequest request, String reason) {
    // Reading the selected policy here pins the refusal to this composed value.
    final policy = _policy.runtimeType.toString();
    try {
      _transport?.flare('delivery.directMergeRefused', {
        'bead': request.bead.id,
        'branch': request.workspace.branch,
        'base': request.workspace.baseBranch,
        'policy': policy,
        'reason': reason,
      });
    } catch (_) {
      // Observability never changes the refusal.
    }
    return Failed('direct merge refused: $reason');
  }
}
