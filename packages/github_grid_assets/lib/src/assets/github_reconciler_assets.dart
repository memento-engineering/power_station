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

/// Describes one repository's resident reconciler subtree — and owns no effect
/// of its own.
///
/// Everything with a LIFETIME belongs to [_GitHubReconcilerLifecycle]: the
/// polling runtime, its attachment to the station-registered
/// [GitHubReconciliationQuery], and the seat's flare rail on the ambient
/// [CiFeedbackProjection]. This seed only describes the subtree and projects
/// [_GitHubReconcilerInputs] — one immutable value carrying every input those
/// resources are built from. The [LifecycleProvider] below creates the
/// participant once per mount and hands it a dependency pass when, and only
/// when, that value actually CHANGES. A rebuild describing the same inputs is
/// therefore a no-op: no replacement runtime, no detach/attach churn, and no
/// reporter mutation that would stamp over a binding another owner installed.
///
/// The flare rail is bound INDEPENDENTLY of the runtime, so the CI-feedback
/// delivery leg reports on the SAME transport a failed cycle does and an absent
/// App client never silently takes that visibility away. This asset is where
/// the transport is already resolved, so binding here adds no second observer,
/// no second provider and no second reporting path.
///
/// The station's [GitHubPollCoordinator] is an INPUT here, never an owned
/// resource: it is mounted once by [GitHubPollCoordinatorAssets] above the
/// repository fan-out, subscribed to like every other ambient dependency so a
/// replacement reaches this seat, and refused by name when a live seat finds
/// none.
class GitHubReconcilerAssets extends SingleChildStatelessSeed {
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
  Seed buildWithChild(TreeContext context, Seed child) {
    // SUBSCRIBE to every ambient input (ADR-0008 D3: the build verb binds), so
    // a re-provisioned station config, a replaced App client, a replaced store
    // or a new feedback leg all reach this seat as a fresh projected value.
    final services = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    final trajectory = context
        .dependOnInheritedSeedOfExactType<TrajectoryConfig>();
    final inputs = _GitHubReconcilerInputs(
      config: _immutableConfig(config),
      client: context.watch<GitHubAppClient>(),
      cursors: context.watch<GitHubCursorStore>(),
      emit: context.watch<GitHubEventSink>(),
      feedback: context.watch<CiFeedbackProjection>(),
      transport: services?.transport,
      // The STATION's shared installation budget, subscribed to
      // unconditionally (ADR-0008 D3) so a replaced coordinator reaches this
      // seat as a changed value rather than leaving it spending a budget
      // nobody owns any more. Whether an ABSENT one is legal is the
      // lifecycle's refusal to make, not a silent arm-down here.
      coordinator: context.watch<GitHubPollCoordinator>(),
      // THE STATION OWNS THE SCHEDULE: this seat contributes reconciliation
      // work to the ratified service tick and adds no wake mechanism of its
      // own. The registered candidates are projected as a VALUE; which
      // cardinality is legal is the lifecycle's refusal to make.
      queries: List<GitHubReconciliationQuery>.unmodifiable(
        (trajectory?.obligationQueryExtensions ?? const <ObligationQuery>[])
            .whereType<GitHubReconciliationQuery>(),
      ),
      runtimeFactory: runtimeFactory,
      environment: environment,
      foreignTransportFactory: foreignTransportFactory,
    );
    return InheritedSeed<_GitHubReconcilerInputs>(
      value: inputs,
      child: LifecycleProvider<_GitHubReconcilerLifecycle>(
        create: _GitHubReconcilerLifecycle.new,
        child: _GitHubReconcilerRuntimeProjection(child: child),
      ),
    );
  }
}

