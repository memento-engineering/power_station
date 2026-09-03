import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
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

typedef _Snapshot = ({List<String> pending, List<String> observed});

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
  test('pending is persisted before the sink and claimed after observers', () async {
    final calls = <String>[];
    final saves = <_Snapshot>[];
    final cursors = _Cursors();
    final reconciler =
        _reconciler(
            transport: _Transport(<GitHubHttpResponse>[
              _response(<Object?>[_issueRow()]),
              _response(const <Object?>[]),
            ]),
            cursors: _RecordingCursors(cursors, calls, saves),
            emit: (_) async => calls.add('emit'),
          )
          ..addObserver('audit', (_) async => calls.add('observer'));

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
  });

  test('a failing observer leaves the observation pending', () async {
    final cursors = _Cursors();
    final emitted = <NormalizedGitHubEvent>[];
    final reconciler =
        _reconciler(
            transport: _Transport(<GitHubHttpResponse>[
              _response(<Object?>[_issueRow()]),
            ]),
            cursors: cursors,
            emit: (event) async => emitted.add(event),
          )
          ..addObserver(
            'audit',
            (_) async => throw StateError('observer failed'),
          );

    await expectLater(reconciler.reconcileOnce(), throwsStateError);

    expect(emitted, hasLength(1));
    expect(cursors.cursor.isPending(_issueId), isTrue);
    expect(cursors.cursor.pendingFor(_issueId)!.acked, <String>[
      kSinkDeliveryLeg,
    ]);
    expect(cursors.cursor.hasObserved(_issueId), isFalse);
  });

  test('replay re-drives only the failed leg, never ci-feedback twice', () async {
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
  });

  test('a duplicate or reserved delivery leg is refused loudly', () {
    final reconciler =
        _reconciler(
            transport: _Transport(<GitHubHttpResponse>[]),
            cursors: _Cursors(),
            emit: (_) async {},
          )
          ..addObserver(kCiFeedbackDeliveryLeg, (_) async {});
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

  test('a restart between persistence and delivery delivers exactly once', () async {
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
      (await FileGitHubCursorStore(cursorPath: path).load()).isPending(_issueId),
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
    expect(GitHubReconcilerCursor.observationIdOf(delivered.single), _issueId);
    expect(calls.first, 'emit');
    final reloaded = await FileGitHubCursorStore(cursorPath: path).load();
    expect(reloaded.pending, isEmpty);
    expect(reloaded.hasObserved(_issueId), isTrue);
  });

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
          )
          ..addObserver(
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
}
