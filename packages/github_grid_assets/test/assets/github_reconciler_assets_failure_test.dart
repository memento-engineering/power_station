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
import 'package:grid_sdk/grid_sdk.dart' show Provider;
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
/// registered, and never polls.
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

  @override
  void start() {}

  @override
  Future<void> stop() async {}
}

GitHubReconcilerRuntime _inert({
  required GitHubReconcilerConfig config,
  required GitHubAppClient client,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
  required ExplorationTransport? transport,
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
  // One cycle inside a test's lifetime: the loop parks for an hour after it.
  interval: Duration(hours: 1),
  minimumSpacing: Duration.zero,
);

const _check = NormalizedGitHubEvent.checkConcluded(
  nodeId: 'C_1',
  actor: 'actions',
  repository: 'memento/power_station',
  substation: 'power_station',
  observationId: 'poll:check:C_1:2026-09-03T16:24:00Z:failure',
  headBranch: 'grid/pow-2xmo',
  checkName: 'build',
  conclusion: 'failure',
);

/// A store holding NO session for the check's bead — the ordinary shape of a
/// check that arrived after its PR landed and its session closed.
CiFeedbackProjection _landedProjection() => CiFeedbackProjection(
  bd: _StateBd('{"schema_version":1,"data":[]}'),
  commandSender: _Sender(),
  gridRoot: '/grid',
  substation: 'power_station',
);

Future<void> _waitForFlare(RecordingExplorationTransport flares) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (flares.flares.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('the failed cycle produced no flare');
}

Seed _seatTree({
  required RecordingExplorationTransport flares,
  required CiFeedbackProjection projection,
}) => sdk.ProviderScope(
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
);

void main() {
  test('a failed cycle flares EXACTLY once on the seat transport', () async {
    final flares = RecordingExplorationTransport();
    final runtime = createGitHubReconcilerRuntime(
      config: _config,
      client: _client,
      cursors: _Cursors(const GitHubReconcilerCursor().enqueue(_check)),
      emit: (_) async {},
      transport: flares,
    );
    runtime.reconciler.addObserver(
      kCiFeedbackDeliveryLeg,
      (_) async => throw StateError('leg refused'),
    );

    runtime.start();
    await _waitForFlare(flares);
    // STOP before the interval elapses, so the count below is one CYCLE's
    // worth and not a race against a second poll.
    await runtime.stop();

    expect(flares.flares, hasLength(1));
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
      commandSender: _Sender(),
      gridRoot: '/grid',
      substation: 'power_station',
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
