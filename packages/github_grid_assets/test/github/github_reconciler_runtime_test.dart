import 'dart:async';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

class _Transport implements GitHubHttpTransport {
  var calls = 0;
  Object? error;

  /// Holds every request open until completed — how a probe keeps one
  /// repository's cycle IN FLIGHT while it observes another's.
  Completer<void>? gate;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    calls++;
    if (gate case final open?) await open.future;
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

/// A coordinator that records the quota key of every scheduled request, so a
/// caller can prove reconciliation rode the installation budget exactly once.
final class _RecordingCoordinator extends GitHubPollCoordinator {
  _RecordingCoordinator() : super(minimumSpacing: Duration.zero);

  final scheduled = <String>[];
  final requestedSpacings = <Duration?>[];

  @override
  Future<T> schedule<T>(
    String key,
    Future<T> Function() request, {
    Duration? minimumSpacing,
  }) {
    scheduled.add(key);
    requestedSpacings.add(minimumSpacing);
    return super.schedule<T>(key, request, minimumSpacing: minimumSpacing);
  }
}

/// The tick's SQL seam, answered without a socket: the standing SELECT returns
/// its one constant row.
final class _FakeTrajectoryDb implements TrajectoryDb {
  final statements = <String>[];

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    statements.add(sql);
    return const SqlResult(
      rows: <Map<String, String?>>[
        <String, String?>{'github_reconciliation_due': '1'},
      ],
    );
  }

  @override
  Future<void> close() async {}
}

/// The tick's fenced-appender seam: authority held, and a record of every
/// append attempted — reconciliation must attempt none.
final class _FakeTickAppender implements TickAppender {
  final appended = <TrajectoryRecord>[];
  var commits = 0;

  @override
  bool get isInert => false;

