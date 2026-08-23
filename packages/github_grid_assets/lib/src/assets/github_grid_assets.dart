library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderTreeContext;

import '../code/github_auto_merge_delivery.dart';
import '../code/github_delivery_policy.dart';
import '../code/github_direct_merge_delivery.dart';
import '../code/github_merge_runner.dart';
import '../code/github_pr_delivery.dart';
import '../github/ci_feedback_projection.dart';
import '../github/github_reconciler.dart';
import '../github/github_reconciler_runtime.dart';
import '../github/reconciler_event.dart';

/// Binds GitHub delivery and resident CI feedback for a substation.
///
/// Delivery is bound only when checkout, [GitOps], and [PrOpener] are all
/// observed. Implementations are supplied through providers; [PrComposition]
/// is the sole public configuration value.
class GitHubGridAssets extends SingleChildStatelessSeed {
  /// Creates the GitHub asset over optional composition values and injected
  /// command seams.
  const GitHubGridAssets({
    this.composition,
    this.policy,
    this.gitRunner,
    this.mergeRunner,
    super.child,
    super.key,
  });

  /// The substation's PR title/body composition knob.
  final PrComposition? composition;

  /// The explicitly selected delivery posture; null preserves PR-without-merge.
  final GitHubDeliveryPolicy? policy;

  /// Optional git command implementation used by the selected delivery method.
  final GitRunner? gitRunner;

  /// Optional GitHub merge command implementation.
  final GitHubMergeRunner? mergeRunner;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final ambient = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    final ops = context.watch<GitOps>();
    final opener = context.watch<PrOpener>();
    final runtime = context.watch<GitHubReconcilerRuntime>();
    final feedback = context.watch<CiFeedbackProjection>();
    final knob = composition;

    var wired = child;
    final checkout = ambient?.sourceControl;
    if (checkout != null && ops != null && opener != null) {
      final resolvedComposition = knob ?? const PrComposition();
      final selected = policy ?? const PrNoMergePolicy();
      final pr = GitHubPrDelivery(
        gitOps: ops,
        prOpener: opener,
        gitRunner: gitRunner,
        composition: resolvedComposition,
      );
      final delivery = switch (selected) {
        PrNoMergePolicy() => pr,
        PrAutoMergePolicy() => GitHubAutoMergeDelivery(
          prDelivery: pr,
          runner: mergeRunner ?? const SystemGitHubMergeRunner(),
          policy: selected,
          transport: ambient?.transport,
        ),
        DirectMergePolicy() => GitHubDirectMergeDelivery(
          gitOps: ops,
          gitRunner: gitRunner ?? SystemGitRunner(),
          mergeRunner: mergeRunner ?? const SystemGitHubMergeRunner(),
          policy: selected,
          transport: ambient?.transport,
          composition: resolvedComposition,
        ),
      };
      wired = DerivedServiceBundleSeed(
        value: ServiceBundle(
          sourceControl: checkout,
          delivery: delivery,
          escalation: ambient?.escalation,
          trust: ambient?.trust,
          trustFloor:
              ambient?.trustFloor ?? const TrustFloor(TrustLevel.trusted),
          transport: ambient?.transport,
          mountEligibility: ambient?.mountEligibility,
        ),
        derivedFrom: [
          checkout,
          ops,
          opener,
          selected,
          gitRunner,
          mergeRunner,
          resolvedComposition,
          ambient?.escalation,
          ambient?.trust,
          ambient?.trustFloor,
          ambient?.transport,
          ambient?.mountEligibility,
        ],
        child: child,
      );
    }
    // The composition knob mounts INDEPENDENTLY of the delivery binding (it is a
    // VALUE, not a service): a pass-through build still carries the substation's
    // PR shaping — and the build agent's commit policy — for whatever source
    // control is ambient.
    if (knob != null) {
      wired = InheritedSeed<PrComposition>(value: knob, child: wired);
    }
    final selectedPolicy = policy;
    if (selectedPolicy != null) {
      wired = InheritedSeed<GitHubDeliveryPolicy>(
        value: selectedPolicy,
        child: wired,
      );
    }
    return _FeedbackBinding(
      runtime: runtime,
      projection: feedback,
      child: wired,
    );
  }
}

Future<void> projectCiFeedback(
  CiFeedbackProjection? projection,
  NormalizedGitHubEvent event,
) async {
  switch (event) {
    case CheckConcluded() when projection != null:
      await projection(event);
    case IssueOpened() || PullRequestOpened() || CheckConcluded():
      return;
  }
}

final class _FeedbackBinding extends SingleChildStatefulSeed {
  const _FeedbackBinding({
    required this.runtime,
    required this.projection,
    required super.child,
  });

  final GitHubReconcilerRuntime? runtime;
  final CiFeedbackProjection? projection;

  @override
  SingleChildState<SingleChildStatefulSeed> createState() =>
      _FeedbackBindingState();
}

final class _FeedbackBindingState
    extends SingleChildState<SingleChildStatefulSeed> {
  GitHubReconcilerRuntime? _runtime;
  late final GitHubEventSink _sink;

  _FeedbackBinding get _binding => seed as _FeedbackBinding;

  @override
  void initState() {
    super.initState();
    _sink = (event) async {
      await projectCiFeedback(_binding.projection, event);
    };
    _runtime = _binding.runtime;
    _runtime?.reconciler.addObserver(_sink);
    _runtime?.start();
  }

  Future<void> _replaceRuntime(
    GitHubReconcilerRuntime? previous,
    GitHubReconcilerRuntime? replacement,
  ) async {
    previous?.reconciler.removeObserver(_sink);
    await previous?.stop();
    if (identical(_runtime, replacement)) {
      replacement?.reconciler.addObserver(_sink);
      replacement?.start();
    }
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final replacement = _binding.runtime;
    if (!identical(_runtime, replacement)) {
      final previous = _runtime;
      _runtime = replacement;
      unawaited(_replaceRuntime(previous, replacement));
    }
    return child;
  }

  @override
  void dispose() {
    if (_runtime case final runtime?) {
      runtime.reconciler.removeObserver(_sink);
      unawaited(runtime.stop());
    }
    super.dispose();
  }
}