/// [config] with its two declared lists copied into unmodifiable ones.
///
/// The projected value has to be IMMUTABLE for input equality to mean
/// anything: a caller that mutated the list it passed would otherwise change
/// what the lifecycle already applied, underneath a value that still compares
/// equal to it.
GitHubReconcilerConfig? _immutableConfig(GitHubReconcilerConfig? config) =>
    config == null
    ? null
    : GitHubReconcilerConfig(
        owner: config.owner,
        repository: config.repository,
        substation: config.substation,
        installationId: config.installationId,
        minimumSpacing: config.minimumSpacing,
        arm: config.arm,
        defaultBranch: config.defaultBranch,
        workflowRuns: List<WorkflowRunIntakeRule>.unmodifiable(
          config.workflowRuns,
        ),
        issueWatches: List<GitHubIssueWatch>.unmodifiable(config.issueWatches),
        foreignReadTokenVariable: config.foreignReadTokenVariable,
        foreignMinimumSpacing: config.foreignMinimumSpacing,
      );

/// Whether two configurations state the same seat, field by field.
bool _sameConfig(GitHubReconcilerConfig? a, GitHubReconcilerConfig? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.owner == b.owner &&
      a.repository == b.repository &&
      a.substation == b.substation &&
      a.installationId == b.installationId &&
      a.minimumSpacing == b.minimumSpacing &&
      a.arm == b.arm &&
      a.defaultBranch == b.defaultBranch &&
      a.foreignReadTokenVariable == b.foreignReadTokenVariable &&
      a.foreignMinimumSpacing == b.foreignMinimumSpacing &&
      _sameElements(a.workflowRuns, b.workflowRuns) &&
      _sameElements(a.issueWatches, b.issueWatches);
}

/// One hash over everything [_sameConfig] compares.
int _configHash(GitHubReconcilerConfig? config) => config == null
    ? 0
    : Object.hash(
        config.owner,
        config.repository,
        config.substation,
        config.installationId,
        config.minimumSpacing,
        config.arm,
        config.defaultBranch,
        config.foreignReadTokenVariable,
        config.foreignMinimumSpacing,
        Object.hashAll(config.workflowRuns),
        Object.hashAll(config.issueWatches),
      );

