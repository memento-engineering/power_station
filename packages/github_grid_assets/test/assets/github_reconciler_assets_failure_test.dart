// The reconciler's FAILURE VISIBILITY: a cycle that dies — and a CI-feedback
// check the leg declines to act on — must reach the seat's own
// `ExplorationTransport`, once per event, and stop reaching it the moment the
// asset that bound the rail is gone.
//
// Pure + offline: the GitHub transport is a Fake that refuses to be called, and
// the state store is a Fake in the PROXIED-SERVER posture. No process spawns.
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show RecordingExplorationTransport;
import 'package:grid_sdk/grid_sdk.dart' show ObligationQuery, Provider;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

final class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

/// A transport that must never be reached: the replay runs BEFORE the poll, so
/// a cycle failed by a delivery leg costs no GitHub request at all.
final class _UnreachedTransport implements GitHubHttpTransport {
  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async =>
      throw StateError('the poll must not run: ${request.uri}');
}

final class _Cursors implements GitHubCursorStore {
  _Cursors([this.cursor = const GitHubReconcilerCursor()]);

  GitHubReconcilerCursor cursor;

  @override
  Future<GitHubReconcilerCursor> load() async => cursor;

  @override
  Future<void> save(GitHubReconcilerCursor value) async => cursor = value;
}

/// A state store answering the type-scoped session list with [sessions] and
/// refusing `export`, exactly as a proxied-server store does.
final class _StateBd implements BdRunner {
  _StateBd(this.sessions);

  final String sessions;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async => switch (args.first) {
    'export' => const BdResult(
      exitCode: 1,
      stdout: '',
      stderr: 'Error: export is not supported in proxied-server mode',
    ),
    'list' => BdResult(exitCode: 0, stdout: sessions, stderr: ''),
    _ => const BdResult(exitCode: 0, stdout: '{}', stderr: ''),
  };
}

/// The seat's OWN work store: the rail the landing mark rides. [result] is
/// what it answers the `bd update` with.
final class _WorkBd implements BdRunner {
  _WorkBd({this.result = const BdResult(exitCode: 0, stdout: '', stderr: '')});

  final BdResult result;
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    return result;
  }
}

/// The substation this seat is mounted under.
const sdk.SubstationScope _scope = sdk.SubstationScope(
  name: 'power_station',
  root: '/work/power_station',
  prefix: 'pow',
);

final class _Sender implements FeedbackCommandSender {
  @override
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  }) async => throw StateError('no decision may be reached for a stale check');
}

/// An inert runtime: it constructs a real reconciler so observers can be
/// registered, and never polls — because nothing in this file ever asks the
/// station's query to run it.
final class _InertRuntime extends GitHubReconcilerRuntime {
  _InertRuntime({required GitHubAppClient client})
    : super(
        installationId: 'installation',
        reconciler: GitHubReconciler(
          owner: 'memento',
          repository: 'power_station',
          substation: 'power_station',
          client: client,
          cursors: _Cursors(),
          emit: (_) async {},
        ),
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );
}

GitHubReconcilerRuntime _inert({
  required GitHubReconcilerConfig config,
  required GitHubAppClient client,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
  required ExplorationTransport? transport,
  required GitHubReadClient? foreignClient,
}) => _InertRuntime(client: client);

final _client = GitHubAppClient(
  config: GitHubAppConfig(
    appId: 'app',
    installationId: 1,
    apiBaseUri: Uri.parse('https://api.github.test'),
  ),
  tokens: _Tokens(),
  transport: _UnreachedTransport(),
);

const _config = GitHubReconcilerConfig(
  owner: 'memento',
  repository: 'power_station',
  substation: 'power_station',
  installationId: 'installation',
  minimumSpacing: Duration.zero,
);

/// One RED open pull request stating its bead in the body's `Refs:` trailer.
final _check = NormalizedGitHubEvent.pullRequestFeedback(
  nodeId: 'PR_1',
  actor: 'nico',
  repository: 'memento/power_station',
  substation: 'power_station',
  observationId: 'poll:pull-feedback:PR_1:abc123:failing',
  number: 8,
  body: 'A human digest.\n\nRefs: pow-2xmo\n',
  headBranch: 'grid/pow-2xmo',
  headSha: 'abc123',
  checkState: PullRequestCheckState.failing,
  mergeability: PullRequestMergeability.mergeable,
  openedAt: DateTime.utc(2026, 9, 3, 15),
  updatedAt: DateTime.utc(2026, 9, 3, 16, 24),
  greenSince: null,
  observedAt: DateTime.utc(2026, 9, 3, 16, 30),
  stalled: false,
);

/// The same pull request, GREEN: the only state that decides a landing mark.
final _green = NormalizedGitHubEvent.pullRequestFeedback(
  nodeId: 'PR_1',
  actor: 'nico',
  repository: 'memento/power_station',
  substation: 'power_station',
  observationId: 'poll:pull-feedback:PR_1:abc123:green',
  number: 8,
  body: 'A human digest.\n\nRefs: pow-2xmo\n',
  headBranch: 'grid/pow-2xmo',
  headSha: 'abc123',
  checkState: PullRequestCheckState.green,
  mergeability: PullRequestMergeability.mergeable,
  openedAt: DateTime.utc(2026, 9, 3, 15),
  updatedAt: DateTime.utc(2026, 9, 3, 16, 24),
  greenSince: null,
  observedAt: DateTime.utc(2026, 9, 3, 16, 30),
  stalled: false,
);

