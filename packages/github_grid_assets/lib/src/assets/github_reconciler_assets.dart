import 'dart:async';
import 'dart:developer' as developer;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderTreeContext;

import '../code/github_app_pr_opener.dart';
import '../code/workflow_run_intake_rule.dart';
import '../credentials.dart';
import '../github/ci_feedback_projection.dart';
import '../github/github_reconciler.dart';
import '../github/github_reconciler_runtime.dart';
import '../github/issue_watch.dart';
import '../github/reconciler_cursor.dart';
import '../github_app_client.dart';
import '../github_read_client.dart';
import 'github_app_client_assets.dart';

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
    this.defaultBranch = 'main',
    this.workflowRuns = const <WorkflowRunIntakeRule>[],
    this.issueWatches = const <GitHubIssueWatch>[],
    this.foreignReadTokenVariable,
    this.foreignMinimumSpacing = kUnauthenticatedGitHubMinimumSpacing,
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

  /// The repository's default branch — what a rule declaring no branches
  /// resolves to.
  final String defaultBranch;

  /// The seat's declared workflow-run intake rules, in authoritative order.
  ///
  /// EMPTY — the default — is the feature-off value: the reconciler's
  /// workflow-run leg makes no request at all, and no workflow failure is
  /// ever filed. Declaration order decides which of two overlapping rules
  /// admits a run.
  final List<WorkflowRunIntakeRule> workflowRuns;

  /// The OUTBOUND issues this seat keeps watching after they were opened.
  ///
  /// EMPTY — the default — is the feature-off value: no watch request is made,
  /// no foreign transport is constructed, and the named token variable is never
  /// read. A watch naming this seat's own [owner]/[repository] rides the
  /// existing installation lane; every other one is FOREIGN and rides the
  /// token-less read lane, because a GitHub App cannot be installed on a third
  /// party's repository.
  final List<GitHubIssueWatch> issueWatches;

  /// The NAME of the environment variable holding an optional personal token
  /// for the foreign read lane; this library never holds the secret itself.
  ///
  /// Null — the default — is the token-less posture. A token is not authority:
  /// it buys nothing but rate limit, and it can never reach a private
  /// repository the way an installation can.
  final String? foreignReadTokenVariable;

  /// Minimum spacing between two FOREIGN reads.
  ///
  /// Defaults to [kUnauthenticatedGitHubMinimumSpacing]. Token-less reads are
  /// clamped UP to that floor even when a seat configures less: GitHub's
  /// unauthenticated allowance is 60 requests an hour, and 65 seconds keeps a
  /// four-request reserve inside it. With a nonblank token the configured value
  /// stands, because the allowance is then 5000 an hour.
  final Duration foreignMinimumSpacing;
}

/// Constructs a runtime from composition values and injected implementations.
typedef GitHubReconcilerRuntimeFactory =
    GitHubReconcilerRuntime Function({
      required GitHubReconcilerConfig config,
      required GitHubAppClient client,
      required GitHubCursorStore cursors,
      required GitHubEventSink emit,
      required ExplorationTransport? transport,
      required GitHubReadClient? foreignClient,
    });

