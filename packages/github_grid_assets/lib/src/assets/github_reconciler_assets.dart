import 'dart:developer' as developer;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show ObligationQuery, ProviderTreeContext, TrajectoryConfig;

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

/// The flare name carried by an open pull the feedback leg could not observe.
///
/// The per-pull DEGRADATION made visible. One pull whose detail or check-runs
/// request failed is skipped for this cycle so the other open pulls are still
/// observed — and skipping in SILENCE would reintroduce, one pull at a time,
/// the same "nobody noticed" this leg exists to remove. The reported error
/// names the pull and a bounded failure, never a GitHub response body.
const String kPullFeedbackSkippedFlare = 'reconciler.pullFeedbackSkipped';

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
      required GitHubPollCoordinator coordinator,
    });

/// Constructs the station's shared poll coordinator.
///
/// Must return a FRESH instance on every call: [GitHubPollCoordinatorAssets]
/// hands the result to `Provider(create:)`, which assigns ownership to the
/// tree, and a pre-built instance passed through that seam would claim an
/// ownership the caller actually keeps. The seam exists so a test can supply a
/// controllable clock and delay.
typedef GitHubPollCoordinatorFactory = GitHubPollCoordinator Function();

/// Owns the STATION's one GitHub poll coordinator and provides it to every
/// repository beneath it.
///
/// A GitHub App installation has ONE request allowance, and the repositories
/// polled under it spend it between them. [GitHubPollCoordinator] has always
/// been written for that — its maps are keyed by an opaque quota identity — but
/// a coordinator constructed per runtime holds a map with exactly one live key,
/// so neither the serialization nor the start-spacing it implements could ever
/// apply across the repositories that actually share the budget. This asset is
/// where the single instance lives: mount it ONCE, above the station's
/// repository fan-out, and the installation id partitions the budget inside it.
///
/// Deliberately NOT part of `SubstationSeed`: that seed is per repository, and
/// mounting a coordinator there would reproduce the defect exactly.
///
/// The TREE owns the value — `Provider(create:)`, created once per station
/// mount and gone with it — so there is no process-global budget surviving the
/// station that spent it. It adds no scheduler: the coordinator spaces STARTS,
/// a transport rate, and when reconciliation happens stays the station tick's
/// through [GitHubReconciliationQuery].
class GitHubPollCoordinatorAssets extends SingleChildStatelessSeed {
  /// Creates the station's coordinator rung.
  const GitHubPollCoordinatorAssets({
    this.coordinatorFactory = GitHubPollCoordinator.new,
    super.child,
    super.key,
  });

  /// Injectable construction seam for the tree-owned coordinator.
  final GitHubPollCoordinatorFactory coordinatorFactory;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      Provider<GitHubPollCoordinator>(
        create: (_) => coordinatorFactory(),
        child: child,
      );
}

/// Reports one reconciler failure for [config] on [transport].
///
/// The seat's ONE reporting path: the injected transport first, and
/// `developer.log` when there is none — or when the flare itself throws, which
/// is reported and then falls through to the log rather than escaping into the
/// caller. Every reconciler-owned failure goes through here — a malformed
/// intake row, a skipped pull's feedback, a failed cycle, and the CI-feedback
/// leg's ignored shapes — so one seat speaks with one voice and there is no
/// second path to keep in step.
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