  @override
  bool get isHalted => false;

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    DateTime? occurredAt,
  }) async {
    appended.add(record);
    return const AppendDeduped(recordId: 'no repair appends');
  }

  @override
  Future<void> doltCommitIfDue() async => commits++;
}

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

  test(
    'conflicting spacing uses the adjacent-pair maximum and then relaxes',
    () async {
      // ONE key, two repositories, two configured rates. The interval between
      // adjacent starts is the stricter of what the pair asked for, whichever
      // way round they arrive.
      var now = DateTime.utc(2026, 9, 21);
      final waits = <Duration>[];
      final coordinator = GitHubPollCoordinator(
        minimumSpacing: const Duration(seconds: 5),
        now: () => now,
        delay: (duration) async {
          waits.add(duration);
          now = now.add(duration);
        },
      );
      const strict = Duration(seconds: 30);
      const loose = Duration(seconds: 2);
      Future<void> cycle([Duration? spacing]) => coordinator.schedule(
        'installation',
        () async {},
        minimumSpacing: spacing,
      );

      await cycle(loose);
      expect(waits, isEmpty, reason: 'a first start spaces from nothing');

      await cycle(strict);
      expect(waits, <Duration>[strict], reason: 'loose then strict: the NEXT');

      await cycle(loose);
      expect(
        waits,
        <Duration>[strict, strict],
        reason:
            'strict then loose: the PREVIOUS — the ordering does not matter',
      );

      await cycle(loose);
      expect(
        waits,
        <Duration>[strict, strict, loose],
        reason: 'the strict repository has left the pair, so the rate relaxes',
      );

      await cycle();
      expect(
        waits,
        <Duration>[strict, strict, loose, const Duration(seconds: 5)],
        reason: 'no request means the coordinator default, as it always did',
      );

      await coordinator.schedule('other', () async {}, minimumSpacing: loose);
      expect(waits, hasLength(4), reason: 'the conflict is per KEY');
    },
  );

  test(
    'one shared coordinator serializes two runtimes by installation',
    () async {
      // The quota partition, at the runtime seam: the coordinator instance is
      // shared, and the INSTALLATION ID is what decides who waits for whom.
      final coordinator = GitHubPollCoordinator(minimumSpacing: Duration.zero);
      final blocked = _Transport()..gate = Completer<void>();
      final waiting = _Transport();
      final elsewhere = _Transport();
      GitHubReconcilerRuntime runtime(
        String installation,
        _Transport transport,
      ) => GitHubReconcilerRuntime(
        installationId: installation,
        reconciler: _reconciler(transport),
        coordinator: coordinator,
      );

      final cycles = Future.wait(<Future<void>>[
        runtime('installation', blocked).runOnce(),
        runtime('installation', waiting).runOnce(),
        runtime('other', elsewhere).runOnce(),
      ]);
      await _tick();

      expect(blocked.calls, 1, reason: 'the first cycle holds the key open');
      expect(waiting.calls, 0, reason: 'the SAME installation waits its turn');
      expect(
        elsewhere.calls,
        2,
        reason: 'another installation is another budget',
      );

      blocked.gate!.complete();
      await cycles;
      expect(waiting.calls, 2, reason: 'and runs once the key is free');
    },
  );

  test('a runtime requests its OWN spacing on the shared key', () async {
    final coordinator = _RecordingCoordinator();
    final runtime = GitHubReconcilerRuntime(
      installationId: 'configured',
      reconciler: _reconciler(_Transport()),
      coordinator: coordinator,
      minimumSpacing: const Duration(seconds: 11),
    );
    expect(runtime.minimumSpacing, const Duration(seconds: 11));

    await runtime.runOnce();
    expect(coordinator.scheduled, <String>['configured']);
    expect(coordinator.requestedSpacings, <Duration?>[
      const Duration(seconds: 11),
    ]);

    // Unconfigured, a runtime means the coordinator's own value — exactly what
    // a direct construction over a dedicated coordinator has always meant. A
    // key of its own, so this probe reads the REQUEST and waits on nothing.
    final inherited = GitHubReconcilerRuntime(
      installationId: 'inherited',
      reconciler: _reconciler(_Transport()),
      coordinator: coordinator,
    );
    expect(inherited.minimumSpacing, coordinator.minimumSpacing);
    await inherited.runOnce();
    expect(coordinator.scheduled.last, 'inherited');
    expect(coordinator.requestedSpacings.last, coordinator.minimumSpacing);
  });

  test('runOnce performs one coordinator-scheduled reconciliation', () async {
    final transport = _Transport();
    final coordinator = _RecordingCoordinator();
    final runtime = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(transport),
      coordinator: coordinator,
    );

    await runtime.runOnce();

    expect(coordinator.scheduled, <String>['one']);
    expect(transport.calls, 2, reason: 'exactly one reconciliation cycle');

    // Nothing re-runs on its own: a second cycle exists only because a caller
    // — in production, the station tick — asked for one.
    await runtime.runOnce();
    expect(coordinator.scheduled, <String>['one', 'one']);
    expect(transport.calls, 4);
  });

  test('a failed run reports locally AND rethrows for the station', () async {
    final transport = _Transport()..error = StateError('network');
    final errors = <Object>[];
    final runtime = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(transport),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      onError: (error, _) => errors.add(error),
    );

    await expectLater(runtime.runOnce(), throwsA(isA<StateError>()));

    expect(errors, hasLength(1), reason: 'the seat flares its own cycle');
    transport.error = null;
    await runtime.runOnce();
    expect(errors, hasLength(1), reason: 'a good cycle reports nothing');
  });

  test('the query names itself stably for tick telemetry', () {
    final query = GitHubReconciliationQuery();
    expect(query.name, 'github-reconciliation');
    expect(query.sql, 'SELECT 1 AS github_reconciliation_due');
    expect(query.parameters, isEmpty);
  });

  test('the query reconciles every attached seat exactly once', () async {
    final first = _Transport();
    final second = _Transport();
    final query = GitHubReconciliationQuery();

    expect(
      await query.repair(const <Map<String, String?>>[]),
      isEmpty,
      reason: 'an empty attachment set is a QUIET repair, not a failure',
    );

    final one = GitHubReconcilerRuntime(
      installationId: 'one',
      reconciler: _reconciler(first),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );
    final two = GitHubReconcilerRuntime(
      installationId: 'two',
      reconciler: _reconciler(second),
      coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
    );
    query
      ..attach(one)
      ..attach(one)
      ..attach(two);
    expect(query.attached, <GitHubReconcilerRuntime>[one, two]);
    expect(query.isAttached(one), isTrue);

    expect(await query.repair(const <Map<String, String?>>[]), isEmpty);
    expect(first.calls, 2, reason: 'the repeated attach is idempotent');
    expect(second.calls, 2);

    query.detach(one);
    expect(query.isAttached(one), isFalse);
    await query.repair(const <Map<String, String?>>[]);
    expect(first.calls, 2, reason: 'a detached seat stops riding the tick');
    expect(second.calls, 4);
  });

  test(
    'a throwing attached runtime is a refusal on every station tick',
    () async {
      final transport = _Transport()..error = StateError('the seat is dead');
      final errors = <Object>[];
      final query = GitHubReconciliationQuery()
        ..attach(
          GitHubReconcilerRuntime(
            installationId: 'one',
            reconciler: _reconciler(transport),
            coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
            onError: (error, _) => errors.add(error),
          ),
        );
      final appender = _FakeTickAppender();
      final db = _FakeTrajectoryDb();
      final tick = TrajectoryTick(
        appender: appender,
        db: db,
        queries: <ObligationQuery>[query],
      );
      addTearDown(tick.dispose);

      final refusals = <TickRefusal>[];
      for (var pass = 0; pass < 5; pass++) {
        final result = await tick.runPass();
        expect(result.ran, isTrue);
        refusals.addAll(result.refusals);
      }

      // THE WHOLE POINT: a dead poll is now somebody's business. Five passes,
      // five accounted refusals — not five silences.
      expect(refusals, hasLength(5));
      expect(refusals.map((refusal) => refusal.kind).toSet(), <TickRefusalKind>{
        TickRefusalKind.queryFailed,
      });
      expect(refusals.map((refusal) => refusal.query).toSet(), <String>{
        'github-reconciliation',
      });
      expect(refusals.first.reason, contains('the seat is dead'));
      expect(errors, hasLength(5), reason: 'the seat still reports locally');
      expect(db.statements, hasLength(5));
      expect(appender.appended, isEmpty, reason: 'the repair appends nothing');
      expect(appender.commits, 5, reason: 'the cadence commit still fires');
    },
  );

  test('schedule returns its request result, per key', () async {
    final coordinator = GitHubPollCoordinator(minimumSpacing: Duration.zero);
    expect(await coordinator.schedule('a', () async => 7), 7);
    expect(
      await coordinator.schedule(kForeignIssueWatchRateKey, () async => 'body'),
      'body',
    );
    expect(await coordinator.schedule('a', () async {}), isNull);
  });

  test('the foreign key keeps a budget of its own on both sides', () async {
    var now = DateTime.utc(2026, 9, 9);
    final waits = <Duration>[];
    final coordinator = GitHubPollCoordinator(
      minimumSpacing: kUnauthenticatedGitHubMinimumSpacing,
      now: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await coordinator.schedule(kForeignIssueWatchRateKey, () async {});
    await coordinator.schedule('installation-1', () async {});
    expect(waits, isEmpty, reason: 'an installed start spends no foreign unit');

    now = now.add(const Duration(seconds: 5));
    await coordinator.schedule(kForeignIssueWatchRateKey, () async {});
    expect(waits, <Duration>[const Duration(seconds: 60)]);

    await coordinator.schedule('installation-1', () async {});
    expect(waits, hasLength(1), reason: 'nor does it wait on the foreign one');
  });

  test('a failed foreign read leaves the key usable', () async {
    final coordinator = GitHubPollCoordinator(minimumSpacing: Duration.zero);
    await expectLater(
      coordinator.schedule<int>(
        kForeignIssueWatchRateKey,
        () async => throw StateError('rate limited'),
      ),
      throwsStateError,
    );
    expect(
      await coordinator.schedule(kForeignIssueWatchRateKey, () async => 1),
      1,
    );
  });
}