/// Reports one reconciler failure for [config] on [transport].
///
/// The seat's ONE reporting path: the injected transport first, and
/// `developer.log` when there is none — or when the flare itself throws, which
/// is reported and then falls through to the log rather than escaping into the
/// caller. Every reconciler-owned failure goes through here — a malformed
/// intake row, a failed cycle, and the CI-feedback leg's ignored shapes — so
/// one seat speaks with one voice and there is no second path to keep in step.
void _reportGitHubReconciler({
  required GitHubReconcilerConfig config,
  required ExplorationTransport? transport,
  required String flareName,
  required String action,
  required Object error,
  required StackTrace stackTrace,
}) {
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

/// Creates the production polling runtime for [config].
GitHubReconcilerRuntime createGitHubReconcilerRuntime({
  required GitHubReconcilerConfig config,
  required GitHubAppClient client,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
  required ExplorationTransport? transport,
  required GitHubReadClient? foreignClient,
}) {
  void report(
    String flareName,
    String action,
    Object error,
    StackTrace stackTrace,
  ) => _reportGitHubReconciler(
    config: config,
    transport: transport,
    flareName: flareName,
    action: action,
    error: error,
    stackTrace: stackTrace,
  );

  final reconciler = GitHubReconciler(
    owner: config.owner,
    repository: config.repository,
    substation: config.substation,
    client: client,
    cursors: cursors,
    emit: emit,
    defaultBranch: config.defaultBranch,
    workflowRuns: config.workflowRuns,
    issueWatches: config.issueWatches,
    foreignClient: foreignClient,
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
///
/// It also binds the seat's flare rail onto the [CiFeedbackProjection] the
/// binding above provides, so the CI-feedback delivery leg reports on the SAME
/// transport a failed cycle does. This asset is where that transport is already
/// resolved, so binding here adds no second observer, no second provider and no
/// second reporting path.
class GitHubReconcilerAssets extends SingleChildStatefulSeed {
  /// Creates an optionally armed reconciler provider.
  const GitHubReconcilerAssets({
    this.config,
    this.runtimeFactory = createGitHubReconcilerRuntime,
    this.environment = platformEnvironment,
    this.foreignTransportFactory = createGitHubHttpTransport,
    super.child,
    super.key,
  });

  /// Repository polling values, or null for an inert composition.
  final GitHubReconcilerConfig? config;

  /// Injectable runtime construction seam.
  final GitHubReconcilerRuntimeFactory runtimeFactory;

  /// Injected environment reader for the FOREIGN lane's optional token.
  ///
  /// Consulted ONLY when at least one configured watch is foreign, so a seat
  /// with no watches — or with installed-only watches — reads no environment at
  /// all. This library never holds the secret; the config names the variable.
  final EnvironmentReader environment;

  /// Injected transport factory for the FOREIGN read client.
  ///
  /// SEPARATE from the App client's transport on purpose: the foreign lane must
  /// never be able to pick up an installation token, and sharing a client is the
  /// easiest way for that to happen by accident.
  final GitHubHttpTransportFactory foreignTransportFactory;

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
  CiFeedbackProjection? _reportingProjection;
  CiFeedbackReporter? _boundReporter;
  GitHubReconcilerConfig? _reporterConfig;
  ExplorationTransport? _reporterTransport;

  GitHubReconcilerAssets get _assets => seed;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final services = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    final client = context.watch<GitHubAppClient>();
    final cursors = context.watch<GitHubCursorStore>();
    final emit = context.watch<GitHubEventSink>();
    final feedback = context.watch<CiFeedbackProjection>();
    final config = _assets.config;
    final transport = services?.transport;
    // Bound INDEPENDENTLY of the runtime: the leg's visibility is not something
    // an absent App client should silently take away.
    _bindReporter(feedback, config, transport);
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
        foreignClient: _foreignClient(config),
      );
      _replaceRuntime(replacement, config, client, cursors, emit, transport);
    }
    return InheritedSeed<GitHubReconcilerRuntime>(
      value: _runtime!,
      child: child,
    );
  }

  /// The token-less read client for [config]'s FOREIGN watches, or null when it
  /// has none.
  ///
  /// Constructed here and nowhere else, so the feature-off posture costs no
  /// transport, no coordinator and no environment read. The foreign lane gets
  /// its OWN [GitHubPollCoordinator] under [kForeignIssueWatchRateKey]: sharing
  /// the installation's coordinator would let a 5000-per-hour lane spend a
  /// 60-per-hour allowance.
  GitHubReadClient? _foreignClient(GitHubReconcilerConfig config) {
    final foreign = config.issueWatches
        .where(
          (watch) => !watch.isInstalledRepository(
            owner: config.owner,
            repository: config.repository,
          ),
        )
        .toList(growable: false);
    if (foreign.isEmpty) return null;
    final variable = config.foreignReadTokenVariable;
    final token = variable == null ? null : _assets.environment()[variable];
    final authenticated = token != null && token.trim().isNotEmpty;
    final spacing =
        authenticated ||
            config.foreignMinimumSpacing >= kUnauthenticatedGitHubMinimumSpacing
        ? config.foreignMinimumSpacing
        : kUnauthenticatedGitHubMinimumSpacing;
    final coordinator = GitHubPollCoordinator(minimumSpacing: spacing);
    return GitHubReadClient(
      transport: _assets.foreignTransportFactory(),
      apiBaseUri: Uri.https('api.github.com', ''),
      personalToken: token,
      schedule: (request) =>
          coordinator.schedule(kForeignIssueWatchRateKey, request),
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

  /// Binds THIS asset's reporter onto [projection] whenever the projection, the
  /// config or the transport it closes over has changed.
  void _bindReporter(
    CiFeedbackProjection? projection,
    GitHubReconcilerConfig? config,
    ExplorationTransport? transport,
  ) {
    if (identical(projection, _reportingProjection) &&
        config == _reporterConfig &&
        identical(transport, _reporterTransport)) {
      return;
    }
    _unbindReporter();
    if (projection == null || config == null) return;
    void reporter(
      String flareName,
      String action,
      Object error,
      StackTrace stackTrace,
    ) => _reportGitHubReconciler(
      config: config,
      transport: transport,
      flareName: flareName,
      action: action,
      error: error,
      stackTrace: stackTrace,
    );

    projection.bindReporter(reporter);
    _reportingProjection = projection;
    _boundReporter = reporter;
    _reporterConfig = config;
    _reporterTransport = transport;
  }

  /// Unbinds only the reporter THIS asset bound; a binding some other owner has
  /// since installed on the same projection stands.
  void _unbindReporter() {
    final projection = _reportingProjection;
    final reporter = _boundReporter;
    if (projection != null && reporter != null) {
      projection.unbindReporter(reporter);
    }
    _reportingProjection = null;
    _boundReporter = null;
    _reporterConfig = null;
    _reporterTransport = null;
  }

  @override
  void dispose() {
    _unbindReporter();
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
