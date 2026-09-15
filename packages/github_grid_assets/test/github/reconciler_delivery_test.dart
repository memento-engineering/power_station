import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

final class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

final class _Transport implements GitHubHttpTransport {
  _Transport(this.responses, [this.calls]);

  final List<GitHubHttpResponse> responses;
  final List<String>? calls;
  final requests = <GitHubHttpRequest>[];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    calls?.add('http:${request.uri.path}');
    if (responses.isEmpty) throw StateError('no response for ${request.uri}');
    return responses.removeAt(0);
  }
}

final class _Cursors implements GitHubCursorStore {
  _Cursors([this.cursor = const GitHubReconcilerCursor()]);

  GitHubReconcilerCursor cursor;

  @override
  Future<GitHubReconcilerCursor> load() async => cursor;

  @override
  Future<void> save(GitHubReconcilerCursor value) async => cursor = value;
}

typedef _Snapshot = ({
  List<String> pending,
  List<String> observed,
  Map<String, List<String>> acked,
  DateTime? since,
});

final class _RecordingCursors implements GitHubCursorStore {
  _RecordingCursors(this.inner, this.calls, this.saves);

  final _Cursors inner;
  final List<String> calls;
  final List<_Snapshot> saves;

  @override
  Future<GitHubReconcilerCursor> load() => inner.load();

  @override
  Future<void> save(GitHubReconcilerCursor value) async {
    calls.add('save');
    saves.add((
      pending: value.pending
          .map((entry) => entry.observationId)
          .toList(growable: false),
      observed: List<String>.of(value.observationIds),
      acked: <String, List<String>>{
        for (final entry in value.pending)
          entry.observationId: List<String>.of(entry.acked),
      },
      since: value.since,
    ));
    await inner.save(value);
  }
}

final class _Bd implements BdRunner {
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    final data = args.first == 'list'
        ? <Object?>[]
        : <String, Object?>{'id': 'pow-intake'};
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode(<String, Object?>{'schema_version': 1, 'data': data}),
      stderr: '',
    );
  }
}

GitHubAppClient _client(_Transport transport) => GitHubAppClient(
  config: GitHubAppConfig(
    appId: 'app',
    installationId: 1,
    apiBaseUri: Uri.parse('https://api.github.test'),
  ),
  tokens: _Tokens(),
  transport: transport,
);

GitHubHttpResponse _response(Object body, {int status = 200}) =>
    GitHubHttpResponse(
      statusCode: status,
      body: body is String ? body : jsonEncode(body),
    );

Map<String, Object?> _issueRow() => <String, Object?>{
  'node_id': 'I_1',
  'updated_at': '2026-08-09T01:00:00Z',
  'state': 'open',
  'number': 1,
  'title': 'issue',
  'body': null,
  'user': <String, Object?>{'login': 'octocat'},
};

const _issueId = 'poll:issue:I_1:2026-08-09T01:00:00Z';

final _issueEvent = NormalizedGitHubEvent.issueOpened(
  nodeId: 'I_1',
  actor: 'octocat',
  repository: 'memento/power',
  substation: 'power',
  observationId: _issueId,
  number: 1,
  title: 'issue',
  body: '',
);

/// The grid STATE store in PROXIED-SERVER mode — the posture every org store
/// and lunar's own state store actually run in: the type-scoped session list is
/// answered, and `export` is REFUSED. A leg that reached export here would fail
/// on every cycle, which is exactly how five seats stopped polling.
final class _StateBd implements BdRunner {
  _StateBd(this.sessions);

  /// The enveloped payload `bd list -t session --all --json` answers with.
  final String sessions;
  final argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    return switch (args.first) {
      'export' => const BdResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Error: export is not supported in proxied-server mode',
      ),
      'list' => BdResult(exitCode: 0, stdout: sessions, stderr: ''),
      _ => const BdResult(exitCode: 0, stdout: '{}', stderr: ''),
    };
  }
}

/// The seat's OWN work store — where the work bead a merged pull is landing
/// actually lives. Separate from [_StateBd] on purpose: a shared fake could not
/// tell the two rails apart.
final class _WorkBd implements BdRunner {
  _WorkBd({this.result = const BdResult(exitCode: 0, stdout: '', stderr: '')});

  /// The result the landing-ready mutation answers with.
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

final class _Sender implements FeedbackCommandSender {
  final calls = <String>[];

  @override
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  }) async {
    calls.add(idempotencyKey);
    return const FeedbackCommandCompleted(<String, Object?>{});
  }
}

