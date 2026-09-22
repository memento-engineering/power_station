import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/testing.dart' show RecordingExplorationTransport;
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
    for (final entry in value.pending) {
      calls.add('pending:${entry.observationId}');
    }
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

GitHubHttpResponse _response(
  Object body, {
  int status = 200,
  String? etag,
  String? link,
}) => GitHubHttpResponse(
  statusCode: status,
  body: body is String ? body : jsonEncode(body),
  headers: <String, String>{
    if (etag != null) 'etag': etag,
    if (link != null) 'link': link,
  },
);

Future<Map<String, Object?>> _pullResource() async =>
    jsonDecode(await File('test/fixtures/pull_resource.json').readAsString())
        as Map<String, Object?>;

/// The recorded `/actions/runs?status=completed` page: one matching nightly
/// failure, one failure of an undeclared workflow, one fork-head run, and one
/// green run.
Future<Map<String, Object?>> _runsPage() async =>
    jsonDecode(
          await File('test/fixtures/actions_runs_page.json').readAsString(),
        )
        as Map<String, Object?>;

/// The recorded `/actions/runs/<id>/jobs?filter=latest` page.
Future<Map<String, Object?>> _jobsPage() async =>
    jsonDecode(
          await File('test/fixtures/actions_run_jobs_page.json').readAsString(),
        )
        as Map<String, Object?>;

