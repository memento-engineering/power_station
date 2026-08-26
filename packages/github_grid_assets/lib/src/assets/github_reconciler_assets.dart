import 'dart:async';
import 'dart:developer' as developer;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderTreeContext;

import '../code/github_app_pr_opener.dart';
import '../credentials.dart';
import '../github/github_reconciler.dart';
import '../github/github_reconciler_runtime.dart';
import '../github/reconciler_cursor.dart';
import '../github_app_client.dart';

/// Selects whether a GitHub reconciler is constructed for a composition.
enum GitHubReconcilerArm {
  /// Construct and provide a polling runtime.
  live,

  /// Keep the composition inert for dry-run operation.
  dry,

  /// Keep the composition inert while GitHub is unavailable.
  offline,
}

/// Value configuration for one repository's resident GitHub reconciler.
class GitHubReconcilerConfig {
  /// Creates repository polling configuration.
  const GitHubReconcilerConfig({
    required this.owner,
    required this.repository,
    required this.substation,
    required this.installationId,
    this.interval = const Duration(minutes: 1),
    this.minimumSpacing = const Duration(seconds: 5),
    this.arm = GitHubReconcilerArm.live,
  });

  /// GitHub repository owner.
  final String owner;

  /// GitHub repository name.
  final String repository;

  /// Substation identity attached to normalized events.
  final String substation;

  /// Installation quota identity used by the poll coordinator.
  final String installationId;

  /// Delay between polling attempts.
  final Duration interval;

  /// Minimum spacing between starts for this installation.
  final Duration minimumSpacing;

  /// Whether this composition may construct a runtime.
  final GitHubReconcilerArm arm;
}

/// Constructs a runtime from composition values and injected implementations.
typedef GitHubReconcilerRuntimeFactory =
    GitHubReconcilerRuntime Function({
      required GitHubReconcilerConfig config,
      required GitHubAppClient client,
      required GitHubCursorStore cursors,
      required GitHubEventSink emit,
      required ExplorationTransport? transport,
    });

/// Creates the production polling runtime for [config].
GitHubReconcilerRuntime createGitHubReconcilerRuntime({
  required GitHubReconcilerConfig config,
  required GitHubAppClient client,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
  required ExplorationTransport? transport,
}) {
  void report(
    String flareName,
    String action,
    Object error,
    StackTrace stackTrace,
  ) {
    final message =
        'GitHub reconciler $action for seat=${config.substation} '
        'repository=${config.owner}/${config.repository}: $error';
    final data = <String, String>{
      'seat': config.substation,
      'repository': '${config.owner}/${config.repository}',
      'error': '$error',
      'stack_trace': '$stackTrace',
    };
    if (transport != null) {
      try {
        transport.flare(flareName, data);
        return;
      } on Object catch (flareError, flareStackTrace) {
        developer.log(
          '$message; flare $flareName failed: $flareError',
          name: 'github_grid_assets.reconciler',
          error: flareError,
          stackTrace: flareStackTrace,
        );
      }
    }
    developer.log(
      message,
      name: 'github_grid_assets.reconciler',
      error: error,
      stackTrace: stackTrace,
    );
  }

  final reconciler = GitHubReconciler(
    owner: config.owner,
    repository: config.repository,
    substation: config.substation,
    client: client,
    cursors: cursors,
    emit: emit,
    onIntakeRowError: (error, stackTrace) => report(
      'reconciler.intakeRowSkipped',
      'skipped malformed intake row',
      error,
      stackTrace,
    ),
  );
  return GitHubReconcilerRuntime(
    installationId: config.installationId,
    reconciler: reconciler,
    coordinator: GitHubPollCoordinator(minimumSpacing: config.minimumSpacing),
    interval: config.interval,
    onError: (error, stackTrace) =>
        report('reconciler.cycleFailed', 'cycle failed', error, stackTrace),
  );
}

/// Owns and provides a live reconciler runtime when the composition is armed.
class GitHubReconcilerAssets extends SingleChildStatefulSeed {
  /// Creates an optionally armed reconciler provider.
  const GitHubReconcilerAssets({
    this.config,
    this.runtimeFactory = createGitHubReconcilerRuntime,
    super.child,
    super.key,
  });

  /// Repository polling values, or null for an inert composition.
  final GitHubReconcilerConfig? config;

  /// Injectable runtime construction seam.
  final GitHubReconcilerRuntimeFactory runtimeFactory;

  @override
  SingleChildState<GitHubReconcilerAssets> createState() =>
      _GitHubReconcilerAssetsState();
}

final class _GitHubReconcilerAssetsState
    extends SingleChildState<GitHubReconcilerAssets> {
  GitHubReconcilerRuntime? _runtime;
  GitHubReconcilerConfig? _builtConfig;
  GitHubAppClient? _builtClient;
  GitHubCursorStore? _builtCursors;
  GitHubEventSink? _builtEmit;
  ExplorationTransport? _builtTransport;

  GitHubReconcilerAssets get _assets => seed;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final services = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    final client = context.watch<GitHubAppClient>();
    final cursors = context.watch<GitHubCursorStore>();
    final emit = context.watch<GitHubEventSink>();
    final config = _assets.config;
    final transport = services?.transport;
    final enabled =
        config?.arm == GitHubReconcilerArm.live &&
        client != null &&
        cursors != null &&
        emit != null;
    if (!enabled) {
      _replaceRuntime(null, null, null, null, null, null);
      return child;
    }
    if (config != _builtConfig ||
        !identical(client, _builtClient) ||
        !identical(cursors, _builtCursors) ||
        !identical(emit, _builtEmit) ||
        !identical(transport, _builtTransport)) {
      final replacement = _assets.runtimeFactory(
        config: config!,
        client: client,
        cursors: cursors,
        emit: emit,
        transport: transport,
      );
      _replaceRuntime(replacement, config, client, cursors, emit, transport);
    }
    return InheritedSeed<GitHubReconcilerRuntime>(
      value: _runtime!,
      child: child,
    );
  }

  void _replaceRuntime(
    GitHubReconcilerRuntime? replacement,
    GitHubReconcilerConfig? config,
    GitHubAppClient? client,
    GitHubCursorStore? cursors,
    GitHubEventSink? emit,
    ExplorationTransport? transport,
  ) {
    final previous = _runtime;
    if (identical(previous, replacement)) return;
    _runtime = replacement;
    _builtConfig = config;
    _builtClient = client;
    _builtCursors = cursors;
    _builtEmit = emit;
    _builtTransport = transport;
    if (previous != null) unawaited(previous.stop());
  }

  @override
  void dispose() {
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) unawaited(runtime.stop());
    super.dispose();
  }
}

/// Provides App-authenticated pull-request opening when configured.
class GitHubPrOpenerAssets extends SingleChildStatelessSeed {
  /// Creates an optional GitHub App opener provider.
  const GitHubPrOpenerAssets({
    this.config,
    this.owner,
    this.repository,
    super.child,
    super.key,
  });

  /// App identity value that enables this provider when present.
  final GitHubAppConfig? config;

  /// Optional configured repository owner.
  final String? owner;

  /// Optional configured repository name.
  final String? repository;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final client = context.watch<GitHubAppClient>();
    if (config == null || client == null) return child;
    return InheritedSeed<PrOpener>(
      value: GitHubAppPrOpener(
        client: client,
        owner: owner,
        repository: repository,
      ),
      child: child,
    );
  }
}
