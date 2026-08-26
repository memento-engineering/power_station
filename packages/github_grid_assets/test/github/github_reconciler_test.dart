import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

class FakeGitHubHttpTransport implements GitHubHttpTransport {
  final requests = <GitHubHttpRequest>[];
  final responses = <GitHubHttpResponse>[];
  Completer<void>? gate;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    await gate?.future;
    if (responses.isEmpty) throw StateError('no response for ${request.uri}');
    return responses.removeAt(0);
  }
}

class FakeGitHubCursorStore implements GitHubCursorStore {
  FakeGitHubCursorStore([this.cursor = const GitHubReconcilerCursor()]);
  GitHubReconcilerCursor cursor;
  final calls = <String>[];

  @override
  Future<GitHubReconcilerCursor> load() async => cursor;

  @override
  Future<void> save(GitHubReconcilerCursor value) async {
    calls.add('save:${value.observationIds.firstOrNull ?? '-'}');
    cursor = value;
  }
}

GitHubAppClient _client(FakeGitHubHttpTransport transport) => GitHubAppClient(
  config: GitHubAppConfig(
    appId: 'app',
    installationId: 1,
    apiBaseUri: Uri.parse('https://api.github.test'),
  ),
  tokens: _Tokens(),
  transport: transport,
);

GitHubHttpResponse _response(Object body, {int status = 200, String? etag}) =>
    GitHubHttpResponse(
      statusCode: status,
      body: body is String ? body : jsonEncode(body),
      headers: <String, String>{if (etag != null) 'etag': etag},
    );

Map<String, Object?> _issue({
  bool pull = false,
  String state = 'open',
  String? nodeId,
  String? updatedAt,
  int? number,
  String? title,
}) {
  final resolvedNumber = number ?? (pull ? 2 : 1);
  return <String, Object?>{
    'node_id': nodeId ?? (pull ? 'PR_2' : 'I_1'),
    'updated_at':
        updatedAt ?? (pull ? '2026-08-09T02:00:00Z' : '2026-08-09T01:00:00Z'),
    'state': state,
    'number': resolvedNumber,
    'title': title ?? (pull ? 'pull' : 'issue'),
    'body': null,
    'user': <String, Object?>{'login': 'octocat'},
    if (pull)
      'pull_request': <String, Object?>{
        'url':
            'https://api.github.test/repos/memento/power/pulls/'
            '$resolvedNumber',
        'html_url': 'https://github.test/memento/power/pull/$resolvedNumber',
        'diff_url':
            'https://github.test/memento/power/pull/$resolvedNumber.diff',
        'patch_url':
            'https://github.test/memento/power/pull/$resolvedNumber.patch',
      },
  };
}

