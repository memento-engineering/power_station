import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../github/file_cursor_store.dart';
import '../github/github_reconciler.dart';
import '../github/reconciler_cursor.dart';
import '../intake/github_intake_projection.dart';
import '../intake/github_intake_store.dart';
import '../intake/github_self_trust.dart';
import 'github_app_client_assets.dart';
import 'github_reconciler_assets.dart';

/// Provides the durable cursor and SELF-only intake sink for one seat.
///
/// Mount this below [GitHubAppClientAssets] and above
/// [GitHubReconcilerAssets]. The reconciler below observes the App client,
/// [GitHubCursorStore], and [GitHubEventSink] through that tree position.
class GitHubReconcilerBindingAssets extends SingleChildStatelessSeed {
  /// Creates the per-seat binding over [config], [runner], and [trust].
  const GitHubReconcilerBindingAssets({
    required this.config,
    required this.runner,
    required this.trust,
    super.child,
    super.key,
  });

  /// The same repository polling value passed to GitHubReconcilerAssets.
  final GitHubReconcilerConfig config;

  /// The seat's existing work-store runner.
  final BdRunner runner;

  /// The existing v1 SELF-only GitHub actor resolver.
  final GitHubSelfTrust trust;

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

    return InheritedSeed<GitHubCursorStore>(
      value: cursors,
      child: InheritedSeed<GitHubEventSink>(value: sink, child: child),
    );
  }
}
