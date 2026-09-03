import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../github/ci_feedback_projection.dart';
import '../github/file_cursor_store.dart';
import '../github/github_reconciler.dart';
import '../github/reconciler_cursor.dart';
import '../github/resident_feedback_command.dart';
import '../intake/github_intake_projection.dart';
import '../intake/github_intake_store.dart';
import '../intake/github_self_trust.dart';
import 'github_app_client_assets.dart';
import 'github_reconciler_assets.dart';

/// Builds the `bd` runner for the grid STATE store rooted at [stateRoot].
///
/// [stateRoot] is `<gridRoot>/.grid` — the workspace whose `.beads/` holds the
/// session beads a completed check is correlated against. Injectable so an
/// offline suite substitutes a fake instead of spawning a real `bd` process at
/// a root that may not exist.
typedef GitHubFeedbackStateRunnerFactory = BdRunner Function(String stateRoot);

BdRunner _processStateRunner(String stateRoot) =>
    ProcessBdRunner(workspaceRoot: stateRoot);

/// Provides the durable cursor, the SELF-only intake sink, and the CI feedback
/// projection for one seat.
///
/// Mount this below [GitHubAppClientAssets] and above
/// [GitHubReconcilerAssets]. The reconciler below observes the App client,
/// [GitHubCursorStore], and [GitHubEventSink] through that tree position;
/// `GitHubGridAssets`, mounted below the reconciler, observes the
/// [CiFeedbackProjection] provided here and registers it with the reconciler
/// under the reserved `ci-feedback` delivery leg. This seed provides the
/// VALUE only: it registers no observer and dispatches no event.
///
/// The projection is DERIVED from watched tree values on every build of this
/// seed, exactly like [GitHubCursorStore] and [GitHubEventSink] beside it. A
/// derived replacement empties the projection's in-memory handled-key set,
/// which is why per-leg durable acknowledgement — not that set — is the
/// idempotency rail for a re-delivery.
class GitHubReconcilerBindingAssets extends SingleChildStatelessSeed {
  /// Creates the per-seat binding over [config], [runner], and [trust].
  const GitHubReconcilerBindingAssets({
    required this.config,
    required this.runner,
    required this.trust,
    this.feedbackCommandSender,
    this.stateRunnerFor = _processStateRunner,
    super.child,
    super.key,
  });

  /// The same repository polling value passed to GitHubReconcilerAssets.
  final GitHubReconcilerConfig config;

  /// The seat's existing work-store runner.
  final BdRunner runner;

  /// The existing v1 SELF-only GitHub actor resolver.
  final GitHubSelfTrust trust;

  /// Injectable CI-feedback command transport.
  ///
  /// Null keeps the production [ResidentFeedbackCommandSender], which reaches
  /// the already-running station over the station lock's control endpoint.
  final FeedbackCommandSender? feedbackCommandSender;

  /// Injectable `bd` runner factory for the GRID STATE store.
  ///
  /// NOT [runner]: [runner] is this seat's WORK store, while the session beads
  /// a check is correlated against live in the grid's own state store.
  final GitHubFeedbackStateRunnerFactory stateRunnerFor;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    if (config.arm != GitHubReconcilerArm.live) return child;

    final scope = sdk.SubstationScope.of(context);
    final cursors = FileGitHubCursorStore(
      cursorPath: p.join(
        scope.root,
        '.grid',
        'github',
        '${config.owner}-${config.repository}.cursor.json',
      ),
    );
    final projection = GitHubIntakeProjection(
      trust: trust,
      store: BdGitHubIntakeStore(runner),
    );
    final GitHubEventSink sink = projection.call;

    // QUIET and SUBSCRIBING: no enclosing grid root is the offline/unit
    // posture, and `projectCiFeedback` already encodes a null projection as a
    // no-op, so intake is untouched when the feedback half is unbound.
    final gridRoot = sdk.GridRoot.maybeOf(context)?.path;
    Seed wired = InheritedSeed<GitHubEventSink>(value: sink, child: child);
    if (gridRoot != null) {
      wired = InheritedSeed<CiFeedbackProjection>(
        value: CiFeedbackProjection(
          bd: stateRunnerFor(
            sdk.GridStateStore.forGridRoot(gridRoot).runtimeDir,
          ),
          commandSender:
              feedbackCommandSender ?? ResidentFeedbackCommandSender(),
          gridRoot: gridRoot,
          substation: config.substation,
        ),
        child: wired,
      );
    }
    return InheritedSeed<GitHubCursorStore>(value: cursors, child: wired);
  }
}