/// One session row per work-bead key, enveloped as `bd list --json` returns it.
String _sessions(List<String> workBeads, {List<String>? ids}) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (var i = 0; i < workBeads.length; i++)
      {
        'id': ids == null ? 'grid_state-session-$i' : ids[i],
        'issue_type': 'session',
        'metadata': {'work_bead': workBeads[i]},
      },
  ],
});

/// The wedged shape, verbatim: ONE open pull request whose checks are RED,
/// acked by the sink leg only.
///
/// It rides a `grid/` branch because the wedged seat's did — but the bead is
/// read from the body's `Refs:` trailer, and the branch takes no part in it.
const _checkId =
    'poll:pull-feedback:PR_1:abc123:2026-09-03T16:24:00.000Z:failing:'
    'mergeable:never-green:fresh';
final _checkCompletedAt = DateTime.parse('2026-09-03T16:24:00Z');

final _checkEvent = NormalizedGitHubEvent.pullRequestFeedback(
  nodeId: 'PR_1',
  actor: 'nico',
  repository: 'memento/power',
  substation: 'power',
  observationId: _checkId,
  number: 8,
  body: 'A human digest.\n\nRefs: pow-2xmo\n',
  headBranch: 'grid/pow-2xmo',
  headSha: 'abc123',
  checkState: PullRequestCheckState.failing,
  mergeability: PullRequestMergeability.mergeable,
  openedAt: DateTime.utc(2026, 9, 3, 15),
  updatedAt: _checkCompletedAt,
  greenSince: null,
  observedAt: DateTime.utc(2026, 9, 3, 16, 30),
  stalled: false,
);

/// An intake row updated AFTER the wedged check — one of the 53 rows GitHub
/// listed for power_station that the blocked poll never observed.
Map<String, Object?> _rowUpdatedAfterCheck() => <String, Object?>{
  ..._issueRow(),
  'updated_at': '2026-09-05T18:40:00Z',
};

GitHubReconcilerCursor _wedged() => const GitHubReconcilerCursor()
    .enqueue(_checkEvent)
    .ack(_checkId, kSinkDeliveryLeg);

/// The same wedged shape with a GREEN aggregate: the state a merged pull
/// request reaches, and the only one that decides a landing mark.
final _greenCheckEvent = NormalizedGitHubEvent.pullRequestFeedback(
  nodeId: 'PR_1',
  actor: 'nico',
  repository: 'memento/power',
  substation: 'power',
  observationId:
      'poll:pull-feedback:PR_1:abc123:2026-09-03T16:24:00.000Z:green:'
      'mergeable:never-green:fresh',
  number: 8,
  body: 'A human digest.\n\nRefs: pow-2xmo\n',
  headBranch: 'grid/pow-2xmo',
  headSha: 'abc123',
  checkState: PullRequestCheckState.green,
  mergeability: PullRequestMergeability.mergeable,
  openedAt: DateTime.utc(2026, 9, 3, 15),
  updatedAt: _checkCompletedAt,
  greenSince: null,
  observedAt: DateTime.utc(2026, 9, 3, 16, 30),
  stalled: false,
);

final String _greenCheckId = GitHubReconcilerCursor.observationIdOf(
  _greenCheckEvent,
);

GitHubReconcilerCursor _wedgedGreen() => const GitHubReconcilerCursor()
    .enqueue(_greenCheckEvent)
    .ack(_greenCheckId, kSinkDeliveryLeg);

/// The substation every fixture here reconciles for.
const sdk.SubstationScope _scope = sdk.SubstationScope(
  name: 'power',
  root: '/work/power',
  prefix: 'pow',
);

/// A projection whose two rails are STATED. [work] is required: a default that
/// fell back to [state] would hide the mis-binding these tests exist to catch.
CiFeedbackProjection _feedback(_StateBd state, _Sender sender, _WorkBd work) =>
    CiFeedbackProjection(
      bd: state,
      workBd: work,
      scope: _scope,
      commandSender: sender,
      gridRoot: '/grid',
    );

GitHubReconciler _reconciler({
  required _Transport transport,
  required GitHubCursorStore cursors,
  required GitHubEventSink emit,
}) => GitHubReconciler(
  owner: 'memento',
  repository: 'power',
  substation: 'power',
  client: _client(transport),
  cursors: cursors,
  emit: emit,
);