/// A store holding NO session for the pull's bead — the ordinary shape of
/// feedback that arrived after its PR landed and its session closed.
CiFeedbackProjection _landedProjection() => CiFeedbackProjection(
  bd: _StateBd('{"schema_version":1,"data":[]}'),
  workBd: _WorkBd(),
  scope: _scope,
  commandSender: _Sender(),
  gridRoot: '/grid',
);

Seed _seatTree({
  required RecordingExplorationTransport flares,
  required CiFeedbackProjection projection,
}) => sdk.ProviderScope(
  // The station rung a live seat composes under: this file never runs the
  // query, so the seat mounts, binds its rail, and reconciles nothing.
  child: InheritedSeed<sdk.TrajectoryConfig>(
    value: sdk.TrajectoryConfig(
      obligationQueryExtensions: <ObligationQuery>[GitHubReconciliationQuery()],
    ),
    child: InheritedSeed<ServiceBundle>(
      value: ServiceBundle(transport: flares),
      child: Provider<GitHubAppClient>.value(
        _client,
        child: Provider<GitHubCursorStore>.value(
          _Cursors(),
          child: Provider<GitHubEventSink>.value(
            (_) async {},
            child: Provider<CiFeedbackProjection>.value(
              projection,
              child: const GitHubReconcilerAssets(
                config: _config,
                runtimeFactory: _inert,
                child: _Leaf(),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('a failed cycle flares locally AND refuses to the station', () async {
    final flares = RecordingExplorationTransport();
    final runtime = createGitHubReconcilerRuntime(
      config: _config,
      client: _client,
      cursors: _Cursors(const GitHubReconcilerCursor().enqueue(_check)),
      emit: (_) async {},
      transport: flares,
      foreignClient: null,
    );
    runtime.reconciler.addObserver(
      kCiFeedbackDeliveryLeg,
      (_) async => throw StateError('leg refused'),
    );

    // The station's pass is the caller now, so the failure has TWO audiences:
    // the seat's own rail, and the tick — which is the one that counts.
    final query = GitHubReconciliationQuery()..attach(runtime);
    await expectLater(
      query.repair(const <Map<String, String?>>[]),
      throwsA(isA<StateError>()),
    );

    expect(flares.flares, hasLength(1), reason: 'one cycle, one flare');
    final flare = flares.flares.single;
    expect(flare.name, 'reconciler.cycleFailed');
    expect(flare.data, containsPair('seat', 'power_station'));
    expect(flare.data, containsPair('repository', 'memento/power_station'));
    expect(flare.data['error'], contains('leg refused'));
    expect(flare.data['stack_trace'], isNotEmpty);
  });

  test(
    'the asset binds the seat rail to the provided CI-feedback leg',
    () async {
      final flares = RecordingExplorationTransport();
      final projection = _landedProjection();
      final owner = TreeOwner();
      owner.mountRoot(_seatTree(flares: flares, projection: projection));
      owner.flush();

      await projection(_check);

      expect(flares.named('reconciler.ciFeedbackIgnored'), hasLength(1));
      final flare = flares.named(kCiFeedbackIgnoredFlare).single;
      expect(flare.data, containsPair('seat', 'power_station'));
      expect(flare.data, containsPair('repository', 'memento/power_station'));
      expect(flare.data['error'], contains('pow-2xmo'));

      // The binding is OWNED: it goes away with the asset that made it.
      owner.unmountRoot();
      await projection(_check);
      expect(flares.flares, hasLength(1));
    },
  );

  test('the asset rail carries an unresolvable landing mark', () async {
    // The SAME binding, a different flare name: the seat's transport is the
    // one reporting path, so a new named degradation needs no second rail.
    final flares = RecordingExplorationTransport();
    final work = _WorkBd(
      result: const BdResult(
        exitCode: 1,
        stdout: '',
        stderr: 'get pow-2xmo: sql: no rows in result set',
      ),
    );
    final projection = CiFeedbackProjection(
      bd: _StateBd(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'data': <Object?>[
            <String, Object?>{
              'id': 'session-0',
              'issue_type': 'session',
              'metadata': <String, Object?>{'work_bead': 'pow-2xmo'},
            },
          ],
        }),
      ),
      workBd: work,
      scope: _scope,
      commandSender: _Sender(),
      gridRoot: '/grid',
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(_seatTree(flares: flares, projection: projection));
    owner.flush();

    await projection(_green);

    final flare = flares.named(kCiFeedbackLandingUnresolvedFlare).single;
    expect(flare.data, containsPair('seat', 'power_station'));
    expect(flare.data, containsPair('repository', 'memento/power_station'));
    expect(flare.data['error'], contains('pow-2xmo'));
    expect(flare.data['error'], contains('/work/power_station'));
    expect(flare.data['error'], contains('sql: no rows in result set'));
    expect(work.argvs.single.take(2), <String>['update', 'pow-2xmo']);
  });

  test('the ignore flare names the shape the store held', () async {
    final flares = RecordingExplorationTransport();
    final projection = CiFeedbackProjection(
      bd: _StateBd(
        jsonEncode({
          'schema_version': 1,
          'data': [
            for (var i = 0; i < 2; i++)
              {
                'id': 'session-$i',
                'issue_type': 'session',
                'metadata': {'work_bead': 'pow-2xmo'},
              },
          ],
        }),
      ),
      workBd: _WorkBd(),
      scope: _scope,
      commandSender: _Sender(),
      gridRoot: '/grid',
    );
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    owner.mountRoot(_seatTree(flares: flares, projection: projection));
    owner.flush();

    await projection(_check);

    expect(
      flares.named(kCiFeedbackIgnoredFlare).single.data['error'],
      contains('found 2'),
    );
  });
}