/// The seat's own nightly rule: `ci.yaml`, scheduled or dispatched, on the
/// default branch, red or timed out.
WorkflowRunIntakeRule _nightlyRule({int priority = 1, bool approve = true}) =>
    WorkflowRunIntakeRule(
      workflowPath: '.github/workflows/ci.yaml',
      validationPlan: 'dart test',
      events: const {'schedule', 'workflow_dispatch'},
      priority: priority,
      approve: approve,
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

/// One recorded issues page of [count] rows starting at [first], one minute
/// apart, ascending by `updated_at` exactly as the poll requests them.
List<Object?> _page(int count, {required int first}) => <Object?>[
  for (var index = first; index < first + count; index++)
    _issue(
      nodeId: 'I_$index',
      number: index,
      title: 'issue $index',
      updatedAt: DateTime.utc(
        2026,
        8,
        9,
      ).add(Duration(minutes: index)).toIso8601String(),
    ),
];

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

/// One row of the `?state=open` pulls page, in GitHub's own shape.
Map<String, Object?> _openPull({
  String nodeId = 'PR_8',
  int number = 8,
  String branch = 'org/lockfile-convention',
  String sha = 'abc123',
  String body = 'A human digest.\n\nRefs: pow-78jk\n',
  String updatedAt = '2026-09-12T09:00:00Z',
}) => <String, Object?>{
  'node_id': nodeId,
  'number': number,
  'body': body,
  'user': <String, Object?>{'login': 'nico'},
  'created_at': '2026-09-12T08:00:00Z',
  'updated_at': updatedAt,
  'head': <String, Object?>{'ref': branch, 'sha': sha},
};

/// The FULL pull resource, the only place `mergeable` lives.
Map<String, Object?> _pullDetail({Object? mergeable = true}) =>
    <String, Object?>{'mergeable': mergeable};

/// One check run of a `/check-runs` page.
Map<String, Object?> _run({
  String nodeId = 'CR_1',
  String status = 'completed',
  String? conclusion = 'success',
  String completedAt = '2026-09-12T09:30:00Z',
}) => <String, Object?>{
  'node_id': nodeId,
  'status': status,
  'conclusion': conclusion,
  'completed_at': completedAt,
  'name': 'test',
  'app': <String, Object?>{'slug': 'actions'},
};

Map<String, Object?> _checkRuns(List<Map<String, Object?>> runs) =>
    <String, Object?>{'check_runs': runs};

/// A cursor whose intake leg is already conditional, so a `304` skips it.
GitHubReconcilerCursor _intakeSettled() => const GitHubReconcilerCursor(
  etags: <String, String>{'intake/issues': '"intake"'},
);

/// A forbidden response whose BODY names something that must never be reported.
const String _secretBody = '{"message":"not accessible: secret-token-echo"}';

/// Pull 2's already-observed baseline: the exact record and tags a cycle that
/// cannot observe it again must leave untouched.
final GitHubPullFeedbackCursorRecord _baseline = GitHubPullFeedbackCursorRecord(
  actor: 'nico',
  number: 2,
  body: 'A human digest.\n\nRefs: pow-earlier\n',
  headBranch: 'org/release-path-ruling',
  headSha: 'older-sha',
  checkState: PullRequestCheckState.pending,
  mergeability: PullRequestMergeability.unknown,
  openedAt: DateTime.utc(2026, 9, 11, 8),
  updatedAt: DateTime.utc(2026, 9, 11, 9),
  greenSince: null,
);

/// A settled cursor already holding [_baseline] and both of its tags.
GitHubReconcilerCursor _feedbackSettled() => GitHubReconcilerCursor(
  etags: const <String, String>{
    'intake/issues': '"intake"',
    'feedback/pull/PR_2': '"detail-2"',
    'feedback/checks/PR_2': '"checks-2"',
  },
  pullFeedback: <String, GitHubPullFeedbackCursorRecord>{'PR_2': _baseline},
);

/// The three open pulls of the failure-domain group, in listed order.
List<Object?> _threeOpenPulls() => <Object?>[
  _openPull(nodeId: 'PR_1', number: 1),
  _openPull(nodeId: 'PR_2', number: 2),
  _openPull(nodeId: 'PR_3', number: 3),
];

/// The `If-None-Match` value [request] carried, or null.
String? _conditional(GitHubHttpRequest request) =>
    request.headers['If-None-Match'];

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
          _response(await _pullResource(), etag: '"pull2"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(rows, etag: '"issues2"'),
          _response('', status: 304),
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
      expect(events, <Matcher>[
        isA<IssueOpened>(),
        isA<PullRequestOpened>().having(
          (event) => event.headRef,
          'headRef',
          'grid/pow-40a4',
        ),
      ]);
      final creates = runner.argvs
          .where((argv) => argv.first == 'create')
          .toList(growable: false);
      expect(creates, hasLength(2));
      for (final argv in creates) {
        expect(
          argv,
          containsAllInOrder(<String>[
            'create',
            '--type',
            'chore',
            '--priority',
            '2',
          ]),
        );
        expect(argv, isNot(contains('--defer')));
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
      const issueId = 'poll:issue:I_1:2026-08-09T01:00:00Z';
      expect(
        calls.indexOf('pending:$issueId'),
        lessThan(calls.indexOf('emit')),
      );
      expect(calls.indexOf('emit'), lessThan(calls.indexOf('save:$issueId')));
      expect(store.cursor.since, DateTime.parse('2026-08-09T02:45:00Z'));
      expect(store.cursor.etags, containsPair('intake/issues', '"issues2"'));
      expect(store.cursor.pullHeads['PR_2'], 'grid/pow-40a4');
      expect(
        transport.requests.first.uri.queryParameters,
        allOf(containsPair('state', 'all'), containsPair('per_page', '100')),
      );
      expect(transport.requests[1].uri.path, '/repos/memento/power/pulls/2');
      expect(
        transport.requests[3].uri.queryParameters['since'],
        '2026-08-09T02:45:00.000Z',
      );
      expect(transport.requests[3].headers['If-None-Match'], '"issues"');
      expect(transport.requests[4].headers['If-None-Match'], '"pull2"');
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
    expect(store.cursor.since, DateTime.parse('2026-08-09T01:00:00Z'));
    expect(store.cursor.etags, containsPair('intake/issues', '"issues"'));
    expect(transport.requests, hasLength(2));
  });

  test('a poll reads every Link page before it returns', () async {
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response(
          _page(100, first: 0),
          etag: '"page1"',
          link:
              '<https://api.github.test/repos/o/r/issues?per_page=100&page=2>; '
              'rel="next", '
              '<https://api.github.test/repos/o/r/issues?per_page=100&page=2>; '
              'rel="last"',
        ),
        _response(_page(20, first: 100)),
        _response(const <Object?>[], etag: '"pulls"'),
      ]);
    final store = FakeGitHubCursorStore();
    final events = <NormalizedGitHubEvent>[];
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event),
    ).reconcileOnce();

    expect(events, hasLength(120));
    expect(events.whereType<IssueOpened>().last.nodeId, 'I_119');
    final issueRequests = transport.requests
        .where((request) => request.uri.path.endsWith('/issues'))
        .toList(growable: false);
    expect(issueRequests, hasLength(2));
    expect(issueRequests.last.uri.queryParameters['page'], '2');
    expect(issueRequests.last.headers.containsKey('If-None-Match'), isFalse);
    expect(store.cursor.since, DateTime.parse('2026-08-09T01:59:00Z'));
  });

  test('since marks the last examined row, never the poll start', () async {
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response(<Object?>[
          _issue(nodeId: 'I_1', number: 1, updatedAt: '2026-08-09T01:00:00Z'),
          _issue(nodeId: 'I_2', number: 2, updatedAt: '2026-08-09T02:00:00Z'),
        ], etag: '"first"'),
        _response(const <Object?>[], etag: '"pulls"'),
        _response(<Object?>[
          _issue(nodeId: 'I_2', number: 2, updatedAt: '2026-08-09T02:00:00Z'),
          _issue(nodeId: 'I_3', number: 3, updatedAt: '2026-08-09T02:30:00Z'),
        ], etag: '"second"'),
        _response(const <Object?>[], etag: '"pulls2"'),
      ]);
    final store = FakeGitHubCursorStore();
    final events = <NormalizedGitHubEvent>[];
    final reconciler = GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event),
    );
    await reconciler.reconcileOnce();

    expect(store.cursor.since, DateTime.parse('2026-08-09T02:00:00Z'));
    expect(events.map((event) => event.toJson()['nodeId']), <String>[
      'I_1',
      'I_2',
    ]);

    await reconciler.reconcileOnce();

    final issueRequests = transport.requests
        .where((request) => request.uri.path.endsWith('/issues'))
        .toList(growable: false);
    expect(
      issueRequests.last.uri.queryParameters['since'],
      '2026-08-09T02:00:00.000Z',
    );
    expect(events.map((event) => event.toJson()['nodeId']), <String>[
      'I_1',
      'I_2',
      'I_3',
    ]);
    expect(store.cursor.since, DateTime.parse('2026-08-09T02:30:00Z'));
  });

  test(
    'a PR row fetches the full pull and a 304 reuses the cached head',
    () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(<Object?>[
            _issue(pull: true, updatedAt: '2026-08-09T02:00:00Z'),
          ], etag: '"issues"'),
          _response(await _pullResource(), etag: '"pull2"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(<Object?>[
            _issue(pull: true, updatedAt: '2026-08-09T03:00:00Z'),
          ], etag: '"issues2"'),
          _response('', status: 304),
          _response(const <Object?>[], etag: '"pulls2"'),
        ]);
      final store = FakeGitHubCursorStore();
      final events = <NormalizedGitHubEvent>[];
      final reconciler = GitHubReconciler(
        owner: 'o',
        repository: 'r',
        substation: 's',
        client: _client(transport),
        cursors: store,
        emit: (event) async => events.add(event),
      );
      await reconciler.reconcileOnce();
      await reconciler.reconcileOnce();

      expect(events, hasLength(2));
      expect(
        events.whereType<PullRequestOpened>().map((event) => event.headRef),
        <String>['grid/pow-40a4', 'grid/pow-40a4'],
      );
      final pullRequests = transport.requests
          .where((request) => request.uri.path.endsWith('/pulls/2'))
          .toList(growable: false);
      expect(pullRequests, hasLength(2));
      expect(pullRequests.first.headers.containsKey('If-None-Match'), isFalse);
      expect(pullRequests.last.headers['If-None-Match'], '"pull2"');
      expect(store.cursor.etags['intake/pull/PR_2'], '"pull2"');
      expect(store.cursor.since, DateTime.parse('2026-08-09T03:00:00Z'));
    },
  );

  test('sink failure leaves the observation pending, never observed', () async {
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
    const id = 'poll:issue:I_1:2026-08-09T01:00:00Z';
    expect(store.cursor.isPending(id), isTrue);
    expect(store.cursor.pendingFor(id)!.acked, isEmpty);
    expect(store.cursor.hasObserved(id), isFalse);
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

  test('a non-grid green pull emits PR feedback', () async {
    // The whole defect in one case: a pull on `org/…`, not `grid/…`, that the
    // loop used to drop on the floor. It is emitted, it is durable, and its
    // branch takes no part in any of it.
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls"'),
        _response(_pullDetail(), etag: '"detail"'),
        _response(_checkRuns(<Map<String, Object?>>[_run()]), etag: '"checks"'),
      ]);
    final store = FakeGitHubCursorStore(_intakeSettled());
    final events = <NormalizedGitHubEvent>[];
    await GitHubReconciler(
      owner: 'memento-engineering',
      repository: 'power_station',
      substation: 'power_station',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event),
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    ).reconcileOnce();

    final feedback = events.single as PullRequestFeedback;
    expect(feedback.headBranch, 'org/lockfile-convention');
    expect(feedback.repository, 'memento-engineering/power_station');
    expect(feedback.number, 8);
    expect(feedback.body, contains('Refs: pow-78jk'));
    expect(feedback.actor, 'nico');
    expect(feedback.headSha, 'abc123');
    expect(feedback.checkState, PullRequestCheckState.green);
    expect(feedback.mergeability, PullRequestMergeability.mergeable);
    expect(feedback.openedAt, DateTime.utc(2026, 9, 12, 8));
    expect(feedback.updatedAt, DateTime.utc(2026, 9, 12, 9));
    expect(feedback.greenSince, DateTime.utc(2026, 9, 12, 9, 30));
    expect(feedback.observedAt, DateTime.utc(2026, 9, 12, 9, 45));
    expect(feedback.stalled, isFalse);

    // Through the DURABLE outbox, not past it.
    expect(store.calls, contains('pending:${feedback.observationId}'));
    expect(store.cursor.hasObserved(feedback.observationId), isTrue);
    expect(store.cursor.pending, isEmpty);
    expect(
      store.cursor.pullFeedback['PR_8']!.checkState,
      PullRequestCheckState.green,
    );
    expect(store.cursor.etags['feedback/pull/PR_8'], '"detail"');
    expect(store.cursor.etags['feedback/checks/PR_8'], '"checks"');
    expect(store.cursor.etags['feedback/pulls'], '"pulls"');
    expect(transport.requests, hasLength(4));
    expect(transport.requests.last.uri.path, contains('abc123/check-runs'));
  });

  test('pull feedback distinguishes every check state', () async {
    // Five pulls, one per aggregate shape, in ONE page: an empty list and a
    // failure are the two that must never read as green, and a still-running
    // job must outrank the successes beside it.
    final shapes = <({String node, List<Map<String, Object?>> runs})>[
      (node: 'PR_none', runs: <Map<String, Object?>>[]),
      (
        node: 'PR_pending',
        runs: <Map<String, Object?>>[
          _run(),
          _run(nodeId: 'CR_2', status: 'in_progress', conclusion: null),
        ],
      ),
      (
        node: 'PR_green',
        runs: <Map<String, Object?>>[
          _run(),
          _run(nodeId: 'CR_2', completedAt: '2026-09-12T09:40:00Z'),
        ],
      ),
      (
        node: 'PR_failing',
        runs: <Map<String, Object?>>[
          _run(),
          _run(nodeId: 'CR_2', conclusion: 'failure'),
        ],
      ),
      (
        node: 'PR_inconclusive',
        runs: <Map<String, Object?>>[
          _run(),
          _run(nodeId: 'CR_2', conclusion: 'skipped'),
        ],
      ),
    ];
    final transport = FakeGitHubHttpTransport()
      ..responses.add(_response('', status: 304))
      ..responses.add(
        _response(<Object?>[
          for (var index = 0; index < shapes.length; index++)
            _openPull(nodeId: shapes[index].node, number: index + 1),
        ], etag: '"pulls"'),
      );
    for (final shape in shapes) {
      transport.responses
        ..add(_response(_pullDetail()))
        ..add(_response(_checkRuns(shape.runs)));
    }
    final events = <PullRequestFeedback>[];
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: FakeGitHubCursorStore(_intakeSettled()),
      emit: (event) async => events.add(event as PullRequestFeedback),
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    ).reconcileOnce();

    expect(
      <String, PullRequestCheckState>{
        for (final event in events) event.nodeId: event.checkState,
      },
      <String, PullRequestCheckState>{
        'PR_none': PullRequestCheckState.notReported,
        'PR_pending': PullRequestCheckState.pending,
        'PR_green': PullRequestCheckState.green,
        'PR_failing': PullRequestCheckState.failing,
        'PR_inconclusive': PullRequestCheckState.inconclusive,
      },
    );
    expect(
      events.where((event) => event.checkState == PullRequestCheckState.green),
      hasLength(1),
      reason: 'a failure and an empty list are never green',
    );
    expect(
      events.singleWhere((event) => event.nodeId == 'PR_green').greenSince,
      DateTime.utc(2026, 9, 12, 9, 40),
      reason: 'green since the LATEST successful completion',
    );
    for (final event in events) {
      if (event.checkState == PullRequestCheckState.green) continue;
      expect(
        event.greenSince,
        isNull,
        reason: '${event.nodeId} was never green',
      );
      expect(event.stalled, isFalse);
    }
    // Every observation is distinct, so nothing collapses in the ledger.
    expect(
      events.map((event) => event.observationId).toSet(),
      hasLength(shapes.length),
    );
  });

  test('pull feedback maps every mergeability value', () async {
    final wire = <String, Object?>{
      'PR_mergeable': true,
      'PR_conflicting': false,
      'PR_unknown': null,
    };
    final transport = FakeGitHubHttpTransport()
      ..responses.add(_response('', status: 304))
      ..responses.add(
        _response(<Object?>[
          for (final node in wire.keys) _openPull(nodeId: node),
        ], etag: '"pulls"'),
      );
    for (final mergeable in wire.values) {
      transport.responses
        ..add(_response(_pullDetail(mergeable: mergeable)))
        ..add(_response(_checkRuns(<Map<String, Object?>>[_run()])));
    }
    final events = <PullRequestFeedback>[];
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: FakeGitHubCursorStore(_intakeSettled()),
      emit: (event) async => events.add(event as PullRequestFeedback),
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    ).reconcileOnce();

    expect(
      <String, PullRequestMergeability>{
        for (final event in events) event.nodeId: event.mergeability,
      },
      <String, PullRequestMergeability>{
        'PR_mergeable': PullRequestMergeability.mergeable,
        'PR_conflicting': PullRequestMergeability.conflicting,
        'PR_unknown': PullRequestMergeability.unknown,
      },
    );
  });

  test('green feedback crosses the one-hour stall bound from cache', () async {
    var now = DateTime.utc(2026, 9, 12, 9, 45);
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        // Cycle one: a fresh green.
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls"'),
        _response(_pullDetail(), etag: '"detail"'),
        _response(_checkRuns(<Map<String, Object?>>[_run()]), etag: '"checks"'),
        // Cycle two: NOTHING changed, and the bound has passed.
        _response('', status: 304),
        _response('', status: 304),
        // Cycle three: still nothing changed, and still past the bound.
        _response('', status: 304),
        _response('', status: 304),
      ]);
    final store = FakeGitHubCursorStore(_intakeSettled());
    final events = <PullRequestFeedback>[];
    final reconciler = GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event as PullRequestFeedback),
      now: () => now,
    );

    await reconciler.reconcileOnce();
    expect(events.single.stalled, isFalse);

    now = DateTime.utc(2026, 9, 12, 10, 30);
    await reconciler.reconcileOnce();
    expect(events, hasLength(2));
    expect(events.last.stalled, isTrue);
    expect(events.last.checkState, PullRequestCheckState.green);
    expect(events.last.greenSince, DateTime.utc(2026, 9, 12, 9, 30));
    expect(events.last.observedAt, now);
    expect(events.last.body, contains('Refs: pow-78jk'));
    expect(events.last.headBranch, 'org/lockfile-convention');
    expect(
      events.last.observationId,
      isNot(events.first.observationId),
      reason: 'the crossing is a DISTINCT observation',
    );
    expect(
      transport.requests,
      hasLength(6),
      reason: 'an unchanged page spends no per-pull request',
    );

    now = DateTime.utc(2026, 9, 12, 11, 30);
    await reconciler.reconcileOnce();
    expect(events, hasLength(2), reason: 'the crossing emits exactly once');
    expect(transport.requests, hasLength(8));
  });

  test('feedback request count stays bounded by etags', () async {
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        // Cycle one: everything is fresh.
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls"'),
        _response(_pullDetail(), etag: '"detail"'),
        _response(_checkRuns(<Map<String, Object?>>[_run()]), etag: '"checks"'),
        // Cycle two: the PAGE changed, both per-pull resources did not.
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls-2"'),
        _response('', status: 304),
        _response('', status: 304),
      ]);
    final store = FakeGitHubCursorStore(_intakeSettled());
    final events = <PullRequestFeedback>[];
    final reconciler = GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event as PullRequestFeedback),
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    );

    await reconciler.reconcileOnce();
    expect(transport.requests, hasLength(4));
    expect(
      transport.requests.skip(2).map(_conditional),
      everyElement(isNull),
      reason: 'nothing was cached to be conditional on',
    );

    await reconciler.reconcileOnce();
    expect(
      transport.requests,
      hasLength(8),
      reason: 'ONE detail and ONE check-runs request per listed pull',
    );
    expect(_conditional(transport.requests[5]), '"pulls"');
    expect(_conditional(transport.requests[6]), '"detail"');
    expect(_conditional(transport.requests[7]), '"checks"');
    // Both `304`s were answered from the cursor, and the tags survived.
    expect(events, hasLength(1), reason: 'an unchanged state deduplicates');
    expect(store.cursor.etags['feedback/pull/PR_8'], '"detail"');
    expect(store.cursor.etags['feedback/checks/PR_8'], '"checks"');
    expect(store.cursor.etags['feedback/pulls'], '"pulls-2"');
    expect(
      store.cursor.pullFeedback['PR_8']!.checkState,
      PullRequestCheckState.green,
    );
  });

  test('a 304 the cursor cannot answer invents nothing', () async {
    // Unreachable by construction — the tag is only sent when a record exists —
    // so a server that answers one anyway is naming a state we must not
    // invent a green for. The refusal stands: nothing is emitted and nothing is
    // recorded. It is REPORTED as that one pull's skip rather than as a dead
    // cycle, because a lying answer about pull 8 says nothing about pull 9.
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls"'),
        _response('', status: 304),
      ]);
    final store = FakeGitHubCursorStore(_intakeSettled());
    final events = <NormalizedGitHubEvent>[];
    final skips = <({int number, String failure})>[];
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (event) async => events.add(event),
      onPullFeedbackError: (number, failure, _) =>
          skips.add((number: number, failure: failure)),
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    ).reconcileOnce();

    expect(events, isEmpty, reason: 'no mergeability was invented');
    expect(store.cursor.pullFeedback, isEmpty);
    expect(skips.single.number, 8);
    expect(skips.single.failure, 'FormatException');
  });

  group('pull feedback failure domains', () {
    // Three open pulls, and the MIDDLE one is the one GitHub will not answer
    // for. One inaccessible pull silencing the two beside it is this bead's own
    // defect at a smaller scale, so the boundary is drawn around ONE pull's
    // observation: the others are observed, the skip is reported, and the
    // skipped pull's baseline is left exactly where the next cycle needs it.

    test('a failed detail request skips only its own pull', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response('', status: 304),
          _response(_threeOpenPulls(), etag: '"pulls"'),
          // Pull 1, observed end to end.
          _response(_pullDetail(), etag: '"detail-1"'),
          _response(
            _checkRuns(<Map<String, Object?>>[_run()]),
            etag: '"checks-1"',
          ),
          // Pull 2's DETAIL is forbidden, body and all.
          _response(_secretBody, status: 403),
          // Pull 3, observed end to end AFTER the failure.
          _response(_pullDetail(), etag: '"detail-3"'),
          _response(
            _checkRuns(<Map<String, Object?>>[_run()]),
            etag: '"checks-3"',
          ),
        ]);
      final store = FakeGitHubCursorStore(_feedbackSettled());
      final events = <PullRequestFeedback>[];
      final skips = <({int number, String failure})>[];
      await GitHubReconciler(
        owner: 'o',
        repository: 'r',
        substation: 's',
        client: _client(transport),
        cursors: store,
        emit: (event) async => events.add(event as PullRequestFeedback),
        onPullFeedbackError: (number, failure, _) =>
            skips.add((number: number, failure: failure)),
        now: () => DateTime.utc(2026, 9, 12, 9, 45),
      ).reconcileOnce();

      expect(
        events.map((event) => event.number),
        <int>[1, 3],
        reason: 'the pulls beside the failure are still observed',
      );
      expect(skips, hasLength(1), reason: 'ONE report for ONE skipped pull');
      expect(skips.single.number, 2);
      expect(skips.single.failure, 'HTTP 403');
      expect(
        skips.single.failure,
        isNot(contains('secret')),
        reason: 'a bounded status, never the response body',
      );
      // Pull 2 keeps the baseline the next cycle re-observes from.
      expect(store.cursor.pullFeedback['PR_2'], _baseline);
      expect(store.cursor.etags['feedback/pull/PR_2'], '"detail-2"');
      expect(store.cursor.etags['feedback/checks/PR_2'], '"checks-2"');
      expect(
        store.cursor.pullFeedback.keys,
        containsAll(<String>['PR_1', 'PR_2', 'PR_3']),
        reason: 'a pull GitHub listed as open is open, observed or not',
      );
      expect(
        store.cursor.etags['feedback/pulls'],
        '"pulls"',
        reason: 'the cycle still completed and saved',
      );
      expect(
        transport.requests,
        hasLength(7),
        reason: 'one attempt for the skipped pull, and no retry inside it',
      );
    });

    test('a failed check-runs request skips only its own pull', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response('', status: 304),
          _response(_threeOpenPulls(), etag: '"pulls"'),
          _response(_pullDetail(), etag: '"detail-1"'),
          _response(
            _checkRuns(<Map<String, Object?>>[_run()]),
            etag: '"checks-1"',
          ),
          // Pull 2's detail SUCCEEDS with a new tag, and its checks do not.
          _response(_pullDetail(), etag: '"detail-2-fresh"'),
          _response(_secretBody, status: 422),
          _response(_pullDetail(), etag: '"detail-3"'),
          _response(
            _checkRuns(<Map<String, Object?>>[_run()]),
            etag: '"checks-3"',
          ),
        ]);
      final store = FakeGitHubCursorStore(_feedbackSettled());
      final events = <PullRequestFeedback>[];
      final skips = <({int number, String failure})>[];
      await GitHubReconciler(
        owner: 'o',
        repository: 'r',
        substation: 's',
        client: _client(transport),
        cursors: store,
        emit: (event) async => events.add(event as PullRequestFeedback),
        onPullFeedbackError: (number, failure, _) =>
            skips.add((number: number, failure: failure)),
        now: () => DateTime.utc(2026, 9, 12, 9, 45),
      ).reconcileOnce();

      expect(events.map((event) => event.number), <int>[1, 3]);
      expect(skips, hasLength(1));
      expect(skips.single.number, 2);
      expect(skips.single.failure, 'HTTP 422');
      expect(skips.single.failure, isNot(contains('secret')));
      expect(store.cursor.pullFeedback['PR_2'], _baseline);
      expect(
        store.cursor.etags['feedback/pull/PR_2'],
        '"detail-2"',
        reason:
            'a HALF-observed pull banks NEITHER tag: the baseline the '
            'surviving tag describes was never written',
      );
      expect(store.cursor.etags['feedback/checks/PR_2'], '"checks-2"');
      expect(
        store.cursor.pullFeedback.keys,
        containsAll(<String>['PR_1', 'PR_2', 'PR_3']),
      );
      expect(store.cursor.etags['feedback/pulls'], '"pulls"');
      expect(transport.requests, hasLength(8));
    });

    test('a failed open-pulls list stays cycle-fatal', () async {
      // The PRECONDITION of every per-pull decision above: without the list
      // there is no pull to skip, no open set to retain against, and a page
      // etag recorded over an unread page would make the next `304` a lie.
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response('', status: 304),
          _response(_secretBody, status: 500),
        ]);
      final store = FakeGitHubCursorStore(_feedbackSettled());
      final skips = <int>[];
      await expectLater(
        GitHubReconciler(
          owner: 'o',
          repository: 'r',
          substation: 's',
          client: _client(transport),
          cursors: store,
          emit: (_) async {},
          onPullFeedbackError: (number, _, _) => skips.add(number),
          now: () => DateTime.utc(2026, 9, 12, 9, 45),
        ).reconcileOnce(),
        throwsA(isA<GitHubPollException>()),
      );

      expect(
        transport.requests,
        hasLength(2),
        reason: 'the cycle died before any per-pull request',
      );
      expect(skips, isEmpty, reason: 'no pull was skipped; the LIST failed');
      expect(store.calls, isEmpty, reason: 'nothing was saved');
      expect(store.cursor.pullFeedback['PR_2'], _baseline);
      expect(store.cursor.etags['feedback/pulls'], isNull);
    });

    test('the skipped pull reaches the seat flare, bounded', () async {
      // The REACHABILITY of the report: a seat composes through the factory, so
      // the callback has to land on the seat's OWN transport under the named
      // flare — with the pull named, the failure bounded, and the response body
      // nowhere on it.
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response('', status: 304),
          _response(<Object?>[
            _openPull(nodeId: 'PR_2', number: 2),
          ], etag: '"pulls"'),
          _response(_secretBody, status: 403),
        ]);
      final flares = RecordingExplorationTransport();
      final runtime = createGitHubReconcilerRuntime(
        config: const GitHubReconcilerConfig(
          owner: 'memento-engineering',
          repository: 'power_station',
          substation: 'power_station',
          installationId: 'installation',
        ),
        client: _client(transport),
        cursors: FakeGitHubCursorStore(_feedbackSettled()),
        emit: (_) async {},
        transport: flares,
        foreignClient: null,
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );
      await runtime.reconciler.reconcileOnce();

      final flare = flares.named(kPullFeedbackSkippedFlare).single;
      expect(flare.data['error'], 'pull #2: HTTP 403');
      expect(flare.data['seat'], 'power_station');
      expect(flare.data['repository'], 'memento-engineering/power_station');
      expect(
        flares.flares.map((entry) => entry.data.values.join()).join(),
        isNot(contains('secret')),
        reason: 'nothing from the response body reaches the seat surface',
      );
    });
  });

  test('feedback preserves the intake high-water mark', () async {
    final since = DateTime.parse('2026-08-09T00:00:00Z');
    final transport = FakeGitHubHttpTransport()
      ..responses.addAll(<GitHubHttpResponse>[
        _response('', status: 304),
        _response(<Object?>[_openPull()], etag: '"pulls"'),
        _response(_pullDetail()),
        _response(_checkRuns(<Map<String, Object?>>[_run()])),
      ]);
    final store = FakeGitHubCursorStore(
      GitHubReconcilerCursor(
        since: since,
        etags: const <String, String>{'intake/issues': '"intake"'},
      ),
    );
    await GitHubReconciler(
      owner: 'o',
      repository: 'r',
      substation: 's',
      client: _client(transport),
      cursors: store,
      emit: (_) async {},
      now: () => DateTime.utc(2026, 9, 12, 9, 45),
    ).reconcileOnce();
    expect(store.cursor.since, since);
  });

  group('workflow run', () {
    test('default config is feature-off and never asks for runs', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
        ]);
      final store = FakeGitHubCursorStore();
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 's',
        client: _client(transport),
        cursors: store,
        emit: (_) async {},
      ).reconcileOnce();

      expect(transport.requests, hasLength(2));
      expect(
        transport.requests.map((request) => request.uri.path),
        everyElement(isNot(contains('/actions/'))),
      );
      expect(store.cursor.workflowRunsSince, isNull);
      expect(store.cursor.etags, isNot(contains('intake/workflow-runs')));
    });

    test('a matching failure emits once with its failed jobs', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(await _runsPage(), etag: '"runs"'),
          _response(await _jobsPage()),
        ]);
      final store = FakeGitHubCursorStore();
      final events = <NormalizedGitHubEvent>[];
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: store,
        emit: (event) async => events.add(event),
        workflowRuns: [_nightlyRule()],
      ).reconcileOnce();

      final run = events.single as WorkflowRunConcluded;
      expect(run.nodeId, 'WFR_NIGHTLY');
      expect(run.runId, 9001);
      expect(run.runNumber, 128);
      expect(run.workflowPath, '.github/workflows/ci.yaml');
      expect(run.workflowName, 'CI');
      expect(run.event, 'schedule');
      expect(run.headBranch, 'main');
      expect(run.conclusion, 'failure');
      expect(run.substation, 'seat');
      expect(run.actor, 'memento/power');
      expect(run.repository, 'memento/power');
      expect(
        run.observationId,
        'poll:run:WFR_NIGHTLY:2026-09-07T06:11:00Z:failure',
      );
      expect(
        run.failedJobs.map((job) => job.jobName),
        ['test', 'integration', 'cancelled-before-any-step'],
        reason: 'a green job is not a failed job',
      );
      expect(run.failedJobs[0].failedStepName, 'dart test');
      expect(
        run.failedJobs[1].failedStepName,
        isNull,
        reason: 'no step of the timed-out job itself failed',
      );
      expect(run.failedJobs[2].failedStepName, isNull);
    });

    test('non-matching and fork-head rows never cost a jobs request', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(await _runsPage(), etag: '"runs"'),
          _response(await _jobsPage()),
        ]);
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: FakeGitHubCursorStore(),
        emit: (_) async {},
        workflowRuns: [_nightlyRule()],
      ).reconcileOnce();

      final jobs = transport.requests
          .where((request) => request.uri.path.endsWith('/jobs'))
          .toList();
      expect(jobs, hasLength(1));
      expect(jobs.single.uri.path, endsWith('/actions/runs/9001/jobs'));
      expect(jobs.single.uri.queryParameters['filter'], 'latest');
      for (final rejected in ['9002', '9003', '9004']) {
        expect(
          transport.requests.where(
            (request) => request.uri.path.contains('/runs/$rejected/'),
          ),
          isEmpty,
          reason: 'run $rejected matched no rule or came from a fork',
        );
      }
    });

    test('the window, the etag and the claim are all persisted', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(await _runsPage(), etag: '"runs"'),
          _response(await _jobsPage()),
        ]);
      final store = FakeGitHubCursorStore();
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: store,
        emit: (_) async {},
        workflowRuns: [_nightlyRule()],
      ).reconcileOnce();

      expect(store.cursor.etags['intake/workflow-runs'], '"runs"');
      expect(
        store.cursor.workflowRunsSince,
        DateTime.parse('2026-09-08T06:00:00Z'),
        reason: 'the greatest created_at on the page, matching or not',
      );
      expect(
        store.cursor.hasObserved(
          'poll:run:WFR_NIGHTLY:2026-09-07T06:11:00Z:failure',
        ),
        isTrue,
      );
      expect(store.cursor.pending, isEmpty);

      final runsRequest = transport.requests.firstWhere(
        (request) => request.uri.path.endsWith('/actions/runs'),
      );
      expect(runsRequest.uri.queryParameters['status'], 'completed');
      expect(runsRequest.uri.queryParameters['per_page'], '50');
      expect(
        runsRequest.uri.queryParameters,
        isNot(contains('created')),
        reason: 'a first poll has no window to narrow',
      );
    });

    test(
      'a claimed run is re-read inside the window and never re-fetched',
      () async {
        final transport = FakeGitHubHttpTransport()
          ..responses.addAll(<GitHubHttpResponse>[
            _response(const <Object?>[], etag: '"issues"'),
            _response(const <Object?>[], etag: '"pulls"'),
            _response(await _runsPage(), etag: '"runs2"'),
          ]);
        final store = FakeGitHubCursorStore(
          GitHubReconcilerCursor(
            workflowRunsSince: DateTime.parse('2026-09-07T06:00:00Z'),
            observationIds: const <String>[
              'poll:run:WFR_NIGHTLY:2026-09-07T06:11:00Z:failure',
            ],
          ),
        );
        final events = <NormalizedGitHubEvent>[];
        await GitHubReconciler(
          owner: 'memento',
          repository: 'power',
          substation: 'seat',
          client: _client(transport),
          cursors: store,
          emit: (event) async => events.add(event),
          workflowRuns: [_nightlyRule()],
        ).reconcileOnce();

        expect(events, isEmpty);
        expect(
          transport.requests.where(
            (request) => request.uri.path.endsWith('/jobs'),
          ),
          isEmpty,
          reason: 'an already-claimed run is dropped BEFORE its jobs request',
        );
        final runsRequest = transport.requests.firstWhere(
          (request) => request.uri.path.endsWith('/actions/runs'),
        );
        expect(
          runsRequest.uri.queryParameters['created'],
          '>=2026-09-07T06:00:00.000Z',
        );
      },
    );

    test('a 304 on the runs endpoint costs nothing further', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response('', status: 304),
        ]);
      final events = <NormalizedGitHubEvent>[];
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: FakeGitHubCursorStore(
          const GitHubReconcilerCursor(
            etags: <String, String>{'intake/workflow-runs': '"runs"'},
          ),
        ),
        emit: (event) async => events.add(event),
        workflowRuns: [_nightlyRule()],
      ).reconcileOnce();

      expect(events, isEmpty);
      expect(transport.requests, hasLength(3));
      expect(transport.requests.last.headers['If-None-Match'], '"runs"');
    });

    test('a rule declaring a non-default branch never matches main', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(const <Object?>[], etag: '"issues"'),
          _response(const <Object?>[], etag: '"pulls"'),
          _response(await _runsPage(), etag: '"runs"'),
        ]);
      final events = <NormalizedGitHubEvent>[];
      await GitHubReconciler(
        owner: 'memento',
        repository: 'power',
        substation: 'seat',
        client: _client(transport),
        cursors: FakeGitHubCursorStore(),
        emit: (event) async => events.add(event),
        defaultBranch: 'release',
        workflowRuns: [_nightlyRule()],
      ).reconcileOnce();

      expect(events, isEmpty);
      expect(transport.requests, hasLength(3));
    });
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

  group('outbound issue watches', () {
    const watch = GitHubIssueWatch(
      originatingBeadId: 'lunar_station-6p9',
      owner: 'ricardoboss',
      repository: 'radioactive_dart',
      issueNumber: 1,
    );
    const installed = GitHubIssueWatch(
      originatingBeadId: 'pow-1rn',
      owner: 'MEMENTO',
      repository: 'Power',
      issueNumber: 4,
    );

    Map<String, Object?> issue({
      String state = 'open',
      String? stateReason,
      bool locked = false,
      String updatedAt = '2026-09-09T10:00:00Z',
    }) => <String, Object?>{
      'node_id': 'I_kwDO',
      'number': 1,
      'user': <String, Object?>{'login': 'nico'},
      'state': state,
      'state_reason': stateReason,
      'locked': locked,
      'updated_at': updatedAt,
      'html_url': 'https://github.test/ricardoboss/radioactive_dart/issues/1',
      'closed_by': null,
    };

    ({
      GitHubReconciler reconciler,
      List<NormalizedGitHubEvent> events,
      FakeGitHubCursorStore cursors,
    })
    build(
      FakeGitHubHttpTransport transport, {
      List<GitHubIssueWatch> watches = const <GitHubIssueWatch>[watch],
      GitHubReconcilerCursor? cursor,
    }) {
      final events = <NormalizedGitHubEvent>[];
      final cursors = FakeGitHubCursorStore(
        cursor ?? const GitHubReconcilerCursor(),
      );
      return (
        reconciler: GitHubReconciler(
          owner: 'memento',
          repository: 'power',
          substation: 'power',
          client: _client(transport),
          cursors: cursors,
          emit: (event) async => events.add(event),
          issueWatches: watches,
          foreignClient: GitHubReadClient(
            transport: transport,
            apiBaseUri: Uri.parse('https://api.github.test'),
          ),
        ),
        events: events,
        cursors: cursors,
      );
    }

    test('a watch on the seat repository is INSTALLED, case-insensitively', () {
      expect(
        installed.isInstalledRepository(owner: 'memento', repository: 'power'),
        isTrue,
      );
      expect(
        watch.isInstalledRepository(owner: 'memento', repository: 'power'),
        isFalse,
      );
      expect(watch.coordinateKey, 'ricardoboss/radioactive_dart#1');
      expect(installed.coordinateKey, 'memento/power#4');
    });

    test('a coordinate the cursor could not read back is refused', () {
      // Both sides share ONE pattern, so nothing can be authored that the
      // cursor then refuses on load — which would brick the seat's polling.
      expect(
        GitHubIssueWatch.isCoordinateKey('memento-engineering/.github#1'),
        isTrue,
        reason: 'the org owns a repository literally named `.github`',
      );
      expect(GitHubIssueWatch.isCoordinateKey('owner/repo#0'), isFalse);
      expect(GitHubIssueWatch.isCoordinateKey('Owner/Repo#1'), isFalse);
      expect(GitHubIssueWatch.isCoordinateKey('owner#1'), isFalse);
      expect(
        const GitHubIssueWatch(
          originatingBeadId: 'b',
          owner: 'owner/nested',
          repository: 'repo',
          issueNumber: 1,
        ).validate,
        throwsArgumentError,
      );
      const dotGitHub = GitHubIssueWatch(
        originatingBeadId: 'b',
        owner: 'memento-engineering',
        repository: '.github',
        issueNumber: 1,
      );
      dotGitHub.validate();
      expect(dotGitHub.coordinateKey, 'memento-engineering/.github#1');
    });

    test('a blank or non-positive watch is refused at construction', () {
      for (final invalid in const <GitHubIssueWatch>[
        GitHubIssueWatch(
          originatingBeadId: '  ',
          owner: 'o',
          repository: 'r',
          issueNumber: 1,
        ),
        GitHubIssueWatch(
          originatingBeadId: 'b',
          owner: '',
          repository: 'r',
          issueNumber: 1,
        ),
        GitHubIssueWatch(
          originatingBeadId: 'b',
          owner: 'o',
          repository: ' ',
          issueNumber: 1,
        ),
        GitHubIssueWatch(
          originatingBeadId: 'b',
          owner: 'o',
          repository: 'r',
          issueNumber: 0,
        ),
      ]) {
        expect(invalid.validate, throwsArgumentError);
        expect(
          () => build(
            FakeGitHubHttpTransport(),
            watches: <GitHubIssueWatch>[invalid],
          ),
          throwsArgumentError,
        );
      }
    });

    test(
      'the baseline poll emits comments but replays no transition',
      () async {
        final transport = FakeGitHubHttpTransport()
          ..responses.addAll(<GitHubHttpResponse>[
            _response(issue(), etag: '"issue"'),
            _response(<Object?>[
              <String, Object?>{
                'event': 'commented',
                'id': 11,
                'node_id': 'IC_first',
                'user': <String, Object?>{'login': 'ricardoboss'},
                'body': 'A reply.',
                'created_at': '2026-09-09T11:00:00Z',
                'html_url': 'https://github.test/1#issuecomment-11',
              },
              <String, Object?>{
                'event': 'closed',
                'id': 91,
                'node_id': 'CE_closed',
                'actor': <String, Object?>{'login': 'ricardoboss'},
                'created_at': '2026-09-09T09:00:00Z',
              },
              <String, Object?>{
                'event': 'reopened',
                'id': 92,
                'node_id': 'CE_reopened',
                'actor': <String, Object?>{'login': 'ricardoboss'},
                'created_at': '2026-09-09T09:30:00Z',
              },
            ], etag: '"timeline"'),
          ]);
        final wired = build(transport);

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        expect(wired.events.whereType<IssueCommented>(), hasLength(1));
        expect(
          wired.events.whereType<WatchedIssueStateChanged>(),
          isEmpty,
          reason: 'the baseline records the mark those rows sit behind',
        );
        final record = wired.cursors.cursor.issueWatches[watch.coordinateKey]!;
        expect(record.lastCommentId, 11);
        expect(record.lastTimelineEventId, 92);
        expect(record.issueNodeId, 'I_kwDO');
        expect(record.issueAuthor, 'nico');
        expect(
          wired
              .cursors
              .cursor
              .etags['issue-watch/${watch.coordinateKey}/issue'],
          '"issue"',
        );
        expect(
          wired
              .cursors
              .cursor
              .etags['issue-watch/${watch.coordinateKey}/timeline'],
          '"timeline"',
        );
      },
    );

    test('a baseline on an already-closed issue says so once', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(issue(state: 'closed', stateReason: 'not_planned')),
          _response(<Object?>[]),
        ]);
      final wired = build(transport);

      await wired.reconciler.reconcileForeignIssueWatchesOnce();

      final change = wired.events.whereType<WatchedIssueStateChanged>().single;
      expect(change.change, GitHubIssueWatchChange.closedNotPlanned);
      expect(
        change.observationId,
        'poll:issue-state:I_kwDO:2026-09-09T10:00:00.000Z:closed_not_planned',
      );
    });

    test('a timeline page is followed through the SAME lane', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(issue()),
          _response(<Object?>[
            <String, Object?>{
              'event': 'commented',
              'id': 11,
              'node_id': 'IC_first',
              'user': <String, Object?>{'login': 'ricardoboss'},
              'body': 'page one',
              'created_at': '2026-09-09T11:00:00Z',
            },
          ], link: '<https://api.github.test/x?page=2>; rel="next"'),
          _response(<Object?>[
            <String, Object?>{
              'event': 'commented',
              'id': 12,
              'node_id': 'IC_second',
              'user': <String, Object?>{'login': 'ricardoboss'},
              'body': 'page two',
              'created_at': '2026-09-09T11:30:00Z',
            },
          ]),
        ]);
      final wired = build(transport);

      await wired.reconciler.reconcileForeignIssueWatchesOnce();

      expect(
        wired.events.whereType<IssueCommented>().map((event) => event.body),
        <String>['page one', 'page two'],
      );
      for (final request in transport.requests) {
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
    });

    test(
      'an unchanged watch costs two conditional 304s and emits nothing',
      () async {
        final seeded = const GitHubReconcilerCursor().recordIssueWatch(
          watch.coordinateKey,
          GitHubIssueWatchCursorRecord(
            issueNodeId: 'I_kwDO',
            issueAuthor: 'nico',
            lastCommentId: 11,
            lastTimelineEventId: 92,
            lastState: 'open',
            lastStateReason: null,
            locked: false,
            lastUpdatedAt: DateTime.utc(2026, 9, 9, 10),
            lastChange: null,
          ),
          issueEtag: '"issue"',
          timelineEtag: '"timeline"',
        );
        final transport = FakeGitHubHttpTransport()
          ..responses.addAll(<GitHubHttpResponse>[
            _response('', status: 304),
            _response('', status: 304),
          ]);
        final wired = build(transport, cursor: seeded);

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        expect(wired.events, isEmpty);
        expect(transport.requests, hasLength(2));
        expect(transport.requests.first.headers['If-None-Match'], '"issue"');
        expect(transport.requests.last.headers['If-None-Match'], '"timeline"');
        expect(
          wired
              .cursors
              .cursor
              .etags['issue-watch/${watch.coordinateKey}/issue'],
          '"issue"',
          reason: 'a 304 retains the tag it was conditional on',
        );
      },
    );

    test('a pull-shaped resource is refused loudly', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.add(
          _response(<String, Object?>{
            ...issue(),
            'pull_request': <String, Object?>{'url': 'https://api.github.test'},
          }),
        );
      final wired = build(transport);

      await expectLater(
        wired.reconciler.reconcileForeignIssueWatchesOnce(),
        throwsFormatException,
      );
    });

    test(
      'a resource change with no timeline row still reaches the bead',
      () async {
        final seeded = const GitHubReconcilerCursor().recordIssueWatch(
          watch.coordinateKey,
          GitHubIssueWatchCursorRecord(
            issueNodeId: 'I_kwDO',
            issueAuthor: 'nico',
            lastCommentId: 0,
            lastTimelineEventId: 0,
            lastState: 'open',
            lastStateReason: null,
            locked: false,
            lastUpdatedAt: DateTime.utc(2026, 9, 9, 10),
            lastChange: null,
          ),
        );
        final transport = FakeGitHubHttpTransport()
          ..responses.addAll(<GitHubHttpResponse>[
            _response(
              issue(
                state: 'closed',
                stateReason: 'completed',
                updatedAt: '2026-09-09T13:00:00Z',
              ),
            ),
            _response(<Object?>[]),
          ]);
        final wired = build(transport, cursor: seeded);

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        final change = wired.events
            .whereType<WatchedIssueStateChanged>()
            .single;
        expect(change.change, GitHubIssueWatchChange.closedCompleted);
        expect(
          change.observationId,
          'poll:issue-state:I_kwDO:2026-09-09T13:00:00.000Z:closed_completed',
        );
        expect(change.actor, kIssueWatchResourceActor);
      },
    );

    test('a foreign-only cycle asks the App client for nothing', () async {
      final transport = FakeGitHubHttpTransport()
        ..responses.addAll(<GitHubHttpResponse>[
          _response(issue()),
          _response(<Object?>[]),
        ]);
      final wired = build(transport);

      await wired.reconciler.reconcileForeignIssueWatchesOnce();

      expect(transport.requests, hasLength(2));
      expect(transport.requests.map((request) => request.uri.path), <String>[
        '/repos/ricardoboss/radioactive_dart/issues/1',
        '/repos/ricardoboss/radioactive_dart/issues/1/timeline',
      ]);
    });

    test(
      'an unconfigured watch loses its record on the next full cycle',
      () async {
        final seeded = const GitHubReconcilerCursor().recordIssueWatch(
          'gone/away#9',
          GitHubIssueWatchCursorRecord(
            issueNodeId: 'I_gone',
            issueAuthor: 'nico',
            lastCommentId: 0,
            lastTimelineEventId: 0,
            lastState: 'open',
            lastStateReason: null,
            locked: false,
            lastUpdatedAt: DateTime.utc(2026, 9, 9, 10),
            lastChange: null,
          ),
          issueEtag: '"stale"',
        );
        final transport = FakeGitHubHttpTransport()
          ..responses.addAll(<GitHubHttpResponse>[
            _response('', status: 304),
            _response('', status: 304),
          ]);
        final wired = build(
          transport,
          watches: const <GitHubIssueWatch>[],
          cursor: seeded,
        );

        await wired.reconciler.reconcileOnce();

        expect(wired.cursors.cursor.issueWatches, isEmpty);
        expect(
          wired.cursors.cursor.etags.containsKey(
            'issue-watch/gone/away#9/issue',
          ),
          isFalse,
        );
      },
    );
  });
}