void main() {
  test('a proxied-mode store drains the wedged check and advances the '
      'poll in ONE cycle', () async {
    final state = _StateBd(_sessions(<String>['pow-2xmo']));
    final sender = _Sender();
    final cursors = _Cursors(_wedged());
    final saves = <_Snapshot>[];
    final reconciler =
        _reconciler(
          transport: _Transport(<GitHubHttpResponse>[
            _response(<Object?>[_rowUpdatedAfterCheck()]),
            _response(const <Object?>[]),
          ]),
          cursors: _RecordingCursors(cursors, <String>[], saves),
          emit: (_) async {},
        )..addObserver(
          kCiFeedbackDeliveryLeg,
          _feedback(state, sender, _WorkBd()).call,
        );

    await reconciler.reconcileOnce();

    // The leg ACKED: an intermediate cursor carries both delivery legs.
    expect(
      saves.map((save) => save.acked[_checkId]),
      contains(
        orderedEquals(<String>[kSinkDeliveryLeg, kCiFeedbackDeliveryLeg]),
      ),
    );
    // ...the queue DRAINED, and the observation is claimed.
    expect(cursors.cursor.pending, isEmpty);
    expect(cursors.cursor.hasObserved(_checkId), isTrue);
    // ...and the poll behind it MOVED: `since` passes the wedged check time.
    expect(cursors.cursor.since, isNotNull);
    expect(cursors.cursor.since!.isAfter(_checkCompletedAt), isTrue);
    // ONE type-scoped read, and nothing reached the refused verb.
    expect(state.argvs.where((argv) => argv.first == 'list').single, <String>[
      'list',
      '-t',
      'session',
      '--all',
      '--json',
      '--limit',
      '0',
    ]);
    expect(state.argvs.map((argv) => argv.first), isNot(contains('export')));
    expect(sender.calls, hasLength(1));
  });

  test('a work bead the scoped store cannot resolve drains and polls '
      'on', () async {
    // THE WEDGE, end to end. The landing mark used to THROW here, which failed
    // the leg, left the observation pending, and aborted the cycle before the
    // poll — so the seat re-drove this one pull request forever. It now
    // degrades: one flare, a durable acknowledgement, and the poll behind it.
    const noRows =
        'Error resolving pow-2xmo: get pow-2xmo: sql: no rows in result set';
    final state = _StateBd(_sessions(<String>['pow-2xmo']));
    final work = _WorkBd(
      result: const BdResult(exitCode: 1, stdout: '', stderr: noRows),
    );
    final sender = _Sender();
    final flares = <({String name, String message})>[];
    final cursors = _Cursors(_wedgedGreen());
    final saves = <_Snapshot>[];
    final projection = _feedback(state, sender, work)
      ..bindReporter(
        (name, action, error, stackTrace) =>
            flares.add((name: name, message: '$error')),
      );
    final reconciler = _reconciler(
      transport: _Transport(<GitHubHttpResponse>[
        _response(<Object?>[_rowUpdatedAfterCheck()]),
        _response(const <Object?>[]),
      ]),
      cursors: _RecordingCursors(cursors, <String>[], saves),
      emit: (_) async {},
    )..addObserver(kCiFeedbackDeliveryLeg, projection.call);

    await reconciler.reconcileOnce();

    // The leg ACKED durably...
    expect(
      saves.map((save) => save.acked[_greenCheckId]),
      contains(
        orderedEquals(<String>[kSinkDeliveryLeg, kCiFeedbackDeliveryLeg]),
      ),
    );
    // ...the queue DRAINED and the observation is claimed...
    expect(cursors.cursor.pending, isEmpty);
    expect(cursors.cursor.hasObserved(_greenCheckId), isTrue);
    // ...and the poll BEHIND it moved past the wedged check.
    expect(cursors.cursor.since, isNotNull);
    expect(cursors.cursor.since!.isAfter(_checkCompletedAt), isTrue);

    // ONE flare, naming the bead, the store root that was attempted, and the
    // store's own words.
    expect(flares.map((flare) => flare.name), <String>[
      kCiFeedbackLandingUnresolvedFlare,
    ]);
    expect(flares.single.message, contains('pow-2xmo'));
    expect(flares.single.message, contains('/work/power'));
    expect(flares.single.message, contains(noRows));

    // The mutation was attempted against the WORK store, and the state store
    // answered reads only.
    expect(work.argvs.single, <String>[
      'update',
      'pow-2xmo',
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);
    expect(state.argvs.map((argv) => argv.first), everyElement('list'));
    expect(sender.calls, isEmpty);
  });

  for (final shape in <({String name, String sessions})>[
    (name: 'no live session', sessions: '{"schema_version":1,"data":[]}'),
    (
      name: 'two current sessions',
      sessions: _sessions(<String>['pow-2xmo', 'pow-2xmo']),
    ),
    (
      name: 'a current session with a blank id',
      sessions: _sessions(<String>['pow-2xmo'], ids: <String>['  ']),
    ),
  ]) {
    test('a stale check whose bead resolves to ${shape.name} still '
        'drains', () async {
      final state = _StateBd(shape.sessions);
      final sender = _Sender();
      final flares = <String>[];
      final cursors = _Cursors(_wedged());
      final projection = _feedback(state, sender, _WorkBd())
        ..bindReporter((name, action, error, stackTrace) => flares.add(name));
      final reconciler = _reconciler(
        transport: _Transport(<GitHubHttpResponse>[
          _response(<Object?>[_rowUpdatedAfterCheck()]),
          _response(const <Object?>[]),
        ]),
        cursors: cursors,
        emit: (_) async {},
      )..addObserver(kCiFeedbackDeliveryLeg, projection.call);

      await reconciler.reconcileOnce();

      expect(flares, <String>[kCiFeedbackIgnoredFlare]);
      expect(sender.calls, isEmpty);
      expect(cursors.cursor.pending, isEmpty);
      expect(cursors.cursor.hasObserved(_checkId), isTrue);
      expect(cursors.cursor.since!.isAfter(_checkCompletedAt), isTrue);
    });
  }

  test(
    'pending is persisted before the sink and claimed after observers',
    () async {
      final calls = <String>[];
      final saves = <_Snapshot>[];
      final cursors = _Cursors();
      final reconciler = _reconciler(
        transport: _Transport(<GitHubHttpResponse>[
          _response(<Object?>[_issueRow()]),
          _response(const <Object?>[]),
        ]),
        cursors: _RecordingCursors(cursors, calls, saves),
        emit: (_) async => calls.add('emit'),
      )..addObserver('audit', (_) async => calls.add('observer'));

      await reconciler.reconcileOnce();

      expect(saves[0].pending, <String>[_issueId]);
      expect(saves[0].observed, isEmpty);
      expect(saves[1].observed, isEmpty);
      expect(saves[2].observed, isEmpty);
      expect(saves[3].pending, isEmpty);
      expect(saves[3].observed, <String>[_issueId]);
      expect(calls.take(6), <String>[
        'save',
        'emit',
        'save',
        'observer',
        'save',
        'save',
      ]);
      expect(cursors.cursor.pending, isEmpty);
      expect(cursors.cursor.hasObserved(_issueId), isTrue);
    },
  );

  test('a failing observer leaves the observation pending', () async {
    final cursors = _Cursors();
    final emitted = <NormalizedGitHubEvent>[];
    final reconciler = _reconciler(
      transport: _Transport(<GitHubHttpResponse>[
        _response(<Object?>[_issueRow()]),
      ]),
      cursors: cursors,
      emit: (event) async => emitted.add(event),
    )..addObserver('audit', (_) async => throw StateError('observer failed'));

    await expectLater(reconciler.reconcileOnce(), throwsStateError);

    expect(emitted, hasLength(1));
    expect(cursors.cursor.isPending(_issueId), isTrue);
    expect(cursors.cursor.pendingFor(_issueId)!.acked, <String>[
      kSinkDeliveryLeg,
    ]);
    expect(cursors.cursor.hasObserved(_issueId), isFalse);
  });

  test(
    'replay re-drives only the failed leg, never ci-feedback twice',
    () async {
      final feedback = <NormalizedGitHubEvent>[];
      var landingFails = true;
      final cursors = _Cursors();
      final reconciler =
          _reconciler(
              transport: _Transport(<GitHubHttpResponse>[
                _response(<Object?>[_issueRow()]),
                _response('', status: 304),
                _response('', status: 304),
              ]),
              cursors: cursors,
              emit: (_) async {},
            )
            ..addObserver(
              kCiFeedbackDeliveryLeg,
              (event) async => feedback.add(event),
            )
            ..addObserver('landing', (_) async {
              if (landingFails) {
                landingFails = false;
                throw StateError('landing store timed out');
              }
            });

      await expectLater(reconciler.reconcileOnce(), throwsStateError);
      expect(cursors.cursor.pendingFor(_issueId)!.acked, <String>[
        kSinkDeliveryLeg,
        kCiFeedbackDeliveryLeg,
      ]);

      await reconciler.reconcileOnce();

      expect(feedback, hasLength(1));
      expect(cursors.cursor.pending, isEmpty);
      expect(cursors.cursor.hasObserved(_issueId), isTrue);
    },
  );

  test('a duplicate or reserved delivery leg is refused loudly', () {
    final reconciler = _reconciler(
      transport: _Transport(<GitHubHttpResponse>[]),
      cursors: _Cursors(),
      emit: (_) async {},
    )..addObserver(kCiFeedbackDeliveryLeg, (_) async {});
    expect(
      () => reconciler.addObserver(kCiFeedbackDeliveryLeg, (_) async {}),
      throwsArgumentError,
    );
    expect(
      () => reconciler.addObserver(kSinkDeliveryLeg, (_) async {}),
      throwsArgumentError,
    );
    reconciler.removeObserver(kCiFeedbackDeliveryLeg);
    reconciler.addObserver(kCiFeedbackDeliveryLeg, (_) async {});
  });

  test(
    'a restart between persistence and delivery delivers exactly once',
    () async {
      final directory = await Directory.systemTemp.createTemp('github-outbox-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/cursor.json';

      await expectLater(
        _reconciler(
          transport: _Transport(<GitHubHttpResponse>[
            _response(<Object?>[_issueRow()]),
          ]),
          cursors: FileGitHubCursorStore(cursorPath: path),
          emit: (_) async => throw StateError('sink failed'),
        ).reconcileOnce(),
        throwsStateError,
      );
      expect(
        (await FileGitHubCursorStore(
          cursorPath: path,
        ).load()).isPending(_issueId),
        isTrue,
      );

      final calls = <String>[];
      final delivered = <NormalizedGitHubEvent>[];
      final restarted = _reconciler(
        transport: _Transport(<GitHubHttpResponse>[
          _response('', status: 304),
          _response('', status: 304),
          _response('', status: 304),
          _response('', status: 304),
        ], calls),
        cursors: FileGitHubCursorStore(cursorPath: path),
        emit: (event) async {
          calls.add('emit');
          delivered.add(event);
        },
      );
      await restarted.reconcileOnce();
      await restarted.reconcileOnce();

      expect(delivered, hasLength(1));
      expect(
        GitHubReconcilerCursor.observationIdOf(delivered.single),
        _issueId,
      );
      expect(calls.first, 'emit');
      final reloaded = await FileGitHubCursorStore(cursorPath: path).load();
      expect(reloaded.pending, isEmpty);
      expect(reloaded.hasObserved(_issueId), isTrue);
    },
  );

  test('a claimed id in the recorded queue replays as a sink no-op', () async {
    final recorded =
        jsonDecode(
              await File('test/fixtures/pending_cursor.json').readAsString(),
            )
            as Map<String, Object?>;
    final cursors = _Cursors(GitHubReconcilerCursor.fromJson(recorded));
    final delivered = <NormalizedGitHubEvent>[];
    final observed = <NormalizedGitHubEvent>[];
    final reconciler =
        _reconciler(
          transport: _Transport(<GitHubHttpResponse>[
            _response('', status: 304),
            _response('', status: 304),
          ]),
          cursors: cursors,
          emit: (event) async => delivered.add(event),
        )..addObserver(
          kCiFeedbackDeliveryLeg,
          (event) async => observed.add(event),
        );

    await reconciler.reconcileOnce();

    expect(delivered.map(GitHubReconcilerCursor.observationIdOf), <String>[
      'poll:issue:PR_2:2026-08-09T01:00:00Z',
    ]);
    expect(observed, hasLength(1));
    expect(cursors.cursor.pending, isEmpty);
    expect(
      cursors.cursor.hasObserved('poll:issue:I_1:2026-08-09T00:00:00Z'),
      isTrue,
    );
    expect(
      cursors.cursor.hasObserved('poll:issue:PR_2:2026-08-09T01:00:00Z'),
      isTrue,
    );
  });

  test('replay precedes the first poll request of its cycle', () async {
    final calls = <String>[];
    final cursors = _Cursors(
      const GitHubReconcilerCursor().enqueue(_issueEvent),
    );
    await _reconciler(
      transport: _Transport(<GitHubHttpResponse>[
        _response('', status: 304),
        _response('', status: 304),
      ], calls),
      cursors: cursors,
      emit: (_) async => calls.add('emit'),
    ).reconcileOnce();

    expect(calls.first, 'emit');
    expect(calls.where((call) => call.startsWith('http:')), hasLength(2));
    expect(cursors.cursor.pending, isEmpty);
  });

  test('the retry rides the same per-key metadata channel', () async {
    final bd = _Bd();
    final projection = GitHubIntakeProjection(
      trust: GitHubSelfTrust(githubUser: 'octocat'),
      store: BdGitHubIntakeStore(bd),
    );
    var failFirst = true;
    final cursors = _Cursors();
    final reconciler = _reconciler(
      transport: _Transport(<GitHubHttpResponse>[
        _response(<Object?>[_issueRow()]),
        _response('', status: 304),
        _response('', status: 304),
      ]),
      cursors: cursors,
      emit: (event) async {
        if (failFirst) {
          failFirst = false;
          throw StateError('store timed out');
        }
        await projection(event);
      },
    );

    await expectLater(reconciler.reconcileOnce(), throwsStateError);
    expect(bd.argvs, isEmpty);
    expect(cursors.cursor.isPending(_issueId), isTrue);

    await reconciler.reconcileOnce();

    expect(bd.argvs.map((argv) => argv.first), <String>[
      'list',
      'create',
      'update',
    ]);
    expect(
      bd.argvs.last,
      containsAllInOrder(<String>[
        '--set-metadata',
        'github.node_id=I_1',
        '--set-metadata',
        'github.kind=issue',
        '--set-metadata',
        'github.repository=memento/power',
        '--set-metadata',
        'github.actor=octocat',
      ]),
    );
    expect(bd.argvs.expand((argv) => argv), isNot(contains('--metadata')));
    expect(cursors.cursor.hasObserved(_issueId), isTrue);
    expect(cursors.cursor.pending, isEmpty);
  });

  test('a watch observation rides the pending queue, acked per leg', () async {
    const watch = GitHubIssueWatch(
      originatingBeadId: 'lunar_station-6p9',
      owner: 'ricardoboss',
      repository: 'radioactive_dart',
      issueNumber: 1,
    );
    final calls = <String>[];
    final saves = <_Snapshot>[];
    final cursors = _RecordingCursors(_Cursors(), calls, saves);
    final transport = _Transport(<GitHubHttpResponse>[
      GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'node_id': 'I_kwDO',
          'number': 1,
          'user': <String, Object?>{'login': 'nico'},
          'state': 'open',
          'state_reason': null,
          'locked': false,
          'updated_at': '2026-09-09T10:00:00Z',
          'html_url': 'https://github.test/1',
          'closed_by': null,
        }),
      ),
      GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode(<Object?>[
          <String, Object?>{
            'event': 'commented',
            'id': 11,
            'node_id': 'IC_first',
            'user': <String, Object?>{'login': 'ricardoboss'},
            'body': 'A reply.',
            'created_at': '2026-09-09T11:00:00Z',
          },
        ]),
      ),
    ], calls);
    final reconciler = GitHubReconciler(
      owner: 'memento',
      repository: 'power',
      substation: 'power',
      client: GitHubAppClient(
        config: GitHubAppConfig(
          appId: 'app',
          installationId: 1,
          apiBaseUri: Uri.parse('https://api.github.test'),
        ),
        tokens: _Tokens(),
        transport: transport,
      ),
      cursors: cursors,
      emit: (_) async => calls.add('sink'),
      issueWatches: const <GitHubIssueWatch>[watch],
      foreignClient: GitHubReadClient(
        transport: transport,
        apiBaseUri: Uri.parse('https://api.github.test'),
      ),
    );
    reconciler.addObserver(kGitHubIssueWatchDeliveryLeg, (_) async {
      calls.add('issue-watch');
    });

    await reconciler.reconcileForeignIssueWatchesOnce();

    const id = 'poll:issue-comment:IC_first';
    expect(
      calls,
      containsAllInOrder(<String>[
        'save', // PENDING is persisted BEFORE any leg runs.
        'sink',
        'save',
        'issue-watch',
        'save',
      ]),
    );
    expect(
      saves.firstWhere((save) => save.pending.contains(id)).acked[id],
      isEmpty,
    );
    expect(
      saves.map((save) => save.acked[id]).whereType<List<String>>(),
      containsAllInOrder(<List<String>>[
        <String>[],
        <String>['sink'],
        <String>['sink', 'issue-watch'],
      ]),
    );
    expect(cursors.inner.cursor.pending, isEmpty);
    expect(cursors.inner.cursor.hasObserved(id), isTrue);
    expect(
      cursors.inner.cursor.issueWatches[watch.coordinateKey]!.lastCommentId,
      11,
      reason: 'the high-water mark advances only AFTER delivery',
    );
  });
}