final class FakeBdRunner implements BdRunner {
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

void main() {
  test(
    'mixed /issues states project only open rows and claim every observation',
    () async {
      final rows = <Object?>[
        _issue(),
        _issue(pull: true),
        _issue(
          state: 'closed',
          nodeId: 'I_CLOSED',
          updatedAt: '2026-08-09T02:30:00Z',
          number: 3,
          title: 'closed issue',
        ),
        _issue(
          pull: true,
          state: 'closed',
          nodeId: 'PR_CLOSED',
          updatedAt: '2026-08-09T02:45:00Z',
          number: 4,
          title: 'closed pull',
        ),
      ];
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(rows, etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(rows, etag: '"issues2"'),
          _response(const <Object?>[], etag: '"pulls2"'),
        ]);
      final runner = FakeBdRunner();
      final projection = GitHubIntakeProjection(
        trust: GitHubSelfTrust(githubUser: 'octocat'),
        store: BdGitHubIntakeStore(runner),
      );
      final store = FakeGitHubCursorStore();
      final events = <NormalizedGitHubEvent>[];
      final calls = store.calls;
      final reconciler = GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: store,
        now: () => DateTime.parse('2026-08-09T03:00:00Z'),
        emit: (event) async {
          calls.add('emit');
          events.add(event);
          await projection(event);
        },
      );
      await reconciler.reconcileOnce();
      await reconciler.reconcileOnce();

      expect(
        rows,
        everyElement(
          isA<Map<String, Object?>>().having(
            (row) => row['state'],
            'state',
            anyOf('open', 'closed'),
          ),
        ),
      );
      expect(_issue(pull: true), contains('pull_request'));
      expect(_issue(pull: true), isNot(contains('head')));
      expect(events, <Matcher>[isA<IssueOpened>(), isA<PullRequestOpened>()]);
      final creates = runner.argvs
          .where((argv) => argv.first == 'create')
          .toList(growable: false);
      expect(creates, hasLength(2));
      for (final argv in creates) {
        expect(argv, containsAllInOrder(<String>['--defer', '9999-12-31']));
      }
      expect(
        creates.map((argv) => argv[argv.indexOf('--external-ref') + 1]).toSet(),
        <String>{'github:I_1', 'github:PR_2'},
      );
      expect(store.cursor.observationIds.toSet(), <String>{
        'poll:issue:I_1:2026-08-09T01:00:00Z',
        'poll:issue:PR_2:2026-08-09T02:00:00Z',
        'poll:issue:I_CLOSED:2026-08-09T02:30:00Z',
        'poll:issue:PR_CLOSED:2026-08-09T02:45:00Z',
      });
      expect(
        calls.indexOf('emit'),
        greaterThan(calls.indexOf('save:poll:issue:I_1:2026-08-09T01:00:00Z')),
      );
      expect(store.cursor.since, DateTime.parse('2026-08-09T03:00:00Z'));
      expect(store.cursor.etags, containsPair('intake/issues', '"issues2"'));
      expect(
        transport.requests.first.uri.queryParameters,
        allOf(containsPair('state', 'all'), containsPair('per_page', '100')),
      );
      expect(
        transport.requests[2].uri.queryParameters['since'],
        '2026-08-09T03:00:00.000Z',
      );
      expect(transport.requests[2].headers['If-None-Match'], '"issues"');
      expect(
        transport.requests,
        everyElement(
          isA<GitHubHttpRequest>().having(
            (request) => request.uri.path,
            'path',
            isNot(contains('/installation/repositories')),
          ),
        ),
      );
    },
  );

  test('malformed intake state reports and does not wedge cursor', () async {
    final malformedState = <String, Object?>{
      ..._issue(
        nodeId: 'I_BAD_STATE',
        updatedAt: '2026-08-09T00:30:00Z',
        number: 0,
        title: 'bad state',
      ),
      'state': 1,
    };
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response(<Object?>[malformedState, _issue()], etag: '"issues"'),
        _response(const <Object?>[], etag: '"pulls"'),
      ]);
    final store = FakeGitHubCursorStore();
    final events = <NormalizedGitHubEvent>[];
    final rowErrors = <Object>[];
    await GitHubReconciler(
      owner: 'memento',
      repository: 'power',
      substation: 'seat',
      client: _client(transport),
      cursors: store,
      now: () => DateTime.parse('2026-08-09T03:00:00Z'),
      emit: (event) async => events.add(event),
      onIntakeRowError: (error, _) => rowErrors.add(error),
    ).reconcileOnce();

    expect(
      rowErrors.single,
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('state must be a string'),
      ),
    );
    expect(events.single, isA<IssueOpened>());
    expect(store.cursor.since, DateTime.parse('2026-08-09T03:00:00Z'));
    expect(store.cursor.etags, containsPair('intake/issues', '"issues"'));
    expect(transport.requests, hasLength(2));
  });

  test('sink failure leaves claimed observation durable', () async {
    final transport = FakeGitHubHttpTransport()
      ..responses.add(_response(<Object?>[_issue()]));
    final store = FakeGitHubCursorStore();
    final reconciler = GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (_) async => throw StateError('sink failed'),
    );
    await expectLater(reconciler.reconcileOnce(), throwsStateError);
    expect(
      store.cursor.observationIds,
      contains('poll:issue:I_1:2026-08-09T01:00:00Z'),
    );
  });

  test('overlapping calls share one in-flight poll', () async {
    final transport = FakeGitHubHttpTransport()
      ..gate = Completer<void>()
      ..responses.addAll(<GitHubHttpResponse>[
        _response(const <Object?>[]),
        _response(const <Object?>[]),
      ]);
    final reconciler = GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: FakeGitHubCursorStore(),
      emit: (_) async {},
    );
    final first = reconciler.reconcileOnce();
    final second = reconciler.reconcileOnce();
    expect(second, same(first));
    transport.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(transport.requests, hasLength(2));
  });

  test('intake 304 is endpoint-local and skips feedback', () async {
    final initial = GitHubReconcilerCursor(
      since: DateTime.parse('2026-08-01T00:00:00Z'),
      etags: const <String, String>{'intake/issues': '"old"'},
      observationIds: const <String>['one'],
    );
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response('', status: 304),
        _response('', status: 304),
      ]);
    final store = FakeGitHubCursorStore(initial);
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (_) async {},
    ).reconcileOnce();
    expect(store.cursor, same(initial));
    expect(store.calls, isEmpty);
    expect(transport.requests, hasLength(2));
  });

  test('feedback filters branches and checks while preserving since', () async {
    final since = DateTime.parse('2026-08-09T00:00:00Z');
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response(const <Object?>[], status: 304),
        _response(<Object?>[
          <String, Object?>{
            'node_id': 'PR_1',
            'head': <String, Object?>{'ref': 'feature/no', 'sha': 'skip'},
          },
          <String, Object?>{
            'node_id': 'PR_2',
            'head': <String, Object?>{'ref': 'grid/yes', 'sha': 'a/b'},
          },
        ], etag: '"pulls"'),
        _response(<String, Object?>{
          'check_runs': <Object?>[
            <String, Object?>{'node_id': 'pending', 'status': 'in_progress'},
            <String, Object?>{
              'node_id': 'CR_1',
              'status': 'completed',
              'conclusion': 'success',
              'completed_at': '2026-08-09T04:00:00Z',
              'name': 'test',
              'app': <String, Object?>{'slug': 'actions'},
            },
          ],
        }, etag: '"checks"'),
      ]);
    final store = FakeGitHubCursorStore(
      GitHubReconcilerCursor(
        since: since,
        etags: const <String, String>{'intake/issues': '"intake"'},
      ),
    );
    final events = <NormalizedGitHubEvent>[];
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event),
    ).reconcileOnce();
    expect(events.single, isA<CheckConcluded>());
    expect(store.cursor.since, since);
    expect(store.cursor.etags['feedback/checks/PR_2'], '"checks"');
    expect(store.cursor.etags['feedback/pulls'], '"pulls"');
    expect(transport.requests, hasLength(3));
    expect(transport.requests.last.uri.path, contains('a%2Fb/check-runs'));
  });

  test(
    'malformed top-level shapes and non-success statuses fail loudly',
    () async {
      for (final response in <GitHubHttpResponse>[
        _response(const <String, Object?>{}),
        _response('', status: 500),
      ]) {
        final transport = FakeGitHubHttpTransport()..responses.add(response);
        final future = GitHubReconciler(
          owner: 'o',
          repository: 'r',
          substation: 's',
          client: _client(transport),
          cursors: FakeGitHubCursorStore(),
          emit: (_) async {},
        ).reconcileOnce();
        await expectLater(
          future,
          throwsA(anyOf(isA<FormatException>(), isA<GitHubPollException>())),
        );
      }
    },
  );
}
