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
import '../intake/github_issue_watch_projection.dart';

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
    final issueWatch = context.watch<GitHubIssueWatchProjection>();
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
        value: ServiceBundle.derive(
          ambient!,
          sourceControl: checkout,
          delivery: delivery,
        ),
        derivedFrom: [
          ambient,
          checkout,
          ops,
          opener,
          selected,
          gitRunner,
          mergeRunner,
          resolvedComposition,
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
    return _ReconcilerObserverBinding(
      runtime: runtime,
      feedback: feedback,
      issueWatch: issueWatch,
      child: wired,
    );
  }
}

/// Routes one observation to the CI-feedback leg, or nowhere.
Future<void> projectCiFeedback(
  CiFeedbackProjection? projection,
  NormalizedGitHubEvent event,
) async {
  switch (event) {
    case CheckConcluded() when projection != null:
      await projection(event);
    case IssueOpened() ||
        PullRequestOpened() ||
        WorkflowRunConcluded() ||
        IssueCommented() ||
        WatchedIssueStateChanged() ||
        CheckConcluded():
      return;
  }
}

/// Routes one observation to the WATCH leg, or nowhere.
///
/// The null-safe exhaustive adapter beside [projectCiFeedback]: a seat with no
/// watch projection mounted is a no-op rather than a throw, and the sealed
/// union keeps a new variant a compile error in BOTH adapters.
Future<void> projectIssueWatch(
  GitHubIssueWatchProjection? projection,
  NormalizedGitHubEvent event,
) async {
  switch (event) {
    case (IssueCommented() || WatchedIssueStateChanged())
        when projection != null:
      await projection(event);
    case IssueOpened() ||
        PullRequestOpened() ||
        WorkflowRunConcluded() ||
        CheckConcluded() ||
        IssueCommented() ||
        WatchedIssueStateChanged():
      return;
  }
}

/// Owns the reconciler runtime's lifecycle and BOTH of its durable observers.
///
/// One owner, not two: the runtime is started and stopped exactly once, and
/// `ci-feedback` and `issue-watch` are registered and removed together. A
/// second binding seed would race this one over the same runtime — both would
/// call `start`, and one would `stop` a runtime the other still believes is
/// running.
final class _ReconcilerObserverBinding extends SingleChildStatefulSeed {
  const _ReconcilerObserverBinding({
    required this.runtime,
    required this.feedback,
    required this.issueWatch,
    required super.child,
  });

  final GitHubReconcilerRuntime? runtime;
  final CiFeedbackProjection? feedback;
  final GitHubIssueWatchProjection? issueWatch;

  @override
  SingleChildState<SingleChildStatefulSeed> createState() =>
      _ReconcilerObserverBindingState();
}

final class _ReconcilerObserverBindingState
    extends SingleChildState<SingleChildStatefulSeed> {
  GitHubReconcilerRuntime? _runtime;
  late final GitHubEventSink _feedbackSink;
  late final GitHubEventSink _issueWatchSink;

  _ReconcilerObserverBinding get _binding => seed as _ReconcilerObserverBinding;

  /// The two legs, in registration order, with their durable keys.
  Map<String, GitHubEventSink> get _legs => <String, GitHubEventSink>{
    kCiFeedbackDeliveryLeg: _feedbackSink,
    kGitHubIssueWatchDeliveryLeg: _issueWatchSink,
  };

  @override
  void initState() {
    super.initState();
    // The sinks close over `_binding`, not over a captured projection, so a
    // rebuilt projection is picked up without re-registering a leg — the
    // durable acknowledgement key must survive a derived replacement.
    _feedbackSink = (event) async {
      await projectCiFeedback(_binding.feedback, event);
    };
    _issueWatchSink = (event) async {
      await projectIssueWatch(_binding.issueWatch, event);
    };
    _runtime = _binding.runtime;
    _register(_runtime);
    _runtime?.start();
  }

  void _register(GitHubReconcilerRuntime? runtime) {
    if (runtime == null) return;
    _legs.forEach(runtime.reconciler.addObserver);
  }

  void _unregister(GitHubReconcilerRuntime? runtime) {
    if (runtime == null) return;
    for (final leg in _legs.keys) {
      runtime.reconciler.removeObserver(leg);
    }
  }

  Future<void> _replaceRuntime(
    GitHubReconcilerRuntime? previous,
    GitHubReconcilerRuntime? replacement,
  ) async {
    _unregister(previous);
    await previous?.stop();
    if (identical(_runtime, replacement)) {
      _register(replacement);
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
      _unregister(runtime);
      unawaited(runtime.stop());
    }
    super.dispose();
  }
}