/// Creates the production polling runtime for [config] on the station's
/// shared [coordinator].
///
/// [coordinator] is REQUIRED and never constructed here: one instance is owned
/// by [GitHubPollCoordinatorAssets] at station scope, and this factory's job is
/// to put this repository's installation id and configured rate onto it.
GitHubReconcilerRuntime createGitHubReconcilerRuntime({
  required GitHubReconcilerConfig config,
  required GitHubAppClient client,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
  required ExplorationTransport? transport,
  required GitHubReadClient? foreignClient,
  required GitHubPollCoordinator coordinator,
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
    onPullFeedbackError: (pullNumber, failure, stackTrace) => report(
      kPullFeedbackSkippedFlare,
      'skipped pull feedback',
      'pull #$pullNumber: $failure',
      stackTrace,
    ),
  );
  return GitHubReconcilerRuntime(
    installationId: config.installationId,
    reconciler: reconciler,
    coordinator: coordinator,
    minimumSpacing: config.minimumSpacing,
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
  GitHubReconciliationQuery? _builtQuery;
  GitHubReconcilerConfig? _builtConfig;
  GitHubAppClient? _builtClient;
  GitHubCursorStore? _builtCursors;
  GitHubEventSink? _builtEmit;
  ExplorationTransport? _builtTransport;
  GitHubPollCoordinator? _builtCoordinator;
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
    // The STATION's shared installation budget, subscribed to unconditionally
    // (ADR-0008 D3) so a replaced coordinator rebuilds this seat onto it rather
    // than leaving it spending a budget nobody owns any more.
    final coordinator = context.watch<GitHubPollCoordinator>();
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
      _replaceRuntime(null, null, null, null, null, null, null, null);
      return child;
    }
    // THE STATION OWNS THE SCHEDULE: this seat contributes reconciliation
    // work to the ratified service tick and adds no wake mechanism of its
    // own. Resolved with the SUBSCRIBING build verb (ADR-0008 D3) so a
    // re-provisioned station config moves this seat onto the new query.
    final query = _registeredQuery(context, config!);
    // LOUD OR GONE, and gone FIRST: the seat stops riding the tick before the
    // refusal is raised, so a station missing the rung has no runtime left
    // spending a budget on nobody's schedule.
    if (coordinator == null) {
      _replaceRuntime(null, null, null, null, null, null, null, null);
      throw StateError(
        'Seat ${config.substation} arms a live GitHub reconciler for '
        'installation ${config.installationId}, whose request allowance is '
        'shared by every repository on it: the station must mount exactly one '
        'GitHubPollCoordinatorAssets above its repositories, and this tree '
        'offers none. A coordinator per repository would serialize nothing '
        'and spend the installation budget once per seat.',
      );
    }
    if (config != _builtConfig ||
        !identical(client, _builtClient) ||
        !identical(cursors, _builtCursors) ||
        !identical(emit, _builtEmit) ||
        !identical(transport, _builtTransport) ||
        !identical(coordinator, _builtCoordinator)) {
      final replacement = _assets.runtimeFactory(
        config: config,
        client: client,
        cursors: cursors,
        emit: emit,
        transport: transport,
        foreignClient: _foreignClient(config),
        coordinator: coordinator,
      );
      _replaceRuntime(
        replacement,
        query,
        config,
        client,
        cursors,
        emit,
        transport,
        coordinator,
      );
    } else if (!identical(query, _builtQuery)) {
      _moveToQuery(query);
    }
    return InheritedSeed<GitHubReconcilerRuntime>(
      value: _runtime!,
      child: child,
    );
  }

  /// THE ONE query this seat attaches to: the single
  /// [GitHubReconciliationQuery] the station registered in
  /// [TrajectoryConfig.obligationQueryExtensions], which is the only
  /// registration point the harness merges into the tick.
  ///
  /// LOUD OR GONE. A live seat with NO registered query would reconcile on
  /// nobody's schedule — the exact silence this design exists to retire —
  /// and a seat matching TWO would reconcile twice per pass under one
  /// installation budget. Both are refusals naming the registration point
  /// and the count observed, never a quiet fallback to a local loop.
  GitHubReconciliationQuery _registeredQuery(
    TreeContext context,
    GitHubReconcilerConfig config,
  ) {
    final trajectory = context
        .dependOnInheritedSeedOfExactType<TrajectoryConfig>();
    final registered =
        (trajectory?.obligationQueryExtensions ?? const <ObligationQuery>[])
            .whereType<GitHubReconciliationQuery>()
            .toList(growable: false);
    if (registered.length != 1) {
      throw StateError(
        'Seat ${config.substation} arms a live GitHub reconciler, which runs '
        'on the station tick: the station must register EXACTLY ONE '
        'GitHubReconciliationQuery in '
        'TrajectoryConfig.obligationQueryExtensions, and this tree offers '
        '${registered.length}.',
      );
    }
    return registered.first;
  }

  /// The token-less read client for [config]'s FOREIGN watches, or null when it
  /// has none.
  ///
  /// Constructed here and nowhere else, so the feature-off posture costs no
  /// transport, no coordinator and no environment read. The foreign lane gets
  /// its OWN [GitHubPollCoordinator] under [kForeignIssueWatchRateKey]: sharing
  /// the installation's coordinator would let a 5000-per-hour lane spend a
  /// 60-per-hour allowance. That stays true now the installation coordinator is
  /// STATION-owned — this one is per seat, holds its own credential posture and
  /// its own spacing state, and neither crosses into installation budgeting.
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
    GitHubReconciliationQuery? query,
    GitHubReconcilerConfig? config,
    GitHubAppClient? client,
    GitHubCursorStore? cursors,
    GitHubEventSink? emit,
    ExplorationTransport? transport,
    GitHubPollCoordinator? coordinator,
  ) {
    final previous = _runtime;
    if (identical(previous, replacement)) return;
    // SYNCHRONOUS detach, before the replacement is attached: a superseded
    // runtime must not reconcile on one more pass.
    if (previous != null) _builtQuery?.detach(previous);
    _runtime = replacement;
    _builtQuery = query;
    _builtConfig = config;
    _builtClient = client;
    _builtCursors = cursors;
    _builtEmit = emit;
    _builtTransport = transport;
    _builtCoordinator = coordinator;
    if (replacement != null) query?.attach(replacement);
  }

  /// Moves the LIVE runtime between registered queries without rebuilding
  /// it: the station replaced its trajectory config, not this seat's
  /// construction inputs, so the seat keeps its cursor tail and its
  /// registered delivery legs.
  void _moveToQuery(GitHubReconciliationQuery query) {
    final runtime = _runtime;
    if (runtime == null) return;
    _builtQuery?.detach(runtime);
    _builtQuery = query;
    query.attach(runtime);
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
    final query = _builtQuery;
    _runtime = null;
    _builtQuery = null;
    // SYNCHRONOUS, like every other detach here: an unmounted seat must be
    // gone from the station's next pass, not from some later microtask.
    if (runtime != null) query?.detach(runtime);
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
