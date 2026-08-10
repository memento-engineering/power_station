import 'dart:async';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

class _Transport implements GitHubHttpTransport {
  var calls = 0;
  Object? error;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    calls++;
    if (error case final failure?) throw failure;
    return const GitHubHttpResponse(statusCode: 304, body: '');
  }
}

class _Store implements GitHubCursorStore {
  @override
  Future<GitHubReconcilerCursor> load() async => const GitHubReconcilerCursor();

  @override
  Future<void> save(GitHubReconcilerCursor cursor) async {}
}

GitHubReconciler _reconciler(_Transport transport) => GitHubReconciler(
  owner: 'o',
  repository: 'r',
  substation: 's',
  client: GitHubAppClient(
    config: GitHubAppConfig(
      appId: 'app',
      installationId: 1,
      apiBaseUri: Uri.parse('https://api.github.test'),
    ),
    tokens: _Tokens(),
    transport: transport,
  ),
  cursors: _Store(),
  emit: (_) async {},
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('different installations overlap while equal ids serialize', () async {
    final coordinator = GitHubPollCoordinator(minimumSpacing: Duration.zero);
    final first = Completer<void>();
    var running = 0;
    var maximum = 0;
    Future<void> request(Completer<void> gate) async {
      running++;
      maximum = running > maximum ? running : maximum;
      await gate.future;
      running--;
    }

    final a = coordinator.schedule('a', () => request(first));
    final second = Completer<void>();
    final b = coordinator.schedule('b', () => request(second));
    await _tick();
    expect(maximum, 2);
    first.complete();
    second.complete();
    await Future.wait(<Future<void>>[a, b]);

    maximum = 0;
    final one = Completer<void>();
    final sameA = coordinator.schedule('same', () => request(one));
    var secondStarted = false;
    final sameB = coordinator.schedule('same', () async {
      secondStarted = true;
    });
    await _tick();
    expect(secondStarted, isFalse);
    one.complete();
    await Future.wait(<Future<void>>[sameA, sameB]);
    expect(secondStarted, isTrue);
  });

  test('same id waits exact remaining spacing after a failure', () async {
    var now = DateTime.utc(2026, 8, 9);
    final waits = <Duration>[];
    final coordinator = GitHubPollCoordinator(
      minimumSpacing: const Duration(seconds: 5),
      now: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );
    await expectLater(
      coordinator.schedule('same', () async => throw StateError('failure')),
      throwsStateError,
    );
    now = now.add(const Duration(seconds: 2));
    await coordinator.schedule('same', () async {});
    expect(waits, <Duration>[const Duration(seconds: 3)]);
    await coordinator.schedule('other', () async {});
    expect(waits, hasLength(1));
  });

  test('start is idempotent and stop interrupts interval sleep', () async {
    final transport = _Transport();
    final sleep = Completer<void>();
    var delays = 0;
    final runtime = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(transport),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      delay: (_) {
        delays++;
        return sleep.future;
      },
    );
    runtime.start();
    runtime.start();
    while (delays == 0) {
      await _tick();
    }
    expect(transport.calls, 2);
    await runtime.stop().timeout(const Duration(seconds: 1));
    await runtime.stop();
    expect(sleep.isCompleted, isFalse);
  });

  test('errors reach observer and retry after interval', () async {
    final transport = _Transport()..error = StateError('network');
    final errors = <Object>[];
    final delays = <Completer<void>>[];
    final runtime = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(transport),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      delay: (_) {
        final completer = Completer<void>();
        delays.add(completer);
        return completer.future;
      },
      onError: (error, _) => errors.add(error),
    );
    runtime.start();
    while (delays.isEmpty) {
      await _tick();
    }
    expect(errors, hasLength(1));
    transport.error = null;
    delays.first.complete();
    while (delays.length < 2) {
      await _tick();
    }
    expect(transport.calls, 3);
    await runtime.stop();
  });

  test('stop before start completes normally', () async {
    final runtime = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(_Transport()),
      coordinator: GitHubPollCoordinator(),
    );
    await runtime.stop();
  });
}