/// Ordered element-wise equality — the declared lists are ORDERED policy, so a
/// reordering is a different configuration.
bool _sameElements<T extends Object>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Ordered IDENTITY equality: a registered query is its attachment set, so two
/// equal-looking queries are two different schedules.
bool _sameQueries(
  List<GitHubReconciliationQuery> a,
  List<GitHubReconciliationQuery> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// The complete answer to "what would this seat's reconciler be built from?",
/// as one immutable tree VALUE.
///
/// Value equality IS the mechanism. The owning lifecycle is handed a dependency
/// pass only when this value changes, so a rebuild that describes the same seat
/// owns no effect at all. Configuration compares BY VALUE — every scalar, and
/// both declared lists element by element; the registered query candidates
/// compare by ordered IDENTITY; and implementations — client, cursor store,
/// event sink, transport, factories and the environment reader — compare by
/// identity, because two instances are two implementations even when they
/// behave alike. Function-valued inputs use `==`, which for a Dart tear-off is
/// that same identity (one method, one receiver) without punishing a caller who
/// spells the tear-off twice.
final class _GitHubReconcilerInputs {
  const _GitHubReconcilerInputs({
    required this.config,
    required this.client,
    required this.cursors,
    required this.emit,
    required this.feedback,
    required this.transport,
    required this.coordinator,
    required this.queries,
    required this.runtimeFactory,
    required this.environment,
    required this.foreignTransportFactory,
  });

  final GitHubReconcilerConfig? config;
  final GitHubAppClient? client;
  final GitHubCursorStore? cursors;
  final GitHubEventSink? emit;
  final CiFeedbackProjection? feedback;
  final ExplorationTransport? transport;
  final GitHubPollCoordinator? coordinator;
  final List<GitHubReconciliationQuery> queries;
  final GitHubReconcilerRuntimeFactory runtimeFactory;
  final EnvironmentReader environment;
  final GitHubHttpTransportFactory foreignTransportFactory;

  /// Whether this seat both ARMS a runtime and has every dependency one needs.
  bool get isLive =>
      config?.arm == GitHubReconcilerArm.live &&
      client != null &&
      cursors != null &&
      emit != null;

  /// Whether [other] would bind the same flare rail: one projection, one
  /// reported seat, one transport to report on.
  bool sameReporting(_GitHubReconcilerInputs other) =>
      identical(other.feedback, feedback) &&
      identical(other.transport, transport) &&
      _sameConfig(other.config, config);

  /// Whether [other] would construct the same runtime from the same inputs —
  /// which is what makes a live seat keep its cursor tail across a rebuild.
  bool sameRuntime(_GitHubReconcilerInputs other) =>
      _sameConfig(other.config, config) &&
      identical(other.client, client) &&
      identical(other.cursors, cursors) &&
      other.emit == emit &&
      identical(other.transport, transport) &&
      identical(other.coordinator, coordinator) &&
      other.runtimeFactory == runtimeFactory &&
      other.environment == environment &&
      other.foreignTransportFactory == foreignTransportFactory;

  /// THE ONE query this seat attaches to: the single
  /// [GitHubReconciliationQuery] the station registered in
  /// [TrajectoryConfig.obligationQueryExtensions], which is the only
  /// registration point the harness merges into the tick.
  ///
  /// LOUD OR GONE. A live seat with NO registered query would reconcile on
  /// nobody's schedule — the exact silence this design exists to retire — and a
  /// seat matching TWO would reconcile twice per pass under one installation
  /// budget. Both are refusals naming the registration point and the count
  /// observed, never a quiet fallback to a local loop.
  GitHubReconciliationQuery requireRegisteredQuery() {
    if (queries.length != 1) {
      throw StateError(
        'Seat ${config!.substation} arms a live GitHub reconciler, which runs '
        'on the station tick: the station must register EXACTLY ONE '
        'GitHubReconciliationQuery in '
        'TrajectoryConfig.obligationQueryExtensions, and this tree offers '
        '${queries.length}.',
      );
    }
    return queries.first;
  }

  /// THE STATION's one poll coordinator, which every repository on this
  /// installation spends its single request allowance through.
  ///
  /// LOUD OR GONE, and second in the refusal order on purpose: the seat has
  /// already stopped riding the tick by the time this is asked, so a station
  /// missing the rung is left with no runtime spending a budget on nobody's
  /// schedule. A coordinator built here per repository would serialize nothing
  /// and spend the installation budget once per seat — the exact defect
  /// [GitHubPollCoordinatorAssets] exists to close — so an absent one is a
  /// refusal naming that rung, never a locally constructed substitute.
  GitHubPollCoordinator requireStationCoordinator() {
    final coordinator = this.coordinator;
    if (coordinator == null) {
      throw StateError(
        'Seat ${config!.substation} arms a live GitHub reconciler for '
        'installation ${config!.installationId}, whose request allowance is '
        'shared by every repository on it: the station must mount exactly one '
        'GitHubPollCoordinatorAssets above its repositories, and this tree '
        'offers none. A coordinator per repository would serialize nothing '
        'and spend the installation budget once per seat.',
      );
    }
    return coordinator;
  }

  /// Builds the runtime these inputs describe on the station's [coordinator].
  /// Callable only for an [isLive] value whose coordinator has already been
  /// required, where every dependency is present by construction.
  GitHubReconcilerRuntime constructRuntime(GitHubPollCoordinator coordinator) =>
      runtimeFactory(
        config: config!,
        client: client!,
        cursors: cursors!,
        emit: emit!,
        transport: transport,
        foreignClient: _foreignClient(),
        coordinator: coordinator,
      );

  /// The token-less read client for the FOREIGN watches, or null when there are
  /// none.
  ///
  /// Constructed here and nowhere else, so the feature-off posture costs no
  /// transport, no coordinator and no environment read. The foreign lane gets
  /// its OWN [GitHubPollCoordinator] under [kForeignIssueWatchRateKey]: sharing
  /// the installation's coordinator would let a 5000-per-hour lane spend a
  /// 60-per-hour allowance. That stays true now the installation coordinator
  /// is STATION-owned — this one is per seat, holds its own credential
  /// posture and its own spacing state, and neither crosses into installation
  /// budgeting.
  GitHubReadClient? _foreignClient() {
    final config = this.config!;
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
    final token = variable == null ? null : environment()[variable];
    final authenticated = token != null && token.trim().isNotEmpty;
    final spacing =
        authenticated ||
            config.foreignMinimumSpacing >= kUnauthenticatedGitHubMinimumSpacing
        ? config.foreignMinimumSpacing
        : kUnauthenticatedGitHubMinimumSpacing;
    final coordinator = GitHubPollCoordinator(minimumSpacing: spacing);
    return GitHubReadClient(
      transport: foreignTransportFactory(),
      apiBaseUri: Uri.https('api.github.com', ''),
      personalToken: token,
      schedule: (request) =>
          coordinator.schedule(kForeignIssueWatchRateKey, request),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GitHubReconcilerInputs &&
      sameRuntime(other) &&
      identical(other.feedback, feedback) &&
      _sameQueries(other.queries, queries);

  @override
  int get hashCode => Object.hash(
    _configHash(config),
    identityHashCode(client),
    identityHashCode(cursors),
    emit,
    identityHashCode(feedback),
    identityHashCode(transport),
    identityHashCode(coordinator),
    Object.hashAll(queries.map(identityHashCode)),
    runtimeFactory,
    environment,
    foreignTransportFactory,
  );
}

/// OWNS the reconciler's effects for one mount: the runtime, the query
/// attachment that schedules it, and the seat's reporter on the CI-feedback
/// leg.
///
/// The participant holds NO tree capability. Every input arrives as the one
/// [_GitHubReconcilerInputs] value it watches inside each synchronous
/// dependency callback, and the call-scoped reader is used there and retained
/// nowhere. What it remembers instead is the LAST APPLIED value plus the
/// resources that value produced — one mirror rather than a field per input —
/// so "did anything that matters change?" is a value comparison and not a
/// hand-kept ledger.
///
/// Reconfiguration has ONE order, and it is the order that cannot leave a
/// superseded seat riding the tick: rebind the rail, release the current
/// attachment, refuse loudly if the station registration or its shared poll
/// coordinator is missing, then construct and attach the replacement. Nothing
/// is attached until it is fully constructed.
final class _GitHubReconcilerLifecycle implements TreeLifecycleParticipant {
  _GitHubReconcilerInputs? _applied;
  GitHubReconcilerRuntime? _runtime;
  GitHubReconciliationQuery? _query;
  CiFeedbackProjection? _reportingProjection;
  CiFeedbackReporter? _boundReporter;

  /// The runtime this lifecycle owns right now, or null for the UNAVAILABLE
  /// posture.
  ///
  /// Read in exactly one place: [_GitHubReconcilerRuntimeProjection]'s build,
  /// mounted directly below the provider that carries this participant, where
  /// the dependency pass that owns this value has already run.
  GitHubReconcilerRuntime? get runtime => _runtime;

  @override
  void initState(TreeSnapshotReader reader) {}

  @override
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) {
    // WATCH the dep: the value is mounted by the asset directly above this
    // provider, so the lookup can never miss and every replacement value lands
    // here as a fresh pass. The reader is used HERE and kept nowhere; this pass
    // is fully synchronous, so no [scope] survives it.
    _apply(reader.watch<_GitHubReconcilerInputs>()!);
  }

  /// Reconfigures every owned resource for [inputs].
  void _apply(_GitHubReconcilerInputs inputs) {
    final previous = _applied;
    _applied = inputs;
    _bindReporter(inputs, previous);
    // A runtime survives only when NOTHING it was constructed from moved: the
    // seat then keeps its cursor tail and its registered delivery legs.
    final reuse =
        inputs.isLive &&
        _runtime != null &&
        previous != null &&
        previous.sameRuntime(inputs);
    // RELEASE FIRST, synchronously and unconditionally: a superseded runtime
    // must not reconcile on one more pass, and the refusal below must not leave
    // one riding a registration this tree no longer states.
    _releaseAttachment();
    if (!reuse) _runtime = null;
    if (!inputs.isLive) return;
    final query = inputs.requireRegisteredQuery();
    // Both refusals throw PAST here having already given up the attachment and
    // — unless every construction input survived — the runtime itself.
    final coordinator = inputs.requireStationCoordinator();
    // Construction throws PAST here with its own stack — and owns nothing yet,
    // because the old runtime is already released and cleared.
    final runtime = _runtime ?? inputs.constructRuntime(coordinator);
    _runtime = runtime;
    _query = query;
    query.attach(runtime);
  }

  /// Detaches the owned runtime from the query it rides, if any. Idempotent.
  void _releaseAttachment() {
    final runtime = _runtime;
    final query = _query;
    _query = null;
    if (runtime != null) query?.detach(runtime);
  }

  /// Binds THIS lifecycle's reporter onto the projection whenever the
  /// projection, the seat config or the transport it closes over has changed.
  void _bindReporter(
    _GitHubReconcilerInputs inputs,
    _GitHubReconcilerInputs? previous,
  ) {
    // The rail in hand still answers — including when it is deliberately no
    // rail at all. Rebinding here would stamp over a binding another owner
    // installed since, for no change.
    if (previous != null && previous.sameReporting(inputs)) return;
    _unbindReporter();
    final projection = inputs.feedback;
    final config = inputs.config;
    if (projection == null || config == null) return;
    final transport = inputs.transport;
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
  }

  /// Unbinds only the reporter THIS lifecycle bound; a binding some other owner
  /// has since installed on the same projection stands.
  ///
  /// Cleared BEFORE the call, so a repeated cleanup is inert.
  void _unbindReporter() {
    final projection = _reportingProjection;
    final reporter = _boundReporter;
    _reportingProjection = null;
    _boundReporter = null;
    if (projection != null && reporter != null) {
      projection.unbindReporter(reporter);
    }
  }

  @override
  void dispose() {
    final runtime = _runtime;
    final query = _query;
    // Owned references are cleared BEFORE anything is released, so a repeated
    // teardown — the failed-mount unwind runs this path too — finds nothing
    // left to release.
    _applied = null;
    _runtime = null;
    _query = null;
    // SYNCHRONOUS, like every other detach here: an unmounted seat must be gone
    // from the station's next pass, not from some later microtask.
    if (runtime != null) query?.detach(runtime);
    _unbindReporter();
  }
}

/// Projects the lifecycle-owned runtime — and NOTHING while there is none.
///
/// Presence in the tree IS availability: an unavailable seat mounts no
/// `Provider<GitHubReconcilerRuntime>` at all, so a descendant's `watch`
/// answers null and, because a provider announces its own arrival and
/// departure, learns the moment that changes. The value is ADOPTED, never
/// owned: neither the factory result nor the foreign read client nor the
/// injected foreign transport publishes a transfer-of-ownership disposal
/// contract, and disposing them here would be this asset inventing one. The
/// station's [GitHubPollCoordinator] is emphatically not this seat's to
/// dispose — it is owned by [GitHubPollCoordinatorAssets] at station scope and
/// outlives every repository that spends through it.
final class _GitHubReconcilerRuntimeProjection
    extends SingleChildStatelessSeed {
  const _GitHubReconcilerRuntimeProjection({super.child});

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final lifecycle = context.watch<_GitHubReconcilerLifecycle>();
    if (lifecycle == null) {
      throw StateError(
        'GitHubReconcilerAssets built its runtime projection outside the '
        'LifecycleProvider that owns the reconciler. The provider is mounted '
        'by this asset directly above this seed, so a miss is a composition '
        'this library cannot produce.',
      );
    }
    final runtime = lifecycle.runtime;
    if (runtime == null) return child;
    return Provider<GitHubReconcilerRuntime>.value(runtime, child: child);
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
